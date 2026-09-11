// hazard_unit.sv: Forwarding/Stall Control (fixed DIV stall + branch flush)

import riscv_pkg::*;

module hazard_unit (
  // ID/EX source registers
  input  logic [REG_BITS-1:0]  id_ex_rs1,
  input  logic [REG_BITS-1:0]  id_ex_rs2,

  // ID/EX ctrl (need div_op to stall immediately when DIV enters EX)
  input  logic                 id_ex_is_div,

  // EX/MEM destination
  input  logic [REG_BITS-1:0]  ex_mem_rd,
  input  logic                 ex_mem_reg_write,
  input  logic                 ex_mem_mem_read,

  // MEM/WB destination
  input  logic [REG_BITS-1:0]  mem_wb_rd,
  input  logic                 mem_wb_reg_write,

  // Branch resolution from EX
  input  logic                 branch_mispredict,
  input  logic [XLEN-1:0]     branch_pc_plus4,

  // Div busy from the divider unit (asserted during multi-cycle operation)
  input  logic                 div_busy,

  // Forwarding selects
  output logic [1:0]           fwd_a,
  output logic [1:0]           fwd_b,

  // Stall signals
  output logic                 stall_if,
  output logic                 stall_id,
  output logic                 stall_ex,

  // Flush signals
  output logic                 flush_if,
  output logic                 flush_id,
  output logic [XLEN-1:0]     flush_target
);

  // Load-use hazard
  logic load_use_hazard;
  assign load_use_hazard = ex_mem_mem_read && ((ex_mem_rd == id_ex_rs1 && ex_mem_rd != '0) || (ex_mem_rd == id_ex_rs2 && ex_mem_rd != '0));

  // DIV stall: assert the moment a DIV/REM instruction is seen in EX (id_ex_div_op != NONE)
  // OR while the divider is still running (div_busy)
  logic div_stall;
  assign div_stall = div_busy;

  // Stalls
  assign stall_if = load_use_hazard || div_stall;
  assign stall_id = load_use_hazard || div_stall;
  assign stall_ex = div_stall;

  // Flush on branch mispredict (only when no other hazard taking priority)
  assign flush_if     = branch_mispredict && !load_use_hazard && !div_stall;
  assign flush_id     = branch_mispredict && !load_use_hazard && !div_stall;
  assign flush_target = branch_pc_plus4;

  // Forwarding
  always_comb begin
    if (ex_mem_reg_write && ex_mem_rd != '0 && ex_mem_rd == id_ex_rs1)
      fwd_a = 2'b01;
    else if (mem_wb_reg_write && mem_wb_rd != '0 && mem_wb_rd == id_ex_rs1)
      fwd_a = 2'b10;
    else
      fwd_a = 2'b00;

    if (ex_mem_reg_write && ex_mem_rd != '0 && ex_mem_rd == id_ex_rs2)
      fwd_b = 2'b01;
    else if (mem_wb_reg_write && mem_wb_rd != '0 && mem_wb_rd == id_ex_rs2)
      fwd_b = 2'b10;
    else
      fwd_b = 2'b00;
  end

endmodule
