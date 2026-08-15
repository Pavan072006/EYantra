// Top module - PIPELINED. funct3 for data memory now comes from the MEM stage.
module t1c_riscv_cpu (
    input         clk, reset,
    output        MemWrite,
    output [31:0] WriteData, DataAdr, ReadData,
    output [31:0] PC, Result
);
wire [31:0] Instr;
wire [2:0]  Mem_funct3;

riscv_cpu rvcpu (clk, reset, PC, Instr,
                 MemWrite, DataAdr, WriteData, Mem_funct3, ReadData, Result);
instr_mem instrmem (PC, Instr);
data_mem  datamem  (clk, MemWrite, Mem_funct3, DataAdr, WriteData, ReadData);
endmodule
