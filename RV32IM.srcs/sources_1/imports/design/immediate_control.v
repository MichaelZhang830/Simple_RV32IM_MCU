module immediate_control(
    input [31:0] instr,
    input [2:0] imm_typ,

    output reg [31:0] imm_32
);

    always @(*) begin
        case (imm_typ)
            3'b000:  imm_32 = {{20{instr[31]}}, instr[31:20]};                          // I-type
            3'b001:  imm_32 = {instr[31:12], 12'b0};                                    // U-type
            3'b010:  imm_32 = {{20{instr[31]}}, instr[31:25], instr[11:7]};             // S-type
            3'b011:  imm_32 = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8],
                               1'b0};                                                   // B-type
            3'b100:  imm_32 = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21],
                               1'b0};                                                   // J-type
            3'b101:  imm_32 = {{20{instr[31]}}, instr[31:20]} & ~(32'd1 << 10);         // I-type shift (bit 10 masked)
            3'b111:  imm_32 = 32'b0;                                                    // unused / zero
            default: imm_32 = 32'b0;
        endcase
    end

endmodule