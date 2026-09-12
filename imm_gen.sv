// imm_gen.sv: Immediate Generator

import riscv_pkg::*;

module imm_gen (
  input  logic [31:0]      instr,
  output logic [XLEN-1:0]  imm
);
  logic [6:0] opcode;
  assign opcode = instr[6:0];

  // Precompute all immediate formats
  logic [XLEN-1:0] imm_i, imm_s, imm_b, imm_u, imm_j;
  assign imm_i = {{20{instr[31]}}, instr[31:20]};
  assign imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
  assign imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
  assign imm_u = {instr[31:12], 12'b0};
  assign imm_j = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};

  always_comb begin
    case (opcode)
      7'b001_0011,   // OP_IMM
      7'b000_0011,   // OP_LOAD
      7'b110_0111:   imm = imm_i;  // OP_JALR
      7'b010_0011:   imm = imm_s;  // OP_STORE
      7'b110_0011:   imm = imm_b;  // OP_BRANCH
      7'b001_0111,   // OP_AUIPC
      7'b011_0111:   imm = imm_u;  // OP_LUI
      7'b110_1111:   imm = imm_j;  // OP_JAL
      default:       imm = '0;
    endcase
  end
endmodule
