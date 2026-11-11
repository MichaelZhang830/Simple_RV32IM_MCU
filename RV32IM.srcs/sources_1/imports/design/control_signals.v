module control_signals(
    input [6:0] opcode,
    input [2:0] func3,
    input [6:0] func7,

    output reg [4:0] alu_op,
    output reg alu_mem_mux_sel,
    output reg [1:0] alua_mux_sel,
    output reg [1:0] alub_mux_sel,
    output reg reg_w_en,
    output reg [1:0] mem_w_en,
    output reg [2:0] read_mem,
    output reg [2:0] imm_typ,
    output reg [1:0] pc_mux_sel
);

// opcode map (rv32i + rv32m)
localparam [6:0] OPCODE_OP_IMM = 7'b0010011;
localparam [6:0] OPCODE_LUI    = 7'b0110111;
localparam [6:0] OPCODE_AUIPC  = 7'b0010111;
localparam [6:0] OPCODE_OP     = 7'b0110011;
localparam [6:0] OPCODE_JAL    = 7'b1101111;
localparam [6:0] OPCODE_JALR   = 7'b1100111;
localparam [6:0] OPCODE_BRANCH = 7'b1100011;
localparam [6:0] OPCODE_LOAD   = 7'b0000011;
localparam [6:0] OPCODE_STORE  = 7'b0100011;

// funct7 map
localparam [6:0] FUNC7_BASE = 7'b0000000;
localparam [6:0] FUNC7_ALT  = 7'b0100000;
localparam [6:0] FUNC7_M    = 7'b0000001;

// alu op map (matches alu.v)
localparam [4:0] ALU_ADD    = 5'b00000;
localparam [4:0] ALU_SUB    = 5'b00001;
localparam [4:0] ALU_AND    = 5'b00010;
localparam [4:0] ALU_OR     = 5'b00011;
localparam [4:0] ALU_XOR    = 5'b00100;
localparam [4:0] ALU_SLL    = 5'b00101;
localparam [4:0] ALU_SLT    = 5'b00110;
localparam [4:0] ALU_SLTU   = 5'b00111;
localparam [4:0] ALU_SRL    = 5'b01000;
localparam [4:0] ALU_SRA    = 5'b01001;
localparam [4:0] ALU_JALR   = 5'b01010;
localparam [4:0] ALU_BEQ    = 5'b01011;
localparam [4:0] ALU_BNE    = 5'b01100;
localparam [4:0] ALU_BLT    = 5'b01101;
localparam [4:0] ALU_BGE    = 5'b01110;
localparam [4:0] ALU_BLTU   = 5'b01111;
localparam [4:0] ALU_BGEU   = 5'b10000;
localparam [4:0] ALU_MUL    = 5'b10001;
localparam [4:0] ALU_MULH   = 5'b10010;
localparam [4:0] ALU_MULHSU = 5'b10011;
localparam [4:0] ALU_MULHU  = 5'b10100;
localparam [4:0] ALU_DIV    = 5'b10101;
localparam [4:0] ALU_DIVU   = 5'b10110;
localparam [4:0] ALU_REM    = 5'b10111;
localparam [4:0] ALU_REMU   = 5'b11000;

// immediate type map
localparam [2:0] IMM_I      = 3'b000;
localparam [2:0] IMM_U      = 3'b001;
localparam [2:0] IMM_S      = 3'b010;
localparam [2:0] IMM_B      = 3'b011;
localparam [2:0] IMM_J      = 3'b100;
localparam [2:0] IMM_SHAMT7 = 3'b101;
localparam [2:0] IMM_NONE   = 3'b111;

// read_mem encoding map
localparam [2:0] READ_NONE = 3'b000;
localparam [2:0] READ_LW   = 3'b001;
localparam [2:0] READ_LHU  = 3'b010;
localparam [2:0] READ_LBU  = 3'b011;
localparam [2:0] READ_LH   = 3'b110;
localparam [2:0] READ_LB   = 3'b111;

// mem_w_en encoding map
localparam [1:0] MEMW_NONE = 2'b00;
localparam [1:0] MEMW_SW   = 2'b01;
localparam [1:0] MEMW_SH   = 2'b10;
localparam [1:0] MEMW_SB   = 2'b11;

