# Simple RV32IM MCU

A small RISC-V microcontroller written in Verilog for the MicroPhase A7-LITE
board (Xilinx Artix-7 XC7A35T). A five-stage RV32IM core boots from an SD card
and drives a UART, LEDs, keys, GPIO and an HDMI framebuffer.

This is the same softcore processor used by the Robomaster 2027 ISP+CNN Based Dart Guidance System designed by MichaelZhang830 (Guidance system will be released before RMUC 2027). 

## Features

- **CPU**: RV32I + M, five-stage pipeline with forwarding and gshare branch
  prediction, running at 50 MHz. No interrupts, CSRs or traps.
- **Memory**: 8 KiB data RAM and 8 KiB instruction memory. Code is loaded from
  the SD card one 8 KiB page at a time, so programs can be larger than 8 KiB.
- **I/O**: 115200 baud UART, 2 LEDs, 2 keys, 32 GPIO pins.
- **Video**: 480 x 270 framebuffer, 8 bits per pixel (R3G3B2), shown at 2x
  scale on a 1280 x 720 HDMI output.

Most instructions take 1 cycle. A jump or mispredicted branch takes 3, a
multiply 6, and a divide 6 to 37 depending on the operands.

## Memory map

| Address | Access | Description |
| --- | --- | --- |
| `0x0000_0000` - `0x0000_1FFF` | R/W | Data RAM, except the MMIO range |
| `0x0000_0400` - `0x0000_04FF` | R/W | MMIO registers |
| `0x0001_0000` - `0x0002_FA3F` | W | Framebuffer, pixel `(x, y)` at `0x0001_0000 + y * 480 + x` |

Code has its own address space starting at 0.

| Address | Register | Access | Description |
| --- | --- | --- | --- |
| `0x400` | LED | R/W | Bit 0 = LED1, bit 1 = LED2 |
| `0x404` | GPIO direction | R/W | 1 = output, 0 = input |
| `0x408` | GPIO output | R/W | Level driven on output pins |
| `0x40C` | GPIO input | R | Pin levels |
| `0x410` | GPIO enable | R/W | 1 = pin enabled, 0 = high impedance |
| `0x414` | UART TX | R/W | Write a byte to send it; read bit 0 = busy |
| `0x418` | UART RX | R | Bit 8 = byte available, bits 7:0 = byte; reading clears bit 8 |
| `0x41C` | KEY1 | R | Bit 0 = 0 while pressed |
| `0x420` | KEY2 | R | Bit 0 = 0 while pressed |

## Getting started

You need Vivado 2023.1. To build programs you also need `make` and a RISC-V
GCC toolchain (`riscv64-unknown-elf-gcc` with RV32IM support). Run the
commands from the repository root.

### Simulate

```sh
vivado -mode batch -notrace -source run_sims.tcl
```

This runs the four testbenches in `RV32IM.sim/sim_1/new/` and prints a
pass/fail line for each.

### Build and program the FPGA

```sh
vivado -mode batch -source build_bitstream.tcl
vivado -mode batch -source program_fpga_bit.tcl
```

### Build a program and write the SD card

```sh
cd payload
make                      # builds pong.c
make SRC=digital_IO.c     # builds another program
```

The result is `payload/build/<name>.bin`. Write it to an SDHC card as a raw
image starting at sector 0:

```sh
sudo dd if=payload/build/pong.bin of=/dev/sdX bs=512 conv=fsync
```

This overwrites the card. Copying the file onto a formatted card does not work.

| Program | Description |
| --- | --- |
| `pong.c` | Pong on the HDMI output, played with the two keys |
| `digital_IO.c` | Copies GPIO inputs to outputs and toggles an LED with KEY2 |

## Repository layout

| Path | Contents |
| --- | --- |
| `RV32IM.srcs/sources_1/imports/design/` | Verilog design; `a7_lite_top.v` is the top level, `rv32i.v` the CPU |
| `RV32IM.srcs/constrs_1/imports/constr/` | Pin and timing constraints |
| `RV32IM.sim/sim_1/new/` | Testbenches |
| `payload/` | C programs, support library (`soc_lib`) and Makefile |
| `doc/` | Board schematic |
| `*.tcl` | Simulation, build and programming scripts |

## Limitations

- Only code is loaded from the SD card. String literals and initialized
  global variables read as zero; use the stack and zero-initialized globals.
- The design meets timing and passes simulation. The latest fixes (SD page
  crossing, byte and halfword stores, UART receive) have not been tested on
  the board yet.

The design uses 7727 of 20800 LUTs and 32 of 50 block RAMs.

## License

MIT, see `LICENSE`. The SD controller files (`sd_ctrl.v`, `sd_init.v`,
`sd_rd.v`, `sd_wr.v`) are MicroPhase reference code under the terms in their
headers.
