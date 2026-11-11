###############################################################################################
## a7_lite.xdc for A7-LITE FPGA Board (XC7A35T-FGG484)
## 50 MHz system clock, USB UART, LEDs, keys, GPIO and HDMI (TMDS_33)
###############################################################################################

## 50MHz system clock
set_property -dict {PACKAGE_PIN J19 IOSTANDARD LVCMOS33} [get_ports {w_clk}];
create_clock -add -name sys_clk -period 20.00 [get_ports {w_clk}];

## MMCM generated clocks for HDMI are auto-derived by Vivado from the
## MMCME2_ADV in clock_gen.v.  Do not add redundant constraints here.

###############################################################################################
## On-board LEDs (active-high)
###############################################################################################
set_property -dict {PACKAGE_PIN M18 IOSTANDARD LVCMOS33} [get_ports {w_led1}];
set_property -dict {PACKAGE_PIN N18 IOSTANDARD LVCMOS33} [get_ports {w_led2}];

###############################################################################################
## Dedicated active-low reset button (K3)
set_property -dict {PACKAGE_PIN L18 IOSTANDARD LVCMOS33 PULLUP true} [get_ports {reset_n}];

###############################################################################################
## On-board keys (active-low, pull-up recommended)
###############################################################################################
set_property -dict {PACKAGE_PIN AA1 IOSTANDARD LVCMOS33 PULLUP true} [get_ports {key1}];
set_property -dict {PACKAGE_PIN W1  IOSTANDARD LVCMOS33 PULLUP true} [get_ports {key2}];

###############################################################################################
## USB-UART (CH340)
##   uart_tx = FPGA output to host (CH340 RX)
##   uart_rx = FPGA input from host (CH340 TX)
###############################################################################################
set_property -dict {PACKAGE_PIN V2 IOSTANDARD LVCMOS33} [get_ports {uart_tx}];
set_property -dict {PACKAGE_PIN U2 IOSTANDARD LVCMOS33} [get_ports {uart_rx}];

###############################################################################################
## SD card (wired to top-level sd_* ports)
###############################################################################################
set_property -dict {PACKAGE_PIN U7 IOSTANDARD LVCMOS33}  [get_ports {sd_clk}];
set_property -dict {PACKAGE_PIN AA8 IOSTANDARD LVCMOS33} [get_ports {sd_cmd}];
set_property -dict {PACKAGE_PIN W9 IOSTANDARD LVCMOS33}  [get_ports {sd_data0}];
set_property -dict {PACKAGE_PIN Y9 IOSTANDARD LVCMOS33}  [get_ports {sd_data1}];
set_property -dict {PACKAGE_PIN Y7 IOSTANDARD LVCMOS33}  [get_ports {sd_data2}];
set_property -dict {PACKAGE_PIN Y8 IOSTANDARD LVCMOS33}  [get_ports {sd_data3}];

