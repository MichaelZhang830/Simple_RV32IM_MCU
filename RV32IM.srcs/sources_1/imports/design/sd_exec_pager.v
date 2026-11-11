`timescale 1ns / 1ps
// SD-backed instruction pager for RV32IM instruction memory.
//
// Paging model:
//   - Physical instruction memory size is fixed at 8 KiB (2048 words).
//   - Program address space is split into 8 KiB pages by PC[31:13].
//   - On boot, page 0 is loaded into instruction memory.
//   - When execution reaches a different page, the core is stalled while the
//     requested page is copied into instruction memory.
//
// Simulation backend:
//   - Reads a raw little-endian binary image from sim/sd_program.bin.
//   - Out-of-range bytes are padded as RISC-V NOP (0x00000013).
//
// Hardware backend:
//   - Uses the vendor SPI-mode SD controller.
//   - SD socket mapping is SPI over SD pins: CMD=MOSI, DAT0=MISO, DAT3=CS.

module sd_exec_pager #(
    parameter integer IMEM_WORDS      = 2048,
    parameter integer PAGE_SHIFT      = 13,
    parameter integer MAX_IMAGE_BYTES = 262144
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        start_boot,
    input  wire [31:0] pc,
    output wire        sd_clk,
    output wire        sd_cs_n,
    input  wire        sd_miso,
    output wire        sd_mosi,

    output wire        hold_core,
    output reg         boot_done,

    output reg         imem_wr_en,
    output reg [10:0]  imem_wr_addr,
    output reg [31:0]  imem_wr_data,

    output reg [18:0]  current_page,
    output reg [15:0]  page_load_count,
    output reg         page_load_pulse,
    output reg         image_load_error
);
    localparam [31:0] NOP = 32'h00000013;
    localparam integer PAGE_BYTES   = IMEM_WORDS * 4;
    localparam integer PAGE_SECTORS = PAGE_BYTES / 512;

    localparam [1:0] S_IDLE = 2'd0;
    localparam [1:0] S_LOAD = 2'd1;

    reg [1:0] state;

    reg [18:0] target_page;
    reg [10:0] load_word_idx;
    reg        boot_pending;
    reg        image_loaded;
    integer    image_size_bytes;

`ifdef SIMULATION
    assign sd_clk  = 1'b0;
    assign sd_cs_n = 1'b1;
    assign sd_mosi = 1'b1;

    reg [7:0] image_mem [0:MAX_IMAGE_BYTES-1];
    integer fd;
    integer i;
    integer byte_base;

    task automatic load_image_once;
        begin
            if (!image_loaded) begin
                fd = $fopen("sim/sd_program.bin", "rb");
                if (fd == 0) fd = $fopen("../sim/sd_program.bin", "rb");
                if (fd == 0) fd = $fopen("../../sim/sd_program.bin", "rb");

                if (fd == 0) begin
                    image_size_bytes = 0;
                    image_load_error = 1'b1;
                end else begin
                    image_size_bytes = $fread(image_mem, fd);
                    $fclose(fd);
                    image_load_error = 1'b0;
                end

                if (image_size_bytes > MAX_IMAGE_BYTES)
                    image_size_bytes = MAX_IMAGE_BYTES;

                for (i = image_size_bytes; i < MAX_IMAGE_BYTES; i = i + 1)
                    image_mem[i] = 8'h13;

                image_loaded = 1'b1;
            end
        end
    endtask
`else
    wire       hw_init_done;
    reg        hw_rd_start;
    reg [31:0] hw_rd_sec_addr;
    wire       hw_rd_data_valid;
    wire [7:0] hw_rd_data;
    wire       hw_rd_done;
    wire       hw_sd_busy;
    reg [3:0]  sector_idx;
    reg        sector_active;
    reg [1:0]  byte_idx;
    reg [7:0]  byte_lane0;
    reg [7:0]  byte_lane1;
    reg [7:0]  byte_lane2;

    sd_ctrl #(
        .SYS_FRENCY (50_000_000),
        .INIT_FRENCY(250_000)
    ) sd_ctrl_inst (
        .clk             (clk),
        .rst_n           (~rst),
        .sd_clk          (sd_clk),
        .sd_cs_n         (sd_cs_n),
        .sd_miso         (sd_miso),
        .sd_mosi         (sd_mosi),
        .init_done       (hw_init_done),
        .sd_wr_start     (1'b0),
        .sd_wr_data_req  (),
        .sd_wr_sec_addr  (32'd0),
        .sd_wr_data      (8'd0),
        .sd_wr_done      (),
        .sd_rd_start     (hw_rd_start),
        .sd_rd_sec_addr  (hw_rd_sec_addr),
        .sd_rd_data_valid(hw_rd_data_valid),
        .sd_rd_data      (hw_rd_data),
        .sd_rd_done      (hw_rd_done),
        .sd_busy         (hw_sd_busy)
    );
`endif

    wire [18:0] pc_page = pc[31:PAGE_SHIFT];
    wire page_miss_req  = boot_done && (pc_page != current_page);

    // imem_wr_en is registered, so the last word of a page is written one
    // cycle after S_LOAD is left; keep the core held for that cycle too.
    assign hold_core = (!boot_done) || (state == S_LOAD) || page_miss_req || boot_pending ||
                       imem_wr_en;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state            <= S_IDLE;
            boot_done        <= 1'b0;
            imem_wr_en       <= 1'b0;
            imem_wr_addr     <= 11'd0;
            imem_wr_data     <= 32'd0;
            current_page     <= 19'd0;
            target_page      <= 19'd0;
            load_word_idx    <= 11'd0;
            boot_pending     <= 1'b0;
            page_load_count  <= 16'd0;
            page_load_pulse  <= 1'b0;
            image_loaded     <= 1'b0;
            image_size_bytes <= 0;
            image_load_error <= 1'b0;
