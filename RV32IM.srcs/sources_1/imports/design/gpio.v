`timescale 1ns / 1ps

module gpio(
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] en,      // enable register 1 pin active 0 disabled
    input  wire [31:0] dir,     // direction register 1 output 0 input
    input  wire [31:0] out_val, // value to drive on output pins
    inout  wire [31:0] gpio_pins,
    output reg  [31:0] in_val  // sampled value of the pins
);

    //input sync buffer
    reg [31:0] gpio_sync0;
    reg [31:0] gpio_sync1;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            gpio_sync0 <= 32'b0;
            gpio_sync1 <= 32'b0;
        end else begin
            gpio_sync0 <= gpio_pins;
            gpio_sync1 <= gpio_sync0;
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst)
            in_val <= 32'b0;
        else
            in_val <= gpio_sync1;
    end

    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin : gpin
            assign gpio_pins[i] = (en[i] && dir[i]) ? out_val[i] : 1'bz;
        end
    endgenerate

endmodule
