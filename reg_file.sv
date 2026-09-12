// =============================================================================
// reg_file.sv: 32×32 Register File
//   • 2 asynchronous read ports (rs1, rs2)
//   • 1 synchronous write port (rd) — write on posedge clk
//   • x0 permanently wired to 0
//   • Write-before-read at same address (forwarding from WB handled externally,
//     but same-cycle bypass is provided here via combinational mux)
// =============================================================================
import riscv_pkg::*;

module reg_file (
  input  logic                    clk,
  input  logic                    rst_n,

  // Read ports (combinational)
  input  logic [REG_BITS-1:0]     rs1_addr,
  input  logic [REG_BITS-1:0]     rs2_addr,
  output logic [XLEN-1:0]         rs1_data,
  output logic [XLEN-1:0]         rs2_data,

  // Write port (synchronous)
  input  logic                    we,
  input  logic [REG_BITS-1:0]     rd_addr,
  input  logic [XLEN-1:0]         rd_data
);

  // -------------------------------------------------------------------------
  // Storage
  // -------------------------------------------------------------------------
  logic [XLEN-1:0] rf [0:31];

  // Reset all registers to 0
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < 32; i++) rf[i] <= '0;
    end else if (we && rd_addr != '0) begin
      rf[rd_addr] <= rd_data;
    end
  end

  // -------------------------------------------------------------------------
  // Read ports are asynchronous with same-cycle WB bypass
  // -------------------------------------------------------------------------
  // If WB is writing the same register we are reading, forward immediately
  // (avoids a 1-cycle stall at the WB→ID boundary — this is the WB forward path)
  assign rs1_data = (we && rd_addr == rs1_addr && rs1_addr != '0)
                     ? rd_data : rf[rs1_addr];

  assign rs2_data = (we && rd_addr == rs2_addr && rs2_addr != '0) ? rd_data : rf[rs2_addr];

endmodule
