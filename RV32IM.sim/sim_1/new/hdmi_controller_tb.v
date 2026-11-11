`timescale 1ns / 1ps

module hdmi_controller_tb;
    reg clk_pixel = 1'b0;
    reg clk_pixel_ser = 1'b0;
    reg clk_serial = 1'b0;
    reg rst_pixel = 1'b1;
    reg rst_serial = 1'b1;

    reg vram_clk = 1'b0;
    reg [31:0] vram_addr = 32'd0;
    reg [31:0] vram_wdata = 32'd0;
    reg [1:0]  vram_mem_w_en = 2'b00;

    wire tmds_clk_p, tmds_clk_n;
    wire tmds_r_p, tmds_r_n;
    wire tmds_g_p, tmds_g_n;
    wire tmds_b_p, tmds_b_n;

    integer errors;
    integer clock_transitions = 0;
    integer data_transitions = 0;
    reg previous_tmds_clk = 1'b0;
    reg previous_tmds_b = 1'b0;

    // Fastened clocks for practical simulation runtime.
    always #5  clk_pixel = ~clk_pixel;      // 100 MHz sim clock
    always #5  clk_pixel_ser = ~clk_pixel_ser;
    always #1  clk_serial = ~clk_serial;    // 500 MHz sim serial clock
    always #5  vram_clk = ~vram_clk;

    always @(negedge clk_serial) begin
        if (!rst_serial) begin
            if (tmds_clk_p !== previous_tmds_clk)
                clock_transitions = clock_transitions + 1;
            if (tmds_b_p !== previous_tmds_b)
                data_transitions = data_transitions + 1;
            previous_tmds_clk = tmds_clk_p;
            previous_tmds_b = tmds_b_p;
        end
    end

    hdmi_controller dut (
        .clk_pixel(clk_pixel),
        .clk_pixel_ser(clk_pixel_ser),
        .clk_serial(clk_serial),
        .rst_pixel(rst_pixel),
        .rst_serial(rst_serial),
        .tmds_clk_p(tmds_clk_p),
        .tmds_clk_n(tmds_clk_n),
        .tmds_r_p(tmds_r_p),
        .tmds_r_n(tmds_r_n),
        .tmds_g_p(tmds_g_p),
        .tmds_g_n(tmds_g_n),
        .tmds_b_p(tmds_b_p),
        .tmds_b_n(tmds_b_n),
        .vram_clk(vram_clk),
        .vram_addr(vram_addr),
        .vram_wdata(vram_wdata),
        .vram_mem_w_en(vram_mem_w_en)
    );

    task vram_write_word;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(posedge vram_clk);
            vram_addr     <= addr;
            vram_wdata    <= data;
            vram_mem_w_en <= 2'b01;
            @(posedge vram_clk);
            vram_mem_w_en <= 2'b00;
            vram_addr     <= 32'd0;
            vram_wdata    <= 32'd0;
        end
    endtask

    task vram_write_byte;
        input [31:0] addr;
        input [7:0] data;
        begin
            @(posedge vram_clk);
            vram_addr     <= addr;
            vram_wdata    <= {24'd0, data};
            vram_mem_w_en <= 2'b11;
            @(posedge vram_clk);
            vram_mem_w_en <= 2'b00;
            vram_addr     <= 32'd0;
            vram_wdata    <= 32'd0;
        end
    endtask

    initial begin
        errors = 0;

        repeat (8) @(posedge clk_pixel);
        rst_pixel  <= 1'b0;
        rst_serial <= 1'b0;

        // Write a few pixels in the first framebuffer word at base 0x0001_0000.
        // bytes: [31:24]=0xE0 (red-ish), [23:16]=0x1C (green-ish), [15:8]=0x03 (blue-ish), [7:0]=0xFF (white-ish)
        vram_write_word(32'h0001_0000, 32'hE01C03FF);
        vram_write_byte(32'h0001_0001, 8'hA5);

        // Let counters and BRAM pipeline advance into active video.
        repeat (40) @(posedge clk_pixel);

        // Sanity checks on timing counters and TMDS clock differential behavior.
        if (dut.h_count == 0 && dut.v_count == 0) begin
            $display("[HDMI_TB][ERROR] timing counters did not advance");
            errors = errors + 1;
        end

        if ((tmds_clk_p ^ tmds_clk_n) !== 1'b1) begin
            $display("[HDMI_TB][ERROR] TMDS clock differential pair invalid");
            errors = errors + 1;
        end

        if (clock_transitions < 4) begin
            $display("[HDMI_TB][ERROR] serialized TMDS clock did not toggle");
            errors = errors + 1;
        end

        if (data_transitions < 4) begin
            $display("[HDMI_TB][ERROR] serialized TMDS data did not toggle");
            errors = errors + 1;
        end

        // Wait until the delayed active region is asserted.
        wait (dut.active_d3 == 1'b1);
        repeat (10) @(posedge clk_pixel);

        // During active video, at least one channel should carry non-control data.
        if (dut.tmds_r === 10'b1101010100 &&
            dut.tmds_g === 10'b1101010100 &&
            dut.tmds_b === 10'b1101010100) begin
            $display("[HDMI_TB][ERROR] TMDS channels look stuck at control symbol");
            errors = errors + 1;
        end

        // Verify framebuffer write landed in BRAM word 0.
        if (dut.fb_mem[0] !== 32'hE01CA5FF) begin
            $display("[HDMI_TB][ERROR] Framebuffer write mismatch. got=%h", dut.fb_mem[0]);
            errors = errors + 1;
        end

        // Sample framebuffer pixel (0,0) at the first centered 2x viewport pixel.
        @(negedge clk_pixel);
        dut.h_count = 12'd160;
        dut.v_count = 11'd90;
        repeat (4) @(posedge clk_pixel);
        if (dut.pixel !== 8'hFF || dut.r_out !== 8'hE0 ||
            dut.g_out !== 8'hE0 || dut.b_out !== 8'hC0) begin
            $display("[HDMI_TB][ERROR] viewport pixel mismatch pixel=%h rgb=%h/%h/%h",
                     dut.pixel, dut.r_out, dut.g_out, dut.b_out);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("[HDMI_TB][PASS] HDMI timing + framebuffer + TMDS smoke test passed");
        else
            $display("[HDMI_TB][FAIL] total errors = %0d", errors);

        #20;
        if (errors == 0) $finish;
        else $stop;
    end
endmodule
