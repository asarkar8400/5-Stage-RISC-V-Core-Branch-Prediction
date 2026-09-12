# =============================================================================
# Makefile — RV32IM Pipeline Core Simulation
#
# Tools:  Icarus Verilog (iverilog) or VCS / Xcelium
# Usage:
#   make sim          — compile + run testbench (iverilog)
#   make wave         — open waveform in GTKWave
#   make clean        — remove generated files
# =============================================================================

TOPLEVEL   = tb_riscv_core
RTL_DIR    = rtl

# Source list (order matters for packages)
SRCS = \
  $(RTL_DIR)/riscv_pkg.sv      \
  $(RTL_DIR)/imm_gen.sv        \
  $(RTL_DIR)/control_unit.sv   \
  $(RTL_DIR)/reg_file.sv       \
  $(RTL_DIR)/alu.sv            \
  $(RTL_DIR)/hazard_unit.sv    \
  $(RTL_DIR)/if_stage.sv       \
  $(RTL_DIR)/instr_buffer.sv   \
  $(RTL_DIR)/id_stage.sv       \
  $(RTL_DIR)/ex_stage.sv       \
  $(RTL_DIR)/mem_stage.sv      \
  $(RTL_DIR)/wb_stage.sv       \
  $(RTL_DIR)/riscv_core.sv     \
  $(RTL_DIR)/tb_riscv_core.sv

OUT = sim_riscv

# ── Icarus Verilog ────────────────────────────────────────────────────────────
IV_FLAGS = -g2012 -Wall -Wno-timescale

sim: $(OUT)
	vvp $(OUT)

$(OUT): $(SRCS)
	iverilog $(IV_FLAGS) -o $(OUT) $(SRCS)

wave: $(OUT)
	vvp $(OUT) -lxt2
	gtkwave dump.lxt &

# ── VCS (Synopsys) ───────────────────────────────────────────────────────────
vcs_sim:
	vcs -sverilog -full64 -debug_all +v2k $(SRCS) -top $(TOPLEVEL) -o vcs_out
	./vcs_out

# ── Xcelium (Cadence) ────────────────────────────────────────────────────────
xcelium_sim:
	xrun -sv $(SRCS) -top $(TOPLEVEL)

clean:
	rm -f $(OUT) *.vcd *.lxt *.fsdb *.log csrc/ xcelium.d/ -rf

.PHONY: sim wave vcs_sim xcelium_sim clean
