// reg_file.v - register file for PIPELINED RISC-V CPU
// CHANGE vs single-cycle: internal write-first bypass.
// In a 5-stage pipeline WB writes and ID reads in the SAME cycle.
// Without this bypass ID would read the stale value.

module reg_file #(parameter DATA_WIDTH = 32) (
    input       clk,
    input       wr_en,
    input       [4:0] rd_addr1, rd_addr2, wr_addr,
    input       [DATA_WIDTH-1:0] wr_data,
    output      [DATA_WIDTH-1:0] rd_data1, rd_data2
);

reg [DATA_WIDTH-1:0] reg_file_arr [0:31];

integer i;
initial begin
    for (i = 0; i < 32; i = i + 1) reg_file_arr[i] = 0;
end

always @(posedge clk) begin
    if (wr_en) reg_file_arr[wr_addr] <= wr_data;
end

// ---- WRITE-FIRST BYPASS (new) ----
wire hit1 = wr_en && (wr_addr != 5'd0) && (wr_addr == rd_addr1);
wire hit2 = wr_en && (wr_addr != 5'd0) && (wr_addr == rd_addr2);

assign rd_data1 = (rd_addr1 == 5'd0) ? {DATA_WIDTH{1'b0}} :
                  hit1               ? wr_data            : reg_file_arr[rd_addr1];
assign rd_data2 = (rd_addr2 == 5'd0) ? {DATA_WIDTH{1'b0}} :
                  hit2               ? wr_data            : reg_file_arr[rd_addr2];
endmodule
