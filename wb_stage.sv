// wb_stage.sv: Write-Back Stage

import riscv_pkg::*;

module wb_stage (
  // MEM/WB inputs
  input  ctrl_t             mem_wb_ctrl,
  input  logic [XLEN-1:0]  mem_wb_alu_result,
  input  logic [XLEN-1:0]  mem_wb_load_data,

  // Outputs to register file (in id_stage)
  output logic              wb_reg_write,
  output logic [REG_BITS-1:0] wb_rd,
  output logic [XLEN-1:0]  wb_data,

  // Forwarding alias
  output logic [XLEN-1:0]  mem_wb_wd
);

  // Write-back mux
  always_comb begin
    unique case (mem_wb_ctrl.wb_sel)
      WB_MEM : wb_data = mem_wb_load_data;
      WB_PC4 : wb_data = mem_wb_ctrl.pc + 4;
      default: wb_data = mem_wb_alu_result;  // WB_ALU
    endcase
  end

  assign wb_reg_write = mem_wb_ctrl.reg_write;
  assign wb_rd        = mem_wb_ctrl.rd;
  assign mem_wb_wd    = wb_data;   // forwarding alias

endmodule
