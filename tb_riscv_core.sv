// tb_riscv_core.sv: Self-Checking Testbench for RISCV Core
import riscv_pkg::*;

module tb_riscv_core;

  logic clk = 0;
  logic rst_n;
  always #5 clk = ~clk;

  riscv_core dut (.clk(clk), .rst_n(rst_n));

  logic [31:0] rf [0:31];
  assign rf = dut.u_id.u_rf.rf;

  int pass_count = 0;
  int fail_count = 0;

  task automatic check(input string name, input logic [31:0] exp, input logic [31:0] act);
    if (exp === act) begin
      $display("[PASS] %-35s expected=0x%08X  actual=0x%08X", name, exp, act);
      pass_count++;
    end else begin
      $display("[FAIL] %-35s expected=0x%08X  actual=0x%08X", name, exp, act);
      fail_count++;
    end
  endtask

  task automatic imem_write(input int addr, input logic [31:0] data);
    dut.u_if.imem[addr] = data; endtask

  task automatic wait_cycles(input int n);
    repeat(n) @(posedge clk); #1; endtask

  task automatic do_reset();
    rst_n = 0; repeat(3) @(posedge clk); #1; rst_n = 1; #1; endtask

  task automatic clear_imem();
    for (int i = 0; i < 1024; i++) dut.u_if.imem[i] = 32'h0000_0013; endtask

  // ── Encoders ──────────────────────────────────────────────────────────────
  function automatic logic [31:0] mk_r(logic[4:0] rd,logic[4:0] rs1,logic[4:0] rs2,
    logic[2:0] f3,logic[6:0] f7,logic[6:0] op);
    return {f7,rs2,rs1,f3,rd,op}; endfunction
  function automatic logic [31:0] mk_i(logic[4:0] rd,logic[4:0] rs1,
    logic[2:0] f3,logic[11:0] imm,logic[6:0] op);
    return {imm,rs1,f3,rd,op}; endfunction
  function automatic logic [31:0] mk_s(logic[4:0] rs1,logic[4:0] rs2,
    logic[2:0] f3,logic[11:0] imm);
    return {imm[11:5],rs2,rs1,f3,imm[4:0],7'b010_0011}; endfunction
  function automatic logic [31:0] mk_b(logic[4:0] rs1,logic[4:0] rs2,
    logic[2:0] f3,logic[12:0] imm);
    return {imm[12],imm[10:5],rs2,rs1,f3,imm[4:1],imm[11],7'b110_0011}; endfunction
  function automatic logic [31:0] mk_j(logic[4:0] rd,logic[20:0] imm);
    return {imm[20],imm[10:1],imm[11],imm[19:12],rd,7'b110_1111}; endfunction

  function automatic logic [31:0] ADD(logic[4:0] rd,logic[4:0] rs1,logic[4:0] rs2);
    return mk_r(rd,rs1,rs2,3'b000,7'b000_0000,7'b011_0011); endfunction
  function automatic logic [31:0] SUB(logic[4:0] rd,logic[4:0] rs1,logic[4:0] rs2);
    return mk_r(rd,rs1,rs2,3'b000,7'b010_0000,7'b011_0011); endfunction
  function automatic logic [31:0] AND(logic[4:0] rd,logic[4:0] rs1,logic[4:0] rs2);
    return mk_r(rd,rs1,rs2,3'b111,7'b000_0000,7'b011_0011); endfunction
  function automatic logic [31:0] OR(logic[4:0] rd,logic[4:0] rs1,logic[4:0] rs2);
    return mk_r(rd,rs1,rs2,3'b110,7'b000_0000,7'b011_0011); endfunction
  function automatic logic [31:0] XOR(logic[4:0] rd,logic[4:0] rs1,logic[4:0] rs2);
    return mk_r(rd,rs1,rs2,3'b100,7'b000_0000,7'b011_0011); endfunction
  function automatic logic [31:0] SLT(logic[4:0] rd,logic[4:0] rs1,logic[4:0] rs2);
    return mk_r(rd,rs1,rs2,3'b010,7'b000_0000,7'b011_0011); endfunction
  function automatic logic [31:0] MUL(logic[4:0] rd,logic[4:0] rs1,logic[4:0] rs2);
    return mk_r(rd,rs1,rs2,3'b000,7'b000_0001,7'b011_0011); endfunction
  function automatic logic [31:0] DIV(logic[4:0] rd,logic[4:0] rs1,logic[4:0] rs2);
    return mk_r(rd,rs1,rs2,3'b100,7'b000_0001,7'b011_0011); endfunction
  function automatic logic [31:0] ADDI(logic[4:0] rd,logic[4:0] rs1,logic[11:0] imm);
    return mk_i(rd,rs1,3'b000,imm,7'b001_0011); endfunction
  function automatic logic [31:0] LW(logic[4:0] rd,logic[4:0] rs1,logic[11:0] imm);
    return mk_i(rd,rs1,3'b010,imm,7'b000_0011); endfunction
  function automatic logic [31:0] SW(logic[4:0] rs1,logic[4:0] rs2,logic[11:0] imm);
    return mk_s(rs1,rs2,3'b010,imm); endfunction
  function automatic logic [31:0] BEQ(logic[4:0] rs1,logic[4:0] rs2,logic[12:0] imm);
    return mk_b(rs1,rs2,3'b000,imm); endfunction
  function automatic logic [31:0] JAL(logic[4:0] rd,logic[20:0] imm);
    return mk_j(rd,imm); endfunction
  // JAL x0, 0 — infinite loop / halt
  function automatic logic [31:0] HALT();
    return mk_j(5'd0, 21'd0); endfunction
  function automatic logic [31:0] NOPI();
    return 32'h0000_0013; endfunction

  // ============================================================================
  // TEST 1: Basic ALU — no hazards
  // ============================================================================
  task automatic test_basic_alu();
    $display("\n=== Test 1: Basic ALU ===");
    clear_imem(); do_reset();
    imem_write(0,  ADDI(5'd1, 5'd0, 12'd10));
    imem_write(1,  ADDI(5'd2, 5'd0, 12'd3));
    imem_write(2,  NOPI()); imem_write(3, NOPI());
    imem_write(4,  ADD(5'd3, 5'd1, 5'd2));
    imem_write(5,  NOPI()); imem_write(6, NOPI());
    imem_write(7,  SUB(5'd4, 5'd1, 5'd2));
    imem_write(8,  NOPI()); imem_write(9, NOPI());
    imem_write(10, AND(5'd5, 5'd1, 5'd2));
    imem_write(11, NOPI()); imem_write(12, NOPI());
    imem_write(13, OR(5'd6, 5'd1, 5'd2));
    imem_write(14, NOPI()); imem_write(15, NOPI());
    imem_write(16, XOR(5'd7, 5'd1, 5'd2));
    imem_write(17, NOPI()); imem_write(18, NOPI());
    imem_write(19, SLT(5'd8, 5'd2, 5'd1));
    wait_cycles(35);
    check("ADD  x3=13",  32'd13, rf[3]);
    check("SUB  x4=7",   32'd7,  rf[4]);
    check("AND  x5=2",   32'd2,  rf[5]);
    check("OR   x6=11",  32'd11, rf[6]);
    check("XOR  x7=9",   32'd9,  rf[7]);
    check("SLT  x8=1",   32'd1,  rf[8]);
  endtask

  // ============================================================================
  // TEST 2: EX→EX and MEM→EX Forwarding
  // ============================================================================
  task automatic test_forwarding();
    $display("\n=== Test 2: Forwarding ===");
    clear_imem(); do_reset();
    imem_write(0, ADDI(5'd1, 5'd0, 12'd5));
    imem_write(1, ADDI(5'd2, 5'd1, 12'd3));   // EX→EX fwd x1
    imem_write(2, ADDI(5'd3, 5'd2, 12'd2));   // EX→EX fwd x2
    imem_write(3, ADD(5'd4, 5'd1, 5'd3));     // MEM→EX fwd x3
    wait_cycles(15);
    check("FWD x1=5",  32'd5,  rf[1]);
    check("FWD x2=8",  32'd8,  rf[2]);
    check("FWD x3=10", 32'd10, rf[3]);
    check("FWD x4=15", 32'd15, rf[4]);
  endtask

  // ============================================================================
  // TEST 3: Load-Use Stall
  // ============================================================================
  task automatic test_load_use();
    $display("\n=== Test 3: Load-Use Stall ===");
    clear_imem(); do_reset();
    imem_write(0, ADDI(5'd1, 5'd0, 12'd42));
    imem_write(1, SW(5'd0, 5'd1, 12'd0));
    imem_write(2, NOPI()); imem_write(3, NOPI()); imem_write(4, NOPI());
    imem_write(5, LW(5'd2, 5'd0, 12'd0));
    imem_write(6, ADD(5'd3, 5'd2, 5'd0));     // load-use stall on x2
    wait_cycles(20);
    check("LU x2=42", 32'd42, rf[2]);
    check("LU x3=42", 32'd42, rf[3]);
  endtask

  // ============================================================================
  // TEST 4: Branch NOT Taken — always-taken mispredict → 1-cycle flush
  // Layout:
  //   word 0-1: set x1=1, x2=2
  //   word 2-3: NOPs (forwarding gap)
  //   word 4:   BEQ x1,x2,+40  → target=word14 (x1≠x2, NOT taken)
  //   word 5:   ADDI x3,x0,99  ← fall-through, MUST execute
  //   word 6-13: HALTs / NOPs  ← padding so PC never naturally reaches word14
  //   word 14:  ADDI x4,x0,55  ← speculative target, must NOT execute
  // ============================================================================
  task automatic test_branch_not_taken();
    $display("\n=== Test 4: Branch NOT Taken (mispredict flush) ===");
    clear_imem(); do_reset();
    imem_write(0, ADDI(5'd1, 5'd0, 12'd1));
    imem_write(1, ADDI(5'd2, 5'd0, 12'd2));
    imem_write(2, NOPI());
    imem_write(3, NOPI());
    // BEQ offset = +40 bytes → target = (4*4)+40 = 56 = word14
    imem_write(4, BEQ(5'd1, 5'd2, 13'sd40));
    imem_write(5, ADDI(5'd3, 5'd0, 12'd99));  // fall-through — must run
    // words 6-13: halt loop so sequential execution stops here
    for (int i = 6; i < 14; i++) imem_write(i, HALT());
    imem_write(14, ADDI(5'd4, 5'd0, 12'd55)); // spec target — must NOT run
    wait_cycles(25);
    check("BNT fallthrough x3=99", 32'd99, rf[3]);
    check("BNT spec target x4=0",  32'd0,  rf[4]);
  endtask

  // ============================================================================
  // TEST 5: Branch Taken — correct prediction, no flush
  // ============================================================================
  task automatic test_branch_taken();
    $display("\n=== Test 5: Branch Taken (correct prediction) ===");
    clear_imem(); do_reset();
    imem_write(0, ADDI(5'd1, 5'd0, 12'd7));
    imem_write(1, NOPI()); imem_write(2, NOPI());
    // BEQ x1,x1 +12 → target=word6 (always taken)
    imem_write(3, BEQ(5'd1, 5'd1, 13'sd12));
    imem_write(4, ADDI(5'd2, 5'd0, 12'd88)); // skipped
    imem_write(5, NOPI());
    imem_write(6, ADDI(5'd3, 5'd0, 12'd77)); // target — must execute
    imem_write(7, HALT());
    wait_cycles(20);
    check("BT  target x3=77",  32'd77, rf[3]);
    check("BT  skipped x2=0",  32'd0,  rf[2]);
  endtask

  // ============================================================================
  // TEST 6: JAL
  // ============================================================================
  task automatic test_jal();
    $display("\n=== Test 6: JAL ===");
    clear_imem(); do_reset();
    // JAL x1, +8 → target=word2; link=PC+4=4
    imem_write(0, JAL(5'd1, 21'sd8));
    imem_write(1, ADDI(5'd2, 5'd0, 12'd33)); // skipped
    imem_write(2, ADDI(5'd3, 5'd0, 12'd22)); // target
    imem_write(3, HALT());
    wait_cycles(15);
    check("JAL link x1=4",    32'd4,  rf[1]);
    check("JAL target x3=22", 32'd22, rf[3]);
    check("JAL skip x2=0",    32'd0,  rf[2]);
  endtask

  // ============================================================================
  // TEST 7: Store + Load
  // ============================================================================
  task automatic test_store_load();
    $display("\n=== Test 7: Store + Load ===");
    clear_imem(); do_reset();
    imem_write(0, ADDI(5'd1, 5'd0, 12'hAB));
    imem_write(1, SW(5'd0, 5'd1, 12'd8));
    imem_write(2, NOPI()); imem_write(3, NOPI()); imem_write(4, NOPI());
    imem_write(5, LW(5'd2, 5'd0, 12'd8));
    imem_write(6, NOPI()); imem_write(7, NOPI()); imem_write(8, NOPI());
    wait_cycles(20);
    check("SW/LW x2=0xAB", 32'h0000_00AB, rf[2]);
  endtask

  // ============================================================================
  // TEST 8: MUL
  // ============================================================================
  task automatic test_mul();
    $display("\n=== Test 8: MUL (M-ext) ===");
    clear_imem(); do_reset();
    imem_write(0, ADDI(5'd1, 5'd0, 12'd6));
    imem_write(1, ADDI(5'd2, 5'd0, 12'd7));
    imem_write(2, NOPI()); imem_write(3, NOPI());
    imem_write(4, MUL(5'd3, 5'd1, 5'd2));
    wait_cycles(15);
    check("MUL x3=42", 32'd42, rf[3]);
  endtask

  // ============================================================================
  // TEST 9: DIV (multi-cycle, pipeline stall)
  // ============================================================================
  task automatic test_div();
    $display("\n=== Test 9: DIV (M-ext, multi-cycle) ===");
    clear_imem(); do_reset();
    imem_write(0, ADDI(5'd1, 5'd0, 12'd100));
    imem_write(1, ADDI(5'd2, 5'd0, 12'd4));
    imem_write(2, NOPI()); imem_write(3, NOPI());
    imem_write(4, DIV(5'd3, 5'd1, 5'd2));    // x3 = 100/4 = 25 (stalls ~34 cycles)
    imem_write(5, ADDI(5'd4, 5'd3, 12'd1));  // x4 = x3+1 = 26 (after stall clears)
    wait_cycles(80);
    check("DIV x3=25",      32'd25, rf[3]);
    check("DIV post x4=26", 32'd26, rf[4]);
  endtask

  // ============================================================================
  // Main
  // ============================================================================
  initial begin
    $display("==========================================");
    $display("   RV32IM 5-Stage Pipeline Testbench");
    $display("==========================================");
    test_basic_alu();
    test_forwarding();
    test_load_use();
    test_branch_not_taken();
    test_branch_taken();
    test_jal();
    test_store_load();
    test_mul();
    test_div();
    $display("\n==========================================");
    $display("  Results: %0d PASS  |  %0d FAIL", pass_count, fail_count);
    $display("==========================================");
    if (fail_count == 0) $display("ALL TESTS PASSED");
    $finish;
  end

  initial begin #2000000; $display("TIMEOUT"); $finish; end

endmodule
