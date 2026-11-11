`timescale 1ns / 1ps
module branch_predictor #(
    parameter integer GHR_BITS = 3,
    parameter integer IDX_BITS = 3
)(
    input  wire                 clk,
    input  wire                 rst,

    // Predict port (IF stage, combinational).
    input  wire [31:0]          pred_pc,
    output wire [IDX_BITS-1:0]  pred_index,
    output wire                 pred_taken,

    // Update port (EX stage).
    input  wire                 upd_en,
    input  wire [IDX_BITS-1:0]  upd_index,
    input  wire                 upd_taken
);

    localparam integer NUM_ENTRIES = (1 << IDX_BITS);

    reg [GHR_BITS-1:0] ghr;
    reg [1:0]          pht [0:NUM_ENTRIES-1];

    integer i;

    // gshare index and prediction bit.
    assign pred_index = ghr ^ pred_pc[IDX_BITS+1:2];
    assign pred_taken = pht[pred_index][1];

    // Predictor state update.
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ghr <= {GHR_BITS{1'b0}};
            for (i = 0; i < NUM_ENTRIES; i = i + 1)
                pht[i] <= 2'b01;
        end else if (upd_en) begin
            if (upd_taken) begin
                if (pht[upd_index] != 2'b11)
                    pht[upd_index] <= pht[upd_index] + 2'b01;
            end else begin
                if (pht[upd_index] != 2'b00)
                    pht[upd_index] <= pht[upd_index] - 2'b01;
            end
            ghr <= {ghr[GHR_BITS-2:0], upd_taken};
        end
    end

endmodule