`ifndef SIMULATION
            hw_rd_start      <= 1'b0;
            hw_rd_sec_addr   <= 32'd0;
            sector_idx       <= 4'd0;
            sector_active    <= 1'b0;
            byte_idx         <= 2'd0;
            byte_lane0       <= 8'd0;
            byte_lane1       <= 8'd0;
            byte_lane2       <= 8'd0;
`endif
        end else begin
            if (start_boot)
                boot_pending <= 1'b1;

            page_load_pulse <= 1'b0;
            imem_wr_en      <= 1'b0;
`ifndef SIMULATION
            hw_rd_start     <= 1'b0;
`endif

            case (state)
                S_IDLE: begin
`ifdef SIMULATION
                    if (!boot_done && boot_pending) begin
                        load_image_once();
                        target_page   <= 19'd0;
                        load_word_idx <= 11'd0;
                        boot_pending  <= 1'b0;
                        state         <= S_LOAD;
                    end else if (page_miss_req) begin
                        target_page   <= pc_page;
                        load_word_idx <= 11'd0;
                        state         <= S_LOAD;
                    end
`else
                    if (!boot_done && boot_pending && hw_init_done) begin
                        target_page   <= 19'd0;
                        load_word_idx <= 11'd0;
                        sector_idx    <= 4'd0;
                        sector_active <= 1'b0;
                        byte_idx      <= 2'd0;
                        boot_pending  <= 1'b0;
                        state         <= S_LOAD;
                    end else if (page_miss_req && hw_init_done) begin
                        target_page   <= pc_page;
                        load_word_idx <= 11'd0;
                        sector_idx    <= 4'd0;
                        sector_active <= 1'b0;
                        byte_idx      <= 2'd0;
                        state         <= S_LOAD;
                    end
`endif
                end

                S_LOAD: begin
`ifdef SIMULATION
                    imem_wr_en   <= 1'b1;
                    imem_wr_addr <= load_word_idx;
                    byte_base = (target_page * PAGE_BYTES) + (load_word_idx * 4);
                    if ((byte_base >= 0) && ((byte_base + 3) < image_size_bytes)) begin
                        imem_wr_data <= {
                            image_mem[byte_base + 3],
                            image_mem[byte_base + 2],
                            image_mem[byte_base + 1],
                            image_mem[byte_base + 0]
                        };
                    end else begin
                        imem_wr_data <= NOP;
                    end

                    if (load_word_idx == IMEM_WORDS - 1) begin
                        state           <= S_IDLE;
                        current_page    <= target_page;
                        boot_done       <= 1'b1;
                        page_load_count <= page_load_count + 1'b1;
                        page_load_pulse <= 1'b1;
                        load_word_idx   <= 11'd0;
                    end else begin
                        load_word_idx <= load_word_idx + 1'b1;
                    end
`else
                    if (!sector_active && !hw_sd_busy && hw_init_done) begin
                        hw_rd_start    <= 1'b1;
                        hw_rd_sec_addr <= ({13'd0, target_page} << 4) + sector_idx;
                        sector_active  <= 1'b1;
                    end

                    if (hw_rd_data_valid) begin
                        case (byte_idx)
                            2'd0: begin
                                byte_lane0 <= hw_rd_data;
                                byte_idx   <= 2'd1;
                            end
                            2'd1: begin
                                byte_lane1 <= hw_rd_data;
                                byte_idx   <= 2'd2;
                            end
                            2'd2: begin
                                byte_lane2 <= hw_rd_data;
                                byte_idx   <= 2'd3;
                            end
                            default: begin
                                imem_wr_en    <= 1'b1;
                                imem_wr_addr  <= load_word_idx;
                                imem_wr_data  <= {hw_rd_data, byte_lane2, byte_lane1, byte_lane0};
                                load_word_idx <= load_word_idx + 1'b1;
                                byte_idx      <= 2'd0;
                            end
                        endcase
                    end

                    if (hw_rd_done) begin
                        sector_active <= 1'b0;
                        if (sector_idx == PAGE_SECTORS - 1) begin
                            state           <= S_IDLE;
                            current_page    <= target_page;
                            boot_done       <= 1'b1;
                            page_load_count <= page_load_count + 1'b1;
                            page_load_pulse <= 1'b1;
                            load_word_idx   <= 11'd0;
                            sector_idx      <= 4'd0;
                        end else begin
                            sector_idx <= sector_idx + 1'b1;
                        end
                    end
`endif
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end
endmodule
