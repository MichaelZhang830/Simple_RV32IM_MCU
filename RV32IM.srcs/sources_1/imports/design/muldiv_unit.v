`timescale 1ns / 1ps
// Multi-cycle multiply/divide unit for the RV32IM M extension.
// Multiply ops MUL/MULH/MULHSU/MULHU use a radix-4 Booth multiplier with two computation cycles after request acceptance
// Divide/remainder ops  use a normalized restoring divider that evaluates only the possible quotient-bit positions
// The parent pipeline must stall when using this module as it requires multiple cycles to complete an operation

module muldiv_unit (
    input  wire        clk,
    input  wire        rst,

    input  wire        start,      // pulse to begin a new M operation
    input  wire        cancel,     // abort current operation for redirect or pipeline flush
    input  wire        hold,       // freeze the unit while the pipeline is externally stalled
    input  wire [4:0]  op,
    input  wire [31:0] a,
    input  wire [31:0] b,

    output reg  [31:0] result,
    output reg         busy,
    output reg         done
);

    localparam [4:0] OP_MUL    = 5'b10001;
    localparam [4:0] OP_MULH   = 5'b10010;
    localparam [4:0] OP_MULHSU = 5'b10011;
    localparam [4:0] OP_MULHU  = 5'b10100;
    localparam [4:0] OP_DIV    = 5'b10101;
    localparam [4:0] OP_DIVU   = 5'b10110;
    localparam [4:0] OP_REM    = 5'b10111;
    localparam [4:0] OP_REMU   = 5'b11000;

    localparam [2:0] S_IDLE       = 3'd0;
    localparam [2:0] S_MUL_REDUCE = 3'd1;
    localparam [2:0] S_MUL_FINAL  = 3'd2;
    localparam [2:0] S_DIV        = 3'd3;
    localparam [2:0] S_DIV_DONE   = 3'd4;

    reg [2:0]  state;
    reg [5:0]  div_cnt;
    reg [31:0] div_b;
    reg [31:0] div_bit;
    reg [31:0] quotient, remainder;
    reg        div_a_neg, div_b_neg;
    reg        div_op_signed;
    reg        div_op_rem;

    reg [4:0]  mul_op;
    reg [32:0] mul_a;
    reg [32:0] mul_b;
    reg [67:0] mul_red0, mul_red1, mul_red2;
    reg [67:0] mul_red3, mul_red4, mul_red5;

    wire is_mul = (op == OP_MUL)   || (op == OP_MULH) ||
                  (op == OP_MULHSU) || (op == OP_MULHU);
    wire is_div = (op == OP_DIV)   || (op == OP_DIVU) ||
                  (op == OP_REM)   || (op == OP_REMU);

    // A 33-bit representation covers signed and unsigned RV32 operands.
    // Radix-4 Booth recoding produces 17 signed partial products
    wire [35:0] booth_b = {{2{mul_b[32]}}, mul_b, 1'b0};

    function [67:0] booth_partial;
        input [32:0] multiplicand;
        input [2:0]  booth_code;
        input integer shift;
        reg signed [67:0] extended_x;
        reg signed [67:0] selected_x;
        begin
            extended_x = {{35{multiplicand[32]}}, multiplicand};
            case (booth_code)
                3'b001, 3'b010: selected_x = extended_x;
                3'b011:         selected_x = extended_x <<< 1;
                3'b100:         selected_x = -(extended_x <<< 1);
                3'b101, 3'b110: selected_x = -extended_x;
                default:        selected_x = 68'sd0;
            endcase
            booth_partial = selected_x <<< shift;
        end
    endfunction

    wire [67:0] pp0  = booth_partial(mul_a, booth_b[2:0],    0);
    wire [67:0] pp1  = booth_partial(mul_a, booth_b[4:2],    2);
    wire [67:0] pp2  = booth_partial(mul_a, booth_b[6:4],    4);
    wire [67:0] pp3  = booth_partial(mul_a, booth_b[8:6],    6);
    wire [67:0] pp4  = booth_partial(mul_a, booth_b[10:8],   8);
    wire [67:0] pp5  = booth_partial(mul_a, booth_b[12:10], 10);
    wire [67:0] pp6  = booth_partial(mul_a, booth_b[14:12], 12);
    wire [67:0] pp7  = booth_partial(mul_a, booth_b[16:14], 14);
    wire [67:0] pp8  = booth_partial(mul_a, booth_b[18:16], 16);
    wire [67:0] pp9  = booth_partial(mul_a, booth_b[20:18], 18);
    wire [67:0] pp10 = booth_partial(mul_a, booth_b[22:20], 20);
    wire [67:0] pp11 = booth_partial(mul_a, booth_b[24:22], 22);
    wire [67:0] pp12 = booth_partial(mul_a, booth_b[26:24], 24);
    wire [67:0] pp13 = booth_partial(mul_a, booth_b[28:26], 26);
    wire [67:0] pp14 = booth_partial(mul_a, booth_b[30:28], 28);
    wire [67:0] pp15 = booth_partial(mul_a, booth_b[32:30], 30);
    wire [67:0] pp16 = booth_partial(mul_a, booth_b[34:32], 32);

    // Carry-save compressors form a Wallace-style tree. Carries are shifted
    // at each level, so no carry propagation occurs before the final stage.
    wire [67:0] l1s0 = pp0 ^ pp1 ^ pp2;
    wire [67:0] l1c0 = ((pp0 & pp1) | (pp0 & pp2) | (pp1 & pp2)) << 1;
    wire [67:0] l1s1 = pp3 ^ pp4 ^ pp5;
    wire [67:0] l1c1 = ((pp3 & pp4) | (pp3 & pp5) | (pp4 & pp5)) << 1;
    wire [67:0] l1s2 = pp6 ^ pp7 ^ pp8;
    wire [67:0] l1c2 = ((pp6 & pp7) | (pp6 & pp8) | (pp7 & pp8)) << 1;
    wire [67:0] l1s3 = pp9 ^ pp10 ^ pp11;
    wire [67:0] l1c3 = ((pp9 & pp10) | (pp9 & pp11) | (pp10 & pp11)) << 1;
    wire [67:0] l1s4 = pp12 ^ pp13 ^ pp14;
    wire [67:0] l1c4 = ((pp12 & pp13) | (pp12 & pp14) | (pp13 & pp14)) << 1;

    wire [67:0] l2s0 = l1s0 ^ l1c0 ^ l1s1;
    wire [67:0] l2c0 = ((l1s0 & l1c0) | (l1s0 & l1s1) | (l1c0 & l1s1)) << 1;
    wire [67:0] l2s1 = l1c1 ^ l1s2 ^ l1c2;
    wire [67:0] l2c1 = ((l1c1 & l1s2) | (l1c1 & l1c2) | (l1s2 & l1c2)) << 1;
    wire [67:0] l2s2 = l1s3 ^ l1c3 ^ l1s4;
    wire [67:0] l2c2 = ((l1s3 & l1c3) | (l1s3 & l1s4) | (l1c3 & l1s4)) << 1;
    wire [67:0] l2s3 = l1c4 ^ pp15 ^ pp16;
    wire [67:0] l2c3 = ((l1c4 & pp15) | (l1c4 & pp16) | (pp15 & pp16)) << 1;

    wire [67:0] l3s0 = l2s0 ^ l2c0 ^ l2s1;
    wire [67:0] l3c0 = ((l2s0 & l2c0) | (l2s0 & l2s1) | (l2c0 & l2s1)) << 1;
    wire [67:0] l3s1 = l2c1 ^ l2s2 ^ l2c2;
    wire [67:0] l3c1 = ((l2c1 & l2s2) | (l2c1 & l2c2) | (l2s2 & l2c2)) << 1;

    wire [67:0] f1s0 = mul_red0 ^ mul_red1 ^ mul_red2;
    wire [67:0] f1c0 = ((mul_red0 & mul_red1) | (mul_red0 & mul_red2) |
                        (mul_red1 & mul_red2)) << 1;
    wire [67:0] f1s1 = mul_red3 ^ mul_red4 ^ mul_red5;
    wire [67:0] f1c1 = ((mul_red3 & mul_red4) | (mul_red3 & mul_red5) |
                        (mul_red4 & mul_red5)) << 1;
    wire [67:0] f2s0 = f1s0 ^ f1c0 ^ f1s1;
    wire [67:0] f2c0 = ((f1s0 & f1c0) | (f1s0 & f1s1) | (f1c0 & f1s1)) << 1;
    wire [67:0] f3s0 = f2s0 ^ f2c0 ^ f1c1;
    wire [67:0] f3c0 = ((f2s0 & f2c0) | (f2s0 & f1c1) | (f2c0 & f1c1)) << 1;
    wire [67:0] mul_product = f3s0 + f3c0;

    wire [31:0] abs_a = (a[31]) ? -a : a;
    wire [31:0] abs_b = (b[31]) ? -b : b;

    wire [31:0] signed_quo = (div_a_neg ^ div_b_neg) ? -quotient  : quotient;
    wire [31:0] signed_rem = (div_a_neg)             ? -remainder : remainder;

    function [5:0] leading_zeros;
        input [31:0] value;
        integer index;
        reg found;
        begin
            leading_zeros = 6'd32;
            found = 1'b0;
            for (index = 31; index >= 0; index = index - 1) begin
                if (!found && value[index]) begin
                    leading_zeros = 31 - index;
                    found = 1'b1;
                end
            end
        end
    endfunction

    wire div_is_signed = (op == OP_DIV) || (op == OP_REM);
    wire div_is_rem    = (op == OP_REM) || (op == OP_REMU);
    wire [31:0] div_mag_a = (div_is_signed && a[31]) ? abs_a : a;
    wire [31:0] div_mag_b = (div_is_signed && b[31]) ? abs_b : b;
    wire [5:0] div_shift = leading_zeros(div_mag_b) - leading_zeros(div_mag_a);
    wire div_signed_overflow = div_is_signed &&
                               (a == 32'h8000_0000) && (b == 32'hFFFF_FFFF);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state        <= S_IDLE;
            busy         <= 1'b0;
            done         <= 1'b0;
            result       <= 32'd0;
            mul_op       <= 5'd0;
            mul_a        <= 33'd0;
            mul_b        <= 33'd0;
            {mul_red0, mul_red1, mul_red2} <= {204'd0};
            {mul_red3, mul_red4, mul_red5} <= {204'd0};
            div_cnt      <= 6'd0;
            div_b        <= 32'd0;
            div_bit      <= 32'd0;
            {quotient, remainder} <= {32'd0, 32'd0};
        end else if (hold) begin
            // Keep all state, including a pending done.
        end else if (cancel) begin
            // Pipeline redirect/flush: kill any in-flight M operation so a
            // bogus result is not written back from a wrongly-fetched path.
            state        <= S_IDLE;
            busy         <= 1'b0;
            done         <= 1'b0;
            result       <= 32'd0;
            mul_op       <= 5'd0;
            mul_a        <= 33'd0;
            mul_b        <= 33'd0;
            {mul_red0, mul_red1, mul_red2} <= {204'd0};
            {mul_red3, mul_red4, mul_red5} <= {204'd0};
            div_cnt      <= 6'd0;
            div_b        <= 32'd0;
            div_bit      <= 32'd0;
            {quotient, remainder} <= {32'd0, 32'd0};
        end else begin
            done <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (start && is_mul) begin
                        busy   <= 1'b1;
                        state  <= S_MUL_REDUCE;
                        mul_op <= op;
                        mul_a  <= (op == OP_MULHU) ? {1'b0, a} : {a[31], a};
                        mul_b  <= ((op == OP_MULHU) || (op == OP_MULHSU)) ?
                                  {1'b0, b} : {b[31], b};
                    end else if (start && is_div) begin
                        if (b == 32'd0) begin
                            result <= div_is_rem ? a : 32'hFFFF_FFFF;
                            busy   <= 1'b0;
                            done   <= 1'b1;
                        end else if (div_signed_overflow) begin
                            result <= div_is_rem ? 32'd0 : 32'h8000_0000;
                            busy   <= 1'b0;
                            done   <= 1'b1;
                        end else if (div_mag_a == 32'd0) begin
                            result <= 32'd0;
                            busy   <= 1'b0;
                            done   <= 1'b1;
                        end else if (div_mag_a < div_mag_b) begin
                            result <= div_is_rem ? a : 32'd0;
                            busy   <= 1'b0;
                            done   <= 1'b1;
                        end else begin
                            busy          <= 1'b1;
                            state         <= S_DIV;
                            div_cnt       <= div_shift;
                            div_op_signed <= div_is_signed;
                            div_op_rem    <= div_is_rem;
                            div_a_neg     <= a[31] && div_is_signed;
                            div_b_neg     <= b[31] && div_is_signed;
                            div_b         <= div_mag_b << div_shift;
                            div_bit       <= 32'd1 << div_shift;
                            quotient      <= 32'd0;
                            remainder     <= div_mag_a;
                        end
                    end
                end

                S_MUL_REDUCE: begin
                    mul_red0 <= l3s0;
                    mul_red1 <= l3c0;
                    mul_red2 <= l3s1;
                    mul_red3 <= l3c1;
                    mul_red4 <= l2s3;
                    mul_red5 <= l2c3;
                    state    <= S_MUL_FINAL;
                end

                S_MUL_FINAL: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= S_IDLE;
                    case (mul_op)
                        OP_MUL:    result <= mul_product[31:0];
                        OP_MULH:   result <= mul_product[63:32];
                        OP_MULHSU: result <= mul_product[63:32];
                        OP_MULHU:  result <= mul_product[63:32];
                        default:   result <= mul_product[31:0];
                    endcase
                end

                S_DIV: begin
                    if (remainder >= div_b) begin
                        remainder <= remainder - div_b;
                        quotient  <= quotient | div_bit;
                    end

                    if (div_cnt == 6'd0) begin
                        state <= S_DIV_DONE;
                    end else begin
                        div_b   <= div_b >> 1;
                        div_bit <= div_bit >> 1;
                        div_cnt <= div_cnt - 1'b1;
                    end
                end

                S_DIV_DONE: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= S_IDLE;

                    if (div_op_rem) begin
                        result <= div_op_signed ? signed_rem : remainder;
                    end else begin
                        result <= div_op_signed ? signed_quo : quotient;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
