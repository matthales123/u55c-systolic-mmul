// Explicit over-approximation for xcel *control-only* proofs.
// The scheduler/CSR RTL is the unmodified production mmul_sysbase_xcel.sv.
// Every datapath output below is unconstrained on every cycle. A passing safety
// proof therefore does not rely on arithmetic or latency guarantees from the
// shell. This model is NOT used for the separate full-RTL shell checks.
module mmul_sysbase_axis_shell #(
    parameter DATA_WIDTH = 32, DIM_WIDTH = 8, ARRAY_SIZE = 4, MAX_DIM = 8
) (
    input ap_clk, ap_rst_n, ap_start,
    input [DIM_WIDTH-1:0] cfg_dim,
    output ap_done, ap_idle, ap_ready, ap_busy,
    input s_axis_in_tvalid,
    output s_axis_in_tready,
    input [DATA_WIDTH-1:0] s_axis_in_tdata,
    output m_axis_out_tvalid,
    input m_axis_out_tready,
    output [DATA_WIDTH-1:0] m_axis_out_tdata
);
    (* anyseq *) reg f_done, f_idle, f_ready, f_busy, f_in_ready, f_out_valid;
    (* anyseq *) reg [DATA_WIDTH-1:0] f_out_data;
    assign ap_done = f_done;
    assign ap_idle = f_idle;
    assign ap_ready = f_ready;
    assign ap_busy = f_busy;
    assign s_axis_in_tready = f_in_ready;
    assign m_axis_out_tvalid = f_out_valid;
    assign m_axis_out_tdata = f_out_data;
endmodule
