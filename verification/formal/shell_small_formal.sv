// Full, unabstracted RTL smoke: 1x1 SysBase array, MAX_DIM=1, 32-bit datapath.
// This is deliberately a small *configuration-specific* proof, not a proof of
// tiled 4x4/8x8 matrix multiplication. Input values and stalls are unrestricted.
module shell_small_formal(
    input clk, rst_n, start, in_valid, out_ready,
    input [31:0] in_data
);
    (* keep *) wire in_ready, out_valid, busy, done, idle, ready;
    (* keep *) wire [31:0] out_data;
    mmul_sysbase_axis_shell #(.DATA_WIDTH(32), .DIM_WIDTH(8), .ARRAY_SIZE(1), .MAX_DIM(1)) dut (
        .ap_clk(clk), .ap_rst_n(rst_n), .ap_start(start), .cfg_dim(8'd1),
        .ap_done(done), .ap_idle(idle), .ap_ready(ready), .ap_busy(busy),
        .s_axis_in_tvalid(in_valid), .s_axis_in_tready(in_ready), .s_axis_in_tdata(in_data),
        .m_axis_out_tvalid(out_valid), .m_axis_out_tready(out_ready), .m_axis_out_tdata(out_data)
    );
    reg f_past_valid = 0;
    reg f_output_seen = 0;
    always @(posedge clk) begin
        f_past_valid <= 1;
        if (!f_past_valid) assume(!rst_n);
        // Legal ready/valid source: once offered, hold the word until accepted.
        if (f_past_valid && rst_n && $past(rst_n && in_valid && !in_ready)) begin
            assume(in_valid);
            assume(in_data == $past(in_data));
        end
`ifdef CHECK_SHELL
        if (f_past_valid && $past(!rst_n)) begin
            assert(!out_valid);
            assert(!busy);
            assert(!done);
        end
        if (f_past_valid && rst_n && $past(rst_n && out_valid && !out_ready)) begin
            assert(out_valid);
            assert(out_data == $past(out_data));
        end
        if (f_past_valid && rst_n) assert(!(busy && done));
`endif
        if (!rst_n) f_output_seen <= 0;
        else if (out_valid && out_ready) f_output_seen <= 1;
`ifdef COVER_SHELL
        cover(rst_n && out_valid && !out_ready);
        cover(rst_n && done && f_output_seen);
`endif
    end
endmodule
