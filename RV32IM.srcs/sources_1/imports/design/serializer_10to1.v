`timescale 1ns / 1ps
//
// 10:1 DDR serializer using a master/slave OSERDESE2 pair.
// clk_serial = 5 * clk_pixel for 10-bit DDR output.
//

module serializer_10to1 (
    input  wire       clk_pixel,
    input  wire       clk_serial,
    input  wire       rst,
    input  wire [9:0] parallel,
    output wire       serial
);

    wire shift1, shift2;

    OSERDESE2 #(
        .DATA_RATE_OQ   ("DDR"),
        .DATA_RATE_TQ   ("BUF"),
        .DATA_WIDTH     (10),
        .TRISTATE_WIDTH (1),
        .SERDES_MODE    ("MASTER"),
        .INIT_OQ        (1'b0),
        .INIT_TQ        (1'b0),
        .SRVAL_OQ       (1'b0),
        .SRVAL_TQ       (1'b0)
    ) master (
        .CLK        (clk_serial),
        .CLKDIV     (clk_pixel),
        .D1         (parallel[0]),
        .D2         (parallel[1]),
        .D3         (parallel[2]),
        .D4         (parallel[3]),
        .D5         (parallel[4]),
        .D6         (parallel[5]),
        .D7         (parallel[6]),
        .D8         (parallel[7]),
        .OCE        (1'b1),
        .OQ         (serial),
        .RST        (rst),
        .SHIFTIN1   (shift1),
        .SHIFTIN2   (shift2),
        .SHIFTOUT1  (),
        .SHIFTOUT2  (),
        .T1         (1'b0),
        .T2         (1'b0),
        .T3         (1'b0),
        .T4         (1'b0),
        .TBYTEIN    (1'b0),
        .TCE        (1'b1),
        .TQ         (),
        .TBYTEOUT   ()
    );

    OSERDESE2 #(
        .DATA_RATE_OQ   ("DDR"),
        .DATA_RATE_TQ   ("BUF"),
        .DATA_WIDTH     (10),
        .TRISTATE_WIDTH (1),
        .SERDES_MODE    ("SLAVE"),
        .INIT_OQ        (1'b0),
        .INIT_TQ        (1'b0),
        .SRVAL_OQ       (1'b0),
        .SRVAL_TQ       (1'b0)
    ) slave (
        .CLK        (clk_serial),
        .CLKDIV     (clk_pixel),
        .D1         (1'b0),
        .D2         (1'b0),
        .D3         (parallel[8]),
        .D4         (parallel[9]),
        .D5         (1'b0),
        .D6         (1'b0),
        .D7         (1'b0),
        .D8         (1'b0),
        .OCE        (1'b1),
        .OQ         (),
        .RST        (rst),
        .SHIFTIN1   (1'b0),
        .SHIFTIN2   (1'b0),
        .SHIFTOUT1  (shift1),
        .SHIFTOUT2  (shift2),
        .T1         (1'b0),
        .T2         (1'b0),
        .T3         (1'b0),
        .T4         (1'b0),
        .TBYTEIN    (1'b0),
        .TCE        (1'b1),
        .TQ         (),
        .TBYTEOUT   ()
    );

endmodule
