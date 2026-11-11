/* Linker script for RV32IM bare-metal programs on the RV32I_proj core.
 * Instruction memory starts at byte address 0x0 and is word-addressed.
 * Data memory is 8 KiB at 0x0000..0x1FFF, with MMIO mapped at 0x0400..0x04FF.
 * Place constants/data above the MMIO hole and keep stack at top of RAM.
 */

ENTRY(_start)

__stack_top = 0x00002000;

SECTIONS
{
    . = 0x00000000;

    .text : {
        *(.text.startup)
        *(.text*)
    }

    /* Keep .rodata/.data out of MMIO (0x400-0x4FF), but if .text already
     * grew past 0x500 place constants immediately after .text to avoid
     * section overlap in the linker address space. */
    . = MAX(., 0x00000500);

    .rodata : {
        *(.rodata*)
        *(.srodata*)
    }

    .data : {
        *(.data*)
        *(.sdata*)
    }

    .bss : {
        __bss_start = .;
        *(.bss*)
        *(.sbss*)
        __bss_end = .;
    }

    /DISCARD/ : {
        *(.comment)
        *(.note*)
    }
}
