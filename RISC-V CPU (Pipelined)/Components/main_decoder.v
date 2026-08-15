// main_decoder.v - PIPELINED version
// CHANGE: no longer takes Zero/ALUR31 and no longer decides TakeBranch.
// It only reports "this is a branch" (Branch). The actual condition is
// evaluated by branch_cond in the EXECUTE stage.

module main_decoder (
    input  [6:0] op,
    output [1:0] ResultSrc,
    output       MemWrite, Branch, ALUSrc,
    output       RegWrite, Jump, Jalr,
    output [1:0] ImmSrc,
    output [1:0] ALUOp
);

reg [10:0] controls;
reg        BranchR;

always @(*) begin
    BranchR = 1'b0;
    casez (op)
        // RegWrite_ImmSrc_ALUSrc_MemWrite_ResultSrc_ALUOp_Jump_Jalr
        7'b0000011: controls = 11'b1_00_1_0_01_00_0_0; // loads
        7'b0100011: controls = 11'b0_01_1_1_00_00_0_0; // stores
        7'b0110011: controls = 11'b1_00_0_0_00_10_0_0; // R-type
        7'b1100011: begin
                    controls = 11'b0_10_0_0_00_01_0_0; // branch
                    BranchR  = 1'b1;
                    end
        7'b0010011: controls = 11'b1_00_1_0_00_10_0_0; // I-type ALU
        7'b0?10111: controls = 11'b1_00_0_0_11_00_0_0; // lui / auipc
        7'b1101111: controls = 11'b1_11_0_0_10_00_1_0; // jal
        7'b1100111: controls = 11'b1_00_1_0_10_00_1_1; // jalr
        default:    controls = 11'b0_00_0_0_00_00_0_0; // NOP / bubble
    endcase
end

assign Branch = BranchR;
assign {RegWrite, ImmSrc, ALUSrc, MemWrite, ResultSrc, ALUOp, Jump, Jalr} = controls;
endmodule
