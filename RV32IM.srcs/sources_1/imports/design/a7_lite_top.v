`timescale 1ns / 1ps
//
// A7-LITE (XC7A35T-FGG484) top-level wrapper for the RV32IM core.
//
// Peripherals:
//   - USB-UART (115200 baud) available through runtime MMIO
//   - 2 user LEDs
//   - 2 user keys (active-low) and dedicated reset button
//   - 32-bit GPIO header
//   - 1280x720 HDMI output driven from a CPU-writable 480x270 framebuffer
//

module a7_lite_top (
    input  wire        w_clk,        // 50 MHz

    // Dedicated active-low reset push-button (K3 -> L18)
    input  wire        reset_n,

    // USB-UART CH340
    input  wire        uart_rx,
    output wire        uart_tx,

    // SD card interface
    output wire        sd_clk,
    output wire        sd_cmd,
    input  wire        sd_data0,
    inout  wire        sd_data1,
    inout  wire        sd_data2,
    output wire        sd_data3,

    // User keys active-low
    input  wire        key1,
    input  wire        key2,

    // User LEDs (active-high)
    output wire        w_led1,
    output wire        w_led2,

    // GPIO header
    inout  wire [31:0] gpio_pins,

    // Unused header pins for analog front end
    output wire [11:0] gpio_nc,

    // HDMI TMDS differential outputs
    output wire        tmds_clk_p,
    output wire        tmds_clk_n,
    output wire        tmds_r_p,
    output wire        tmds_r_n,
    output wire        tmds_g_p,
    output wire        tmds_g_n,
    output wire        tmds_b_p,
    output wire        tmds_b_n
);

    // -------------------------------------------------------------------------
    // Unused header pins: tie to logic 0 so the tools do not flag them.
    // -------------------------------------------------------------------------
    assign gpio_nc = 12'd0;

    // The vendor SD controller uses SPI mode on the SD slot:
    //   CMD  -> MOSI
    //   DAT0 -> MISO
    //   DAT3 -> CS_N
    //   DAT1/DAT2 remain unused/high-Z.
    wire sd_spi_clk;
    wire sd_spi_cs_n;
    wire sd_spi_mosi;
    wire sd_spi_miso;

    assign sd_clk       = sd_spi_clk;
    assign sd_cmd       = sd_spi_mosi;
    assign sd_spi_miso  = sd_data0;
    assign sd_data1     = 1'bz;
    assign sd_data2     = 1'bz;
    assign sd_data3     = sd_spi_cs_n;

    // -------------------------------------------------------------------------
    // System reset from dedicated K3 reset button (active-low).
    // -------------------------------------------------------------------------
    wire sys_rst_n = reset_n;
    wire sys_rst   = ~sys_rst_n;

    // -------------------------------------------------------------------------
    // HDMI clock generation (50 MHz -> 74.0625 MHz / 370.3125 MHz).
    // -------------------------------------------------------------------------
    wire clk_pixel;
    wire clk_pixel_ser;
    wire clk_serial;
    wire hdmi_locked;

    // Asynchronous HDMI reset request: asserted immediately on system reset or
    // when the MMCM loses lock; de-assertion is synchronized to each HDMI clock.
    wire hdmi_rst_async = sys_rst | ~hdmi_locked;

    // Synchronized reset for the HDMI pixel clock domain.
    // The serial (BUFIO) clock cannot drive fabric flip-flops, so the
    // OSERDESE2 reset is supplied from the pixel-clock domain.
    reg [1:0] hdmi_rst_pixel_sync;

    always @(posedge clk_pixel or posedge hdmi_rst_async) begin
        if (hdmi_rst_async)
            hdmi_rst_pixel_sync <= 2'b11;
        else
            hdmi_rst_pixel_sync <= {hdmi_rst_pixel_sync[0], 1'b0};
    end

    wire hdmi_rst_pixel = hdmi_rst_pixel_sync[1];

    clock_gen hdmi_clk_gen (
        .clk_in        (w_clk),
        .rst           (sys_rst),
        .clk_pixel     (clk_pixel),
        .clk_pixel_ser (clk_pixel_ser),
        .clk_serial    (clk_serial),
        .locked        (hdmi_locked)
    );

    // -------------------------------------------------------------------------
    // HDMI controller and frame buffer.
    // The frame buffer is mapped at byte address 0x0001_0000.
    // -------------------------------------------------------------------------
    wire        vram_wr_en;
    wire [31:0] vram_addr;
    wire [31:0] vram_wdata;
    wire [1:0]  vram_mem_w_en;

    hdmi_controller hdmi (
        .clk_pixel      (clk_pixel),
        .clk_pixel_ser  (clk_pixel_ser),
        .clk_serial     (clk_serial),
        .rst_pixel      (hdmi_rst_pixel),
        .rst_serial     (hdmi_rst_pixel),

        .tmds_clk_p     (tmds_clk_p),
        .tmds_clk_n     (tmds_clk_n),
        .tmds_r_p       (tmds_r_p),
        .tmds_r_n       (tmds_r_n),
        .tmds_g_p       (tmds_g_p),
        .tmds_g_n       (tmds_g_n),
        .tmds_b_p       (tmds_b_p),
        .tmds_b_n       (tmds_b_n),

        .vram_clk       (w_clk),
        .vram_addr      (vram_addr),
        .vram_wdata     (vram_wdata),
        .vram_mem_w_en  (vram_mem_w_en)
    );

    // -------------------------------------------------------------------------
    // RV32IM core.
    // -------------------------------------------------------------------------
    wire [31:0] pc_debug;
    wire [31:0] result_debug;
    wire        mmio_wr_en;
    wire        mmio_rd_en;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [1:0]  mem_w_en;
    wire [31:0] mmio_r_data;

    wire        cpu_rst;
    wire        pager_hold_core;
    wire        pager_boot_done;
    wire        pager_imem_wr_en;
    wire [10:0] pager_imem_wr_addr;
    wire [31:0] pager_imem_wr_data;
    wire [18:0] pager_current_page;
    wire [15:0] pager_page_load_count;
    wire        pager_page_load_pulse;
    wire        pager_image_load_error;

    rv32i #(
        .ENABLE_M_EXT(1'b1)
    ) core (
        .clk               (w_clk),
        .rst               (cpu_rst),
        .ext_stall         (pager_hold_core),
        .pc_debug          (pc_debug),
        .result_debug      (result_debug),
        .mmio_wr_en        (mmio_wr_en),
        .mmio_rd_en        (mmio_rd_en),
        .mem_addr          (mem_addr),
        .mem_wdata         (mem_wdata),
        .mem_w_en          (mem_w_en),
        .mmio_r_data       (mmio_r_data),
        .imem_wr_en        (pager_imem_wr_en),
        .imem_wr_addr      (pager_imem_wr_addr),
        .imem_wr_data      (pager_imem_wr_data)
    );

    // -------------------------------------------------------------------------
    // Frame-buffer address decode: 0x0001_0000 .. 0x0002_FFFF (480x270 bytes).
    // The 8bpp framebuffer is 129600 bytes; the decode covers a 128 KB window
    // starting at 0x0001_0000 so the CPU can fill the whole 480 x 270 area.
    // -------------------------------------------------------------------------
    assign vram_wr_en    = ((mem_addr[31:16] == 16'h0001) ||
                            (mem_addr[31:16] == 16'h0002)) &&
                           (mem_w_en != 2'b00);
    assign vram_addr     = mem_addr;
    assign vram_wdata    = mem_wdata;
    assign vram_mem_w_en = vram_wr_en ? mem_w_en : 2'b00;

    // -------------------------------------------------------------------------
    // MMIO aggregator.
    // -------------------------------------------------------------------------
    wire        led_wr_en;
    wire [4:0]  led_wr_data;
    wire [31:0] gpio_in;
    wire [31:0] gpio_dir;
    wire [31:0] gpio_out;
    wire [31:0] gpio_en;
    wire [7:0]  uart_rx_data;
    wire        uart_rx_valid;
    wire        uart_tx_busy;
    wire        uart_tx_start;
    wire [7:0]  uart_tx_data;

    mmio mmio_inst (
        .clk         (w_clk),
        .rst         (cpu_rst),
        .addr        (mem_addr),
        .mmio_wr_en  (mmio_wr_en),
        .mmio_rd_en  (mmio_rd_en),
        .mem_w_en    (mem_w_en),
        .w_data      (mem_wdata),
        .r_data      (mmio_r_data),

        .led_wr_en   (led_wr_en),
        .led_wr_data (led_wr_data),

        .key1        (key1),
        .key2        (key2),

        .uart_rx_valid (uart_rx_valid),
        .uart_rx_data   (uart_rx_data),
        .uart_tx_busy   (uart_tx_busy),
        .uart_tx_start  (uart_tx_start),
        .uart_tx_data   (uart_tx_data),

        .gpio_in     (gpio_in),
        .gpio_dir    (gpio_dir),
        .gpio_out    (gpio_out),
        .gpio_en     (gpio_en)
    );

    // -------------------------------------------------------------------------
    // LED output register.
    //
    // A7-LITE user LEDs are wired active-low (cathode to FPGA pin), so invert
    // here.  Software sees active-high semantics: writing bit 0/1 to 0x400
    // turns LED1/LED2 on.
    // -------------------------------------------------------------------------
    reg led1_reg, led2_reg;
    always @(posedge w_clk or posedge sys_rst) begin
        if (sys_rst) begin
            led1_reg <= 1'b0;
            led2_reg <= 1'b0;
        end else if (led_wr_en) begin
            led1_reg <= led_wr_data[0];
            led2_reg <= led_wr_data[1];
        end
    end

    assign w_led1 = ~led1_reg;
    assign w_led2 = ~led2_reg;

    // -------------------------------------------------------------------------
    // GPIO pad controller.
    // -------------------------------------------------------------------------
    gpio gpio_inst (
        .clk          (w_clk),
        .rst          (sys_rst),
        .en           (gpio_en),
        .dir          (gpio_dir),
        .out_val      (gpio_out),
        .gpio_pins    (gpio_pins),
        .in_val       (gpio_in)
    );

    // -------------------------------------------------------------------------
    // UART receiver and transmitter behind the runtime UART MMIO registers.
    // -------------------------------------------------------------------------
    uart_rx #(
        .CLK_FREQ_HZ(50_000_000),
        .BAUD_RATE  (115_200)
    ) uart_rx_inst (
        .clk        (w_clk),
        .rst        (sys_rst),
        .rx         (uart_rx),
        .data       (uart_rx_data),
        .data_valid (uart_rx_valid)
    );

    uart_tx #(
        .CLK_FREQ_HZ(50_000_000),
        .BAUD_RATE  (115_200)
    ) uart_tx_inst (
        .clk   (w_clk),
        .rst   (sys_rst),
        .data  (uart_tx_data),
        .start (uart_tx_start),
        .tx    (uart_tx),
        .busy  (uart_tx_busy)
    );

    assign cpu_rst = sys_rst | ~pager_boot_done;

    // One-shot boot trigger for the SD pager after reset de-assertion.
    reg pager_boot_req;

    always @(posedge w_clk or posedge sys_rst) begin
        if (sys_rst)
            pager_boot_req <= 1'b1;
        else if (pager_boot_req)
            pager_boot_req <= 1'b0;
    end

    sd_exec_pager #(
        .IMEM_WORDS(2048),
        .PAGE_SHIFT(13),
        .MAX_IMAGE_BYTES(262144)
    ) sd_pager_inst (
        .clk             (w_clk),
        .rst             (sys_rst),
        .start_boot      (pager_boot_req),
        .pc              (pc_debug),
        .sd_clk          (sd_spi_clk),
        .sd_cs_n         (sd_spi_cs_n),
        .sd_miso         (sd_spi_miso),
        .sd_mosi         (sd_spi_mosi),
        .hold_core       (pager_hold_core),
        .boot_done       (pager_boot_done),
        .imem_wr_en      (pager_imem_wr_en),
        .imem_wr_addr    (pager_imem_wr_addr),
        .imem_wr_data    (pager_imem_wr_data),
        .current_page    (pager_current_page),
        .page_load_count (pager_page_load_count),
        .page_load_pulse (pager_page_load_pulse),
        .image_load_error(pager_image_load_error)
    );

endmodule
