module alu(
    input wire [31:0] a,
    input wire [31:0] b,
    input wire [4:0] alu_op,
    output reg [31:0] result, 
    output reg branch_sel
);


always @(*) begin
    branch_sel = 1'b0;
    result = 32'b0;
    case (alu_op)
        5'b00000: result = a + b;
        5'b00001: result = a - b;
        5'b00010: result = a & b;
        5'b00011: result = a | b;
        5'b00100: result = a ^ b;
        5'b00101: result = a << b[4:0]; // slli
        5'b00110: result = ($signed(a) < ($signed(b))) ? 32'b1 : 32'b0; // slti
        5'b00111: result = (a < b) ? 32'b1 : 32'b0; // sltiu
        5'b01000: result = a >> b[4:0]; // srli
        5'b01001: result = ($signed(a)) >>> b[4:0]; // srai
        5'b01010: begin 
            result = a + b;
            result[0] = 1'b0;
        end
        5'b01011: branch_sel = (a == b); //branch equal (beq)
        5'b01100: branch_sel = (a != b); //branch not equal (bne)
        5'b01101: branch_sel = ($signed(a) < $signed(b)); //branch less than (blt)
        5'b01110: branch_sel = ($signed(a) >= $signed(b)); //branch greater than or equal (bge)
        5'b01111: branch_sel = (a < b); //branch less than unsigned (bltu)
        5'b10000: branch_sel = (a >= b); //branch greater than or equal unsigned (bgeu)
        //M extension commands are handled by muldiv unit
        5'b10001,
        5'b10010,
        5'b10011,
        5'b10100,
        5'b10101,
        5'b10110,
        5'b10111,
        5'b11000: result = 32'd0;
        default: result = 32'b0;
    endcase
end

endmodule