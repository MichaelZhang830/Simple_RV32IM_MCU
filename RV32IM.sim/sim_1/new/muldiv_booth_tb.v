`timescale 1ns / 1ps

module muldiv_booth_tb;
    localparam [4:0] OP_MUL    = 5'b10001;
    localparam [4:0] OP_MULH   = 5'b10010;
    localparam [4:0] OP_MULHSU = 5'b10011;
    localparam [4:0] OP_MULHU  = 5'b10100;
    localparam [4:0] OP_DIV    = 5'b10101;
    localparam [4:0] OP_DIVU   = 5'b10110;
    localparam [4:0] OP_REM    = 5'b10111;
    localparam [4:0] OP_REMU   = 5'b11000;

    reg         clk = 1'b0;
    reg         rst = 1'b1;
    reg         start = 1'b0;
    reg         cancel = 1'b0;
    reg         hold = 1'b0;
    reg  [4:0]  op = 5'd0;
    reg  [31:0] a = 32'd0;
    reg  [31:0] b = 32'd0;
    wire [31:0] result;
    wire        busy;
    wire        done;

    integer errors;
    integer test_index;
    integer cycles;
    reg [31:0] random_a;
    reg [31:0] random_b;
    reg signed [32:0] reference_a;
    reg signed [32:0] reference_b;
    reg signed [65:0] reference_product;
    reg signed [31:0] signed_random_a;
    reg signed [31:0] signed_random_b;

    always #5 clk = ~clk;

    muldiv_unit dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .cancel(cancel),
        .hold(hold),
        .op(op),
        .a(a),
        .b(b),
        .result(result),
        .busy(busy),
        .done(done)
    );

    task check_result;
        input [31:0] expected;
        input [159:0] tag;
        begin
            if (result !== expected) begin
                $display("[BOOTH_TB][ERROR] %0s got=%h expected=%h", tag, result, expected);
                errors = errors + 1;
            end
        end
    endtask

    task run_mul;
        input [4:0]   test_op;
        input [31:0]  test_a;
        input [31:0]  test_b;
        input [31:0]  expected;
        input [159:0] tag;
        begin
            @(negedge clk);
            op = test_op;
            a = test_a;
            b = test_b;
            start = 1'b1;
            @(posedge clk);
            #1 start = 1'b0;

            cycles = 0;
            while (!done && cycles < 8) begin
                @(posedge clk);
                #1 cycles = cycles + 1;
            end

            if (!done) begin
                $display("[BOOTH_TB][ERROR] %0s timed out", tag);
                errors = errors + 1;
            end else begin
                check_result(expected, tag);
                if (cycles != 2) begin
                    $display("[BOOTH_TB][ERROR] %0s latency=%0d expected=2", tag, cycles);
                    errors = errors + 1;
                end
            end
        end
    endtask

    task run_div;
        input [4:0]   test_op;
        input [31:0]  test_a;
        input [31:0]  test_b;
        input [31:0]  expected;
        input integer expected_cycles;
        input [159:0] tag;
        begin
            @(negedge clk);
            op = test_op;
            a = test_a;
            b = test_b;
            start = 1'b1;
            @(posedge clk);
            #1 start = 1'b0;

            cycles = 0;
            while (!done && cycles < 40) begin
                @(posedge clk);
                #1 cycles = cycles + 1;
            end

            if (!done) begin
                $display("[BOOTH_TB][ERROR] %0s timed out", tag);
                errors = errors + 1;
            end else begin
                check_result(expected, tag);
                if ((expected_cycles >= 0) && (cycles != expected_cycles)) begin
                    $display("[BOOTH_TB][ERROR] %0s latency=%0d expected=%0d",
                             tag, cycles, expected_cycles);
                    errors = errors + 1;
                end
            end
        end
    endtask

    initial begin
        errors = 0;
        repeat (4) @(posedge clk);
        #1 rst = 1'b0;

        run_mul(OP_MUL, 32'd21, 32'd2, 32'd42, "mul basic");
        run_mul(OP_MULH, 32'hFFFF_FFFC, 32'd2, 32'hFFFF_FFFF, "mulh negative");
        run_mul(OP_MULHSU, 32'hFFFF_FFFC, 32'd3, 32'hFFFF_FFFF, "mulhsu mixed");
        run_mul(OP_MULHU, 32'hFFFF_FFFC, 32'd3, 32'h0000_0002, "mulhu basic");
        run_mul(OP_MUL, 32'h8000_0000, 32'hFFFF_FFFF, 32'h8000_0000, "mul minint");
        run_mul(OP_MULH, 32'h8000_0000, 32'h8000_0000, 32'h4000_0000, "mulh minint");
        run_mul(OP_MULHSU, 32'h8000_0000, 32'hFFFF_FFFF, 32'h8000_0000, "mulhsu limits");
        run_mul(OP_MULHU, 32'hFFFF_FFFF, 32'hFFFF_FFFF, 32'hFFFF_FFFE, "mulhu max");

        for (test_index = 0; test_index < 128; test_index = test_index + 1) begin
            random_a = $random;
            random_b = $random;

            reference_a = {random_a[31], random_a};
            reference_b = {random_b[31], random_b};
            reference_product = reference_a * reference_b;
            run_mul(OP_MUL, random_a, random_b, reference_product[31:0], "random mul");
            run_mul(OP_MULH, random_a, random_b, reference_product[63:32], "random mulh");

            reference_b = {1'b0, random_b};
            reference_product = reference_a * reference_b;
            run_mul(OP_MULHSU, random_a, random_b, reference_product[63:32], "random mulhsu");

            reference_a = {1'b0, random_a};
            reference_product = reference_a * reference_b;
            run_mul(OP_MULHU, random_a, random_b, reference_product[63:32], "random mulhu");
        end

        @(negedge clk);
        op = OP_MULH;
        a = 32'h8000_0000;
        b = 32'd2;
        start = 1'b1;
        @(posedge clk);
        #1 start = 1'b0;
        op = OP_MULHU;
        a = 32'd7;
        b = 32'd9;
        wait (done);
        #1 check_result(32'hFFFF_FFFF, "latched request");

        @(negedge clk);
        op = OP_MUL;
        a = 32'h1234_5678;
        b = 32'h8765_4321;
        start = 1'b1;
        @(posedge clk);
        #1 start = 1'b0;
        @(negedge clk);
        cancel = 1'b1;
        @(posedge clk);
        #1;
        if (busy || done) begin
            $display("[BOOTH_TB][ERROR] cancel did not return unit to idle");
            errors = errors + 1;
        end
        cancel = 1'b0;
        run_mul(OP_MUL, 32'd9, 32'd11, 32'd99, "multiply after cancel");

        run_div(OP_DIV, 32'd55, 32'd6, 32'd9, 5, "normalized div");
        run_div(OP_DIVU, 32'hFFFF_FFF6, 32'd6, 32'h2AAA_AAA9, 31, "normalized divu");
        run_div(OP_REM, 32'd55, 32'd6, 32'd1, 5, "normalized rem");
        run_div(OP_REMU, 32'hFFFF_FFF6, 32'd6, 32'd0, 31, "normalized remu");
        run_div(OP_DIV, 32'd77, 32'd0, 32'hFFFF_FFFF, 0, "divide by zero");
        run_div(OP_REM, 32'd77, 32'd0, 32'd77, 0, "remainder by zero");
        run_div(OP_DIV, 32'h8000_0000, 32'hFFFF_FFFF, 32'h8000_0000, 0,
            "signed overflow quotient");
        run_div(OP_REM, 32'h8000_0000, 32'hFFFF_FFFF, 32'd0, 0,
            "signed overflow remainder");
        run_div(OP_DIVU, 32'h8000_0000, 32'hFFFF_FFFF, 32'd0, 0,
            "unsigned is not overflow");
        run_div(OP_REMU, 32'h8000_0000, 32'hFFFF_FFFF, 32'h8000_0000, 0,
            "unsigned remainder is not overflow");
        run_div(OP_DIVU, 32'd1234, 32'd1234, 32'd1, 2, "equal operands");
        run_div(OP_DIVU, 32'd0, 32'd9, 32'd0, 0, "zero dividend");

        for (test_index = 0; test_index < 128; test_index = test_index + 1) begin
            random_a = $random;
            random_b = $random;
            if (random_b == 32'd0)
            random_b = 32'd1;

            run_div(OP_DIVU, random_a, random_b, random_a / random_b, -1,
                "random divu");
            run_div(OP_REMU, random_a, random_b, random_a % random_b, -1,
                "random remu");

            signed_random_a = random_a;
            signed_random_b = random_b;
            if ((signed_random_a == -32'sh8000_0000) && (signed_random_b == -1))
            signed_random_b = 1;
            run_div(OP_DIV, signed_random_a, signed_random_b,
                signed_random_a / signed_random_b, -1, "random div");
            run_div(OP_REM, signed_random_a, signed_random_b,
                signed_random_a % signed_random_b, -1, "random rem");
        end

        // hold freezes a multiply in flight and keeps a pending done asserted.
        @(negedge clk);
        op = OP_MUL;
        a = 32'd1234;
        b = 32'd5678;
        start = 1'b1;
        @(posedge clk);
        #1 start = 1'b0;
        hold = 1'b1;
        repeat (5) @(posedge clk);
        #1;
        if (done || !busy) begin
            $display("[BOOTH_TB][ERROR] unit advanced while held");
            errors = errors + 1;
        end
        hold = 1'b0;
        repeat (2) @(posedge clk);
        #1 hold = 1'b1;
        repeat (3) @(posedge clk);
        #1;
        if (!done) begin
            $display("[BOOTH_TB][ERROR] done lost while held");
            errors = errors + 1;
        end
        check_result(32'd7006652, "multiply across hold");
        hold = 1'b0;

        if (errors == 0)
            $display("[MDU_TB][PASS] Booth multiplier and normalized divider tests passed");
        else
            $display("[MDU_TB][FAIL] total errors=%0d", errors);

        #20;
        $finish;
    end
endmodule