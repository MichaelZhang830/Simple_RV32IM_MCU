`timescale 1ns / 1ps
//   0x00000400 -> LED[1:0] register
//   0x00000404 -> GPIO_0 direction register (1=output, 0=input per bit)
//   0x00000408 -> GPIO_0 output register
//   0x0000040C -> GPIO_0 input register  (read-only, returns sampled pins)
//   0x00000410 -> GPIO_0 enable register  (1=pin active, 0=high-Z / disabled)
//   0x00000414 -> UART TX data / busy status
//   0x00000418 -> UART RX data / valid status
//   0x0000041C -> KEY[1] state (read-only, active-low)
//   0x00000420 -> KEY[2] state (read-only, active-low)

module mmio(
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] addr,
    input  wire        mmio_wr_en,
    input  wire        mmio_rd_en, // a load from addr completes this cycle
    input  wire [1:0]  mem_w_en,   // 01=sw 10=sh 11=sb
    input  wire [31:0] w_data,
    output reg  [31:0] r_data,

    // LED
    output reg         led_wr_en,
    output reg  [4:0]  led_wr_data,

    // key inputs
    input  wire        key1,
    input  wire        key2,

    //UART
    input  wire        uart_rx_valid,
    input  wire [7:0]  uart_rx_data,
    input  wire        uart_tx_busy,
    output reg         uart_tx_start,
    output reg  [7:0]  uart_tx_data,

    // GPIO
    input  wire [31:0] gpio_in,
    output reg  [31:0] gpio_dir,   // 1 output 0input
    output reg  [31:0] gpio_out,
    output reg  [31:0] gpio_en     // 1 pin enabled 0 disabled
);

    wire        sel_led     = (addr == 32'h00000400);
    wire        sel_dir     = (addr == 32'h00000404);
    wire        sel_out     = (addr == 32'h00000408);
    wire        sel_in      = (addr == 32'h0000040C);
    wire        sel_en      = (addr == 32'h00000410);
    wire        sel_uart_tx = (addr == 32'h00000414);
    wire        sel_uart_rx = (addr == 32'h00000418);
    wire        sel_key1    = (addr == 32'h0000041C);
    wire        sel_key2    = (addr == 32'h00000420);
    wire        write       = mmio_wr_en;

    reg         uart_rx_valid_reg;
    reg [7:0]   uart_rx_data_reg;

    initial begin
        uart_rx_valid_reg = 1'b0;
        uart_rx_data_reg  = 8'd0;
        uart_tx_start     = 1'b0;
        uart_tx_data      = 8'd0;
        led_wr_en         = 1'b0;
        led_wr_data       = 5'd0;
        gpio_dir          = 32'd0;
        gpio_out          = 32'd0;
        gpio_en           = 32'd0;
    end

    always @(*) begin
        if (sel_led)          r_data = {27'b0, led_wr_data};
        else if (sel_dir)     r_data = gpio_dir;
        else if (sel_out)     r_data = gpio_out;
        else if (sel_in)      r_data = gpio_in;
        else if (sel_en)      r_data = gpio_en;
        else if (sel_uart_tx) r_data = {31'b0, uart_tx_busy};
        else if (sel_uart_rx) r_data = {23'b0, uart_rx_valid_reg, uart_rx_data_reg};
        else if (sel_key1)    r_data = {31'b0, key1};
        else if (sel_key2)    r_data = {31'b0, key2};
        else                  r_data = 32'b0;
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            led_wr_en        <= 1'b0;
            led_wr_data      <= 5'd0;
            gpio_dir         <= 32'd0;
            gpio_out         <= 32'd0;
            gpio_en          <= 32'd0;
            uart_tx_start    <= 1'b0;
            uart_tx_data     <= 8'd0;
            uart_rx_valid_reg <= 1'b0;
            uart_rx_data_reg  <= 8'd0;
        end else begin
            led_wr_en <= 1'b0;
            uart_tx_start <= 1'b0;

            // cleared only by an actual load, the address alone also matches
            // unrelated ALU results; a byte arriving in the same cycle is kept
            if (sel_uart_rx && mmio_rd_en) begin
                uart_rx_valid_reg <= 1'b0;
            end

            if (uart_rx_valid) begin
                uart_rx_valid_reg <= 1'b1;
                uart_rx_data_reg  <= uart_rx_data;
            end

            if (sel_led && write) begin
                led_wr_en   <= 1'b1;
                led_wr_data <= w_data[4:0];
            end else if (sel_uart_tx && write && !uart_tx_busy) begin
                uart_tx_data  <= w_data[7:0];
                uart_tx_start <= 1'b1;
            end else if (sel_dir && write) begin
                gpio_dir <= w_data;
            end else if (sel_out && write) begin
                gpio_out <= w_data;
            end else if (sel_en && write) begin
                gpio_en <= w_data;
            end
        end
    end

endmodule
