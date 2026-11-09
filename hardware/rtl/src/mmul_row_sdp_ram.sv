`timescale 1ns/1ps

module mmul_row_sdp_ram #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 8,
    parameter int DEPTH = 256
) (
    input  logic                         clk,
    input  logic                         we,
    input  logic [ADDR_WIDTH-1:0]        waddr,
    input  logic signed [DATA_WIDTH-1:0] wdata,
    input  logic                         re,
    input  logic [ADDR_WIDTH-1:0]        raddr,
    output logic signed [DATA_WIDTH-1:0] rdata
);

(* ram_style = "block" *) logic signed [DATA_WIDTH-1:0] mem [0:DEPTH-1];

always_ff @(posedge clk) begin
    if (we) begin
        mem[waddr] <= wdata;
    end

    if (re) begin
        rdata <= mem[raddr];
    end
end

endmodule
