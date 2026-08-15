// riscv_cpu.v - 5-stage PIPELINED RISC-V CPU
module riscv_cpu (
    input         clk, reset,
    output [31:0] PC,
    input  [31:0] Instr,
    output        MemWrite,
    output [31:0] Mem_WrAddr, Mem_WrData,
    output [2:0]  Mem_funct3,
    input  [31:0] ReadData,
    output [31:0] Result
);
datapath dp (clk, reset, PC, Instr,
             MemWrite, Mem_WrAddr, Mem_WrData, Mem_funct3,
             ReadData, Result);
endmodule
