// alu.sv: ALU + restoring divider (zero enum comparisons)

import riscv_pkg::*;

module alu (
  input  logic              clk,
  input  logic              rst_n,
  input  logic [XLEN-1:0]  a,
  input  logic [XLEN-1:0]  b,
  input  logic [XLEN-1:0]  pc_in,
  input  alu_op_e           alu_op,
  input  div_op_e           div_op,     
  input  logic              is_mul,
  input  logic [2:0]        funct3,
  
  // DIV control — precomputed in ctrl_t, no enum comparison needed here
  input  logic              div_start,
  input  logic              is_signed_div,
  input  logic              want_rem,
  output logic [XLEN-1:0]  result,
  output logic              div_busy,
  output logic [XLEN-1:0]  div_result
);

  logic [63:0] mul_ss, mul_su, mul_uu;
  assign mul_ss = $signed(a) * $signed(b);
  assign mul_su = $signed(a) * $unsigned(b);
  assign mul_uu = $unsigned(a) * $unsigned(b);

  always_comb begin
    case (alu_op)
      ALU_ADD   : result = a + b;
      ALU_SUB   : result = a - b;
      ALU_AND   : result = a & b;
      ALU_OR    : result = a | b;
      ALU_XOR   : result = a ^ b;
      ALU_SLL   : result = a << b[4:0];
      ALU_SRL   : result = a >> b[4:0];
      ALU_SRA   : result = $signed(a) >>> b[4:0];
      ALU_SLT   : result = {31'b0, ($signed(a) < $signed(b))};
      ALU_SLTU  : result = {31'b0, (a < b)};
      ALU_LUI   : result = b;
      ALU_AUIPC : result = pc_in + b;
      ALU_MUL   : result = mul_ss[31:0];
      ALU_MULH  : result = mul_ss[63:32];
      ALU_MULHSU: result = mul_su[63:32];
      ALU_MULHU : result = mul_uu[63:32];
      default   : result = '0;
    endcase
  end

  div_unit u_div (
    .clk       (clk),
    .rst_n     (rst_n),
    .start     (div_start),
    .dividend  (a),
    .divisor   (b),
    .is_signed (is_signed_div),
    .want_rem  (want_rem),
    .busy      (div_busy),
    .result    (div_result)
  );

endmodule


// =============================================================================
// div_unit: 32-bit restoring long divider
// =============================================================================
module div_unit (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        start,
  input  logic [31:0] dividend,
  input  logic [31:0] divisor,
  input  logic        is_signed,
  input  logic        want_rem,
  output logic        busy,
  output logic [31:0] result
);
  typedef enum logic [1:0] { ST_IDLE=2'd0, ST_RUN=2'd1, ST_DONE=2'd2 } state_e;
  state_e state;

  logic [31:0] dvd_abs, dvs_abs;
  logic [31:0] quot_acc;
  logic [32:0] partial;
  logic [5:0]  count;
  logic        neg_quot, neg_rem;
  logic [31:0] quot_out, rem_out;
  logic        just_done;

  assign busy = (state != ST_IDLE) || (start && !just_done);
  assign result = want_rem ? rem_out : quot_out;

  // Combinational for RUN state
  logic [5:0]  bit_idx;
  logic [32:0] shifted_rem;
  assign bit_idx     = count - 6'd1;
  assign shifted_rem = {partial[31:0], dvd_abs[bit_idx]};

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state    <= ST_IDLE;
      quot_acc <= '0;
      partial  <= '0;
      count    <= '0;
      neg_quot <= '0;
      neg_rem  <= '0;
      dvd_abs  <= '0;
      dvs_abs  <= '0;
      quot_out  <= '0;
      rem_out  <= '0;
      just_done <= '0;
    end else begin
      case (state)

        ST_IDLE: begin
          just_done <= 1'b0;
          if (start && !just_done) begin
            dvd_abs  <= (is_signed && dividend[31]) ? (~dividend + 32'b1) : dividend;
            dvs_abs  <= (is_signed && divisor[31])  ? (~divisor  + 32'b1) : divisor;
            neg_quot <= is_signed && (dividend[31] ^ divisor[31]) && !want_rem && (divisor != '0);
            neg_rem  <= is_signed && dividend[31] && want_rem;
            if (divisor == 32'b0) begin
              quot_out <= 32'hFFFF_FFFF;
              rem_out  <= dividend;
              state    <= ST_DONE;
            end else begin
              quot_acc <= '0;
              partial  <= '0;
              count    <= 6'd32;
              state    <= ST_RUN;
            end
          end
        end

        ST_RUN: begin
          if (shifted_rem >= {1'b0, dvs_abs}) begin
            partial  <= shifted_rem - {1'b0, dvs_abs};
            quot_acc <= quot_acc | (32'b1 << bit_idx);
          end else begin
            partial  <= shifted_rem;
          end
          count <= count - 1;
          if (count == 6'd1) state <= ST_DONE;
        end

        ST_DONE: begin
          // Latch sign-corrected results
          quot_out  <= neg_quot ? (~quot_acc + 32'b1) : quot_acc;
          rem_out   <= neg_rem  ? (~partial[31:0] + 32'b1) : partial[31:0];
          just_done <= 1'b1;  // prevent immediate relaunch when we return to IDLE
          state     <= ST_IDLE;
        end

        default: state <= ST_IDLE;
      endcase
    end
  end
endmodule
