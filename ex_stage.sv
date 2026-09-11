// ex_stage.sv — Execute Stage

import riscv_pkg::*;

module ex_stage (
  input  logic              clk,
  input  logic              rst_n,
  input  ctrl_t             id_ex_ctrl,
  input  logic [XLEN-1:0]  id_ex_rs1_data,
  input  logic [XLEN-1:0]  id_ex_rs2_data,
  input  logic [31:0]       id_ex_raw_instr,
  input  logic [1:0]        fwd_a,
  input  logic [1:0]        fwd_b,
  input  logic [XLEN-1:0]  ex_mem_alu_result,
  input  logic [XLEN-1:0]  mem_wb_wd,
  input  logic              stall_ex,
  input  logic              flush_ex,
  output logic              branch_mispredict,
  output logic [XLEN-1:0]  branch_pc_plus4,
  output ctrl_t             ex_mem_ctrl,
  output logic [XLEN-1:0]  ex_mem_alu_result_o,
  output logic [XLEN-1:0]  ex_mem_rs2_data,
  output logic              ex_mem_div_busy
);

  // Forwarding muxes
  logic [XLEN-1:0] op_a, op_b_reg;
  always_comb begin
    case (fwd_a)
      2'b01:   op_a = ex_mem_alu_result;
      2'b10:   op_a = mem_wb_wd;
      default: op_a = id_ex_rs1_data;
    endcase
    case (fwd_b)
      2'b01:   op_b_reg = ex_mem_alu_result;
      2'b10:   op_b_reg = mem_wb_wd;
      default: op_b_reg = id_ex_rs2_data;
    endcase
  end

  // ALU src-B mux
  logic [XLEN-1:0] alu_b;
  always_comb begin
    case (id_ex_ctrl.src_b)
      SRC_B_IMM,
      SRC_B_PC : alu_b = id_ex_ctrl.imm;
      default:   alu_b = op_b_reg;
    endcase
  end

  // Precomputed DIV controls from ctrl_t (all plain logic, no enum comparison)
  logic div_start;
  assign div_start = id_ex_ctrl.is_div;

  logic [XLEN-1:0] alu_result, div_result;
  logic div_busy;

  alu u_alu (
    .clk           (clk),
    .rst_n         (rst_n),
    .a             (op_a),
    .b             (alu_b),
    .pc_in         (id_ex_ctrl.pc),
    .alu_op        (id_ex_ctrl.alu_op),
    .div_op        (id_ex_ctrl.div_op),
    .is_mul        (id_ex_ctrl.is_mul),
    .funct3        (id_ex_raw_instr[14:12]),
    .div_start     (div_start),
    .is_signed_div (id_ex_ctrl.is_signed_div),
    .want_rem      (id_ex_ctrl.want_rem),
    .result        (alu_result),
    .div_busy      (div_busy),
    .div_result    (div_result)
  );

  assign ex_mem_div_busy = div_busy;

  // Result mux: div result when is_div set, else ALU result
  logic [XLEN-1:0] ex_result;
  assign ex_result = id_ex_ctrl.is_div ? div_result : alu_result;

  // Branch condition evaluation
  logic branch_taken;
  always_comb begin
    branch_taken = 1'b0;
    if (id_ex_ctrl.branch) begin
      case (id_ex_raw_instr[14:12])
        3'b000: branch_taken = (op_a == op_b_reg);
        3'b001: branch_taken = (op_a != op_b_reg);
        3'b100: branch_taken = ($signed(op_a) <  $signed(op_b_reg));
        3'b101: branch_taken = ($signed(op_a) >= $signed(op_b_reg));
        3'b110: branch_taken = (op_a < op_b_reg);
        3'b111: branch_taken = (op_a >= op_b_reg);
        default: branch_taken = 1'b0;
      endcase
    end
  end

  assign branch_mispredict = id_ex_ctrl.branch && !branch_taken;
  assign branch_pc_plus4   = id_ex_ctrl.pc + 4;

  // EX/MEM pipeline register
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n || flush_ex) begin
      ex_mem_ctrl         <= '0;
      ex_mem_alu_result_o <= '0;
      ex_mem_rs2_data     <= '0;
    end else if (!stall_ex) begin
      ex_mem_ctrl         <= id_ex_ctrl;
      ex_mem_alu_result_o <= ex_result;
      ex_mem_rs2_data     <= op_b_reg;
    end
  end

endmodule
