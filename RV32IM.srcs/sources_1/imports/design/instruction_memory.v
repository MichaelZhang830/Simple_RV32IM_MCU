`timescale 1ns / 1ps

`ifdef SIMULATION

module instruction_memory(
    input  wire        clk,
    input  wire [31:0] pc,
    output wire [31:0] inst,
    input  wire        wr_en,
    input  wire [10:0] wr_addr,
    input  wire [31:0] wr_data
);
    (* ram_style = "block" *) reg [31:0] mem [0:2047];

    reg [7:0] byte_mem [0:8191];
    integer   fd, bytes_read, i;

    initial begin
        fd = $fopen("program.bin", "rb");
        if (fd == 0) fd = $fopen("../../program.bin", "rb");
        if (fd == 0) fd = $fopen("../../../sim/program.bin", "rb");
        if (fd == 0) fd = $fopen("../../../../sim/program.bin", "rb");
        if (fd == 0) begin
            $display("WARNING: Could not open program.bin");
            $display("Searched: ./program.bin");
            $display("          ../../program.bin");
            $display("          ../../../sim/program.bin");
            $display("          ../../../../sim/program.bin");
            $display("Falling back to NOP-filled instruction memory.");
            bytes_read = 0;
        end else begin
            bytes_read = $fread(byte_mem, fd);
            $fclose(fd);
            $display("Loaded %0d bytes from program.bin", bytes_read);
        end

        for (i = 0; i < 2048; i = i + 1) begin
            if ((i * 4 + 3) < bytes_read)
                mem[i] = {byte_mem[i*4+3], byte_mem[i*4+2],
                          byte_mem[i*4+1], byte_mem[i*4]};
            else
                mem[i] = 32'h00000013; // NOP padding
        end
    end
    always @(posedge clk) begin
        if (wr_en)
            mem[wr_addr[10:0]] <= wr_data;
    end

    assign inst = mem[pc[12:2]];
endmodule
`else

//actual HDL design
module instruction_memory(
    input  wire        clk,
    input  wire [31:0] pc,
    output wire [31:0] inst,
    input  wire        wr_en,
    input  wire [10:0] wr_addr,
    input  wire [31:0] wr_data
);
    //BRAM
    (* ram_style = "block" *) reg [31:0] mem [0:2047];

    integer init_i;

    // initial begin
    //     for (init_i = 0; init_i < 2048; init_i = init_i + 1)
    //         mem[init_i] = 32'h00000013; // NOP nop by adding 0 to 0 reg
    // end

    always @(posedge clk) begin
        if (wr_en)
            mem[wr_addr[10:0]] <= wr_data;
    end

    assign inst = mem[pc[12:2]];
endmodule
`endif
