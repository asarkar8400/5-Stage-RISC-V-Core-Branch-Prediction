# RV32IM 5-Stage Pipelined CPU Core

A synthesizable RISC-V CPU core written in SystemVerilog, implementing the RV32IM instruction set.

---
The CPU follows the **RISC-V** open standard instruction set architecture (ISA), specifically the **RV32IM** variant:
- **RV32** — 32-bit registers and addresses
- **I** — base integer instructions (arithmetic, loads, stores, branches, jumps)
- **M** — multiply and divide instructions

---

## Pipeline Stages

This design uses **5 pipeline stages**:

```
  ┌────┐   ┌────┐   ┌────┐   ┌────┐   ┌────┐
  │ IF │──▶│ ID │──▶│ EX │──▶│MEM │──▶│ WB │
  └────┘   └────┘   └────┘   └────┘   └────┘
  Fetch    Decode   Execute   Memory   Write
                              Access   Back
```

| Stage | Name | What it does |
|-------|------|--------------|
| **IF** | Instruction Fetch | Reads the next instruction from memory using the Program Counter (PC) |
| **IB** | Instruction Buffer | A 1-entry skid buffer that sits between IF and ID to absorb stalls |
| **ID** | Instruction Decode | Figures out what the instruction means; reads register values |
| **EX** | Execute | Runs the ALU (arithmetic), resolves branches, starts multiply/divide |
| **MEM** | Memory Access | Reads or writes data memory for load/store instructions |
| **WB** | Write-Back | Writes the result back into the register file |

### Hazard Handling

This design handles three types:

**1. Data Hazard — Forwarding**
If instruction B needs the result of instruction A, and A is still in the pipeline, we can "forward" A's result directly to B rather than waiting. This design supports:
- **EX→EX forwarding**: forward from EX/MEM register to EX input (1-cycle latency)
- **MEM→EX forwarding**: forward from MEM/WB register to EX input (2-cycle latency)

**2. Load-Use Hazard — Stall**
A load instruction (`LW`) reads from memory, so its result isn't available until the MEM stage. If the very next instruction needs that value, forwarding alone isn't enough — we need to stall the pipeline for 1 cycle and insert a bubble.

**3. Control Hazard — Branch Prediction + Flush**
When the CPU sees a branch instruction, it doesn't yet know whether the branch will be taken. This design uses an **always-taken** prediction strategy: whenever a branch or jump is seen in ID, we immediately redirect the PC to the branch target. If the branch turns out to be **not taken** (resolved in EX), we flush the speculatively fetched instruction with a 1-cycle penalty.

---

## File Structure

```
riscv_cpu/
├── README.md
├── Makefile
└── rtl/
    ├── riscv_pkg.sv       # Package: all shared types, enums, and the ctrl_t struct
    ├── riscv_core.sv      # Top-level: wires all stages and the hazard unit together
    ├── if_stage.sv        # Instruction Fetch: PC logic, instruction memory
    ├── instr_buffer.sv    # Skid buffer between IF and ID
    ├── id_stage.sv        # Instruction Decode: control decode, register file read
    ├── imm_gen.sv         # Immediate generator (I/S/B/U/J formats)
    ├── control_unit.sv    # Main decoder: instruction → control signals
    ├── reg_file.sv        # 32×32 register file with write-before-read bypass
    ├── ex_stage.sv        # Execute: forwarding muxes, ALU, branch resolution
    ├── alu.sv             # ALU + iterative 32-bit restoring divider
    ├── hazard_unit.sv     # Forwarding selects, stall signals, flush signals
    ├── mem_stage.sv       # Data memory: byte/halfword/word loads and stores
    ├── wb_stage.sv        # Write-back mux (ALU result / load data / PC+4)
    └── tb_riscv_core.sv   # Self-checking testbench (9 test cases)
```

### Key design file: `riscv_pkg.sv`

This package defines the **control word** (`ctrl_t`) — a packed struct that travels through every pipeline stage carrying all the signals an instruction needs:

