`timescale 1ns/1ps

module mmul_sysbase_axis_shell #(
    parameter int DATA_WIDTH = 32,
    parameter int DIM_WIDTH = 8,
    parameter int ARRAY_SIZE = 4,
    parameter int MAX_DIM = 8
) (
    input  logic                     ap_clk,
    input  logic                     ap_rst_n,
    input  logic                     ap_start,
    input  logic [DIM_WIDTH-1:0]     cfg_dim,
    output logic                     ap_done,
    output logic                     ap_idle,
    output logic                     ap_ready,
    output logic                     ap_busy,
    input  logic                     s_axis_in_tvalid,
    output logic                     s_axis_in_tready,
    input  logic [DATA_WIDTH-1:0]    s_axis_in_tdata,
    output logic                     m_axis_out_tvalid,
    input  logic                     m_axis_out_tready,
    output logic [DATA_WIDTH-1:0]    m_axis_out_tdata
);

logic ap_start_d;
logic ap_start_pulse;
logic core_done;
logic core_busy;

always_ff @(posedge ap_clk) begin
    if (!ap_rst_n) begin
        ap_start_d <= 1'b0;
    end else begin
        ap_start_d <= ap_start;
    end
end

assign ap_start_pulse = ap_start & ~ap_start_d;

mmul_sysbase_core #(
    .DATA_WIDTH(DATA_WIDTH),
    .DIM_WIDTH(DIM_WIDTH),
    .ARRAY_SIZE(ARRAY_SIZE),
    .MAX_DIM(MAX_DIM)
) u_core (
    .clk(ap_clk),
    .rst_n(ap_rst_n),
    .start(ap_start_pulse),
    .cfg_dim(cfg_dim),
    .in_valid(s_axis_in_tvalid),
    .in_ready(s_axis_in_tready),
    .in_data(s_axis_in_tdata),
    .out_valid(m_axis_out_tvalid),
    .out_ready(m_axis_out_tready),
    .out_data(m_axis_out_tdata),
    .busy(core_busy),
    .done(core_done)
);

assign ap_done = core_done;
assign ap_busy = core_busy;
assign ap_idle = ~core_busy;
assign ap_ready = ~core_busy;

endmodule
