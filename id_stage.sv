// id_stage.sv — Instruction Decode Stage

import riscv_pkg::*;

module id_stage (
  input  logic              clk,
  input  logic              rst_n,
  input  logic [XLEN-1:0]  ib_pc,
  input  logic [31:0]       ib_instr,
  input  logic              ib_valid,
  input  logic              stall_id,
  input  logic              flush_id,
  input  logic              wb_reg_write,
  input  logic [REG_BITS-1:0] wb_rd,
  input  logic [XLEN-1:0]  wb_data,
  output logic              branch_taken_id,
  output logic [XLEN-1:0]  branch_target_id,
  output ctrl_t             id_ex_ctrl,
  output logic [XLEN-1:0]  id_ex_rs1_data,
  output logic [XLEN-1:0]  id_ex_rs2_data,
  output logic [31:0]       id_ex_raw_instr
);

  ctrl_t ctrl_w;

  control_unit u_ctrl (
    .instr (ib_instr),
    .pc    (ib_pc),
    .ctrl  (ctrl_w)
  );

  logic [XLEN-1:0] rs1_data_w, rs2_data_w;

  reg_file u_rf (
    .clk      (clk),
    .rst_n    (rst_n),
    .rs1_addr (ctrl_w.rs1),
    .rs2_addr (ctrl_w.rs2),
    .rs1_data (rs1_data_w),
    .rs2_data (rs2_data_w),
    .we       (wb_reg_write),
    .rd_addr  (wb_rd),
    .rd_data  (wb_data)
  );

  logic [XLEN-1:0] branch_target_w;
  assign branch_target_w = ctrl_w.jalr ? ((rs1_data_w + ctrl_w.imm) & ~32'h1) : (ib_pc + ctrl_w.imm);

  assign branch_taken_id  = ib_valid && !stall_id && !flush_id && (ctrl_w.branch || ctrl_w.jump);
  assign branch_target_id = branch_target_w;

  // NOP ctrl = '0 (all enum zeros: ALU_ADD=0, SRC_B_RS2=0, WB_ALU=0, DIV_NONE=0)
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n || flush_id) begin
      id_ex_ctrl      <= '0;
      id_ex_rs1_data  <= '0;
      id_ex_rs2_data  <= '0;
      id_ex_raw_instr <= 32'h0000_0013;
    end else if (!stall_id) begin
      if (!ib_valid) begin
        id_ex_ctrl      <= '0;
        id_ex_rs1_data  <= '0;
        id_ex_rs2_data  <= '0;
        id_ex_raw_instr <= 32'h0000_0013;
      end else begin
        id_ex_ctrl      <= ctrl_w;
        id_ex_rs1_data  <= rs1_data_w;
        id_ex_rs2_data  <= rs2_data_w;
        id_ex_raw_instr <= ib_instr;
      end
    end
  end

endmodule
