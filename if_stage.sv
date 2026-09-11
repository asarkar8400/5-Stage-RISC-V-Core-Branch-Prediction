// if_stage.sv — Instruction Fetch Stage

import riscv_pkg::*;

module if_stage (
  input  logic              clk,
  input  logic              rst_n,

  // Stall from hazard unit (load-use)
  input  logic              stall_if,

  // Redirect from ID (branch target — always-taken speculation)
  input  logic              branch_taken_id,
  input  logic [XLEN-1:0]  branch_target_id,

  // Flush from EX (mispredict — branch was NOT taken)
  input  logic              flush_if,
  input  logic [XLEN-1:0]  flush_target,   // PC+4 of the branch

  // Output to Instruction Buffer
  output logic [XLEN-1:0]  if_pc,
  output logic [31:0]       if_instr,
  output logic              if_valid
);

  // -------------------------------------------------------------------------
  // Program Counter
  // -------------------------------------------------------------------------
  logic [XLEN-1:0] pc_q, pc_next;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)        pc_q <= '0;
    else if (!stall_if) pc_q <= pc_next;
  end

  // PC mux priority: flush > branch speculation > +4
  always_comb begin
    if (flush_if)
      pc_next = flush_target;
    else if (branch_taken_id)
      pc_next = branch_target_id;
    else
      pc_next = pc_q + 4;
  end

  // -------------------------------------------------------------------------
  // Instruction Memory
  // 4 KB by default, parameterisable
  // -------------------------------------------------------------------------
  localparam int MEM_DEPTH = 1024;  // words

  logic [31:0] imem [0:MEM_DEPTH-1];

  // Initialise from hex file when available (simulation only)
  initial begin
    for (int i = 0; i < MEM_DEPTH; i++) imem[i] = 32'h0000_0013; // NOP
    `ifdef IMEM_INIT_FILE
      $readmemh(`IMEM_INIT_FILE, imem);
    `endif
  end

  // Single-cycle combinational read (Harvard model)
  assign if_instr = imem[pc_q[XLEN-1:2]];   // word-aligned

  // -------------------------------------------------------------------------
  // Outputs
  // -------------------------------------------------------------------------
  assign if_pc    = pc_q;
  assign if_valid = !flush_if;   // bubble during flush cycle

endmodule
