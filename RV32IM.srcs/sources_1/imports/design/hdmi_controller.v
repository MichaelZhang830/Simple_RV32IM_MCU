`timescale 1ns / 1ps
//
// HDMI output controller for the A7-LITE board.
// Generates a 1280x720 @ 60 Hz DVI signal (CEA-861) from a CPU-writable
// 8bpp framebuffer.  The on-chip BRAM holds a 480x270 byte frame buffer
// that is scaled 2x and centered in the active area.
//
// CPU interface:
//   vram_addr          byte address within the frame buffer (0 .. 129599)
//   vram_wdata[7:0]    pixel data (8bpp R3G3B2)
//   vram_mem_w_en[1:0] 01=word 10=halfword 11=byte (00=no write)
//

module hdmi_controller (
    // Pixel domain
    input  wire        clk_pixel,
    input  wire        clk_pixel_ser,
    input  wire        clk_serial,
    input  wire        rst_pixel,   // synchronous reset for clk_pixel logic
    input  wire        rst_serial,  // synchronous reset for clk_serial/OSERDES logic

    // TMDS differential outputs
    output wire        tmds_clk_p,
    output wire        tmds_clk_n,
    output wire        tmds_r_p,
    output wire        tmds_r_n,
    output wire        tmds_g_p,
    output wire        tmds_g_n,
    output wire        tmds_b_p,
    output wire        tmds_b_n,

    // CPU-writable frame buffer (CPU clock domain)
    input  wire        vram_clk,
    input  wire [31:0] vram_addr,
    input  wire [31:0] vram_wdata,
    input  wire [1:0]  vram_mem_w_en   // 01=word 10=halfword 11=byte
);

    // ---------------------------------------------------------------------
    // 1280x720 @ 60 Hz timing (CEA-861, nominal 74.25 MHz pixel clock)
    // ---------------------------------------------------------------------
    localparam H_ACTIVE = 11'd1280;
    localparam H_FRONT  = 11'd110;
    localparam H_SYNC   = 11'd40;
    localparam H_BACK   = 11'd220;
    localparam H_TOTAL  = 12'd1650;

    localparam V_ACTIVE = 11'd720;
    localparam V_FRONT  = 11'd5;
    localparam V_SYNC   = 11'd5;
    localparam V_BACK   = 11'd20;
    localparam V_TOTAL  = 11'd750;

    // Scaled-down CPU framebuffer: 480 x 270 (2x scale, centered at 160,90).
    // 480 * 270 = 129,600 bytes -> ~29 36 Kbit BRAMs on XC7A35T.
    localparam FB_WIDTH  = 9'd480;
    localparam FB_HEIGHT = 9'd270;
    localparam H_VIEW_START = 11'd160;
    localparam H_VIEW_END   = 11'd1120;
    localparam V_VIEW_START = 11'd90;
    localparam V_VIEW_END   = 11'd630;

    // ---------------------------------------------------------------------
    // Timing counters
    // ---------------------------------------------------------------------
    reg [11:0] h_count;
    reg [10:0] v_count;

    always @(posedge clk_pixel) begin
        if (rst_pixel) begin
            h_count <= 10'd0;
            v_count <= 10'd0;
        end else begin
            if (h_count == H_TOTAL - 1'b1) begin
                h_count <= 10'd0;
                if (v_count == V_TOTAL - 1'b1)
                    v_count <= 10'd0;
                else
                    v_count <= v_count + 1'b1;
            end else begin
                h_count <= h_count + 1'b1;
            end
        end
    end

    wire h_active = (h_count < H_ACTIVE);
    wire v_active = (v_count < V_ACTIVE);
    wire active   = h_active && v_active;

    wire hsync = (h_count >= (H_ACTIVE + H_FRONT)) &&
                 (h_count <  (H_ACTIVE + H_FRONT + H_SYNC));
    wire vsync = (v_count >= (V_ACTIVE + V_FRONT)) &&
                 (v_count <  (V_ACTIVE + V_FRONT + V_SYNC));

    // ---------------------------------------------------------------------
    // Frame buffer: 480 x 270 bytes, simple dual-port BRAM.
    // Write port: CPU clock domain.  Read port: pixel clock domain.
    // The framebuffer is scaled 2x and centered in the 1280x720 active area.
    // ---------------------------------------------------------------------
    localparam FB_ADDR_BITS = 17;
    localparam FB_WORDS     = (480 * 270) / 4; // 32400 32-bit words (129600 bytes)
    localparam FB_BASE_ADDR = 17'h10000;       // byte address where the framebuffer is mapped

    // Frame buffer implemented as 32-bit wide simple dual-port RAM so that
    // Vivado infers block RAM instead of distributed registers.
    reg [31:0] fb_mem [0:FB_WORDS-1];

    // Video read address (always valid during active video).
    wire fb_visible = active &&
                      (h_count >= H_VIEW_START) && (h_count < H_VIEW_END) &&
                      (v_count >= V_VIEW_START) && (v_count < V_VIEW_END);
    wire [8:0] fb_x = (h_count - H_VIEW_START) >> 1;
    wire [8:0] fb_y = (v_count - V_VIEW_START) >> 1;

    // Pipelined read address to break the 480x270 combinational multiply.
    reg [FB_ADDR_BITS-1:0] rd_addr_p1;
    always @(posedge clk_pixel) begin
        if (rst_pixel)
            rd_addr_p1 <= {FB_ADDR_BITS{1'b0}};
        else if (fb_visible)
            rd_addr_p1 <= fb_y * FB_WIDTH + fb_x;
        else
            rd_addr_p1 <= {FB_ADDR_BITS{1'b0}};
    end
    wire [FB_ADDR_BITS-1:0] rd_addr = rd_addr_p1;

    reg [FB_ADDR_BITS-3:0] rd_word_addr;
    reg [1:0]              rd_byte_sel_p1;
    reg [1:0]              rd_byte_sel_p2;
    reg [31:0]             pixel_word;

    always @(posedge clk_pixel) begin
        if (rst_pixel) begin
            rd_word_addr   <= {(FB_ADDR_BITS-2){1'b0}};
            rd_byte_sel_p1 <= 2'b00;
        end else begin
            rd_word_addr   <= rd_addr[FB_ADDR_BITS-1:2];
            rd_byte_sel_p1 <= rd_addr[1:0];
        end
    end

    always @(posedge clk_pixel) begin
        pixel_word <= fb_mem[rd_word_addr];

        if (rst_pixel)
            rd_byte_sel_p2 <= 2'b00;
        else
            rd_byte_sel_p2 <= rd_byte_sel_p1;
    end

    wire [7:0] pixel = pixel_word[rd_byte_sel_p2 * 8 +: 8];

    // Delay the timing/control signals to match the 3-cycle pixel read latency.
    reg active_d1, active_d2, active_d3;
    reg visible_d1, visible_d2, visible_d3;
    reg hsync_d1,  hsync_d2,  hsync_d3;
    reg vsync_d1,  vsync_d2,  vsync_d3;
    reg [11:0] h_count_d1, h_count_d2, h_count_d3;
    reg [10:0] v_count_d1, v_count_d2, v_count_d3;
    always @(posedge clk_pixel) begin
        if (rst_pixel) begin
            active_d1 <= 1'b0;
            active_d2 <= 1'b0;
            active_d3 <= 1'b0;
            visible_d1 <= 1'b0;
            visible_d2 <= 1'b0;
            visible_d3 <= 1'b0;
            hsync_d1  <= 1'b0;
            hsync_d2  <= 1'b0;
            hsync_d3  <= 1'b0;
            vsync_d1  <= 1'b0;
            vsync_d2  <= 1'b0;
            vsync_d3  <= 1'b0;
            h_count_d1 <= 12'd0;
            h_count_d2 <= 12'd0;
            h_count_d3 <= 12'd0;
            v_count_d1 <= 11'd0;
            v_count_d2 <= 11'd0;
            v_count_d3 <= 11'd0;
        end else begin
            active_d1 <= active;
            active_d2 <= active_d1;
            active_d3 <= active_d2;
            visible_d1 <= fb_visible;
            visible_d2 <= visible_d1;
            visible_d3 <= visible_d2;
            hsync_d1  <= hsync;
            hsync_d2  <= hsync_d1;
            hsync_d3  <= hsync_d2;
            vsync_d1  <= vsync;
            vsync_d2  <= vsync_d1;
            vsync_d3  <= vsync_d2;
            h_count_d1 <= h_count;
            h_count_d2 <= h_count_d1;
            h_count_d3 <= h_count_d2;
            v_count_d1 <= v_count;
            v_count_d2 <= v_count_d1;
            v_count_d3 <= v_count_d2;
        end
    end

    // CPU write port: supports word, halfword and byte writes.
    // The CPU address decode window is 0x0001_0000 - 0x0002_FFFF.  Convert the
    // incoming byte address to a framebuffer offset (0 .. 129599).
    wire [FB_ADDR_BITS-1:0] vram_byte_addr = vram_addr[FB_ADDR_BITS:0] - FB_BASE_ADDR;
    wire [FB_ADDR_BITS-1:2] vram_word_addr = vram_byte_addr[FB_ADDR_BITS-1:2];
    wire [1:0]              vram_byte_sel  = vram_byte_addr[1:0];

    reg [3:0] fb_wen;
    reg [FB_ADDR_BITS-1:2] fb_waddr;
    reg [31:0] fb_wdata;
    reg [3:0] fb_wen_reg;
    reg [FB_ADDR_BITS-1:2] fb_waddr_reg;
    reg [31:0] fb_wdata_reg;

    always @(*) begin
        fb_wen   = 4'b0000;
        fb_waddr = vram_word_addr;
        fb_wdata = 32'b0;
        case (vram_mem_w_en)
            2'b01: begin
                fb_wen   = 4'b1111;
                fb_wdata = vram_wdata;
            end
            2'b10: begin
                fb_wen   = vram_byte_sel[1] ? 4'b1100 : 4'b0011;
                fb_wdata = {2{vram_wdata[15:0]}};
            end
            2'b11: begin
                fb_wen   = 4'b0001 << vram_byte_sel;
                fb_wdata = {4{vram_wdata[7:0]}};
            end
            default: fb_wen = 4'b0000;
        endcase
    end

    always @(posedge vram_clk) begin
        fb_wen_reg   <= fb_wen;
        fb_waddr_reg <= fb_waddr;
        fb_wdata_reg <= fb_wdata;

        if (fb_wen_reg[0]) fb_mem[fb_waddr_reg][7:0]   <= fb_wdata_reg[7:0];
        if (fb_wen_reg[1]) fb_mem[fb_waddr_reg][15:8]  <= fb_wdata_reg[15:8];
        if (fb_wen_reg[2]) fb_mem[fb_waddr_reg][23:16] <= fb_wdata_reg[23:16];
        if (fb_wen_reg[3]) fb_mem[fb_waddr_reg][31:24] <= fb_wdata_reg[31:24];
    end

    // 8bpp R3G3B2 -> 24bpp expansion.
    wire [7:0] r_val = {pixel[7:5], 5'b0};
    wire [7:0] g_val = {pixel[4:2], 5'b0};
    wire [7:0] b_val = {pixel[1:0], 6'b0};

    // ---------------------------------------------------------------------
    // Default pattern if VRAM has not been written (all-zero => black).
    // Draw a simple border so something is visible before the CPU writes.
    // ---------------------------------------------------------------------
    wire border = active_d3 && ((h_count_d3 == 12'd0) || (h_count_d3 == H_ACTIVE - 1'b1) ||
                                (v_count_d3 == 11'd0) || (v_count_d3 == V_ACTIVE - 1'b1));

    wire [7:0] r_out = active_d3 ? (border ? 8'hFF : (visible_d3 ? r_val : 8'h00)) : 8'h00;
    wire [7:0] g_out = active_d3 ? (border ? 8'hFF : (visible_d3 ? g_val : 8'h00)) : 8'h00;
    wire [7:0] b_out = active_d3 ? (border ? 8'hFF : (visible_d3 ? b_val : 8'h00)) : 8'h00;

    // ---------------------------------------------------------------------
    // TMDS encoding
    // ---------------------------------------------------------------------
    wire [9:0] tmds_r, tmds_g, tmds_b;

    dvi_encoder enc_r (
        .clk   (clk_pixel),
        .rst   (rst_pixel),
        .data  (r_out),
        .ctrl  (2'b00),
        .de    (active_d3),
        .tmds  (tmds_r)
    );

    dvi_encoder enc_g (
        .clk   (clk_pixel),
        .rst   (rst_pixel),
        .data  (g_out),
        .ctrl  (2'b00),
        .de    (active_d3),
        .tmds  (tmds_g)
    );

    dvi_encoder enc_b (
        .clk   (clk_pixel),
        .rst   (rst_pixel),
        .data  (b_out),
        .ctrl  ({vsync_d3, hsync_d3}),
        .de    (active_d3),
        .tmds  (tmds_b)
    );

    // ---------------------------------------------------------------------
    // 10:1 serializers for the three colour channels.
    // ---------------------------------------------------------------------
    wire tmds_clk_s, tmds_r_s, tmds_g_s, tmds_b_s;

    serializer_10to1 ser_clk (
        .clk_pixel  (clk_pixel_ser),
        .clk_serial (clk_serial),
        .rst        (rst_serial),
        .parallel   (10'b0000011111),
        .serial     (tmds_clk_s)
    );

    serializer_10to1 ser_r (
        .clk_pixel  (clk_pixel_ser),
        .clk_serial (clk_serial),
        .rst        (rst_serial),
        .parallel   (tmds_r),
        .serial     (tmds_r_s)
    );

    serializer_10to1 ser_g (
        .clk_pixel  (clk_pixel_ser),
        .clk_serial (clk_serial),
        .rst        (rst_serial),
        .parallel   (tmds_g),
        .serial     (tmds_g_s)
    );

    serializer_10to1 ser_b (
        .clk_pixel  (clk_pixel_ser),
        .clk_serial (clk_serial),
        .rst        (rst_serial),
        .parallel   (tmds_b),
        .serial     (tmds_b_s)
    );

    // ---------------------------------------------------------------------
    // Differential output buffers.
    // ---------------------------------------------------------------------
    OBUFDS obuf_clk (
        .I  (tmds_clk_s),
        .O  (tmds_clk_p),
        .OB (tmds_clk_n)
    );

    OBUFDS obuf_r (
        .I  (tmds_r_s),
        .O  (tmds_r_p),
        .OB (tmds_r_n)
    );

    OBUFDS obuf_g (
        .I  (tmds_g_s),
        .O  (tmds_g_p),
        .OB (tmds_g_n)
    );

    OBUFDS obuf_b (
        .I  (tmds_b_s),
        .O  (tmds_b_p),
        .OB (tmds_b_n)
    );

endmodule
