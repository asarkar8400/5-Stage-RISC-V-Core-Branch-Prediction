// riscv_core.sv — Top-Level Core
import riscv_pkg::*;

module riscv_core (
  input  logic clk,
  input  logic rst_n
);

  // IF outputs
  logic [XLEN-1:0] if_pc;
  logic [31:0]     if_instr;
  logic            if_valid;

  // IB outputs
  logic [XLEN-1:0] ib_pc;
  logic [31:0]     ib_instr;
  logic            ib_valid;
  logic            ib_stall_if;

  // ID outputs
  ctrl_t           id_ex_ctrl;
  logic [XLEN-1:0] id_ex_rs1_data, id_ex_rs2_data;
  logic [31:0]     id_ex_raw_instr;
  logic            branch_taken_id;
  logic [XLEN-1:0] branch_target_id;

  // EX outputs
  ctrl_t           ex_mem_ctrl;
  logic [XLEN-1:0] ex_mem_alu_result;
  logic [XLEN-1:0] ex_mem_rs2_data;
  logic            branch_mispredict;
  logic [XLEN-1:0] branch_pc_plus4;
  logic            ex_mem_div_busy;

  // MEM outputs
  ctrl_t           mem_wb_ctrl;
  logic [XLEN-1:0] mem_wb_alu_result;
  logic [XLEN-1:0] mem_wb_load_data;

  // WB outputs
  logic            wb_reg_write;
  logic [REG_BITS-1:0] wb_rd;
  logic [XLEN-1:0] wb_data;
  logic [XLEN-1:0] mem_wb_wd;

  // Hazard outputs
  logic [1:0]      fwd_a, fwd_b;
  logic            stall_if, stall_id, stall_ex;
  logic            flush_if, flush_id;
  logic [XLEN-1:0] flush_target;

  // IF
  if_stage u_if (
    .clk              (clk),
    .rst_n            (rst_n),
    .stall_if         (stall_if || ib_stall_if),
    .branch_taken_id  (branch_taken_id),
    .branch_target_id (branch_target_id),
    .flush_if         (flush_if),
    .flush_target     (flush_target),
    .if_pc            (if_pc),
    .if_instr         (if_instr),
    .if_valid         (if_valid)
  );

  // Instruction Buffer
  instr_buffer u_ib (
    .clk         (clk),
    .rst_n       (rst_n),
    .if_pc       (if_pc),
    .if_instr    (if_instr),
    .if_valid    (if_valid),
    .stall_id    (stall_id),
    .flush       (flush_if),
    .ib_stall_if (ib_stall_if),
    .ib_pc       (ib_pc),
    .ib_instr    (ib_instr),
    .ib_valid    (ib_valid)
  );

  // ID
  id_stage u_id (
    .clk              (clk),
    .rst_n            (rst_n),
    .ib_pc            (ib_pc),
    .ib_instr         (ib_instr),
    .ib_valid         (ib_valid),
    .stall_id         (stall_id),
    .flush_id         (flush_id),
    .wb_reg_write     (wb_reg_write),
    .wb_rd            (wb_rd),
    .wb_data          (wb_data),
    .branch_taken_id  (branch_taken_id),
    .branch_target_id (branch_target_id),
    .id_ex_ctrl       (id_ex_ctrl),
    .id_ex_rs1_data   (id_ex_rs1_data),
    .id_ex_rs2_data   (id_ex_rs2_data),
    .id_ex_raw_instr  (id_ex_raw_instr)
  );

  // EX
  ex_stage u_ex (
    .clk                (clk),
    .rst_n              (rst_n),
    .id_ex_ctrl         (id_ex_ctrl),
    .id_ex_rs1_data     (id_ex_rs1_data),
    .id_ex_rs2_data     (id_ex_rs2_data),
    .id_ex_raw_instr    (id_ex_raw_instr),
    .fwd_a              (fwd_a),
    .fwd_b              (fwd_b),
    .ex_mem_alu_result  (ex_mem_alu_result),
    .mem_wb_wd          (mem_wb_wd),
    .stall_ex           (stall_ex),
    .flush_ex           (flush_id),
    .branch_mispredict  (branch_mispredict),
    .branch_pc_plus4    (branch_pc_plus4),
    .ex_mem_ctrl        (ex_mem_ctrl),
    .ex_mem_alu_result_o(ex_mem_alu_result),
    .ex_mem_rs2_data    (ex_mem_rs2_data),
    .ex_mem_div_busy    (ex_mem_div_busy)
  );

  // MEM
  mem_stage u_mem (
    .clk               (clk),
    .rst_n             (rst_n),
    .ex_mem_ctrl       (ex_mem_ctrl),
    .ex_mem_alu_result (ex_mem_alu_result),
    .ex_mem_rs2_data   (ex_mem_rs2_data),
    .mem_wb_ctrl       (mem_wb_ctrl),
    .mem_wb_alu_result (mem_wb_alu_result),
    .mem_wb_load_data  (mem_wb_load_data)
  );

  // WB
  wb_stage u_wb (
    .mem_wb_ctrl       (mem_wb_ctrl),
    .mem_wb_alu_result (mem_wb_alu_result),
    .mem_wb_load_data  (mem_wb_load_data),
    .wb_reg_write      (wb_reg_write),
    .wb_rd             (wb_rd),
    .wb_data           (wb_data),
    .mem_wb_wd         (mem_wb_wd)
  );

  // Hazard Unit
  hazard_unit u_haz (
    .id_ex_rs1         (id_ex_ctrl.rs1),
    .id_ex_rs2         (id_ex_ctrl.rs2),
    .id_ex_is_div      (id_ex_ctrl.is_div),      // ← new: immediate DIV stall
    .ex_mem_rd         (ex_mem_ctrl.rd),
    .ex_mem_reg_write  (ex_mem_ctrl.reg_write),
    .ex_mem_mem_read   (ex_mem_ctrl.mem_read),
    .mem_wb_rd         (mem_wb_ctrl.rd),
    .mem_wb_reg_write  (mem_wb_ctrl.reg_write),
    .branch_mispredict (branch_mispredict),
    .branch_pc_plus4   (branch_pc_plus4),
    .div_busy          (ex_mem_div_busy),
    .fwd_a             (fwd_a),
    .fwd_b             (fwd_b),
    .stall_if          (stall_if),
    .stall_id          (stall_id),
    .stall_ex          (stall_ex),
    .flush_if          (flush_if),
    .flush_id          (flush_id),
    .flush_target      (flush_target)
  );

endmodule
