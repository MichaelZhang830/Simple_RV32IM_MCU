# Bare-metal startup for RV32IM FPGA target.
# Initializes the stack pointer and calls main().
# When main returns, sit in an infinite loop.

    .section .text.startup
    .global _start
    .align 2

_start:
    # Stack grows downward from the linker-defined top of data RAM.
    la      sp, __stack_top

    # Zero the .bss section so static/global variables start at 0.
    # __bss_start and __bss_end are provided by the linker script.
    la      t0, __bss_start
    la      t1, __bss_end
1:
    bgeu    t0, t1, 2f
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       1b
2:

    # Jump to main(). Return value will be in a0 (x10).
    call    main

    # Infinite loop after main returns.
3:  j       3b
