// riscv_pkg.sv: shared types, opcodes, and control signals

package riscv_pkg;

  localparam int XLEN     = 32;
  localparam int REG_BITS = 5;

  typedef enum logic [6:0] {
    OP_LOAD    = 7'b000_0011,
    OP_STORE   = 7'b010_0011,
    OP_BRANCH  = 7'b110_0011,
    OP_JALR    = 7'b110_0111,
    OP_JAL     = 7'b110_1111,
    OP_AUIPC   = 7'b001_0111,
    OP_LUI     = 7'b011_0111,
    OP_IMM     = 7'b001_0011,
    OP_REG     = 7'b011_0011,
    OP_SYSTEM  = 7'b111_0011,
    OP_MISC    = 7'b000_1111
  } opcode_e;

  localparam logic [2:0] F3_BEQ  = 3'b000;
  localparam logic [2:0] F3_BNE  = 3'b001;
  localparam logic [2:0] F3_BLT  = 3'b100;
  localparam logic [2:0] F3_BGE  = 3'b101;
  localparam logic [2:0] F3_BLTU = 3'b110;
  localparam logic [2:0] F3_BGEU = 3'b111;

  localparam logic [2:0] F3_LB  = 3'b000;
  localparam logic [2:0] F3_LH  = 3'b001;
  localparam logic [2:0] F3_LW  = 3'b010;
  localparam logic [2:0] F3_LBU = 3'b100;
  localparam logic [2:0] F3_LHU = 3'b101;

  localparam logic [2:0] F3_SB  = 3'b000;
  localparam logic [2:0] F3_SH  = 3'b001;
  localparam logic [2:0] F3_SW  = 3'b010;

  typedef enum logic [3:0] {
    ALU_ADD   = 4'd0,
    ALU_SUB   = 4'd1,
    ALU_AND   = 4'd2,
    ALU_OR    = 4'd3,
    ALU_XOR   = 4'd4,
    ALU_SLL   = 4'd5,
    ALU_SRL   = 4'd6,
    ALU_SRA   = 4'd7,
    ALU_SLT   = 4'd8,
    ALU_SLTU  = 4'd9,
    ALU_LUI   = 4'd10,
    ALU_AUIPC = 4'd11,
    ALU_MUL   = 4'd12,
    ALU_MULH  = 4'd13,
    ALU_MULHSU= 4'd14,
    ALU_MULHU = 4'd15
  } alu_op_e;

  typedef enum logic [1:0] {
    DIV_NONE = 2'd0,
    DIV_DIV  = 2'd1,
    DIV_DIVU = 2'd2,
    DIV_REM  = 2'd3
  } div_op_e;

  typedef enum logic [1:0] {
    SRC_B_RS2 = 2'd0,
    SRC_B_IMM = 2'd1,
    SRC_B_PC  = 2'd2
  } src_b_sel_e;

  typedef enum logic [1:0] {
    WB_ALU = 2'd0,
    WB_MEM = 2'd1,
    WB_PC4 = 2'd2
  } wb_sel_e;

  typedef struct packed {
    logic        reg_write;
    logic        mem_read;
    logic        mem_write;
    logic [2:0]  mem_size;
    logic        branch;
    logic        jump;
    logic        jalr;
    alu_op_e     alu_op;
    src_b_sel_e  src_b;
    wb_sel_e     wb_sel;
    div_op_e     div_op;
    logic        is_mul;
    logic        is_div;
    logic        is_signed_div;
    logic        want_rem;
    logic [REG_BITS-1:0] rd;
    logic [REG_BITS-1:0] rs1;
    logic [REG_BITS-1:0] rs2;
    logic [XLEN-1:0]     imm;
    logic [XLEN-1:0]     pc;
  } ctrl_t;

endpackage