always @(*) begin
    // default decode is a safe no-op
    alu_op = ALU_ADD;
    alu_mem_mux_sel = 1'b0;
    alua_mux_sel = 2'b00;
    alub_mux_sel = 2'b00;
    reg_w_en = 1'b0;
    mem_w_en = MEMW_NONE;
    read_mem = READ_NONE;
    imm_typ = IMM_NONE;
    pc_mux_sel = 2'b00;

    case (opcode)
        // i-type alu instructions
        OPCODE_OP_IMM: begin
            reg_w_en = 1'b1;
            alub_mux_sel = 2'b01;
            imm_typ = IMM_I;

            case (func3)
                3'b000: alu_op = ALU_ADD;  // addi
                3'b010: alu_op = ALU_SLT;  // slti
                3'b011: alu_op = ALU_SLTU; // sltiu
                3'b100: alu_op = ALU_XOR;  // xori
                3'b110: alu_op = ALU_OR;   // ori
                3'b111: alu_op = ALU_AND;  // andi
                3'b001: begin               // slli
                    if (func7 == FUNC7_BASE) begin
                        alu_op = ALU_SLL;
                    end
                end
                3'b101: begin               // srli, srai
                    if (func7 == FUNC7_BASE) begin
                        alu_op = ALU_SRL;
                    end else if (func7 == FUNC7_ALT) begin
                        imm_typ = IMM_SHAMT7;
                        alu_op = ALU_SRA;
                    end
                end
                default: begin
                end
            endcase
        end

        // lui
        OPCODE_LUI: begin
            reg_w_en = 1'b1;
            alua_mux_sel = 2'b10; // select constant 0 so rd = 0 + imm
            alub_mux_sel = 2'b01;
            imm_typ = IMM_U;
            alu_op = ALU_ADD;
        end

        // auipc
        OPCODE_AUIPC: begin
            reg_w_en = 1'b1;
            alua_mux_sel = 2'b01;
            alub_mux_sel = 2'b01;
            imm_typ = IMM_U;
            alu_op = ALU_ADD;
        end

        // r-type alu instructions (rv32i + rv32m)
        OPCODE_OP: begin
            reg_w_en = 1'b1;
            imm_typ = IMM_NONE;

            if (func7 == FUNC7_M) begin
                case (func3)
                    3'b000: alu_op = ALU_MUL;    // mul
                    3'b001: alu_op = ALU_MULH;   // mulh
                    3'b010: alu_op = ALU_MULHSU; // mulhsu
                    3'b011: alu_op = ALU_MULHU;  // mulhu
                    3'b100: alu_op = ALU_DIV;    // div
                    3'b101: alu_op = ALU_DIVU;   // divu
                    3'b110: alu_op = ALU_REM;    // rem
                    3'b111: alu_op = ALU_REMU;   // remu
                    default: begin
                    end
                endcase
            end else begin
                case (func3)
                    3'b000: begin // add, sub
                        if (func7 == FUNC7_BASE) begin
                            alu_op = ALU_ADD;
                        end else if (func7 == FUNC7_ALT) begin
                            alu_op = ALU_SUB;
                        end
                    end
                    3'b001: begin // sll
                        if (func7 == FUNC7_BASE) begin
                            alu_op = ALU_SLL;
                        end
                    end
                    3'b010: begin // slt
                        if (func7 == FUNC7_BASE) begin
                            alu_op = ALU_SLT;
                        end
                    end
                    3'b011: begin // sltu
                        if (func7 == FUNC7_BASE) begin
                            alu_op = ALU_SLTU;
                        end
                    end
                    3'b100: begin // xor
                        if (func7 == FUNC7_BASE) begin
                            alu_op = ALU_XOR;
                        end
                    end
                    3'b101: begin // srl, sra
                        if (func7 == FUNC7_BASE) begin
                            alu_op = ALU_SRL;
                        end else if (func7 == FUNC7_ALT) begin
                            alu_op = ALU_SRA;
                        end
                    end
                    3'b110: begin // or
                        if (func7 == FUNC7_BASE) begin
                            alu_op = ALU_OR;
                        end
                    end
                    3'b111: begin // and
                        if (func7 == FUNC7_BASE) begin
                            alu_op = ALU_AND;
                        end
                    end
                    default: begin
                    end
                endcase
            end
        end

        // jal
        OPCODE_JAL: begin
            reg_w_en = 1'b1;
            alua_mux_sel = 2'b01;
            alub_mux_sel = 2'b10;
            imm_typ = IMM_J;
            pc_mux_sel = 2'b01;
            alu_op = ALU_ADD;
        end

        // jalr (rv32i requires func3 == 000)
        OPCODE_JALR: begin
            if (func3 == 3'b000) begin
                reg_w_en = 1'b1;
                alua_mux_sel = 2'b01;
                alub_mux_sel = 2'b10;
                imm_typ = IMM_I;
                pc_mux_sel = 2'b10;
                alu_op = ALU_JALR;
            end
        end

        // b-type branch instructions
        OPCODE_BRANCH: begin
            imm_typ = IMM_B;
            case (func3)
                3'b000: alu_op = ALU_BEQ;  // beq
                3'b001: alu_op = ALU_BNE;  // bne
                3'b100: alu_op = ALU_BLT;  // blt
                3'b101: alu_op = ALU_BGE;  // bge
                3'b110: alu_op = ALU_BLTU; // bltu
                3'b111: alu_op = ALU_BGEU; // bgeu
                default: begin
                end
            endcase
        end

        // l-type load instructions
        OPCODE_LOAD: begin
            reg_w_en = 1'b1;
            alu_mem_mux_sel = 1'b1;
            alub_mux_sel = 2'b01;
            imm_typ = IMM_I;
            alu_op = ALU_ADD;

            case (func3)
                3'b010: read_mem = READ_LW;  // lw
                3'b001: read_mem = READ_LH;  // lh
                3'b000: read_mem = READ_LB;  // lb
                3'b100: read_mem = READ_LBU; // lbu
                3'b101: read_mem = READ_LHU; // lhu
                default: begin
                end
            endcase
        end

        // s-type store instructions
        OPCODE_STORE: begin
            alub_mux_sel = 2'b01;
            imm_typ = IMM_S;
            alu_op = ALU_ADD;

            case (func3)
                3'b010: mem_w_en = MEMW_SW; // sw
                3'b001: mem_w_en = MEMW_SH; // sh
                3'b000: mem_w_en = MEMW_SB; // sb
                default: begin
                end
            endcase
        end

        default: begin
        end
    endcase
end

endmodule