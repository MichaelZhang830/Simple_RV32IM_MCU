`timescale 1ns / 1ps
// Integration test for the rv32i core together with the MMIO block.
//
// A directed program is loaded through the instruction-memory write port and
// its results are checked. It runs twice: undisturbed, and with ext_stall
// asserted at random, which must not change any result or MMIO access.
//
// USE_PAYLOAD = 1 instead runs the program.bin built by payload/Makefile for
// PAYLOAD_CYCLES clocks and reports its MMIO and framebuffer stores.

module rv32im_core_tb #(
    parameter USE_PAYLOAD    = 0,
    parameter PAYLOAD_CYCLES = 20000
);
    localparam integer PROG_WORDS   = 148;
    localparam integer RESULT_WORD0 = 128;          // results live at RAM address 0x200
    localparam integer TIMEOUT      = 20000;        // clock cycles per run
    localparam [31:0]  DONE_MARKER  = 32'h0000_600D;
    localparam [31:0]  GPIO_IN_VAL  = 32'hCAFE_F00D;
    localparam [7:0]   UART_RX_BYTE = 8'hA7;

    reg clk = 1'b0;
    reg rst = 1'b1;

    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Device under test
    // -------------------------------------------------------------------------
    reg         ext_stall    = 1'b0;
    reg         imem_wr_en   = 1'b0;
    reg  [10:0] imem_wr_addr = 11'd0;
    reg  [31:0] imem_wr_data = 32'd0;

    wire [31:0] pc_debug, result_debug;
    wire [31:0] mem_addr, mem_wdata, mmio_r_data;
    wire [1:0]  mem_w_en;
    wire        mmio_wr_en, mmio_rd_en;

    rv32i #(
        .ENABLE_M_EXT (1'b1)
    ) dut (
        .clk          (clk),
        .rst          (rst),
        .ext_stall    (ext_stall),
        .pc_debug     (pc_debug),
        .result_debug (result_debug),
        .mem_addr     (mem_addr),
        .mem_wdata    (mem_wdata),
        .mem_w_en     (mem_w_en),
        .mmio_wr_en   (mmio_wr_en),
        .mmio_rd_en   (mmio_rd_en),
        .mmio_r_data  (mmio_r_data),
        .imem_wr_en   (imem_wr_en),
        .imem_wr_addr (imem_wr_addr),
        .imem_wr_data (imem_wr_data)
    );

    reg         uart_rx_valid = 1'b0;
    reg  [7:0]  uart_rx_data  = 8'd0;
    wire        led_wr_en, uart_tx_start;
    wire [4:0]  led_wr_data;
    wire [7:0]  uart_tx_data;
    wire [31:0] gpio_dir, gpio_out, gpio_en;

    mmio mmio_dut (
        .clk           (clk),
        .rst           (rst),
        .addr          (mem_addr),
        .mmio_wr_en    (mmio_wr_en),
        .mmio_rd_en    (mmio_rd_en),
        .mem_w_en      (mem_w_en),
        .w_data        (mem_wdata),
        .r_data        (mmio_r_data),
        .led_wr_en     (led_wr_en),
        .led_wr_data   (led_wr_data),
        .key1          (1'b0),
        .key2          (1'b1),
        .uart_rx_valid (uart_rx_valid),
        .uart_rx_data  (uart_rx_data),
        .uart_tx_busy  (1'b0),
        .uart_tx_start (uart_tx_start),
        .uart_tx_data  (uart_tx_data),
        .gpio_in       (GPIO_IN_VAL),
        .gpio_dir      (gpio_dir),
        .gpio_out      (gpio_out),
        .gpio_en       (gpio_en)
    );

    // -------------------------------------------------------------------------
    // Monitors
    // -------------------------------------------------------------------------
    integer errors = 0;
    integer mmio_stores, fb_stores, led_writes, uart_tx_count, uart_rx_polls;
    reg [7:0]  uart_tx_last;
    reg [31:0] fb_last_addr, fb_last_data;

    wire fb_store = !ext_stall && (mem_w_en != 2'b00) &&
                    ((mem_addr[31:16] == 16'h0001) || (mem_addr[31:16] == 16'h0002));

    always @(posedge clk) begin
        if (rst) begin
            mmio_stores   <= 0;
            fb_stores     <= 0;
            led_writes    <= 0;
            uart_tx_count <= 0;
            uart_rx_polls <= 0;
        end else begin
            if (mmio_wr_en) mmio_stores <= mmio_stores + 1;
            if (led_wr_en)  led_writes  <= led_writes + 1;
            if (mmio_rd_en && (mem_addr == 32'h0000_0418)) uart_rx_polls <= uart_rx_polls + 1;
            if (uart_tx_start) begin
                uart_tx_count <= uart_tx_count + 1;
                uart_tx_last  <= uart_tx_data;
            end
            if (fb_store) begin
                fb_stores    <= fb_stores + 1;
                fb_last_addr <= mem_addr;
                fb_last_data <= mem_wdata;
            end
        end
    end

    // Random external stalls, enabled for the second run.
    reg        stalls_on = 1'b0;
    reg [15:0] lfsr      = 16'hACE1;
    integer    stall_cycles;

    always @(negedge clk) begin
        lfsr      <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
        ext_stall <= stalls_on && (lfsr[2:0] != 3'b000) && lfsr[5];
        if (ext_stall) stall_cycles = stall_cycles + 1;
    end

    // -------------------------------------------------------------------------
    // Directed program (GNU as, -march=rv32im). Result slot N is the RAM word
    // at 0x200 + 4*N, written through x20.
    // -------------------------------------------------------------------------
    reg [31:0] prog [0:PROG_WORDS-1];

    task init_program;
        begin            prog[  0] = 32'h20000A13;  // 000: addi x20,x0,512
            prog[  1] = 32'h00500093;  // 004: addi x1,x0,5
            prog[  2] = 32'h00700113;  // 008: addi x2,x0,7
            prog[  3] = 32'h002081B3;  // 00c: add x3,x1,x2
            prog[  4] = 32'h40118233;  // 010: sub x4,x3,x1
            prog[  5] = 32'h0021C2B3;  // 014: xor x5,x3,x2
            prog[  6] = 32'h0012E333;  // 018: or x6,x5,x1
            prog[  7] = 32'h002373B3;  // 01c: and x7,x6,x2
            prog[  8] = 32'h003A2023;  // 020: sw x3,0(x20)
            prog[  9] = 32'h004A2223;  // 024: sw x4,4(x20)
            prog[ 10] = 32'h005A2423;  // 028: sw x5,8(x20)
            prog[ 11] = 32'h006A2623;  // 02c: sw x6,12(x20)
            prog[ 12] = 32'h007A2823;  // 030: sw x7,16(x20)
            prog[ 13] = 32'h00409413;  // 034: slli x8,x1,0x4
            prog[ 14] = 32'h800004B7;  // 038: lui x9,0x80000
            prog[ 15] = 32'h4044D513;  // 03c: srai x10,x9,0x4
            prog[ 16] = 32'h0044D593;  // 040: srli x11,x9,0x4
            prog[ 17] = 32'h0014A633;  // 044: slt x12,x9,x1
            prog[ 18] = 32'h0014B6B3;  // 048: sltu x13,x9,x1
            prog[ 19] = 32'h008A2A23;  // 04c: sw x8,20(x20)
            prog[ 20] = 32'h00AA2C23;  // 050: sw x10,24(x20)
            prog[ 21] = 32'h00BA2E23;  // 054: sw x11,28(x20)
            prog[ 22] = 32'h02CA2023;  // 058: sw x12,32(x20)
            prog[ 23] = 32'h02DA2223;  // 05c: sw x13,36(x20)
            prog[ 24] = 32'hFFF0C713;  // 060: xori x14,x1,-1
            prog[ 25] = 32'h0060A793;  // 064: slti x15,x1,6
            prog[ 26] = 32'h0050B813;  // 068: sltiu x16,x1,5
            prog[ 27] = 32'h0700E893;  // 06c: ori x17,x1,112
            prog[ 28] = 32'h00937913;  // 070: andi x18,x6,9
            prog[ 29] = 32'h02EA2423;  // 074: sw x14,40(x20)
            prog[ 30] = 32'h02FA2623;  // 078: sw x15,44(x20)
            prog[ 31] = 32'h030A2823;  // 07c: sw x16,48(x20)
            prog[ 32] = 32'h031A2A23;  // 080: sw x17,52(x20)
            prog[ 33] = 32'h032A2C23;  // 084: sw x18,56(x20)
            prog[ 34] = 32'h00000997;  // 088: auipc x19,0x0 <pc_probe>
            prog[ 35] = 32'h033A2E23;  // 08c: sw x19,60(x20)
            prog[ 36] = 32'h10902023;  // 090: sw x9,256(x0)
            prog[ 37] = 32'h01100A93;  // 094: addi x21,x0,17
            prog[ 38] = 32'h11500223;  // 098: sb x21,260(x0)
            prog[ 39] = 32'h02200A93;  // 09c: addi x21,x0,34
            prog[ 40] = 32'h115002A3;  // 0a0: sb x21,261(x0)
            prog[ 41] = 32'h03300A93;  // 0a4: addi x21,x0,51
            prog[ 42] = 32'h11500323;  // 0a8: sb x21,262(x0)
            prog[ 43] = 32'h0F400A93;  // 0ac: addi x21,x0,244
            prog[ 44] = 32'h115003A3;  // 0b0: sb x21,263(x0)
            prog[ 45] = 32'h10402B03;  // 0b4: lw x22,260(x0)
            prog[ 46] = 32'h056A2023;  // 0b8: sw x22,64(x20)
            prog[ 47] = 32'h10700B03;  // 0bc: lb x22,263(x0)
            prog[ 48] = 32'h056A2223;  // 0c0: sw x22,68(x20)
            prog[ 49] = 32'h10704B03;  // 0c4: lbu x22,263(x0)
            prog[ 50] = 32'h056A2423;  // 0c8: sw x22,72(x20)
            prog[ 51] = 32'hCAFECAB7;  // 0cc: lui x21,0xcafec
            prog[ 52] = 32'hEEFA8A93;  // 0d0: addi x21,x21,-273
            prog[ 53] = 32'h11501423;  // 0d4: sh x21,264(x0)
            prog[ 54] = 32'h010ADB13;  // 0d8: srli x22,x21,0x10
            prog[ 55] = 32'h11601523;  // 0dc: sh x22,266(x0)
            prog[ 56] = 32'h10802B03;  // 0e0: lw x22,264(x0)
            prog[ 57] = 32'h056A2623;  // 0e4: sw x22,76(x20)
            prog[ 58] = 32'h10A01B03;  // 0e8: lh x22,266(x0)
            prog[ 59] = 32'h056A2823;  // 0ec: sw x22,80(x20)
            prog[ 60] = 32'h10A05B03;  // 0f0: lhu x22,266(x0)
            prog[ 61] = 32'h056A2A23;  // 0f4: sw x22,84(x20)
            prog[ 62] = 32'h10402A83;  // 0f8: lw x21,260(x0)
            prog[ 63] = 32'h001A8B13;  // 0fc: addi x22,x21,1
            prog[ 64] = 32'h056A2C23;  // 100: sw x22,88(x20)
            prog[ 65] = 32'h10402A83;  // 104: lw x21,260(x0)
            prog[ 66] = 32'h055A2E23;  // 108: sw x21,92(x20)
            prog[ 67] = 32'h00000B93;  // 10c: addi x23,x0,0
            prog[ 68] = 32'h00A00C13;  // 110: addi x24,x0,10
            prog[ 69] = 32'h018B8BB3;  // 114: add x23,x23,x24 <loop>
            prog[ 70] = 32'hFFFC0C13;  // 118: addi x24,x24,-1
            prog[ 71] = 32'hFE0C1CE3;  // 11c: bne x24,x0,114
            prog[ 72] = 32'h077A2023;  // 120: sw x23,96(x20)
            prog[ 73] = 32'h00000C93;  // 124: addi x25,x0,0
            prog[ 74] = 32'h00208463;  // 128: beq x1,x2,130
            prog[ 75] = 32'h001CEC93;  // 12c: ori x25,x25,1
            prog[ 76] = 32'h00108463;  // 130: beq x1,x1,138
            prog[ 77] = 32'h100CEC93;  // 134: ori x25,x25,256
            prog[ 78] = 32'h0014C463;  // 138: blt x9,x1,140
            prog[ 79] = 32'h200CEC93;  // 13c: ori x25,x25,512
            prog[ 80] = 32'h0014E463;  // 140: bltu x9,x1,148
            prog[ 81] = 32'h002CEC93;  // 144: ori x25,x25,2
            prog[ 82] = 32'h0090D463;  // 148: bge x1,x9,150
            prog[ 83] = 32'h400CEC93;  // 14c: ori x25,x25,1024
            prog[ 84] = 32'h0090F463;  // 150: bgeu x1,x9,158
            prog[ 85] = 32'h004CEC93;  // 154: ori x25,x25,4
            prog[ 86] = 32'h079A2223;  // 158: sw x25,100(x20)
            prog[ 87] = 32'h01000D6F;  // 15c: jal x26,16c
            prog[ 88] = 32'h07BA2423;  // 160: sw x27,104(x20) <ret_point>
            prog[ 89] = 32'h07AA2623;  // 164: sw x26,108(x20)
            prog[ 90] = 32'h0100006F;  // 168: jal x0,178
            prog[ 91] = 32'h12300D93;  // 16c: addi x27,x0,291 <func>
            prog[ 92] = 32'h000D0067;  // 170: jalr x0,0(x26)
            prog[ 93] = 32'hFFF00D93;  // 174: addi x27,x0,-1
            prog[ 94] = 32'hFF900E13;  // 178: addi x28,x0,-7 <after_func>
            prog[ 95] = 32'h00300E93;  // 17c: addi x29,x0,3
            prog[ 96] = 32'h03DE0F33;  // 180: mul x30,x28,x29
            prog[ 97] = 32'h07EA2823;  // 184: sw x30,112(x20)
            prog[ 98] = 32'h029E1F33;  // 188: mulh x30,x28,x9
            prog[ 99] = 32'h07EA2A23;  // 18c: sw x30,116(x20)
            prog[100] = 32'h029E3F33;  // 190: mulhu x30,x28,x9
            prog[101] = 32'h07EA2C23;  // 194: sw x30,120(x20)
            prog[102] = 32'h029E2F33;  // 198: mulhsu x30,x28,x9
            prog[103] = 32'h07EA2E23;  // 19c: sw x30,124(x20)
            prog[104] = 32'h03DE4F33;  // 1a0: div x30,x28,x29
            prog[105] = 32'h09EA2023;  // 1a4: sw x30,128(x20)
            prog[106] = 32'h03DE6F33;  // 1a8: rem x30,x28,x29
            prog[107] = 32'h09EA2223;  // 1ac: sw x30,132(x20)
            prog[108] = 32'h03DE5F33;  // 1b0: divu x30,x28,x29
            prog[109] = 32'h09EA2423;  // 1b4: sw x30,136(x20)
            prog[110] = 32'h021E7F33;  // 1b8: remu x30,x28,x1
            prog[111] = 32'h09EA2623;  // 1bc: sw x30,140(x20)
            prog[112] = 32'h020E4F33;  // 1c0: div x30,x28,x0
            prog[113] = 32'h09EA2823;  // 1c4: sw x30,144(x20)
            prog[114] = 32'h020E6F33;  // 1c8: rem x30,x28,x0
            prog[115] = 32'h09EA2A23;  // 1cc: sw x30,148(x20)
            prog[116] = 32'h03DE8F33;  // 1d0: mul x30,x29,x29
            prog[117] = 32'h03DF0F33;  // 1d4: mul x30,x30,x29
            prog[118] = 32'h01EF0FB3;  // 1d8: add x31,x30,x30
            prog[119] = 32'h09FA2C23;  // 1dc: sw x31,152(x20)
            prog[120] = 32'h060A2A83;  // 1e0: lw x21,96(x20)
            prog[121] = 32'h03DA8B33;  // 1e4: mul x22,x21,x29
            prog[122] = 32'h096A2E23;  // 1e8: sw x22,156(x20)
            prog[123] = 32'h00200A93;  // 1ec: addi x21,x0,2
            prog[124] = 32'h41502023;  // 1f0: sw x21,1024(x0)
            prog[125] = 32'h41F02423;  // 1f4: sw x31,1032(x0)
            prog[126] = 32'h40C02A83;  // 1f8: lw x21,1036(x0)
            prog[127] = 32'h0B5A2023;  // 1fc: sw x21,160(x20)
            prog[128] = 32'h41C02A83;  // 200: lw x21,1052(x0)
            prog[129] = 32'h0B5A2223;  // 204: sw x21,164(x20)
            prog[130] = 32'h42002A83;  // 208: lw x21,1056(x0)
            prog[131] = 32'h0B5A2423;  // 20c: sw x21,168(x20)
            prog[132] = 32'h05500A93;  // 210: addi x21,x0,85
            prog[133] = 32'h41502A23;  // 214: sw x21,1044(x0)
            prog[134] = 32'h41800A93;  // 218: addi x21,x0,1048 <rx_wait>
            prog[135] = 32'h000AAB03;  // 21c: lw x22,0(x21)
            prog[136] = 32'h100B7B93;  // 220: andi x23,x22,256
            prog[137] = 32'hFE0B8AE3;  // 224: beq x23,x0,218
            prog[138] = 32'h0FFB7B13;  // 228: andi x22,x22,255
            prog[139] = 32'h0B6A2623;  // 22c: sw x22,172(x20)
            prog[140] = 32'h41802B03;  // 230: lw x22,1048(x0)
            prog[141] = 32'h0B6A2823;  // 234: sw x22,176(x20)
            prog[142] = 32'h00010AB7;  // 238: lui x21,0x10
            prog[143] = 32'h001A81A3;  // 23c: sb x1,3(x21)
            prog[144] = 32'h00006AB7;  // 240: lui x21,0x6
            prog[145] = 32'h00DA8A93;  // 244: addi x21,x21,13
            prog[146] = 32'h41502223;  // 248: sw x21,1028(x0)
            prog[147] = 32'h0000006F;  // 24c: jal x0,24c <done>
        end
    endtask

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------
    task expect_eq;
        input [31:0]  got;
        input [31:0]  exp;
        input [255:0] name;
        begin
            if (got !== exp) begin
                $display("[CORE_TB][ERROR] %0s: got %h, expected %h", name, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    task expect_result;
        input integer slot;
        input [31:0]  exp;
        input [255:0] name;
        begin
            expect_eq(dut.DMEM.mem[RESULT_WORD0 + slot], exp, name);
        end
    endtask

    // Resets the system, loads the program through the instruction-memory
    // write port, and runs it until it signals completion.
    task run_program;
        input         with_stalls;
        input [255:0] run_name;
        integer i, cycles;
        begin
            stalls_on = 1'b0;
            rst       = 1'b1;
            for (i = 0; i < 64; i = i + 1)
                dut.DMEM.mem[RESULT_WORD0 + i] = 32'hDEAD_DEAD;
            for (i = 0; i < PROG_WORDS; i = i + 1) begin
                @(negedge clk);
                imem_wr_en = 1'b1; imem_wr_addr = i; imem_wr_data = prog[i];
            end
            @(negedge clk);
            imem_wr_en   = 1'b0;
            stall_cycles = 0;
            stalls_on    = with_stalls;
            @(negedge clk);
            rst = 1'b0;

            // The program polls UART_RX; hand it a byte once it is waiting.
            cycles = 0;
            while ((uart_rx_polls < 3) && (cycles < TIMEOUT)) begin
                @(negedge clk);
                cycles = cycles + 1;
            end
            uart_rx_data = UART_RX_BYTE; uart_rx_valid = 1'b1;
            @(negedge clk);
            uart_rx_valid = 1'b0;

            while ((gpio_dir !== DONE_MARKER) && (cycles < TIMEOUT)) begin
                @(negedge clk);
                cycles = cycles + 1;
            end
            repeat (8) @(negedge clk);

            if (gpio_dir !== DONE_MARKER) begin
                $display("[CORE_TB][ERROR] %0s: program did not finish (pc = %h)", run_name, pc_debug);
                errors = errors + 1;
            end else begin
                check_results;
                $display("[CORE_TB] %0s: finished in %0d cycles, %0d of them stalled",
                         run_name, cycles, stall_cycles);
            end
            stalls_on = 1'b0;
        end
    endtask

    task check_results;
        begin
            expect_result( 0, 32'd12,         "add");
            expect_result( 1, 32'd7,          "sub");
            expect_result( 2, 32'd11,         "xor");
            expect_result( 3, 32'd15,         "or");
            expect_result( 4, 32'd7,          "and");
            expect_result( 5, 32'd80,         "slli");
            expect_result( 6, 32'hF800_0000,  "srai");
            expect_result( 7, 32'h0800_0000,  "srli");
            expect_result( 8, 32'd1,          "slt");
            expect_result( 9, 32'd0,          "sltu");
            expect_result(10, 32'hFFFF_FFFA,  "xori");
            expect_result(11, 32'd1,          "slti");
            expect_result(12, 32'd0,          "sltiu");
            expect_result(13, 32'h0000_0075,  "ori");
            expect_result(14, 32'd9,          "andi");
            expect_result(15, 32'h0000_0088,  "auipc");

            expect_result(16, 32'hF433_2211,  "sb x4 then lw");
            expect_result(17, 32'hFFFF_FFF4,  "lb");
            expect_result(18, 32'h0000_00F4,  "lbu");
            expect_result(19, 32'hCAFE_BEEF,  "sh x2 then lw");
            expect_result(20, 32'hFFFF_CAFE,  "lh");
            expect_result(21, 32'h0000_CAFE,  "lhu");
            expect_result(22, 32'hF433_2212,  "load then dependent addi");
            expect_result(23, 32'hF433_2211,  "load then dependent store");

            expect_result(24, 32'd55,         "loop sum 1..10");
            expect_result(25, 32'd7,          "conditional branches");
            expect_result(26, 32'h0000_0123,  "jal/jalr call executed");
            expect_result(27, 32'h0000_0160,  "jal link address");

            expect_result(28, 32'hFFFF_FFEB,  "mul");
            expect_result(29, 32'd3,          "mulh");
            expect_result(30, 32'h7FFF_FFFC,  "mulhu");
            expect_result(31, 32'hFFFF_FFFC,  "mulhsu");
            expect_result(32, 32'hFFFF_FFFE,  "div");
            expect_result(33, 32'hFFFF_FFFF,  "rem");
            expect_result(34, 32'h5555_5553,  "divu");
            expect_result(35, 32'd4,          "remu");
            expect_result(36, 32'hFFFF_FFFF,  "div by zero");
            expect_result(37, 32'hFFFF_FFF9,  "rem by zero");
            expect_result(38, 32'd54,         "mul feeding mul feeding add");
            expect_result(39, 32'd165,        "load feeding mul");

            expect_result(40, GPIO_IN_VAL,    "GPIO_IN read");
            expect_result(41, 32'd0,          "KEY1 read");
            expect_result(42, 32'd1,          "KEY2 read");
            expect_result(43, {24'd0, UART_RX_BYTE},  "UART_RX polled byte");
            expect_result(44, {24'd0, UART_RX_BYTE},  "UART_RX flag cleared by the read");

            expect_eq(led_wr_data,   5'd2,          "LED register");
            expect_eq(led_writes,    1,             "LED written once");
            expect_eq(gpio_out,      32'd54,        "GPIO_OUT register");
            expect_eq(uart_tx_count, 1,             "UART_TX started once");
            expect_eq(uart_tx_last,  8'h55,         "UART_TX byte");
            expect_eq(mmio_stores,   4,             "MMIO store count");
            expect_eq(fb_stores,     1,             "framebuffer store count");
            expect_eq(fb_last_addr,  32'h0001_0003, "framebuffer store address");
            expect_eq(fb_last_data[7:0], 8'd5,      "framebuffer store data");
        end
    endtask

    // -------------------------------------------------------------------------
    // Test sequence
    // -------------------------------------------------------------------------
    initial begin
        if (USE_PAYLOAD) begin
            repeat (4) @(negedge clk);
            rst = 1'b0;
            repeat (PAYLOAD_CYCLES) @(negedge clk);
            $display("[CORE_TB] payload run: pc = %h, %0d MMIO stores, %0d framebuffer stores",
                     pc_debug, mmio_stores, fb_stores);
            if ((^pc_debug === 1'bx) || (mmio_stores + fb_stores == 0)) begin
                $display("[CORE_TB][ERROR] payload produced no MMIO or framebuffer activity");
                errors = errors + 1;
            end
        end else begin
            init_program;
            run_program(1'b0, "free run");
            run_program(1'b1, "run with random stalls");
        end

        if (errors == 0)
            $display("[CORE_TB][PASS] all core checks passed");
        else
            $display("[CORE_TB][FAIL] %0d errors", errors);
        $finish;
    end
endmodule
