# Pipelining the RV32I core — change log

Converts the single-cycle core into a classic 5-stage pipeline
(**IF → ID → EX → MEM → WB**) with full forwarding, load-use stalling,
and branch flushing.

Verified with Icarus Verilog against the original `rv32i_test.hex`:
**all 31 architectural registers match the single-cycle core bit-for-bit.**

---

## Files

### New
| File | Purpose |
|---|---|
| `components/hazard_unit.v` | Forwarding selects, load-use stall, branch flush |
| `components/branch_cond.v` | Branch comparator in EX (also fixes `bltu`/`bgeu`) |
| `components/pipe_reg.v` | Parameterised pipeline register with `en`/`clr` |

### Modified
| File | Change |
|---|---|
| `components/datapath.v` | Rewritten — 4 pipeline registers, forwarding muxes, hazard wiring |
| `components/controller.v` | Dropped `Zero`/`ALUR31` inputs and `PCSrc` output |
| `components/main_decoder.v` | Reports `Branch` only; no longer evaluates the condition |
| `components/reg_file.v` | Added **write-first internal bypass** |
| `riscv_cpu.v` | Exposes `Mem_funct3` from the MEM stage |
| `t1c_riscv_cpu.v` | Data memory `funct3` now from MEM, not `Instr[14:12]` |

### Unchanged
`alu.v`, `alu_decoder.v`, `imm_extend.v`, `adder.v`, `mux2/3/4.v`,
`instr_mem.v`, `data_mem.v`

---

## The five changes that matter

### 1. Pipeline registers
`IF/ID` carries `Instr, PC, PC+4`.
`ID/EX` carries the control word, `RD1, RD2, PC, Imm, PC+4, lAuiPC, Rs1, Rs2, Rd, funct3`.
`EX/MEM` and `MEM/WB` carry progressively less.

`IF/ID` and the PC need an **enable** (for stalls); `IF/ID` and `ID/EX` need a
**synchronous clear** (for flushes).

### 2. Branch moved from decode to execute
The single-cycle `main_decoder` evaluated `TakeBranch` using `Zero` and
`ALUR31` combinationally. That is impossible once pipelined — those come from
the ALU, a stage later. A dedicated `branch_cond` unit now sits in EX and takes
the **forwarded** operands.

### 3. Forwarding
```
ForwardAE = (RegWriteM && RdM!=0 && RdM==Rs1E) ? 2'b10   // from MEM
          : (RegWriteW && RdW!=0 && RdW==Rs1E) ? 2'b01   // from WB
          : 2'b00;                                        // register file
```
MEM is checked **before** WB so the most recent value wins.

### 4. Load-use stall
```
lwStall = LoadInE && (RdE!=0) && ((Rs1D==RdE) || (Rs2D==RdE));
StallF = StallD = lwStall;   FlushE = lwStall || PCSrcE;
```

> ⚠️ **Encoding-specific detail.** Textbooks write `ResultSrcE[0]` to detect a
> load. That is **wrong for this core**, because `ResultSrc == 2'b11` is
> lui/auipc and would falsely trigger a stall. This design uses
> `LoadInE = (ResultSrcE == 2'b01)`.

### 5. Register file write-first bypass
WB writes and ID reads in the same cycle. Without a bypass, ID reads stale data.

---

## Bugs fixed along the way

**`bltu` / `bgeu` were functionally wrong.** The original used
`ALUResult[31]` — the sign bit of `a-b` — for *unsigned* comparison.
Counterexample: `a=0x00000001, b=0xFFFFFFFF`. Unsigned, `a < b` is true, but
`a-b = 0x00000002` has sign bit 0, so no branch was taken.
`blt`/`bge` were also fragile because the sign bit of `a-b` is only correct
when the subtraction does not overflow.
Fixed by comparing operands directly in `branch_cond`.

**`jalr` now clears the target LSB** (`ALUResultE & ~32'd1`) per the RISC-V spec.

---

## Measured results

| | Single-cycle | Pipelined |
|---|---|---|
| Cycles to complete `rv32i_test` | 171 | 235 |
| CPI | 1.00 | 1.37 |
| Load-use stalls | — | 0 |
| Branch flushes | — | 32 |

`171 + (32 × 2) = 235` — every extra cycle is accounted for by the two-cycle
branch penalty. The payoff is a much shorter critical path, so a much higher
achievable clock.

**Next optimisation:** move branch resolution from EX to ID to cut the penalty
from 2 cycles to 1, at the cost of an extra forwarding path into the comparator.
