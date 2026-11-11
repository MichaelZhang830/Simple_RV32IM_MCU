`timescale 1ns / 1ps

module dependence_unit(
    input  wire       idex_is_load,
    input  wire [4:0] idex_rd,
    input  wire [4:0] ifid_rs1,
    input  wire [4:0] ifid_rs2,
    output reg        stall
);

    always @(*) begin
        //stall if the instruction in ID/EX stage is a load and the destination register matches either source register of IF/ID stage
        if (idex_is_load && (idex_rd != 5'b0) && ((idex_rd == ifid_rs1) || (idex_rd == ifid_rs2)))
            stall = 1'b1;
        else
            stall = 1'b0;
    end

endmodule
