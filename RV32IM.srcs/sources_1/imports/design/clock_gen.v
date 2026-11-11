`timescale 1ns / 1ps
//
// MMCM clock generation for the A7-LITE HDMI output.
// Input:  50 MHz
// Output: clk_pixel      = 74.0625 MHz  (global fabric clock for HDMI logic)
//         clk_pixel_ser  = 74.0625 MHz  (regional BUFR clock for OSERDES CLKDIV)
//         clk_serial     = 370.3125 MHz (BUFIO clock for OSERDESE2 10:1 DDR)
//
// VCO = 50 MHz / 2 * 29.625 = 740.625 MHz (within 600-1440 MHz range)
// The HDMI serializer uses a supported BUFIO/BUFR clock pair so the OSERDES
// CLK and CLKDIV inputs stay phase-aligned, while the rest of the HDMI logic
// runs from a global BUFG clock derived from a second MMCM output.
//

module clock_gen (
    input  wire clk_in,      // 50 MHz reference
    input  wire rst,         // active-high reset
    output wire clk_pixel,      // 74.0625 MHz via BUFG
    output wire clk_pixel_ser,  // 74.0625 MHz via BUFR
    output wire clk_serial,     // 370.3125 MHz via BUFIO
    output wire locked
);

    wire clk_fb;
    wire clk_serial_unbuf;
    wire clk_pixel_unbuf;
    wire clk_serial_bufio;
    wire clk_pixel_bufr;

    MMCME2_ADV #(
        .BANDWIDTH          ("OPTIMIZED"),
        .CLKFBOUT_MULT_F    (29.625),
        .CLKFBOUT_PHASE     (0.0),
        .CLKIN1_PERIOD      (20.0),
        .CLKOUT0_DIVIDE_F   (2.0),
        .CLKOUT0_DUTY_CYCLE (0.5),
        .CLKOUT0_PHASE      (0.0),
        .CLKOUT1_DIVIDE     (10),
        .CLKOUT1_DUTY_CYCLE (0.5),
        .CLKOUT1_PHASE      (0.0),
        .DIVCLK_DIVIDE      (2),
        .REF_JITTER1        (0.010)
    ) mmcm_adv_inst (
        .CLKIN1     (clk_in),
        .CLKIN2     (1'b0),
        .CLKINSEL   (1'b1),
        .RST        (rst),
        .PWRDWN     (1'b0),
        .CLKFBIN    (clk_fb),
        .CLKFBOUT   (clk_fb),
        .CLKOUT0    (clk_serial_unbuf),
        .CLKOUT1    (clk_pixel_unbuf),
        .CLKOUT2    (),
        .CLKOUT3    (),
        .CLKOUT4    (),
        .CLKOUT5    (),
        .CLKOUT6    (),
        .LOCKED     (locked),
        .DADDR      (7'h0),
        .DCLK       (1'b0),
        .DEN        (1'b0),
        .DI         (16'h0),
        .DO         (),
        .DRDY       (),
        .DWE        (1'b0),
        .PSCLK      (1'b0),
        .PSEN       (1'b0),
        .PSINCDEC   (1'b0),
        .PSDONE     ()
    );

    BUFR #(
        .BUFR_DIVIDE("5"),
        .SIM_DEVICE("7SERIES")
    ) bufr_pixel (
        .I   (clk_serial_unbuf),
        .CE  (1'b1),
        .CLR (1'b0),
        .O   (clk_pixel_bufr)
    );

    BUFG bufg_pixel (.I(clk_pixel_unbuf), .O(clk_pixel));

    BUFIO bufio_serial (.I(clk_serial_unbuf), .O(clk_serial_bufio));

    assign clk_pixel_ser = clk_pixel_bufr;
    assign clk_serial    = clk_serial_bufio;

endmodule
