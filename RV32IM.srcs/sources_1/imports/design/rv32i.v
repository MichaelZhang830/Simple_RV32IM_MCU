`timescale 1ns / 1ps
// 5-stage pipelined RISC-V RV32IM core.
// Stages: IF -> ID -> EX -> MEM -> WB.

module rv32i #(
    parameter ENABLE_M_EXT = 1'b1
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        ext_stall,
    output wire [31:0] pc_debug,
    output wire [31:0] result_debug,
    output wire        mmio_wr_en,
    output wire        mmio_rd_en,
    output wire [31:0] mem_addr,
    output wire [31:0] mem_wdata,
    output wire [1:0]  mem_w_en,
    input  wire [31:0] mmio_r_data,
    input  wire        imem_wr_en,
    input  wire [10:0] imem_wr_addr,
    input  wire [31:0] imem_wr_data
);

    localparam [31:0] NOP         = 32'h00000013;

    localparam [6:0] OPC_BRANCH = 7'b1100011;
    localparam [6:0] OPC_RTYPE  = 7'b0110011;

    // IF stage.
    wire [31:0] pc;
    wire [31:0] pc_plus4 = pc + 32'd4;
    wire [31:0] if_inst;


    assign pc_debug = pc;

    instruction_memory IMEM(
        .clk(clk),
        .pc(pc),
        .inst(if_inst),
        .wr_en(imem_wr_en),
        .wr_addr(imem_wr_addr),
        .wr_data(imem_wr_data)
    );

    // Branch prediction
    wire [31:0] if_bimm      = {{20{if_inst[31]}}, if_inst[7], if_inst[30:25], if_inst[11:8], 1'b0};
    wire [31:0] if_btarget   = pc + if_bimm;
    wire [3:0]  bp_index;
    wire        bp_pred_taken;
    wire        if_is_branch = (if_inst[6:0] == OPC_BRANCH);
    wire        if_predict_taken = if_is_branch & bp_pred_taken;

    // IF/ID pipeline register
    reg [31:0] ifid_pc;
    reg [31:0] ifid_inst;
    reg        ifid_pred_taken;
    reg [3:0]  ifid_pred_index;

    // ID stage
    wire [6:0]  id_opcode, id_func7;
    wire [4:0]  id_rd, id_rs1, id_rs2;
    wire [2:0]  id_func3;
    wire [31:0] id_imm;
    wire [31:0] id_rs1_val, id_rs2_val;

    wire [4:0]  id_alu_op_raw;
    wire [4:0]  id_alu_op;
    wire        id_alu_mem_sel;
    wire [1:0]  id_alua_sel, id_alub_sel;
    wire        id_reg_w_en_raw;
    wire        id_reg_w_en;
    wire [1:0]  id_mem_w_en;
    wire [2:0]  id_read_mem;
    wire [2:0]  id_imm_typ;
    wire [1:0]  id_pc_mux_sel;

    wire        id_is_branch = (id_opcode == OPC_BRANCH);
    wire        id_is_m_inst = (id_opcode == OPC_RTYPE) && (id_func7 == 7'b0000001);

    // WB-stage signals
    wire        wb_reg_w_en;
    wire [4:0]  wb_rd;
    wire [31:0] wb_data;

    instruction_decoder DEC(
        .inst(ifid_inst),
        .opcode(id_opcode),
        .rd(id_rd),
        .funct3(id_func3),
        .rs1(id_rs1),
        .rs2(id_rs2),
        .funct7(id_func7)
    );

    immediate_control IMM(
        .instr(ifid_inst),
        .imm_typ(id_imm_typ),
        .imm_32(id_imm)
    );

    control_signals CTRL(
        .opcode(id_opcode),
        .func3(id_func3),
        .func7(id_func7),
        .alu_op(id_alu_op_raw),
        .alu_mem_mux_sel(id_alu_mem_sel),
        .alua_mux_sel(id_alua_sel),
        .alub_mux_sel(id_alub_sel),
        .reg_w_en(id_reg_w_en_raw),
        .mem_w_en(id_mem_w_en),
        .read_mem(id_read_mem),
        .imm_typ(id_imm_typ),
        .pc_mux_sel(id_pc_mux_sel)
    );

    assign id_alu_op   = (!ENABLE_M_EXT && id_is_m_inst) ? 5'b00000 : id_alu_op_raw;
    assign id_reg_w_en = (!ENABLE_M_EXT && id_is_m_inst) ? 1'b0     : id_reg_w_en_raw;

    register_file REGS(
        .rst(rst),
        .clk(clk),
        .w_en(wb_reg_w_en),
        .rs1(id_rs1),
        .rs2(id_rs2),
        .rd(wb_rd),
        .w_data(wb_data),
        .r_data1(id_rs1_val),
        .r_data2(id_rs2_val),
        .dbg_addr(5'd10),
        .dbg_data(result_debug)
    );

    // ID/EX pipeline register.
    reg [31:0] idex_pc;
    reg [31:0] idex_rs1_val, idex_rs2_val;
    reg [31:0] idex_imm;
    reg [4:0]  idex_rd, idex_rs1, idex_rs2;
    reg [4:0]  idex_alu_op;
    reg        idex_alu_mem_sel;
    reg [1:0]  idex_alua_sel, idex_alub_sel;
    reg        idex_reg_w_en;
    reg [1:0]  idex_mem_w_en;
    reg [2:0]  idex_read_mem;
    reg [1:0]  idex_pc_mux_sel;
    reg        idex_is_branch;
    reg        idex_pred_taken;
    reg [3:0]  idex_pred_index;

    // EX/MEM pipeline register.
    reg [31:0] exmem_alu_result;
    reg [31:0] exmem_store_data;
    reg [4:0]  exmem_rd;
    reg        exmem_reg_w_en;
    reg        exmem_alu_mem_sel;
    reg [1:0]  exmem_mem_w_en;
    reg [2:0]  exmem_read_mem;

    // MEM/WB pipeline register.
    reg [31:0] memwb_alu_result;
    reg [31:0] memwb_mem_data;
    reg [4:0]  memwb_rd;
    reg        memwb_reg_w_en;
    reg        memwb_alu_mem_sel;

    // Hazard detection.
    wire stall;
    wire idex_is_load = (idex_read_mem != 3'b000);
    wire exmem_is_load = (exmem_read_mem != 3'b000);

    dependence_unit HAZARD(
        .idex_is_load(idex_is_load),
        .idex_rd(idex_rd),
        .ifid_rs1(id_rs1),
        .ifid_rs2(id_rs2),
        .stall(stall)
    );

    // Load-use hazard: stall IF/ID while a load is in EX or MEM stage and the
    // instruction in IF/ID reads the load destination.  ID/EX is bubbled so the
    // load advances; holding ID/EX (the old behaviour) caused deadlock.
    wire load_use_stall = stall ||
                          (exmem_is_load && (exmem_rd != 5'b0) &&
                           ((exmem_rd == id_rs1) || (exmem_rd == id_rs2)));

    // EX stage.
    wire [1:0] forwardA, forwardB;

    bypass_unit FORWARD(
        .idex_rs1(idex_rs1),
        .idex_rs2(idex_rs2),
        .exmem_rd(exmem_rd),
        .exmem_reg_w_en(exmem_reg_w_en),
        .memwb_rd(memwb_rd),
        .memwb_reg_w_en(memwb_reg_w_en),
        .forwardA(forwardA),
        .forwardB(forwardB)
    );

    // Forwarding muxes: 00=register value, 01=EX/MEM result, 10=WB data
    wire [31:0] fwd_rs1, fwd_rs2;

    mux_3to1 FWD_A(
        .a(idex_rs1_val),
        .b(exmem_alu_result),
        .c(wb_data),
        .sel(forwardA),
        .y(fwd_rs1)
    );

    mux_3to1 FWD_B(
        .a(idex_rs2_val),
        .b(exmem_alu_result),
        .c(wb_data),
        .sel(forwardB),
        .y(fwd_rs2)
    );

    // ALU operand selection: A=rs1/pc/zero, B=rs2/imm/4
    wire [31:0] alu_a, alu_b, alu_result;
    wire        branch_sel;

    mux_3to1 MUX_A(
        .a(fwd_rs1),
        .b(idex_pc),
        .c(32'b0),
        .sel(idex_alua_sel),
        .y(alu_a)
    );

    mux_3to1 MUX_B(
        .a(fwd_rs2),
        .b(idex_imm),
        .c(32'd4),
        .sel(idex_alub_sel),
        .y(alu_b)
    );

    alu ALU(
        .a(alu_a),
        .b(alu_b),
        .alu_op(idex_alu_op),
        .result(alu_result),
        .branch_sel(branch_sel)
    );

    // Branch / jump resolution in EX.
    wire        ex_actual_taken = branch_sel;
    wire        br_mispredict   = idex_is_branch & (ex_actual_taken != idex_pred_taken);

    wire is_jal   = (idex_pc_mux_sel == 2'b01);
    wire is_jalr  = (idex_pc_mux_sel == 2'b10);
    // Redirect on JAL/JALR/branch-mispredict.  Any in-flight multi-cycle M
    // operation is cancelled separately by muldiv_cancel.
    wire redirect = (is_jal | is_jalr | br_mispredict);

    wire [31:0] br_target = idex_pc + idex_imm;
    wire [31:0] br_fall   = idex_pc + 32'd4;
    wire [31:0] redirect_target =
          is_jalr         ? ((fwd_rs1 + idex_imm) & ~32'b1) :
          is_jal          ? (idex_pc + idex_imm)            :
          ex_actual_taken ? br_target                       :
                            br_fall;

    // Multi-cycle RV32IM multiply/divide unit.
    wire        idex_is_m_op = (idex_alu_op >= 5'b10001) && (idex_alu_op <= 5'b11000);
    wire        ifid_is_m_op = (id_alu_op    >= 5'b10001) && (id_alu_op    <= 5'b11000);
    wire [31:0] muldiv_result;
    wire        muldiv_busy;
    wire        muldiv_done;
    // Only start a multi-cycle M operation when the instruction is actually
    // valid in EX (i.e. the pipeline is not stalled for a hazard) and the unit
    // is not already finishing a previous operation.  The delayed-done term
    // prevents the unit from restarting for the same instruction on the bubble
    // cycle that follows a completed M operation.
    reg        muldiv_done_d1;
    always @(posedge clk or posedge rst) begin
        if (rst)
            muldiv_done_d1 <= 1'b0;
        else if (!ext_stall)
            muldiv_done_d1 <= muldiv_done;
    end

    // Detect the cycle an M-op enters the EX stage so the front-end can
    // advance exactly one instruction and capture the instruction after the
    // M-op in IF/ID.  Without this one-cycle window the PC is held too early
    // and the instruction after the M-op is lost.
    reg idex_is_m_op_d1;
    always @(posedge clk or posedge rst) begin
        if (rst)
            idex_is_m_op_d1 <= 1'b0;
        else if (!ext_stall)
            idex_is_m_op_d1 <= idex_is_m_op;
    end
    wire m_op_enter_ex = idex_is_m_op && !idex_is_m_op_d1;

    wire        muldiv_bubble = muldiv_done_d1;
    wire        muldiv_start  = idex_is_m_op && !muldiv_busy && !muldiv_done &&
                                !muldiv_done_d1;
    // Cancel any in-flight M operation when the front-end is redirected.
    wire        muldiv_cancel = redirect;

    muldiv_unit MDU(
        .clk    (clk),
        .rst    (rst),
        .hold   (ext_stall),
        .start  (muldiv_start),
        .cancel (muldiv_cancel),
        .op     (idex_alu_op),
        .a      (fwd_rs1),
        .b      (fwd_rs2),
        .result (muldiv_result),
        .busy   (muldiv_busy),
        .done   (muldiv_done)
    );

    // Hold the back-end while an M-op is computing or finishing.
    wire muldiv_hold_ex = muldiv_busy || muldiv_done ||
                          (idex_is_m_op && !muldiv_done && !muldiv_done_d1);
    // Keep the front-end frozen while any M-op is in flight (including the
    // post-completion bubble), but release for exactly one cycle when an M-op
    // enters EX so the following instruction can be captured in IF/ID.
    wire muldiv_active  = muldiv_busy || muldiv_done || muldiv_done_d1;
    // An external stall freezes the front-end unconditionally.
    wire ifid_stall     = ext_stall || ((load_use_stall || muldiv_active) && !m_op_enter_ex);
    wire pc_stall       = ext_stall ||
                          ((load_use_stall || muldiv_active || ifid_is_m_op) && !m_op_enter_ex);

    // Program counter: sequential, predicted, stalled, or redirected.
    program_counter PC_UNIT(
        .clk            (clk),
        .rst            (rst),
        .redirect       (redirect && !ext_stall),
        .redirect_target(redirect_target),
        .stall          (pc_stall),
        .predict_taken  (if_predict_taken),
        .predict_target (if_btarget),
        .fallback_pc    (pc_plus4),
        .pc             (pc)
    );

    wire bp_upd_en = idex_is_branch && !ext_stall;

    branch_predictor #(
        .GHR_BITS(4),
        .IDX_BITS(4)
    ) BP(
        .clk(clk),
        .rst(rst),
        .pred_pc(pc),
        .pred_index(bp_index),
        .pred_taken(bp_pred_taken),
        .upd_en(bp_upd_en),
        .upd_index(idex_pred_index),
        .upd_taken(ex_actual_taken)
    );

    // MEM stage.
    wire        dmem_mmio_region;
    wire        dmem_mmio_wr_en;
    wire [31:0] dmem_ram_r_data;
    wire [31:0] mem_data;

    data_memory DMEM(
        .clk(clk),
        .read_mem(exmem_read_mem),
        .mem_w_en(exmem_mem_w_en),
        .addr(exmem_alu_result),
        .w_data(exmem_store_data),
        .r_data(dmem_ram_r_data),
        .mmio_region(dmem_mmio_region),
        .mmio_wr_en(dmem_mmio_wr_en)
    );

    // Loads from the MMIO region return the value from mmio.v; otherwise RAM.
    assign mem_data = dmem_mmio_region ? mmio_r_data : dmem_ram_r_data;

    // MMIO strobes forwarded to the top-level mmio.v.  Masked during an
    // external stall so each access takes effect exactly once.
    assign mmio_wr_en = dmem_mmio_wr_en && !ext_stall;
    assign mmio_rd_en = dmem_mmio_region && exmem_is_load && !ext_stall;
    assign mem_addr   = exmem_alu_result;
    assign mem_wdata  = exmem_store_data;
    assign mem_w_en   = exmem_mem_w_en;

    // WB stage.
    assign wb_data     = memwb_alu_mem_sel ? memwb_mem_data : memwb_alu_result;
    assign wb_rd       = memwb_rd;
    assign wb_reg_w_en = memwb_reg_w_en;

    // IF/ID
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ifid_pc         <= 32'b0;
            ifid_inst       <= NOP;
            ifid_pred_taken <= 1'b0;
            ifid_pred_index <= 4'b0;
        end else begin
            if (ext_stall) begin
                // Freeze IF/ID while instruction memory is being refilled.
            end else if (redirect) begin
                ifid_pc         <= 32'b0;
                ifid_inst       <= NOP;
                ifid_pred_taken <= 1'b0;
                ifid_pred_index <= 4'b0;
            end else if (ifid_stall) begin
                // Hold IF/ID during stalls (including the M-op done and bubble
                // cycles) so the instruction after the M-op is not lost.
                ifid_pc         <= ifid_pc;
                ifid_inst       <= ifid_inst;
                ifid_pred_taken <= ifid_pred_taken;
                ifid_pred_index <= ifid_pred_index;
            end else begin
                ifid_pc         <= pc;
                ifid_inst       <= if_inst;
                ifid_pred_taken <= if_predict_taken;
                ifid_pred_index <= bp_index;
            end
        end
    end

    // ID/EX
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            idex_pc          <= 32'b0;
            idex_rs1_val     <= 32'b0;
            idex_rs2_val     <= 32'b0;
            idex_imm         <= 32'b0;
            idex_rd          <= 5'b0;
            idex_rs1         <= 5'b0;
            idex_rs2         <= 5'b0;
            idex_alu_op      <= 5'b0;
            idex_alu_mem_sel <= 1'b0;
            idex_alua_sel    <= 2'b0;
            idex_alub_sel    <= 2'b0;
            idex_reg_w_en    <= 1'b0;
            idex_mem_w_en    <= 2'b0;
            idex_read_mem    <= 3'b0;
            idex_pc_mux_sel  <= 2'b0;
            idex_is_branch   <= 1'b0;
            idex_pred_taken  <= 1'b0;
            idex_pred_index  <= 4'b0;
        end else if (ext_stall) begin
            // Hold ID/EX during external front-end stalls (e.g. instruction
            // page refill) so the in-flight instruction context is preserved.
        end else if (muldiv_hold_ex) begin
            // Hold the M-extension instruction in ID/EX while the multi-cycle
            // unit computes or finishes.  Clearing it would lose the destination
            // register and control signals, so the M result would compute but
            // never be written back.
        end else if (muldiv_bubble || redirect || load_use_stall) begin
            // Bubble ID/EX:
            //  - after a completed M operation (result already in EX/MEM);
            //  - on any branch/jump redirect;
            //  - during a load-use stall (bubble so the load advances to MEM/WB
            //    while the dependent instruction stays in IF/ID).
            idex_pc          <= 32'b0;
            idex_rs1_val     <= 32'b0;
            idex_rs2_val     <= 32'b0;
            idex_imm         <= 32'b0;
            idex_rd          <= 5'b0;
            idex_rs1         <= 5'b0;
            idex_rs2         <= 5'b0;
            idex_alu_op      <= 5'b0;
            idex_alu_mem_sel <= 1'b0;
            idex_alua_sel    <= 2'b0;
            idex_alub_sel    <= 2'b0;
            idex_reg_w_en    <= 1'b0;
            idex_mem_w_en    <= 2'b0;
            idex_read_mem    <= 3'b0;
            idex_pc_mux_sel  <= 2'b0;
            idex_is_branch   <= 1'b0;
            idex_pred_taken  <= 1'b0;
            idex_pred_index  <= 4'b0;
        end else begin
            idex_pc          <= ifid_pc;
            idex_rs1_val     <= id_rs1_val;
            idex_rs2_val     <= id_rs2_val;
            idex_imm         <= id_imm;
            idex_rd          <= id_rd;
            idex_rs1         <= id_rs1;
            idex_rs2         <= id_rs2;
            idex_alu_op      <= id_alu_op;
            idex_alu_mem_sel <= id_alu_mem_sel;
            idex_alua_sel    <= id_alua_sel;
            idex_alub_sel    <= id_alub_sel;
            idex_reg_w_en    <= id_reg_w_en;
            idex_mem_w_en    <= id_mem_w_en;
            idex_read_mem    <= id_read_mem;
            idex_pc_mux_sel  <= id_pc_mux_sel;
            idex_is_branch   <= id_is_branch;
            idex_pred_taken  <= ifid_pred_taken;
            idex_pred_index  <= ifid_pred_index;
        end
    end

    // EX/MEM
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            exmem_alu_result  <= 32'b0;
            exmem_store_data  <= 32'b0;
            exmem_rd          <= 5'b0;
            exmem_reg_w_en    <= 1'b0;
            exmem_alu_mem_sel <= 1'b0;
            exmem_mem_w_en    <= 2'b0;
            exmem_read_mem    <= 3'b0;
        end else if (ext_stall) begin
            // Freeze EX/MEM while instruction memory is being refilled.
        end else if (muldiv_done) begin
            // Capture the multi-cycle unit result.  Checked before `busy`
            // because `done` is asserted on the final computation cycle.
            exmem_alu_result  <= muldiv_result;
            exmem_store_data  <= fwd_rs2;
            exmem_rd          <= idex_rd;
            exmem_reg_w_en    <= idex_reg_w_en;
            exmem_alu_mem_sel <= idex_alu_mem_sel;
            exmem_mem_w_en    <= idex_mem_w_en;
            exmem_read_mem    <= idex_read_mem;
        end else if (muldiv_busy || muldiv_bubble) begin
            // Hold EX/MEM while the multi-cycle unit is computing and during
            // the post-M bubble so the captured result is safely written back.
        end else begin
            exmem_alu_result  <= alu_result;
            exmem_store_data  <= fwd_rs2;
            exmem_rd          <= idex_rd;
            exmem_reg_w_en    <= idex_reg_w_en;
            exmem_alu_mem_sel <= idex_alu_mem_sel;
            exmem_mem_w_en    <= idex_mem_w_en;
            exmem_read_mem    <= idex_read_mem;
        end
    end

    // MEM/WB
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            memwb_alu_result  <= 32'b0;
            memwb_mem_data    <= 32'b0;
            memwb_rd          <= 5'b0;
            memwb_reg_w_en    <= 1'b0;
            memwb_alu_mem_sel <= 1'b0;
        end else if (ext_stall) begin
            // Freeze MEM/WB while instruction memory is being refilled.
        end else begin
            memwb_alu_result  <= exmem_alu_result;
            memwb_mem_data    <= mem_data;
            memwb_rd          <= exmem_rd;
            memwb_reg_w_en    <= exmem_reg_w_en;
            memwb_alu_mem_sel <= exmem_alu_mem_sel;
        end
    end

endmodule
