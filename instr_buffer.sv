// =============================================================================
// instr_buffer.sv — 1-Deep Skid Buffer (Instruction Buffer) between IF and ID
//
// This is a skid buffer that:
//   • Decouples the IF stage from the ID stage during stalls
//   • When ID is stalled and IF produces a new instruction, we hold it here so IF does not need to re-fetch
//   • Injects bubbles on flush (sets valid=0)
//
// State machine:
//   EMPTY : no entry held; pass-through from IF to ID
//   FULL  : ID stalled, holding an instruction; freeze IF
// =============================================================================

import riscv_pkg::*;

module instr_buffer (
  input  logic              clk,
  input  logic              rst_n,

  // From IF
  input  logic [XLEN-1:0]  if_pc,
  input  logic [31:0]       if_instr,
  input  logic              if_valid,

  // Stall from hazard unit (ID cannot accept new instruction)
  input  logic              stall_id,

  // Flush (mispredict or branch redirect — invalidate contents)
  input  logic              flush,

  // To IF (back-pressure)
  output logic              ib_stall_if,  // tell IF to hold its PC

  // To ID
  output logic [XLEN-1:0]  ib_pc,
  output logic [31:0]       ib_instr,
  output logic              ib_valid
);

  // -------------------------------------------------------------------------
  // Internal storage
  // -------------------------------------------------------------------------
  logic [XLEN-1:0]  hold_pc;
  logic [31:0]       hold_instr;
  logic              hold_valid;   // buffer occupancy

  // -------------------------------------------------------------------------
  // Skid buffer logic
  // -------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      hold_pc    <= '0;
      hold_instr <= 32'h0000_0013;
      hold_valid <= 1'b0;
    end else if (flush) begin
      // Flush: discard whatever we hold
      hold_valid <= 1'b0;
    end else if (stall_id && !hold_valid && if_valid) begin
      // ID stalled and buffer empty: capture incoming instruction
      hold_pc    <= if_pc;
      hold_instr <= if_instr;
      hold_valid <= 1'b1;
    end else if (!stall_id && hold_valid) begin
      // ID accepts the held instruction; drain the buffer
      hold_valid <= 1'b0;
    end
  end

  // -------------------------------------------------------------------------
  // Output mux: serve from buffer if full, else pass IF through
  // -------------------------------------------------------------------------
  always_comb begin
    if (hold_valid) begin
      ib_pc    = hold_pc;
      ib_instr = hold_instr;
      ib_valid = 1'b1;
    end else begin
      ib_pc    = if_pc;
      ib_instr = if_instr;
      ib_valid = if_valid;
    end
  end

  // Back-pressure to IF: stall IF when buffer is full (ID stalled, buffer occupied)
  assign ib_stall_if = hold_valid;

endmodule
