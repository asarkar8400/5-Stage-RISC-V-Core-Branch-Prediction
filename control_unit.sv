// control_unit.sv

import riscv_pkg::*;

module control_unit (
  input  logic [31:0]      instr,
  input  logic [XLEN-1:0]  pc,
  output ctrl_t             ctrl
);
  logic [6:0] opcode;
  logic [2:0] funct3;
  logic [6:0] funct7;
  assign opcode = instr[6:0];
  assign funct3 = instr[14:12];
  assign funct7 = instr[31:25];

  logic [XLEN-1:0] imm_w;
  imm_gen u_imm (.instr(instr), .imm(imm_w));

  // NOP ctrl = all zeros except alu_op=ADD, src_b=RS2, wb_sel=ALU, div_op=NONE
  always_comb begin
    // Default: NOP (all zeros = ALU_ADD, SRC_B_RS2, WB_ALU, DIV_NONE)
    ctrl          = '0;
    ctrl.rd       = instr[11:7];
    ctrl.rs1      = instr[19:15];
    ctrl.rs2      = instr[24:20];
    ctrl.imm      = imm_w;
    ctrl.pc       = pc;

    case (opcode)
      7'b011_0011: begin // OP_REG
        ctrl.reg_write = 1'b1;
        if (funct7 == 7'b000_0001) begin
          // M-extension
          case (funct3)
            3'b000: begin ctrl.is_mul=1; ctrl.alu_op=ALU_MUL;     end
            3'b001: begin ctrl.is_mul=1; ctrl.alu_op=ALU_MULH;    end
            3'b010: begin ctrl.is_mul=1; ctrl.alu_op=ALU_MULHSU;  end
            3'b011: begin ctrl.is_mul=1; ctrl.alu_op=ALU_MULHU;   end
            3'b100: begin ctrl.div_op=DIV_DIV;  ctrl.is_div=1'b1; ctrl.is_signed_div=1'b1; ctrl.want_rem=1'b0; end
            3'b101: begin ctrl.div_op=DIV_DIVU; ctrl.is_div=1'b1; ctrl.is_signed_div=1'b0; ctrl.want_rem=1'b0; end
            3'b110: begin ctrl.div_op=DIV_REM;  ctrl.is_div=1'b1; ctrl.is_signed_div=1'b1; ctrl.want_rem=1'b1; end
            3'b111: begin ctrl.div_op=DIV_NONE; ctrl.is_div=1'b1; ctrl.is_signed_div=1'b0; ctrl.want_rem=1'b1; end // REMU
            default:;
          endcase
        end else begin
          case ({funct7[5], funct3})
            4'b0_000: ctrl.alu_op = ALU_ADD;
            4'b1_000: ctrl.alu_op = ALU_SUB;
            4'b0_001: ctrl.alu_op = ALU_SLL;
            4'b0_010: ctrl.alu_op = ALU_SLT;
            4'b0_011: ctrl.alu_op = ALU_SLTU;
            4'b0_100: ctrl.alu_op = ALU_XOR;
            4'b0_101: ctrl.alu_op = ALU_SRL;
            4'b1_101: ctrl.alu_op = ALU_SRA;
            4'b0_110: ctrl.alu_op = ALU_OR;
            4'b0_111: ctrl.alu_op = ALU_AND;
            default:  ctrl.alu_op = ALU_ADD;
          endcase
        end
      end

      7'b001_0011: begin // OP_IMM
        ctrl.reg_write = 1'b1;
        ctrl.src_b     = SRC_B_IMM;
        case (funct3)
          3'b000: ctrl.alu_op = ALU_ADD;
          3'b010: ctrl.alu_op = ALU_SLT;
          3'b011: ctrl.alu_op = ALU_SLTU;
          3'b100: ctrl.alu_op = ALU_XOR;
          3'b110: ctrl.alu_op = ALU_OR;
          3'b111: ctrl.alu_op = ALU_AND;
          3'b001: ctrl.alu_op = ALU_SLL;
          3'b101: ctrl.alu_op = funct7[5] ? ALU_SRA : ALU_SRL;
          default: ctrl.alu_op = ALU_ADD;
        endcase
      end

      7'b000_0011: begin // OP_LOAD
        ctrl.reg_write = 1'b1;
        ctrl.mem_read  = 1'b1;
        ctrl.src_b     = SRC_B_IMM;
        ctrl.wb_sel    = WB_MEM;
        ctrl.alu_op    = ALU_ADD;
        ctrl.mem_size  = funct3;
      end

      7'b010_0011: begin // OP_STORE
        ctrl.mem_write = 1'b1;
        ctrl.src_b     = SRC_B_IMM;
        ctrl.alu_op    = ALU_ADD;
        ctrl.mem_size  = funct3;
      end

      7'b110_0011: begin // OP_BRANCH
        ctrl.branch  = 1'b1;
        ctrl.alu_op  = ALU_SUB;
      end

      7'b110_1111: begin // OP_JAL
        ctrl.reg_write = 1'b1;
        ctrl.jump      = 1'b1;
        ctrl.wb_sel    = WB_PC4;
      end

      7'b110_0111: begin // OP_JALR
        ctrl.reg_write = 1'b1;
        ctrl.jump      = 1'b1;
        ctrl.jalr      = 1'b1;
        ctrl.src_b     = SRC_B_IMM;
        ctrl.wb_sel    = WB_PC4;
        ctrl.alu_op    = ALU_ADD;
      end

      7'b011_0111: begin // OP_LUI
        ctrl.reg_write = 1'b1;
        ctrl.src_b     = SRC_B_IMM;
        ctrl.alu_op    = ALU_LUI;
      end

      7'b001_0111: begin // OP_AUIPC
        ctrl.reg_write = 1'b1;
        ctrl.src_b     = SRC_B_PC;
        ctrl.alu_op    = ALU_AUIPC;
      end

      default: ; // NOP / illegal
    endcase
  end
endmodule
