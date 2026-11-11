`timescale 1ns / 1ps

module program_counter(
    input  wire        clk,
    input  wire        rst,
    input  wire        redirect,
    input  wire [31:0] redirect_target,
    input  wire        stall,
    input  wire        predict_taken,
    input  wire [31:0] predict_target,
    input  wire [31:0] fallback_pc,
    output reg  [31:0] pc
);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pc <= 32'b0;
        end else begin
            if (redirect)
                pc <= redirect_target;
            else if (stall)
                pc <= pc;
            else if (predict_taken)
                pc <= predict_target;
            else
                pc <= fallback_pc;
        end
    end

endmodule