```systemverilog
typedef struct packed {
    logic        reg_write;      // does this instruction write a register?
    logic        mem_read;       // is this a load?
    logic        mem_write;      // is this a store?
    logic [2:0]  mem_size;       // byte / halfword / word
    logic        branch;         // conditional branch
    logic        jump;           // unconditional jump (JAL/JALR)
    alu_op_e     alu_op;         // which ALU operation
    wb_sel_e     wb_sel;         // what to write back (ALU/MEM/PC+4)
    logic        is_div;         // is this a DIV/REM instruction?
    logic        is_signed_div;  // signed or unsigned divide?
    logic        want_rem;       // quotient or remainder?
    // ... register indices, immediate, PC
} ctrl_t;
```

---

## Supported Instructions

### Base Integer (RV32I)

| Category | Instructions |
|----------|-------------|
| Arithmetic | `ADD`, `ADDI`, `SUB` |
| Logical | `AND`, `ANDI`, `OR`, `ORI`, `XOR`, `XORI` |
| Shift | `SLL`, `SLLI`, `SRL`, `SRLI`, `SRA`, `SRAI` |
| Compare | `SLT`, `SLTI`, `SLTU`, `SLTIU` |
| Load upper | `LUI`, `AUIPC` |
| Loads | `LB`, `LH`, `LW`, `LBU`, `LHU` |
| Stores | `SB`, `SH`, `SW` |
| Branch | `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU` |
| Jump | `JAL`, `JALR` |
| System | `ECALL`, `EBREAK` (treated as NOP) |

### M Extension (Multiply/Divide)

| Instruction | Operation |
|-------------|-----------|
| `MUL` | Lower 32 bits of signed × signed |
| `MULH` | Upper 32 bits of signed × signed |
| `MULHSU` | Upper 32 bits of signed × unsigned |
| `MULHU` | Upper 32 bits of unsigned × unsigned |
| `DIV` | Signed 32-bit division |
| `DIVU` | Unsigned 32-bit division |
| `REM` | Signed 32-bit remainder |
| `REMU` | Unsigned 32-bit remainder |

Multiply is **single-cycle** (maps to DSP blocks on FPGA). Divide/remainder uses an **iterative restoring algorithm** (32 shift-subtract cycles) with full pipeline stall until complete.

---

## The Divider — How It Works

The `div_unit` inside `alu.sv` uses classic **restoring long division** on unsigned magnitudes, with sign correction applied at the end for signed operations.

```
State machine:  IDLE ──(start)──▶ RUN (32 cycles) ──▶ DONE ──▶ IDLE
                                   │                     │
                               shift + trial           latch
                               subtract loop           result
```

The `busy` signal asserts combinatorially the moment a DIV instruction enters EX, so the hazard unit stalls the entire pipeline immediately. When the divider finishes and transitions back to `IDLE`, `busy` drops, the stall releases, and the EX/MEM register captures the result on the next clock.

A `just_done` flag prevents the divider from immediately relaunching (since `start` is still asserted for one cycle while the pipeline advances past the instruction).

---

## Branch Prediction Detail

```
Cycle 1  Cycle 2  Cycle 3  Cycle 4  Cycle 5
  IF       IF       ID       EX       MEM
  ──       BEQ      BEQ      BEQ      ──
           ^        │        │
           │        └─ redirect IF    └─ resolve: taken or not?
           fetch    to target PC         if NOT taken → flush 1 bubble
```

When a branch or jump reaches **ID**, the branch target (`PC + imm`) is computed and the **IF stage is immediately redirected**. One instruction is speculatively fetched from the target. When the branch reaches **EX** two cycles later and resolves:

- **Taken** → prediction was correct, no penalty, no flush
- **Not taken** → 1-cycle penalty: the speculatively fetched instruction is flushed (replaced with a bubble), and IF is redirected back to `PC+4`

---

## Prerequisites

You need a SystemVerilog simulator. The easiest free option is **Icarus Verilog**.

### Install Icarus Verilog

**Ubuntu / Debian:**
```bash
sudo apt-get install iverilog
```

