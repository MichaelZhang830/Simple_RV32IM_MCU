`timescale 1ns / 1ps
module bypass_unit(
    input  wire [4:0] idex_rs1,
    input  wire [4:0] idex_rs2,
    input  wire [4:0] exmem_rd,
    input  wire       exmem_reg_w_en,
    input  wire [4:0] memwb_rd,
    input  wire       memwb_reg_w_en,
    output reg  [1:0] forwardA,
    output reg  [1:0] forwardB
);

    always @(*) begin
        if (exmem_reg_w_en && (exmem_rd != 5'b0) && (exmem_rd == idex_rs1))
        // If the instruction in EX/MEM stage is writing to a register and that register matches the source register rs1 of the instruction in ID/EX stage forward from EX/MEM
            forwardA = 2'b01;
        else if (memwb_reg_w_en && (memwb_rd != 5'b0) && (memwb_rd == idex_rs1))
        // If the instruction in MEM/WB stage is writing to a register and that register matches the source register rs1 of the instruction in ID/EX stage forward from MEM/WB
            forwardA = 2'b10;
        else
            forwardA = 2'b00;

        if (exmem_reg_w_en && (exmem_rd != 5'b0) && (exmem_rd == idex_rs2))
            forwardB = 2'b01;
        else if (memwb_reg_w_en && (memwb_rd != 5'b0) && (memwb_rd == idex_rs2))
            forwardB = 2'b10;
        else
            forwardB = 2'b00;
    end

endmodule
