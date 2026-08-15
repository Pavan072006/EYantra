// controller.v - PIPELINED version (decode stage only)
// CHANGE: no Zero/ALUR31 inputs, no PCSrc output. PCSrc is now formed in EX.

module controller (
    input  [6:0]  op,
    input  [2:0]  funct3,
    input         funct7b5,
    output [1:0]  ResultSrc,
    output        MemWrite, Branch, ALUSrc,
    output        RegWrite, Jump, Jalr,
    output [1:0]  ImmSrc,
    output [3:0]  ALUControl
);
wire [1:0] ALUOp;

main_decoder md (op, ResultSrc, MemWrite, Branch, ALUSrc,
                 RegWrite, Jump, Jalr, ImmSrc, ALUOp);

alu_decoder  ad (op[5], funct3, funct7b5, ALUOp, ALUControl);
endmodule