**macOS (Homebrew):**
```bash
brew install icarus-verilog
```

**Windows:**
Download the installer from [bleyer.org/icarus](http://bleyer.org/icarus/) or use WSL (Windows Subsystem for Linux) and follow the Ubuntu instructions.

**Verify your install:**
```bash
iverilog -V
# Should print: Icarus Verilog version 11.0 (or higher)
```

> The Makefile also includes targets for **VCS** (Synopsys) and **Xcelium** (Cadence)

---

## Running the Simulation

### Step 1 — Clone / download the project

If you cloned from GitHub:
```bash
git clone https://github.com/yourname/riscv-core.git
cd riscv-core
```

Or if you downloaded the files manually, make sure your directory looks like:
```
riscv_cpu/
├── Makefile
└── rtl/
    ├── riscv_pkg.sv
    ├── riscv_core.sv
    └── ... (all .sv files)
```

### Step 2 — Compile

```bash
cd riscv_cpu
make sim
```

This runs `iverilog` to compile all the SystemVerilog source files and produces an executable called `sim_riscv`.

You can also compile manually without `make`:
```bash
iverilog -g2012 -Wall \
  rtl/riscv_pkg.sv \
  rtl/imm_gen.sv \
  rtl/control_unit.sv \
  rtl/reg_file.sv \
  rtl/alu.sv \
  rtl/hazard_unit.sv \
  rtl/if_stage.sv \
  rtl/instr_buffer.sv \
  rtl/id_stage.sv \
  rtl/ex_stage.sv \
  rtl/mem_stage.sv \
  rtl/wb_stage.sv \
  rtl/riscv_core.sv \
  rtl/tb_riscv_core.sv \
  -o sim_riscv
```

> **Flag explanation:**
> - `-g2012` — enables SystemVerilog (IEEE 1800-2012) mode
> - `-Wall` — show all warnings

### Step 3 — Run

```bash
vvp sim_riscv
```

You should see output like this:

```
==========================================
   RV32IM 5-Stage Pipeline Testbench
==========================================

=== Test 1: Basic ALU ===
[PASS] ADD  x3=13          expected=0x0000000d  actual=0x0000000d
[PASS] SUB  x4=7           expected=0x00000007  actual=0x00000007
...

=== Test 9: DIV (M-ext, multi-cycle) ===
[PASS] DIV x3=25           expected=0x00000019  actual=0x00000019
[PASS] DIV post x4=26      expected=0x0000001a  actual=0x0000001a

==========================================
  Results: 23 PASS  |  0 FAIL
==========================================
ALL TESTS PASSED
```

---

## What the Testbench Tests

The testbench (`tb_riscv_core.sv`) directly writes machine code (encoded RISC-V instructions) into the instruction memory, resets the CPU, runs it for a set number of clock cycles, then peeks at the register file and checks the values against expected results.

| Test | What it checks |
|------|---------------|
| 1. Basic ALU | `ADD`, `SUB`, `AND`, `OR`, `XOR`, `SLT` with NOPs between — verifies baseline decode and execute |
| 2. Forwarding | Back-to-back dependent `ADDI` instructions — verifies EX→EX and MEM→EX forwarding paths |
| 3. Load-Use Stall | `LW` immediately followed by a dependent `ADD` — verifies the 1-cycle bubble and stall |
| 4. Branch Not Taken | `BEQ` with unequal operands — verifies mispredict flush kills speculative instruction |
| 5. Branch Taken | `BEQ` with equal operands — verifies correct prediction executes target, skips fall-through |
| 6. JAL | Unconditional jump — verifies link register (`PC+4`) and target execution |
| 7. Store + Load | `SW` then `LW` at same address — verifies data memory round-trip |
| 8. MUL | `MUL` of 6 × 7 — verifies M-extension single-cycle multiply |
| 9. DIV | `DIV` of 100 ÷ 4, then `ADDI` using result — verifies multi-cycle divide and stall |

---

## Loading Your Own Program

The instruction memory in `if_stage.sv` is initialized to NOPs and can be loaded from a hex file at simulation time by defining `IMEM_INIT_FILE`:

```bash
iverilog -g2012 -DIMEM_INIT_FILE='"my_program.hex"' \
  rtl/riscv_pkg.sv ... rtl/riscv_core.sv rtl/tb_riscv_core.sv \
  -o sim_riscv
```

The hex file format is one 32-bit word per line (the standard `$readmemh` format). You can generate this from a RISC-V C or assembly program using the GNU RISC-V toolchain:

```bash
# Install toolchain (Ubuntu)
sudo apt-get install gcc-riscv64-unknown-elf

# Compile a C file to a flat binary
riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 -nostdlib \
  -Ttext=0x0 -o program.elf program.c

# Convert to hex
riscv64-unknown-elf-objcopy -O verilog program.elf my_program.hex
```
---

## Known Limitations

- **No caches** — instruction and data memories are simple synchronous SRAMs (1 KB each by default). Real implementations would add I-cache and D-cache.
- **No exception handling** — illegal instructions and misaligned accesses are silently ignored (treated as NOPs).
- **No privilege modes** — no machine/supervisor/user mode separation; `ECALL`/`EBREAK` are treated as NOPs.
- **JALR branch prediction** — JALR target requires `rs1 + imm` which depends on a register. If `rs1` has a forwarding hazard, the predicted target may be wrong and a mispredict penalty occurs.
- **Single-issue, in-order** — one instruction per cycle maximum throughput; no out-of-order execution.

---

## Architecture Diagram

```
          ┌─────────────────────────────────────────────────────────────────────┐
          │                        riscv_core.sv                               │
          │                                                                     │
  ┌───────▼──────┐  ┌────────────┐  ┌───────────┐  ┌────────────┐  ┌────────┐│
  │   if_stage   │  │instr_buffer│  │  id_stage  │  │  ex_stage  │  │  mem   ││
  │              │  │ (skid buf) │  │            │  │            │  │ stage  ││
  │  PC logic    ├─▶│            ├─▶│ ctrl decode├─▶│ fwd muxes  ├─▶│        ││
  │  IMEM read   │  │ 1-deep FIFO│  │ reg file   │  │ ALU / DIV  │  │ DMEM   ││
  │              │  │            │  │ imm gen    │  │ branch eval│  │ r/w    ││
  └──────────────┘  └────────────┘  └───────────┘  └────────────┘  └───┬────┘│
        ▲                 ▲                ▲               ▲             │     │
        │                 │                │               │             ▼     │
        │           ┌─────┴────────────────┴───────────────┴──────┐ ┌──────┐ │
        └───────────│              hazard_unit.sv                  │ │  wb  │ │
  flush/redirect    │  forwarding selects (fwd_a, fwd_b)          │ │stage │ │
  branch target     │  load-use stall (stall_if, stall_id)        │ └──┬───┘ │
                    │  branch mispredict flush (flush_if, flush_id)│    │     │
                    │  div stall (div_busy)                        │    │     │
                    └──────────────────────────────────────────────┘    │     │
                                                                         │     │
                                              reg_file write ◀──────────┘     │
          └─────────────────────────────────────────────────────────────────────┘
```

---

## Simulating on a Specific Tool

### Icarus Verilog (free, recommended for getting started)
```bash
make sim
```

### Synopsys VCS
```bash
make vcs_sim
```

### Cadence Xcelium
```bash
make xcelium_sim
```

---

## Project Background

All RTL is original SystemVerilog; no third-party IP or pre-existing cores. The testbench encodes raw machine code by hand using instruction encoder functions, giving precise control over pipeline timing and hazard scenarios.
The most interesting debugging challenge was the M-extension divide where iverilog does not resolve packed-struct enum fields in submodule port comparisons reliably, so all DIV control signals (`is_div`, `is_signed_div`, `want_rem`) are precomputed as plain `logic` bits in the decode stage and threaded through the pipeline in the `ctrl_t` struct, avoiding any enum comparison below the ID stage.
I used Claude to help me make this README.MD
