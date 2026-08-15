// datapath.v - 5-STAGE PIPELINED RISC-V DATAPATH
// Stages: F (fetch) | D (decode) | E (execute) | M (memory) | W (writeback)

module datapath (
    input         clk, reset,
    // instruction memory
    output [31:0] PCF,
    input  [31:0] InstrF,
    // data memory
    output        MemWriteM,
    output [31:0] ALUResultM, WriteDataM,
    output [2:0]  funct3M,
    input  [31:0] ReadDataM,
    // debug
    output [31:0] ResultW
);

// ============================================================
// F : FETCH
// ============================================================
wire [31:0] PCNextF, PCPlus4F;
wire        StallF, StallD, FlushD, FlushE;
wire        PCSrcE;
wire [31:0] PCTargetE;

assign PCNextF = PCSrcE ? PCTargetE : PCPlus4F;

// PC register with stall enable
reg [31:0] PCF_r;
always @(posedge clk or posedge reset) begin
    if (reset)       PCF_r <= 32'd0;
    else if (!StallF) PCF_r <= PCNextF;
end
assign PCF = PCF_r;

adder pcadd4 (PCF, 32'd4, PCPlus4F);

// ============================================================
// F/D pipeline register
// ============================================================
reg [31:0] InstrD, PCD, PCPlus4D;
always @(posedge clk or posedge reset) begin
    if (reset) begin
        InstrD <= 32'd0; PCD <= 32'd0; PCPlus4D <= 32'd0;
    end else if (FlushD) begin
        InstrD <= 32'd0; PCD <= 32'd0; PCPlus4D <= 32'd0;   // squash
    end else if (!StallD) begin
        InstrD <= InstrF; PCD <= PCF; PCPlus4D <= PCPlus4F;
    end
end

// ============================================================
// D : DECODE
// ============================================================
wire [1:0] ResultSrcD, ImmSrcD;
wire       MemWriteD, BranchD, ALUSrcD, RegWriteD, JumpD, JalrD;
wire [3:0] ALUControlD;
wire [31:0] RD1D, RD2D, ImmExtD;

wire [4:0] Rs1D = InstrD[19:15];
wire [4:0] Rs2D = InstrD[24:20];
wire [4:0] RdD  = InstrD[11:7];
wire [2:0] funct3D = InstrD[14:12];

controller c (InstrD[6:0], InstrD[14:12], InstrD[30],
              ResultSrcD, MemWriteD, BranchD, ALUSrcD,
              RegWriteD, JumpD, JalrD, ImmSrcD, ALUControlD);

// writeback signals declared early (regfile write port)
wire        RegWriteW;
wire [4:0]  RdW;

reg_file rf (clk, RegWriteW, Rs1D, Rs2D, RdW, ResultW, RD1D, RD2D);
imm_extend ext (InstrD[31:7], ImmSrcD, ImmExtD);

// lui / auipc value computed in D (needs PCD and the U-immediate)
wire [31:0] UImmD   = {InstrD[31:12], 12'b0};
wire [31:0] lAuiPCD = InstrD[5] ? UImmD : (PCD + UImmD);  // lui : auipc

// ============================================================
// D/E pipeline register
// ============================================================
reg        RegWriteE, MemWriteE, ALUSrcE, BranchE, JumpE, JalrE;
reg [1:0]  ResultSrcE;
reg [3:0]  ALUControlE;
reg [31:0] RD1E, RD2E, PCE, ImmExtE, PCPlus4E, lAuiPCE;
reg [4:0]  Rs1E, Rs2E, RdE;
reg [2:0]  funct3E;

always @(posedge clk or posedge reset) begin
    if (reset || FlushE) begin
        RegWriteE <= 1'b0; MemWriteE <= 1'b0; ALUSrcE <= 1'b0;
        BranchE   <= 1'b0; JumpE     <= 1'b0; JalrE   <= 1'b0;
        ResultSrcE<= 2'b00; ALUControlE <= 4'b0000;
        RD1E <= 0; RD2E <= 0; PCE <= 0; ImmExtE <= 0;
        PCPlus4E <= 0; lAuiPCE <= 0;
        Rs1E <= 0; Rs2E <= 0; RdE <= 0; funct3E <= 3'b000;
    end else begin
        RegWriteE <= RegWriteD; MemWriteE <= MemWriteD; ALUSrcE <= ALUSrcD;
        BranchE   <= BranchD;   JumpE     <= JumpD;     JalrE   <= JalrD;
        ResultSrcE<= ResultSrcD; ALUControlE <= ALUControlD;
        RD1E <= RD1D; RD2E <= RD2D; PCE <= PCD; ImmExtE <= ImmExtD;
        PCPlus4E <= PCPlus4D; lAuiPCE <= lAuiPCD;
        Rs1E <= Rs1D; Rs2E <= Rs2D; RdE <= RdD; funct3E <= funct3D;
    end
end

// ============================================================
// E : EXECUTE
// ============================================================
wire [1:0]  ForwardAE, ForwardBE;
wire [31:0] ExResultM_w;      // forwarded value from MEM stage
wire [31:0] SrcAE, WriteDataE, SrcBE, ALUResultE;
wire        ZeroE;

mux3 #(32) fwdA (RD1E, ResultW, ExResultM_w, ForwardAE, SrcAE);
mux3 #(32) fwdB (RD2E, ResultW, ExResultM_w, ForwardBE, WriteDataE);

mux2 #(32) srcbmux (WriteDataE, ImmExtE, ALUSrcE, SrcBE);
alu alu_i (SrcAE, SrcBE, ALUControlE, ALUResultE, ZeroE);

// branch condition (fixed comparator, uses forwarded operands)
wire TakeBranchE;
branch_cond bc (funct3E, SrcAE, WriteDataE, TakeBranchE);

assign PCSrcE    = (BranchE && TakeBranchE) || JumpE;
assign PCTargetE = JalrE ? (ALUResultE & ~32'd1) : (PCE + ImmExtE);

// Collapse the PCPlus4 / lui-auipc selection into EX so that the
// forwarded MEM value is already correct for jal / lui / auipc.
wire [31:0] ExResultE = (ResultSrcE == 2'b10) ? PCPlus4E :
                        (ResultSrcE == 2'b11) ? lAuiPCE  : ALUResultE;

// ============================================================
// E/M pipeline register
// ============================================================
reg        RegWriteM_r, MemWriteM_r;
reg [1:0]  ResultSrcM;
reg [31:0] ExResultM, WriteDataM_r;
reg [4:0]  RdM;
reg [2:0]  funct3M_r;

always @(posedge clk or posedge reset) begin
    if (reset) begin
        RegWriteM_r <= 0; MemWriteM_r <= 0; ResultSrcM <= 0;
        ExResultM <= 0; WriteDataM_r <= 0; RdM <= 0; funct3M_r <= 0;
    end else begin
        RegWriteM_r <= RegWriteE; MemWriteM_r <= MemWriteE;
        ResultSrcM  <= ResultSrcE;
        ExResultM   <= ExResultE; WriteDataM_r <= WriteDataE;
        RdM         <= RdE;       funct3M_r    <= funct3E;
    end
end

assign MemWriteM  = MemWriteM_r;
assign ALUResultM = ExResultM;
assign WriteDataM = WriteDataM_r;
assign funct3M    = funct3M_r;
assign ExResultM_w = ExResultM;

// ============================================================
// M/W pipeline register
// ============================================================
reg        RegWriteW_r;
reg [1:0]  ResultSrcW;
reg [31:0] ExResultW, ReadDataW;
reg [4:0]  RdW_r;

always @(posedge clk or posedge reset) begin
    if (reset) begin
        RegWriteW_r <= 0; ResultSrcW <= 0;
        ExResultW <= 0; ReadDataW <= 0; RdW_r <= 0;
    end else begin
        RegWriteW_r <= RegWriteM_r; ResultSrcW <= ResultSrcM;
        ExResultW   <= ExResultM;   ReadDataW  <= ReadDataM;
        RdW_r       <= RdM;
    end
end

assign RegWriteW = RegWriteW_r;
assign RdW       = RdW_r;

// ============================================================
// W : WRITEBACK
// ============================================================
assign ResultW = (ResultSrcW == 2'b01) ? ReadDataW : ExResultW;

// ============================================================
// HAZARD UNIT
// ============================================================
wire LoadInE = (ResultSrcE == 2'b01);   // NOTE: this encoding, not ResultSrc[0]

hazard_unit hz (
    .Rs1D(Rs1D), .Rs2D(Rs2D),
    .Rs1E(Rs1E), .Rs2E(Rs2E), .RdE(RdE),
    .RdM(RdM), .RdW(RdW_r),
    .RegWriteM(RegWriteM_r), .RegWriteW(RegWriteW_r),
    .LoadInE(LoadInE), .PCSrcE(PCSrcE),
    .ForwardAE(ForwardAE), .ForwardBE(ForwardBE),
    .StallF(StallF), .StallD(StallD), .FlushD(FlushD), .FlushE(FlushE)
);

endmodule