###############################################################################################
## PMOD / GPIO header (GPIO1)
## First 32 single-ended pins are connected to gpio_pins[31:0].
## The remaining header pins are constrained as unused inputs.
###############################################################################################
set_property -dict {PACKAGE_PIN F13 IOSTANDARD LVCMOS33} [get_ports {gpio_pins[0]}];
set_property -dict {PACKAGE_PIN F14 IOSTANDARD LVCMOS33} [get_ports {gpio_pins[1]}];
set_property -dict {PACKAGE_PIN E13 IOSTANDARD LVCMOS33} [get_ports {gpio_pins[2]}];
set_property -dict {PACKAGE_PIN E14 IOSTANDARD LVCMOS33} [get_ports {gpio_pins[3]}];
set_property -dict {PACKAGE_PIN D14 IOSTANDARD LVCMOS33} [get_ports {gpio_pins[4]}];
set_property -dict {PACKAGE_PIN D15 IOSTANDARD LVCMOS33} [get_ports {gpio_pins[5]}];
set_property -dict {PACKAGE_PIN E16 IOSTANDARD LVCMOS33} [get_ports {gpio_pins[6]}];
set_property -dict {PACKAGE_PIN D16 IOSTANDARD LVCMOS33} [get_ports {gpio_pins[7]}];
set_property -dict {PACKAGE_PIN D17 IOSTANDARD LVCMOS33} [get_ports {gpio_pins[8]}];
set_property -dict {PACKAGE_PIN C17 IOSTANDARD LVCMOS33} [get_ports {gpio_pins[9]}];
set_property -dict {PACKAGE_PIN C13 IOSTANDARD LVCMOS33} [get_ports {gpio_pins[10]}];
set_property -dict {PACKAGE_PIN B13 IOSTANDARD LVCMOS33} [get_ports {gpio_pins[11]}];
set_property -dict {PACKAGE_PIN A13 IOSTANDARD LVCMOS33} [get_ports {gpio_pins[12]}];
set_property -dict {PACKAGE_PIN A14 IOSTANDARD LVCMOS33} [get_ports {gpio_pins[13]}];
set_property -dict {PACKAGE_PIN C14 IOSTANDARD LVCMOS33} [get_ports {gpio_pins[14]}];
set_property -dict {PACKAGE_PIN C15 IOSTANDARD LVCMOS33} [get_ports {gpio_pins[15]}];
set_property -dict {PACKAGE_PIN A15 IOSTANDARD LVCMOS33} [get_ports {gpio_pins[16]}];
set_property -dict {PACKAGE_PIN A16 IOSTANDARD LVCMOS33} [get_ports {gpio_pins[17]}];
set_property -dict {PACKAGE_PIN B15 IOSTANDARD LVCMOS33} [get_ports {gpio_pins[18]}];
set_property -dict {PACKAGE_PIN B16 IOSTANDARD LVCMOS33} [get_ports {gpio_pins[19]}];
set_property -dict {PACKAGE_PIN F16 IOSTANDARD LVCMOS33} [get_ports {gpio_pins[20]}];
set_property -dict {PACKAGE_PIN E17 IOSTANDARD LVCMOS33} [get_ports {gpio_pins[21]}];
set_property -dict {PACKAGE_PIN A18 IOSTANDARD LVCMOS33} [get_ports {gpio_pins[22]}];
set_property -dict {PACKAGE_PIN A19 IOSTANDARD LVCMOS33} [get_ports {gpio_pins[23]}];
set_property -dict {PACKAGE_PIN B17 IOSTANDARD LVCMOS33} [get_ports {gpio_pins[24]}];
set_property -dict {PACKAGE_PIN B18 IOSTANDARD LVCMOS33} [get_ports {gpio_pins[25]}];
set_property -dict {PACKAGE_PIN B20 IOSTANDARD LVCMOS33} [get_ports {gpio_pins[26]}];
set_property -dict {PACKAGE_PIN A20 IOSTANDARD LVCMOS33} [get_ports {gpio_pins[27]}];
set_property -dict {PACKAGE_PIN F19 IOSTANDARD LVCMOS33} [get_ports {gpio_pins[28]}];
set_property -dict {PACKAGE_PIN F20 IOSTANDARD LVCMOS33} [get_ports {gpio_pins[29]}];
set_property -dict {PACKAGE_PIN E19 IOSTANDARD LVCMOS33} [get_ports {gpio_pins[30]}];
set_property -dict {PACKAGE_PIN D19 IOSTANDARD LVCMOS33} [get_ports {gpio_pins[31]}];

## Unused header pins (constrained so bitstream generation does not fail if left unconnected)
set_property -dict {PACKAGE_PIN C18 IOSTANDARD LVCMOS33} [get_ports {gpio_nc[0]}];
set_property -dict {PACKAGE_PIN C19 IOSTANDARD LVCMOS33} [get_ports {gpio_nc[1]}];
set_property -dict {PACKAGE_PIN F18 IOSTANDARD LVCMOS33} [get_ports {gpio_nc[2]}];
set_property -dict {PACKAGE_PIN E18 IOSTANDARD LVCMOS33} [get_ports {gpio_nc[3]}];
set_property -dict {PACKAGE_PIN D20 IOSTANDARD LVCMOS33} [get_ports {gpio_nc[4]}];
set_property -dict {PACKAGE_PIN C20 IOSTANDARD LVCMOS33} [get_ports {gpio_nc[5]}];
set_property -dict {PACKAGE_PIN B21 IOSTANDARD LVCMOS33} [get_ports {gpio_nc[6]}];
set_property -dict {PACKAGE_PIN A21 IOSTANDARD LVCMOS33} [get_ports {gpio_nc[7]}];
set_property -dict {PACKAGE_PIN D21 IOSTANDARD LVCMOS33} [get_ports {gpio_nc[8]}];
set_property -dict {PACKAGE_PIN G21 IOSTANDARD LVCMOS33} [get_ports {gpio_nc[9]}];
set_property -dict {PACKAGE_PIN C22 IOSTANDARD LVCMOS33} [get_ports {gpio_nc[10]}];
set_property -dict {PACKAGE_PIN B22 IOSTANDARD LVCMOS33} [get_ports {gpio_nc[11]}];

