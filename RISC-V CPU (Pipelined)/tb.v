`timescale 1ns/1ps
//=====================================================================
// tb.v - Testbench for the 5-stage pipelined RV32I core
//
//  Checks three things:
//   1. Architectural state  - final register file contents
//   2. Hazard activity      - forwarding / stall / flush counts
//   3. Performance          - cycles and CPI to reach the end of program
//
//  Golden reference: the single-cycle core in "RISC-V CPU (Single-Cycle)"
//  running the same rv32i_test.hex must produce identical registers.
//=====================================================================
module tb;

  localparam END_PC   = 32'h138;   // final infinite-loop instruction
  localparam MAX_CYC  = 2000;
  localparam DRAIN    = 5;         // cycles needed to flush D/E/M/W

  reg  clk = 0, reset = 1;
  wire        MemWrite;
  wire [31:0] WriteData, DataAdr, ReadData, PC, Result;

  integer cyc      = 0;
  integer stalls   = 0;
  integer flushes  = 0;
  integer fwd_mem  = 0;
  integer fwd_wb   = 0;
  integer done     = 0;
  integer i;

  t1c_riscv_cpu dut (clk, reset, MemWrite, WriteData, DataAdr, ReadData, PC, Result);

  always #5 clk = ~clk;

  // ---------------- monitors ----------------
  always @(posedge clk) if (!reset && !done) begin
    cyc = cyc + 1;

    if (dut.rvcpu.dp.hz.StallD) begin
      stalls = stalls + 1;
      $display("[cyc %4d] STALL  : load-use hazard, PC=0x%03h", cyc, PC);
    end

    if (dut.rvcpu.dp.FlushD) flushes = flushes + 1;

    if (dut.rvcpu.dp.ForwardAE == 2'b10 || dut.rvcpu.dp.ForwardBE == 2'b10)
      fwd_mem = fwd_mem + 1;
    if (dut.rvcpu.dp.ForwardAE == 2'b01 || dut.rvcpu.dp.ForwardBE == 2'b01)
      fwd_wb  = fwd_wb + 1;

    if (PC == END_PC) begin
      done = 1;
      repeat (DRAIN) @(posedge clk);
      report;
    end

    if (cyc == MAX_CYC) begin
      $display("\nTIMEOUT: never reached PC=0x%03h", END_PC);
      report;
    end
  end

  // ---------------- reporting ----------------
  task report;
    begin
      $display("\n========== HAZARD ACTIVITY ==========");
      $display("  load-use stalls        : %0d", stalls);
      $display("  branch/jump flushes    : %0d", flushes);
      $display("  forwards from MEM stage: %0d", fwd_mem);
      $display("  forwards from WB stage : %0d", fwd_wb);

      $display("\n========== PERFORMANCE ==========");
      $display("  cycles to reach 0x%03h : %0d", END_PC, cyc);
      $display("  (single-cycle reference: 171 cycles, CPI 1.00)");
      $display("  extra cycles           : %0d", cyc - 171);
      $display("  accounted for by flushes: %0d x 2 = %0d",
               flushes, flushes*2);

      $display("\n========== REGISTER FILE ==========");
      for (i = 1; i < 32; i = i + 1)
        $display("  x%-2d = %11d  (0x%08x)", i,
                 $signed(dut.rvcpu.dp.rf.reg_file_arr[i]),
                        dut.rvcpu.dp.rf.reg_file_arr[i]);
      $display("\nCompare against the single-cycle core: all 31 must match.\n");
      #20 $finish;
    end
  endtask

  // ---------------- stimulus ----------------
  initial begin
    $dumpfile("pipelined_cpu.vcd");   // waveform for GTKWave / Questa
    $dumpvars(0, tb);
    repeat (2) @(posedge clk);
    reset = 0;
  end

endmodule
