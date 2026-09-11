// mem_stage.sv: Memory Access Stage

import riscv_pkg::*;

module mem_stage (
  input  logic              clk,
  input  logic              rst_n,
  input  ctrl_t             ex_mem_ctrl,
  input  logic [XLEN-1:0]  ex_mem_alu_result,
  input  logic [XLEN-1:0]  ex_mem_rs2_data,
  output ctrl_t             mem_wb_ctrl,
  output logic [XLEN-1:0]  mem_wb_alu_result,
  output logic [XLEN-1:0]  mem_wb_load_data
);

  localparam int DMEM_DEPTH = 1024;
  logic [31:0] dmem [0:DMEM_DEPTH-1];

  initial begin
    integer i;
    for (i = 0; i < DMEM_DEPTH; i++) dmem[i] = '0;
  end

  logic [9:0]  word_addr;
  logic [1:0]  byte_off;
  assign word_addr = ex_mem_alu_result[11:2];
  assign byte_off  = ex_mem_alu_result[1:0];

  // Store
  always_ff @(posedge clk) begin
    if (ex_mem_ctrl.mem_write) begin
      case (ex_mem_ctrl.mem_size)
        3'b010: dmem[word_addr] <= ex_mem_rs2_data; // SW
        3'b001: begin                               // SH
          if (byte_off[1])
            dmem[word_addr][31:16] <= ex_mem_rs2_data[15:0];
          else
            dmem[word_addr][15:0]  <= ex_mem_rs2_data[15:0];
        end
        3'b000: begin                               // SB
          case (byte_off)
            2'b00: dmem[word_addr][ 7: 0] <= ex_mem_rs2_data[7:0];
            2'b01: dmem[word_addr][15: 8] <= ex_mem_rs2_data[7:0];
            2'b10: dmem[word_addr][23:16] <= ex_mem_rs2_data[7:0];
            2'b11: dmem[word_addr][31:24] <= ex_mem_rs2_data[7:0];
          endcase
        end
        default: ;
      endcase
    end
  end

  // Load (combinational)
  logic [31:0] raw_ld;
  assign raw_ld = dmem[word_addr];

  logic [XLEN-1:0] load_data_w;
  always_comb begin
    load_data_w = '0;
    if (ex_mem_ctrl.mem_read) begin
      case (ex_mem_ctrl.mem_size)
        3'b010: load_data_w = raw_ld;                                    // LW
        3'b001: begin                                                    // LH
          logic [15:0] hw;
          hw = byte_off[1] ? raw_ld[31:16] : raw_ld[15:0];
          load_data_w = {{16{hw[15]}}, hw};
        end
        3'b101: begin                                                    // LHU
          logic [15:0] hw;
          hw = byte_off[1] ? raw_ld[31:16] : raw_ld[15:0];
          load_data_w = {16'b0, hw};
        end
        3'b000: begin                                                    // LB
          logic [7:0] b;
          case (byte_off)
            2'b00: b = raw_ld[ 7: 0];
            2'b01: b = raw_ld[15: 8];
            2'b10: b = raw_ld[23:16];
            2'b11: b = raw_ld[31:24];
          endcase
          load_data_w = {{24{b[7]}}, b};
        end
        3'b100: begin                                                    // LBU
          logic [7:0] b;
          case (byte_off)
            2'b00: b = raw_ld[ 7: 0];
            2'b01: b = raw_ld[15: 8];
            2'b10: b = raw_ld[23:16];
            2'b11: b = raw_ld[31:24];
          endcase
          load_data_w = {24'b0, b};
        end
        default: load_data_w = raw_ld;
      endcase
    end
  end

  // MEM/WB register
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mem_wb_ctrl       <= '0;
      mem_wb_alu_result <= '0;
      mem_wb_load_data  <= '0;
    end else begin
      mem_wb_ctrl       <= ex_mem_ctrl;
      mem_wb_alu_result <= ex_mem_alu_result;
      mem_wb_load_data  <= load_data_w;
    end
  end

endmodule
