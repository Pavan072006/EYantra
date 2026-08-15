// hazard_unit.v - NEW MODULE
// Handles data hazards (forwarding), load-use hazards (stall)
// and control hazards (flush).

module hazard_unit (
    // source/dest registers
    input  [4:0] Rs1D, Rs2D,
    input  [4:0] Rs1E, Rs2E, RdE,
    input  [4:0] RdM,  RdW,
    // writeback enables further down the pipe
    input        RegWriteM, RegWriteW,
    // is the instruction in EX a load?  (ResultSrcE == 2'b01 in THIS encoding)
    input        LoadInE,
    // taken branch / jump resolved in EX
    input        PCSrcE,

    output [1:0] ForwardAE, ForwardBE,
    output       StallF, StallD, FlushD, FlushE
);

// ---------- FORWARDING (EX operands) ----------
// 2'b10 = from MEM stage, 2'b01 = from WB stage, 2'b00 = register file
assign ForwardAE = (RegWriteM && (RdM != 5'd0) && (RdM == Rs1E)) ? 2'b10 :
                   (RegWriteW && (RdW != 5'd0) && (RdW == Rs1E)) ? 2'b01 : 2'b00;

assign ForwardBE = (RegWriteM && (RdM != 5'd0) && (RdM == Rs2E)) ? 2'b10 :
                   (RegWriteW && (RdW != 5'd0) && (RdW == Rs2E)) ? 2'b01 : 2'b00;

// ---------- LOAD-USE HAZARD ----------
// Load data is not ready until MEM, so forwarding cannot help. Stall one cycle.
wire lwStall = LoadInE && (RdE != 5'd0) && ((Rs1D == RdE) || (Rs2D == RdE));

assign StallF = lwStall;
assign StallD = lwStall;

// ---------- FLUSH ----------
// Bubble into EX on a stall; squash IF/ID and ID/EX on a taken branch.
assign FlushE = lwStall || PCSrcE;
assign FlushD = PCSrcE;
endmodule
