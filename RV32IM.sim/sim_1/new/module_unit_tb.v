`timescale 1ns / 1ps

module module_unit_tb;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg [7:0] phase = 8'd0;

    integer errors;

    always #5 clk = ~clk;

    // ---------- ALU ----------
    reg [31:0] alu_a;
    reg [31:0] alu_b;
    reg [4:0]  alu_op;
    wire [31:0] alu_result;
    wire        alu_branch;

    alu alu_dut (
        .a(alu_a),
        .b(alu_b),
        .alu_op(alu_op),
        .result(alu_result),
        .branch_sel(alu_branch)
    );

    // ---------- Decoder ----------
    reg [31:0] dec_inst;
    wire [6:0] dec_opcode;
    wire [4:0] dec_rd;
    wire [2:0] dec_funct3;
    wire [4:0] dec_rs1;
    wire [4:0] dec_rs2;
    wire [6:0] dec_funct7;

    instruction_decoder dec_dut (
        .inst(dec_inst),
        .opcode(dec_opcode),
        .rd(dec_rd),
        .funct3(dec_funct3),
        .rs1(dec_rs1),
        .rs2(dec_rs2),
        .funct7(dec_funct7)
    );

    // ---------- Immediate control ----------
    reg [31:0] imm_instr;
    reg [2:0]  imm_typ;
    wire [31:0] imm_32;

    immediate_control imm_dut (
        .instr(imm_instr),
        .imm_typ(imm_typ),
        .imm_32(imm_32)
    );

    // ---------- Control signals ----------
    reg [6:0] ctrl_opcode;
    reg [2:0] ctrl_func3;
    reg [6:0] ctrl_func7;
    wire [4:0] ctrl_alu_op;
    wire       ctrl_alu_mem_mux_sel;
    wire [1:0] ctrl_alua_mux_sel;
    wire [1:0] ctrl_alub_mux_sel;
    wire       ctrl_reg_w_en;
    wire [1:0] ctrl_mem_w_en;
    wire [2:0] ctrl_read_mem;
    wire [2:0] ctrl_imm_typ;
    wire [1:0] ctrl_pc_mux_sel;

    control_signals ctrl_dut (
        .opcode(ctrl_opcode),
        .func3(ctrl_func3),
        .func7(ctrl_func7),
        .alu_op(ctrl_alu_op),
        .alu_mem_mux_sel(ctrl_alu_mem_mux_sel),
        .alua_mux_sel(ctrl_alua_mux_sel),
        .alub_mux_sel(ctrl_alub_mux_sel),
        .reg_w_en(ctrl_reg_w_en),
        .mem_w_en(ctrl_mem_w_en),
        .read_mem(ctrl_read_mem),
        .imm_typ(ctrl_imm_typ),
        .pc_mux_sel(ctrl_pc_mux_sel)
    );

    // ---------- Program counter ----------
    reg        pc_redirect;
    reg [31:0] pc_redirect_target;
    reg        pc_stall;
    reg        pc_predict_taken;
    reg [31:0] pc_predict_target;
    reg [31:0] pc_fallback_pc;
    wire [31:0] pc_out;

    program_counter pc_dut (
        .clk(clk),
        .rst(rst),
        .redirect(pc_redirect),
        .redirect_target(pc_redirect_target),
        .stall(pc_stall),
        .predict_taken(pc_predict_taken),
        .predict_target(pc_predict_target),
        .fallback_pc(pc_fallback_pc),
        .pc(pc_out)
    );

    // ---------- Branch predictor ----------
    reg [31:0] bp_pred_pc;
    wire [3:0] bp_pred_index;
    wire       bp_pred_taken;
    reg        bp_upd_en;
    reg [3:0]  bp_upd_index;
    reg        bp_upd_taken;

    branch_predictor #(
        .GHR_BITS(4),
        .IDX_BITS(4)
    ) bp_dut (
        .clk(clk),
        .rst(rst),
        .pred_pc(bp_pred_pc),
        .pred_index(bp_pred_index),
        .pred_taken(bp_pred_taken),
        .upd_en(bp_upd_en),
        .upd_index(bp_upd_index),
        .upd_taken(bp_upd_taken)
    );

    // ---------- Dependence + bypass ----------
    reg        haz_idex_is_load;
    reg [4:0]  haz_idex_rd;
    reg [4:0]  haz_ifid_rs1;
    reg [4:0]  haz_ifid_rs2;
    wire       haz_stall;

    dependence_unit haz_dut (
        .idex_is_load(haz_idex_is_load),
        .idex_rd(haz_idex_rd),
        .ifid_rs1(haz_ifid_rs1),
        .ifid_rs2(haz_ifid_rs2),
        .stall(haz_stall)
    );

    reg [4:0]  f_idex_rs1;
    reg [4:0]  f_idex_rs2;
    reg [4:0]  f_exmem_rd;
    reg        f_exmem_reg_w_en;
    reg [4:0]  f_memwb_rd;
    reg        f_memwb_reg_w_en;
    wire [1:0] fwdA;
    wire [1:0] fwdB;

    bypass_unit fwd_dut (
        .idex_rs1(f_idex_rs1),
        .idex_rs2(f_idex_rs2),
        .exmem_rd(f_exmem_rd),
        .exmem_reg_w_en(f_exmem_reg_w_en),
        .memwb_rd(f_memwb_rd),
        .memwb_reg_w_en(f_memwb_reg_w_en),
        .forwardA(fwdA),
        .forwardB(fwdB)
    );

    // ---------- Register file ----------
    reg        rf_w_en;
    reg [4:0]  rf_rs1;
    reg [4:0]  rf_rs2;
    reg [4:0]  rf_rd;
    reg [31:0] rf_w_data;
    reg [4:0]  rf_dbg_addr;
    wire [31:0] rf_r_data1;
    wire [31:0] rf_r_data2;
    wire [31:0] rf_dbg_data;

    register_file rf_dut (
        .rst(rst),
        .clk(clk),
        .w_en(rf_w_en),
        .rs1(rf_rs1),
        .rs2(rf_rs2),
        .rd(rf_rd),
        .w_data(rf_w_data),
        .r_data1(rf_r_data1),
        .r_data2(rf_r_data2),
        .dbg_addr(rf_dbg_addr),
        .dbg_data(rf_dbg_data)
    );

    // ---------- Data memory ----------
    reg [2:0]  dm_read_mem;
    reg [1:0]  dm_mem_w_en;
    reg [31:0] dm_addr;
    reg [31:0] dm_w_data;
    wire [31:0] dm_r_data;
    wire        dm_mmio_region;
    wire        dm_mmio_wr_en;

    data_memory dm_dut (
        .clk(clk),
        .read_mem(dm_read_mem),
        .mem_w_en(dm_mem_w_en),
        .addr(dm_addr),
        .w_data(dm_w_data),
        .r_data(dm_r_data),
        .mmio_region(dm_mmio_region),
        .mmio_wr_en(dm_mmio_wr_en)
    );

    // ---------- MMIO ----------
    reg [31:0] mm_addr;
    reg        mm_mmio_wr_en;
    reg        mm_mmio_rd_en;
    reg [1:0]  mm_mem_w_en;
    reg [31:0] mm_w_data;
    wire [31:0] mm_r_data;

    wire       mm_led_wr_en;
    wire [4:0] mm_led_wr_data;
    reg        mm_key1;
    reg        mm_key2;

    reg        mm_uart_rx_valid;
    reg [7:0]  mm_uart_rx_data;
    reg        mm_uart_tx_busy;
    wire       mm_uart_tx_start;
    wire [7:0] mm_uart_tx_data;

    reg [31:0] mm_gpio_in;
    wire [31:0] mm_gpio_dir;
    wire [31:0] mm_gpio_out;
    wire [31:0] mm_gpio_en;

    mmio mmio_dut (
        .clk(clk),
        .rst(rst),
        .addr(mm_addr),
        .mmio_wr_en(mm_mmio_wr_en),
        .mmio_rd_en(mm_mmio_rd_en),
        .mem_w_en(mm_mem_w_en),
        .w_data(mm_w_data),
        .r_data(mm_r_data),
        .led_wr_en(mm_led_wr_en),
        .led_wr_data(mm_led_wr_data),
        .key1(mm_key1),
        .key2(mm_key2),
        .uart_rx_valid(mm_uart_rx_valid),
        .uart_rx_data(mm_uart_rx_data),
        .uart_tx_busy(mm_uart_tx_busy),
        .uart_tx_start(mm_uart_tx_start),
        .uart_tx_data(mm_uart_tx_data),
        .gpio_in(mm_gpio_in),
        .gpio_dir(mm_gpio_dir),
        .gpio_out(mm_gpio_out),
        .gpio_en(mm_gpio_en)
    );

    // ---------- UART ----------
    reg [7:0] uart_tx_data_in;
    reg       uart_tx_start_in;
    wire      uart_tx_line;
    wire      uart_tx_busy_out;

    wire [7:0] uart_rx_data_out;
    wire       uart_rx_valid_out;

    uart_tx #(
        .CLK_FREQ_HZ(100000000),
        .BAUD_RATE(10000000)
    ) uart_tx_dut (
        .clk(clk),
        .rst(rst),
        .data(uart_tx_data_in),
        .start(uart_tx_start_in),
        .tx(uart_tx_line),
        .busy(uart_tx_busy_out)
    );

    uart_rx #(
        .CLK_FREQ_HZ(100000000),
        .BAUD_RATE(10000000)
    ) uart_rx_dut (
        .clk(clk),
        .rst(rst),
        .rx(uart_tx_line),
        .data(uart_rx_data_out),
        .data_valid(uart_rx_valid_out)
    );

    task expect_eq32;
        input [31:0] got;
        input [31:0] exp;
        input [255:0] tag;
        begin
            if (got !== exp) begin
                $display("[UNIT_TB][ERROR] %0s got=%h exp=%h", tag, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    task expect_true;
        input cond;
        input [255:0] tag;
        begin
            if (!cond) begin
                $display("[UNIT_TB][ERROR] %0s", tag);
                errors = errors + 1;
            end
        end
    endtask

    task step_phase;
        input [7:0] new_phase;
        begin
            phase = new_phase;
            repeat (2) @(posedge clk);
        end
    endtask

    initial begin
        errors = 0;
        phase = 8'd0;

        // Defaults
        alu_a = 0; alu_b = 0; alu_op = 0;
        dec_inst = 0;
        imm_instr = 0; imm_typ = 0;
        ctrl_opcode = 0; ctrl_func3 = 0; ctrl_func7 = 0;
        pc_redirect = 0; pc_redirect_target = 0; pc_stall = 0; pc_predict_taken = 0; pc_predict_target = 0; pc_fallback_pc = 0;
        bp_pred_pc = 0; bp_upd_en = 0; bp_upd_index = 0; bp_upd_taken = 0;
        haz_idex_is_load = 0; haz_idex_rd = 0; haz_ifid_rs1 = 0; haz_ifid_rs2 = 0;
        f_idex_rs1 = 0; f_idex_rs2 = 0; f_exmem_rd = 0; f_exmem_reg_w_en = 0; f_memwb_rd = 0; f_memwb_reg_w_en = 0;
        rf_w_en = 0; rf_rs1 = 0; rf_rs2 = 0; rf_rd = 0; rf_w_data = 0; rf_dbg_addr = 0;
        dm_read_mem = 0; dm_mem_w_en = 0; dm_addr = 0; dm_w_data = 0;
        mm_addr = 0; mm_mmio_wr_en = 0; mm_mmio_rd_en = 0; mm_mem_w_en = 0; mm_w_data = 0; mm_key1 = 1'b1; mm_key2 = 1'b1; mm_uart_rx_valid = 0; mm_uart_rx_data = 0; mm_uart_tx_busy = 0; mm_gpio_in = 32'hA5A5_5A5A;
        uart_tx_data_in = 0; uart_tx_start_in = 0;

        repeat (5) @(posedge clk);
        rst <= 1'b0;
        repeat (2) @(posedge clk);

        // ALU
        step_phase(8'd1);
        alu_a = 32'd11; alu_b = 32'd7; alu_op = 5'b00000; @(posedge clk); #1; expect_eq32(alu_result, 32'd18, "alu add");
        alu_op = 5'b00001; @(posedge clk); #1; expect_eq32(alu_result, 32'd4, "alu sub");
        alu_op = 5'b00010; @(posedge clk); #1; expect_eq32(alu_result, 32'd3, "alu and");
        alu_op = 5'b00011; @(posedge clk); #1; expect_eq32(alu_result, 32'd15, "alu or");
        alu_op = 5'b00100; @(posedge clk); #1; expect_eq32(alu_result, 32'd12, "alu xor");
        alu_op = 5'b00101; @(posedge clk); #1; expect_eq32(alu_result, 32'd1408, "alu sll");
        alu_op = 5'b00110; @(posedge clk); #1; expect_eq32(alu_result, 32'd0, "alu slt false");
        alu_op = 5'b00111; @(posedge clk); #1; expect_eq32(alu_result, 32'd0, "alu sltu false");
        alu_op = 5'b01000; @(posedge clk); #1; expect_eq32(alu_result, 32'd0, "alu srl");
        alu_op = 5'b01011; @(posedge clk); #1; expect_true(alu_branch == 1'b0, "alu beq false");
        alu_a = 32'hFFFF_FFFF; alu_b = 32'hFFFF_FFFF; @(posedge clk); #1; expect_true(alu_branch == 1'b1, "alu beq true");
        alu_op = 5'b01001; @(posedge clk); #1; expect_eq32(alu_result, 32'hFFFF_FFFF, "alu sra");
        alu_a = 32'h0000_0011; alu_b = 32'h0000_0007; alu_op = 5'b01010; @(posedge clk); #1; expect_eq32(alu_result, 32'h0000_0018, "alu jalr align");
        alu_op = 5'b01100; @(posedge clk); #1; expect_true(alu_branch == 1'b1, "alu bne true");
        alu_a = 32'hFFFF_FFFF; alu_b = 32'd1; alu_op = 5'b01101; @(posedge clk); #1; expect_true(alu_branch == 1'b1, "alu blt true");
        alu_op = 5'b01110; @(posedge clk); #1; expect_true(alu_branch == 1'b0, "alu bge false");
        alu_op = 5'b01111; @(posedge clk); #1; expect_true(alu_branch == 1'b0, "alu bltu false");
        alu_op = 5'b10000; @(posedge clk); #1; expect_true(alu_branch == 1'b1, "alu bgeu true");

        // Decoder
        step_phase(8'd2);
        dec_inst = 32'h00C5_0533; @(posedge clk); #1;
        expect_eq32({25'd0, dec_opcode}, 32'h0000_0033, "decoder opcode");
        expect_eq32({27'd0, dec_rd}, 32'd10, "decoder rd");
        expect_eq32({29'd0, dec_funct3}, 32'd0, "decoder funct3");
        expect_eq32({27'd0, dec_rs1}, 32'd10, "decoder rs1");
        expect_eq32({27'd0, dec_rs2}, 32'd12, "decoder rs2");
        expect_eq32({25'd0, dec_funct7}, 32'd0, "decoder funct7");

        // Immediate control
        step_phase(8'd3);
        imm_instr = 32'hFFF1_0113; imm_typ = 3'b000; @(posedge clk); #1; expect_eq32(imm_32, 32'hFFFF_FFFF, "imm i-type");
        imm_instr = 32'h1234_5000; imm_typ = 3'b001; @(posedge clk); #1; expect_eq32(imm_32, 32'h1234_5000, "imm u-type");
        imm_instr = 32'hFE20_AC23; imm_typ = 3'b010; @(posedge clk); #1; expect_eq32(imm_32, 32'hFFFF_FFF8, "imm s-type");
        imm_instr = 32'h0020_8463; imm_typ = 3'b011; @(posedge clk); #1; expect_eq32(imm_32, 32'h0000_0008, "imm b-type");
        imm_instr = 32'h0080_00EF; imm_typ = 3'b100; @(posedge clk); #1; expect_eq32(imm_32, 32'h0000_0008, "imm j-type");
        imm_instr = 32'h4011_5093; imm_typ = 3'b101; @(posedge clk); #1; expect_eq32(imm_32, 32'h0000_0001, "imm shamt7-type");
        imm_instr = 32'hFFFF_FFFF; imm_typ = 3'b111; @(posedge clk); #1; expect_eq32(imm_32, 32'h0000_0000, "imm none");

        // Control signals
        step_phase(8'd4);
        ctrl_opcode = 7'b0010011; ctrl_func3 = 3'b000; ctrl_func7 = 7'b0000000; @(posedge clk); #1;
        expect_true(ctrl_reg_w_en, "ctrl addi writeback");
        ctrl_opcode = 7'b0100011; ctrl_func3 = 3'b010; @(posedge clk); #1;
        expect_eq32({30'd0, ctrl_mem_w_en}, 32'd1, "ctrl sw mem_w_en");
        ctrl_opcode = 7'b0110011; ctrl_func3 = 3'b000; ctrl_func7 = 7'b0100000; @(posedge clk); #1;
        expect_eq32({27'd0, ctrl_alu_op}, 32'd1, "ctrl sub alu op");
        ctrl_opcode = 7'b0110011; ctrl_func3 = 3'b110; ctrl_func7 = 7'b0000001; @(posedge clk); #1;
        expect_eq32({27'd0, ctrl_alu_op}, 32'd23, "ctrl rem alu op");
        ctrl_opcode = 7'b0000011; ctrl_func3 = 3'b001; ctrl_func7 = 7'b0000000; @(posedge clk); #1;
        expect_eq32({29'd0, ctrl_read_mem}, 32'd6, "ctrl lh read code");
        ctrl_opcode = 7'b0000011; ctrl_func3 = 3'b100; ctrl_func7 = 7'b0000000; @(posedge clk); #1;
        expect_eq32({29'd0, ctrl_read_mem}, 32'd3, "ctrl lbu read code");
        ctrl_opcode = 7'b0100011; ctrl_func3 = 3'b000; ctrl_func7 = 7'b0000000; @(posedge clk); #1;
        expect_eq32({30'd0, ctrl_mem_w_en}, 32'd3, "ctrl sb mem_w_en");
        ctrl_opcode = 7'b1101111; ctrl_func3 = 3'b000; ctrl_func7 = 7'b0000000; @(posedge clk); #1;
        expect_eq32({30'd0, ctrl_pc_mux_sel}, 32'd1, "ctrl jal pc mux");
        ctrl_opcode = 7'b1100111; ctrl_func3 = 3'b000; ctrl_func7 = 7'b0000000; @(posedge clk); #1;
        expect_eq32({30'd0, ctrl_pc_mux_sel}, 32'd2, "ctrl jalr pc mux");
        ctrl_opcode = 7'b1100011; ctrl_func3 = 3'b111; ctrl_func7 = 7'b0000000; @(posedge clk); #1;
        expect_eq32({27'd0, ctrl_alu_op}, 32'd16, "ctrl bgeu alu op");

        // Program counter
        step_phase(8'd5);
        pc_fallback_pc = 32'h0000_0004;
        @(posedge clk); #1;
        expect_eq32(pc_out, 32'h0000_0004, "pc fallback");
        pc_stall = 1'b1; pc_fallback_pc = 32'h0000_0008;
        @(posedge clk); #1;
        expect_eq32(pc_out, 32'h0000_0004, "pc stall hold");
        pc_stall = 1'b0; pc_predict_taken = 1'b1; pc_predict_target = 32'h0000_0020;
        @(posedge clk); #1;
        expect_eq32(pc_out, 32'h0000_0020, "pc predict");
        pc_predict_taken = 1'b0; pc_redirect = 1'b1; pc_redirect_target = 32'h0000_0100;
        @(posedge clk); #1;
        expect_eq32(pc_out, 32'h0000_0100, "pc redirect");
        pc_redirect = 1'b0;

        // Branch predictor train taken then not-taken.
        step_phase(8'd6);
        bp_pred_pc = 32'h0000_0040;
        repeat (2) @(posedge clk);
        bp_upd_index = bp_pred_index;
        bp_upd_taken = 1'b1;
        bp_upd_en = 1'b1;
        @(posedge clk);
        bp_upd_en = 1'b0;
        repeat (1) @(posedge clk);
        expect_true(bp_dut.pht[bp_upd_index] == 2'b10, "bp taken state");
        bp_upd_taken = 1'b1;
        bp_upd_en = 1'b1;
        @(posedge clk);
        bp_upd_en = 1'b0;
        repeat (1) @(posedge clk);
        expect_true(bp_dut.pht[bp_upd_index] == 2'b11, "bp saturate high");
        bp_upd_taken = 1'b0;
        bp_upd_en = 1'b1;
        @(posedge clk);
        bp_upd_en = 1'b0;
        bp_upd_taken = 1'b0;
        bp_upd_en = 1'b1;
        @(posedge clk);
        bp_upd_en = 1'b0;
        bp_upd_taken = 1'b0;
        bp_upd_en = 1'b1;
        @(posedge clk);
        bp_upd_en = 1'b0;
        repeat (1) @(posedge clk);
        expect_true(bp_dut.pht[bp_upd_index] == 2'b00, "bp saturate low");

        // Hazard + bypass
        step_phase(8'd7);
        haz_idex_is_load = 1'b1; haz_idex_rd = 5'd8; haz_ifid_rs1 = 5'd8; haz_ifid_rs2 = 5'd1; @(posedge clk); #1;
        expect_true(haz_stall, "hazard stall asserted");
        haz_idex_is_load = 1'b0; haz_idex_rd = 5'd8; haz_ifid_rs1 = 5'd8; haz_ifid_rs2 = 5'd1; @(posedge clk); #1;
        expect_true(haz_stall == 1'b0, "hazard stall clear");

        f_idex_rs1 = 5'd3; f_idex_rs2 = 5'd4; f_exmem_rd = 5'd3; f_exmem_reg_w_en = 1'b1; f_memwb_rd = 5'd4; f_memwb_reg_w_en = 1'b1; @(posedge clk); #1;
        expect_eq32({30'd0, fwdA}, 32'd1, "bypass A exmem");
        expect_eq32({30'd0, fwdB}, 32'd2, "bypass B memwb");
        f_idex_rs1 = 5'd1; f_idex_rs2 = 5'd2; f_exmem_rd = 5'd0; f_exmem_reg_w_en = 1'b1; f_memwb_rd = 5'd0; f_memwb_reg_w_en = 1'b1; @(posedge clk); #1;
        expect_eq32({30'd0, fwdA}, 32'd0, "bypass A none");
        expect_eq32({30'd0, fwdB}, 32'd0, "bypass B none");

        // Register file
        step_phase(8'd8);
        rf_rd = 5'd9; rf_w_data = 32'hDEAD_BEEF; rf_w_en = 1'b1;
        @(posedge clk);
        rf_w_en = 1'b0; rf_rs1 = 5'd9; rf_dbg_addr = 5'd9;
        @(posedge clk); #1;
        expect_eq32(rf_r_data1, 32'hDEAD_BEEF, "regfile read");
        expect_eq32(rf_dbg_data, 32'hDEAD_BEEF, "regfile dbg");
        rf_w_en = 1'b1; rf_rd = 5'd0; rf_w_data = 32'h1111_1111; rf_rs1 = 5'd0;
        @(posedge clk); #1;
        rf_w_en = 1'b0;
        expect_eq32(rf_r_data1, 32'h0000_0000, "regfile x0 hardwired");

        // Data memory writes/reads + mmio decode
        step_phase(8'd9);
        dm_addr = 32'h0000_0020; dm_w_data = 32'h1122_3344; dm_mem_w_en = 2'b01;
        @(posedge clk);
        dm_mem_w_en = 2'b00;
        dm_read_mem = 3'b001; #1;
        expect_eq32(dm_r_data, 32'h1122_3344, "dmem lw");

        dm_addr = 32'h0000_0024; dm_w_data = 32'hAABB_CCDD; dm_mem_w_en = 2'b10;
        @(posedge clk);
        dm_mem_w_en = 2'b00;
        dm_read_mem = 3'b001; #1;
        expect_eq32(dm_r_data, 32'h0000_CCDD, "dmem sh lower half");

        dm_addr = 32'h0000_0028; dm_w_data = 32'h0000_00F2; dm_mem_w_en = 2'b11;
        @(posedge clk);
        dm_mem_w_en = 2'b00;
        dm_read_mem = 3'b111; #1;
        expect_eq32(dm_r_data, 32'hFFFF_FFF2, "dmem lb sign extend");
        dm_read_mem = 3'b011; #1;
        expect_eq32(dm_r_data, 32'h0000_00F2, "dmem lbu zero extend");
        dm_addr = 32'h0000_0024; dm_read_mem = 3'b110; #1;
        expect_eq32(dm_r_data, 32'hFFFF_CCDD, "dmem lh sign extend");
        dm_read_mem = 3'b010; #1;
        expect_eq32(dm_r_data, 32'h0000_CCDD, "dmem lhu zero extend");

        // sb/sh into the upper byte lanes of the word at 0x28
        dm_addr = 32'h0000_0029; dm_w_data = 32'h0000_005A; dm_mem_w_en = 2'b11;
        @(posedge clk);
        dm_mem_w_en = 2'b00; #1;
        dm_addr = 32'h0000_002A; dm_w_data = 32'h0000_BEEF; dm_mem_w_en = 2'b10;
        @(posedge clk);
        dm_mem_w_en = 2'b00;
        dm_addr = 32'h0000_0028; dm_read_mem = 3'b001; #1;
        expect_eq32(dm_r_data, 32'hBEEF_5AF2, "dmem sb/sh upper lanes");

        dm_addr = 32'h0001_0000; dm_read_mem = 3'b001; #1;
        expect_eq32(dm_r_data, 32'h0000_0000, "dmem out-of-range read zero");

        dm_addr = 32'h0000_0400; dm_mem_w_en = 2'b01; #1;
        expect_true(dm_mmio_region, "dmem mmio region");
        expect_true(dm_mmio_wr_en, "dmem mmio wr_en");
        dm_mem_w_en = 2'b00;

        // MMIO register behavior
        step_phase(8'd10);
        mm_addr = 32'h0000_0400; mm_w_data = 32'd2; mm_mmio_wr_en = 1'b1; mm_mem_w_en = 2'b01;
        @(posedge clk); #1;
        expect_true(mm_led_wr_en == 1'b1, "mmio led pulse asserted");
        mm_mmio_wr_en = 1'b0;
        @(posedge clk); #1;
        expect_true(mm_led_wr_en == 1'b0, "mmio led pulse one-shot");
        mm_addr = 32'h0000_0400; #1; expect_eq32(mm_r_data, 32'd2, "mmio led readback");

        mm_addr = 32'h0000_0404; mm_w_data = 32'hFFFF_0000; mm_mmio_wr_en = 1'b1;
        @(posedge clk); mm_mmio_wr_en = 1'b0; #1;
        expect_eq32(mm_gpio_dir, 32'hFFFF_0000, "mmio gpio dir");

        mm_addr = 32'h0000_0408; mm_w_data = 32'h1234_5678; mm_mmio_wr_en = 1'b1;
        @(posedge clk); mm_mmio_wr_en = 1'b0; #1;
        expect_eq32(mm_gpio_out, 32'h1234_5678, "mmio gpio out");

        mm_addr = 32'h0000_0410; mm_w_data = 32'h00FF_00FF; mm_mmio_wr_en = 1'b1;
        @(posedge clk); mm_mmio_wr_en = 1'b0; #1;
        expect_eq32(mm_gpio_en, 32'h00FF_00FF, "mmio gpio enable");

        mm_addr = 32'h0000_040C; #1;
        expect_eq32(mm_r_data, 32'hA5A5_5A5A, "mmio gpio input read");

        mm_addr = 32'h0000_0418; mm_uart_rx_data = 8'h5A; mm_uart_rx_valid = 1'b1;
        @(posedge clk); #1; mm_uart_rx_valid = 1'b0;
        @(posedge clk); #1;
        expect_true(mm_r_data[8], "mmio uart rx valid sticky");
        expect_eq32({24'd0, mm_r_data[7:0]}, 32'h0000_005A, "mmio uart rx data");
        mm_mmio_rd_en = 1'b1;
        @(posedge clk); #1;
        mm_mmio_rd_en = 1'b0;
        expect_true(mmio_dut.uart_rx_valid_reg == 1'b0, "mmio uart rx clear-on-read");

        mm_addr = 32'h0000_0414; mm_w_data = 32'h0000_00C3; mm_mmio_wr_en = 1'b1;
        @(posedge clk); #1;
        expect_true(mm_uart_tx_start, "mmio uart tx pulse");
        expect_eq32({24'd0, mm_uart_tx_data}, 32'h0000_00C3, "mmio uart tx payload");
        mm_mmio_wr_en = 1'b0;

        mm_uart_tx_busy = 1'b1;
        mm_addr = 32'h0000_0414; mm_w_data = 32'h0000_0044; mm_mmio_wr_en = 1'b1;
        @(posedge clk); #1;
        expect_true(mm_uart_tx_start == 1'b0, "mmio uart tx blocked when busy");
        mm_mmio_wr_en = 1'b0;
        mm_uart_tx_busy = 1'b0;

        mm_key1 = 1'b0; mm_key2 = 1'b1;
        mm_addr = 32'h0000_041C; #1; expect_eq32(mm_r_data, 32'h0000_0000, "mmio key1 read");
        mm_addr = 32'h0000_0420; #1; expect_eq32(mm_r_data, 32'h0000_0001, "mmio key2 read");

        // UART loopback end-to-end (tx->rx)
        step_phase(8'd11);
        uart_tx_data_in = 8'hA6;
        uart_tx_start_in = 1'b1;
        @(posedge clk);
        uart_tx_start_in = 1'b0;
        wait (uart_rx_valid_out == 1'b1);
        #1;
        expect_eq32({24'd0, uart_rx_data_out}, 32'h0000_00A6, "uart loopback payload");
        wait (uart_tx_busy_out == 1'b0);
        @(posedge clk);
        uart_tx_data_in = 8'h3C;
        uart_tx_start_in = 1'b1;
        @(posedge clk);
        uart_tx_start_in = 1'b0;
        wait (uart_rx_valid_out == 1'b1);
        #1;
        expect_eq32({24'd0, uart_rx_data_out}, 32'h0000_003C, "uart loopback payload 2");

        step_phase(8'd12);
        repeat (16) @(posedge clk);

        if (errors == 0)
            $display("[UNIT_TB][PASS] module-level directed tests passed");
        else
            $display("[UNIT_TB][FAIL] total errors = %0d", errors);

        #20;
        if (errors == 0) $finish;
        else $stop;
    end
endmodule
