// branch_cond.v - NEW MODULE
// Dedicated branch comparator, evaluated in the EXECUTE stage.
// Also FIXES the bltu/bgeu bug in the single-cycle version, which used
// ALUResult[31] (sign bit of a-b) for UNSIGNED comparison.

module branch_cond (
    input  [2:0]  funct3,
    input  [31:0] a, b,
    output reg    take
);
wire eq   = (a == b);
wire lt_s = ($signed(a) < $signed(b));
wire lt_u = (a < b);

always @(*) begin
    case (funct3)
        3'b000: take =  eq;    // beq
        3'b001: take = !eq;    // bne
        3'b100: take =  lt_s;  // blt
        3'b101: take = !lt_s;  // bge
        3'b110: take =  lt_u;  // bltu  (was broken)
        3'b111: take = !lt_u;  // bgeu  (was broken)
        default: take = 1'b0;
    endcase
end
endmodule
