#
#   make                 # build SRC into build/<name>.bin
#   make SRC=xxxx.c      # build a different payload source
#   make clean           # remove build and sim artifacts

TOOLCHAIN := riscv64-unknown-elf
CC        := $(TOOLCHAIN)-gcc
OBJCOPY   := $(TOOLCHAIN)-objcopy
OBJDUMP   := $(TOOLCHAIN)-objdump

ARCH := rv32im
ABI  := ilp32
OPT  ?= O0
# Extra C flags.
CFLAGS ?=

STARTUP  := software/startup.s
LDSCRIPT := software/rv32im.lds
SRC      ?= pong.c
LIBSRC   := soc_lib.c

BUILD_DIR := build
BASE_NAME := $(basename $(notdir $(SRC)))
ELF       := $(BUILD_DIR)/$(BASE_NAME).elf
BIN       := $(BUILD_DIR)/$(BASE_NAME).bin

# Simulation / project directories.
ROOT_DIR := ..
SIM_DIR  := $(ROOT_DIR)/sim

# Artifacts copied out so the simulator can find them.
SIM_BIN  := $(SIM_DIR)/program.bin
SIM_SD_BIN := $(SIM_DIR)/sd_program.bin

.PHONY: all sync_images clean

all: $(BIN) sync_images

# Link startup + user C code into a flat RV32IM ELF.
$(ELF): $(STARTUP) $(SRC) $(LIBSRC) $(LDSCRIPT)
	@mkdir -p $(BUILD_DIR)
	$(CC) -march=$(ARCH) -mabi=$(ABI) \
	      -$(OPT) -Wall -Wno-array-bounds \
	      $(CFLAGS) \
	      -ffreestanding -nostdlib -nostartfiles \
	      -T $(LDSCRIPT) \
	      $(STARTUP) $(SRC) $(LIBSRC) \
	      -o $@

# Raw binary image written to the SD card.
$(BIN): $(ELF)
	$(OBJCOPY) -O binary $< $@

# Always refresh runtime images from the currently selected SRC.
# This avoids stale program.bin/sd_program.bin when switching SRC targets.
sync_images: $(BIN)
	@mkdir -p $(SIM_DIR)
	cp $(BIN) $(SIM_BIN)
	cp $(BIN) $(SIM_SD_BIN)

clean:
	rm -rf $(BUILD_DIR) $(SIM_BIN) $(SIM_SD_BIN)
