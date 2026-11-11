`timescale 1ns / 1ps
//
// TMDS encoder for DVI/HDMI.
// Converts 8-bit colour + 2-bit control + data-enable into a 10-bit TMDS symbol.
//

module dvi_encoder (
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] data,
    input  wire [1:0] ctrl,
    input  wire       de,
    output reg  [9:0] tmds
);

    // -----------------------------------------------------------------
    // 8b/10b "TMDS" encoding (DVI 1.0 spec)
    // -----------------------------------------------------------------

    // Count ones in the input byte.
    function [3:0] popcount8;
        input [7:0] x;
        begin
            popcount8 = x[0] + x[1] + x[2] + x[3] + x[4] + x[5] + x[6] + x[7];
        end
    endfunction

    wire [3:0] ones = popcount8(data);

    // Decision bit: 0 -> XOR path, 1 -> XNOR path.
    wire decision = (ones > 4'd4) || ((ones == 4'd4) && (data[0] == 1'b0));

    // Intermediate 9-bit symbol (q_m[8] is the flag bit).
    wire [8:0] q_m;
    assign q_m[0] = data[0];
    assign q_m[1] = (decision) ? ~(q_m[0] ^ data[1]) : (q_m[0] ^ data[1]);
    assign q_m[2] = (decision) ? ~(q_m[1] ^ data[2]) : (q_m[1] ^ data[2]);
    assign q_m[3] = (decision) ? ~(q_m[2] ^ data[3]) : (q_m[2] ^ data[3]);
    assign q_m[4] = (decision) ? ~(q_m[3] ^ data[4]) : (q_m[3] ^ data[4]);
    assign q_m[5] = (decision) ? ~(q_m[4] ^ data[5]) : (q_m[4] ^ data[5]);
    assign q_m[6] = (decision) ? ~(q_m[5] ^ data[6]) : (q_m[5] ^ data[6]);
    assign q_m[7] = (decision) ? ~(q_m[6] ^ data[7]) : (q_m[6] ^ data[7]);
    assign q_m[8] = (decision) ? 1'b0 : 1'b1;

    wire [3:0] qm_ones = popcount8(q_m[7:0]);
    // diff = N1(q_m) - N0(q_m) = 2*N1(q_m) - 8
    wire signed [4:0] diff = {1'b0, qm_ones} + {1'b0, qm_ones} - 5'd8;

    reg signed [4:0] bias;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            tmds <= 10'b1101010100;
            bias <= 5'd0;
        end else if (!de) begin
            // Control symbols during blanking.
            case (ctrl)
                2'b00: tmds <= 10'b1101010100;
                2'b01: tmds <= 10'b0010101011;
                2'b10: tmds <= 10'b0101010100;
                2'b11: tmds <= 10'b1010101011;
            endcase
            bias <= 5'd0;
        end else begin
            if ((bias == 5'd0) || (qm_ones == 4'd4)) begin
                tmds[9]   <= ~q_m[8];
                tmds[8]   <=  q_m[8];
                tmds[7:0] <= (q_m[8]) ? q_m[7:0] : ~q_m[7:0];
                bias <= q_m[8] ? (bias + diff) : (bias - diff);
            end else if ((bias > 5'sd0 && qm_ones > 4'd4) ||
                         (bias < 5'sd0 && qm_ones < 4'd4)) begin
                // Invert q_m[7:0] to reduce running disparity.
                tmds[9]   <= 1'b1;
                tmds[8]   <= q_m[8];
                tmds[7:0] <= ~q_m[7:0];
                bias <= q_m[8] ? (bias + diff - 5'sd2) : (bias - diff + 5'sd2);
            end else begin
                // Do not invert.
                tmds[9]   <= 1'b0;
                tmds[8]   <= q_m[8];
                tmds[7:0] <= q_m[7:0];
                bias <= q_m[8] ? (bias - diff + 5'sd2) : (bias + diff - 5'sd2);
            end
        end
    end

endmodule