###############################################################################################
## HDMI (TMDS_33)
###############################################################################################
set_property -dict {PACKAGE_PIN L19 IOSTANDARD TMDS_33} [get_ports {tmds_clk_p}];
set_property -dict {PACKAGE_PIN L20 IOSTANDARD TMDS_33} [get_ports {tmds_clk_n}];

set_property -dict {PACKAGE_PIN G17 IOSTANDARD TMDS_33} [get_ports {tmds_r_p}];
set_property -dict {PACKAGE_PIN G18 IOSTANDARD TMDS_33} [get_ports {tmds_r_n}];

set_property -dict {PACKAGE_PIN J20 IOSTANDARD TMDS_33} [get_ports {tmds_g_p}];
set_property -dict {PACKAGE_PIN J21 IOSTANDARD TMDS_33} [get_ports {tmds_g_n}];

set_property -dict {PACKAGE_PIN K21 IOSTANDARD TMDS_33} [get_ports {tmds_b_p}];
set_property -dict {PACKAGE_PIN K22 IOSTANDARD TMDS_33} [get_ports {tmds_b_n}];

###############################################################################################
## I/O timing constraints (relaxed; this is a demo design)
###############################################################################################
set_input_delay  -clock sys_clk -max 5.0 [get_ports {uart_rx reset_n}];
set_input_delay  -clock sys_clk -min  0.0 [get_ports {uart_rx reset_n}];
set_output_delay -clock sys_clk -max 5.0 [get_ports {uart_tx w_led1 w_led2 gpio_nc}];
set_output_delay -clock sys_clk -min  0.0 [get_ports {uart_tx w_led1 w_led2 gpio_nc}];

## GPIO pins and user keys are slow header/push-button I/O; they are not
## timing-critical for this demo.
set_false_path -from [get_ports {gpio_pins[*]}] -to [get_ports {gpio_pins[*]}];
set_false_path -from [get_ports {key1 key2}]     -to [get_ports {gpio_pins[*]}];

## HDMI TMDS outputs are source-synchronous and self-timed by the OSERDES;
## no explicit output delay is needed.

###############################################################################################
## Clock-domain crossings
## The system clock and HDMI clocks are generated from the same MMCM but have
## no required phase relationship across the frame-buffer BRAM.
################################################################################
set_clock_groups -asynchronous \
    -group [get_clocks sys_clk] \
    -group [get_clocks -include_generated_clocks -of_objects [get_pins hdmi_clk_gen/mmcm_adv_inst/CLKOUT0]] \
    -group [get_clocks -include_generated_clocks -of_objects [get_pins hdmi_clk_gen/mmcm_adv_inst/CLKOUT1]];

###############################################################################################
## Timing constraints for HDMI pixel/serial clocks
## The MMCM in clock_gen.v derives these from the 50 MHz input; Vivado auto-derives them.
###############################################################################################
## No extra timing constraints required for the simple demo.
###############################################################################################
## Configuration
## Set the bitstream up for Quad-SPI flash boot so the FPGA configures
## automatically from the on-board non-volatile memory on power-up.
###############################################################################################
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design];
set_property CONFIG_VOLTAGE 3.3 [current_design];
set_property CFGBVS VCCO [current_design];
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design];
set_property CONFIG_MODE SPIx4 [current_design];
