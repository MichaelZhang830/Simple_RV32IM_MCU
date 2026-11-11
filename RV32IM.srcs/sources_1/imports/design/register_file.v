module register_file(
    input rst, clk, w_en,
    input [4:0] rs1, rs2, rd,
    input [31:0] w_data,
    output [31:0] r_data1, r_data2,
    input [4:0] dbg_addr,
    output [31:0] dbg_data
);

    reg [31:0] regs[31:0];
    integer i;

    // Read data (x0 hardwired to 0). Write-first bypass: if WB is writing the
    // same register this cycle, forward w_data so the ID read sees the new value.
    assign r_data1 = (rs1 == 5'b0) ? 32'b0 :
                     (w_en && (rd == rs1)) ? w_data : regs[rs1];
    assign r_data2 = (rs2 == 5'b0) ? 32'b0 :
                     (w_en && (rd == rs2)) ? w_data : regs[rs2];
    assign dbg_data = (dbg_addr == 5'b0) ? 32'b0 : regs[dbg_addr];


    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1) begin
                regs[i] <= 32'b0;
            end
        end else if (w_en && rd != 5'b0) begin
            regs[rd] <= w_data;
        end
    end

endmodule

