`timescale 1ns/1ps

module mmul_sysbase_axis_shell_tb;

logic clk;
logic rst_n;
logic ap_start;
logic [7:0] cfg_dim;
logic s_axis_in_tvalid;
logic s_axis_in_tready;
logic [31:0] s_axis_in_tdata;
logic m_axis_out_tvalid;
logic m_axis_out_tready;
logic [31:0] m_axis_out_tdata;
logic ap_done;
logic ap_idle;
logic ap_ready;
logic ap_busy;
integer error_count;
integer case_count;

localparam int TB_ARRAY_SIZE = 4;
localparam int TB_MAX_DIM = 8;

integer signed mat_a [0:TB_MAX_DIM-1][0:TB_MAX_DIM-1];
integer signed mat_b [0:TB_MAX_DIM-1][0:TB_MAX_DIM-1];
integer signed mat_exp [0:TB_MAX_DIM-1][0:TB_MAX_DIM-1];

mmul_sysbase_axis_shell #(
    .DATA_WIDTH(32),
    .DIM_WIDTH(8),
    .ARRAY_SIZE(TB_ARRAY_SIZE),
    .MAX_DIM(TB_MAX_DIM)
) dut (
    .ap_clk(clk),
    .ap_rst_n(rst_n),
    .ap_start(ap_start),
    .cfg_dim(cfg_dim),
    .ap_done(ap_done),
    .ap_idle(ap_idle),
    .ap_ready(ap_ready),
    .ap_busy(ap_busy),
    .s_axis_in_tvalid(s_axis_in_tvalid),
    .s_axis_in_tready(s_axis_in_tready),
    .s_axis_in_tdata(s_axis_in_tdata),
    .m_axis_out_tvalid(m_axis_out_tvalid),
    .m_axis_out_tready(m_axis_out_tready),
    .m_axis_out_tdata(m_axis_out_tdata)
);

always #5 clk = ~clk;

function automatic integer signed gen_a_value(
    input integer dim,
    input integer r,
    input integer c,
    input integer pattern
);
begin
    case (pattern)
        0: gen_a_value = (r * dim) + c + 1;
        1: gen_a_value = (((r * 3) + (c * 5) + dim + 1) % 17) - 8;
        2: gen_a_value = ((((r + 1) * (c + 2)) + dim) % 13) - 6;
        3: gen_a_value = ((r - c) * 3) + 1;
        default: gen_a_value = (((r + c + dim) % 9) - 4);
    endcase
end
endfunction

function automatic integer signed gen_b_value(
    input integer dim,
    input integer r,
    input integer c,
    input integer pattern
);
begin
    case (pattern)
        0: gen_b_value = ((dim - r) * (c + 1));
        1: gen_b_value = (((r * 7) + (c * 2) + 3 + dim) % 15) - 7;
        2: gen_b_value = ((((r + 2) * (c + 1)) + 1) % 19) - 9;
        3: gen_b_value = ((c - r) * 2) - 1;
        default: gen_b_value = (((r * dim) + c + 5) % 11) - 5;
    endcase
end
endfunction

function automatic integer lcg_next(input integer cur);
begin
    lcg_next = ((cur * 1103515245) + 12345) & 32'h7fffffff;
end
endfunction

task automatic pulse_start(input [7:0] dim);
begin
    cfg_dim <= dim;
    ap_start <= 1'b1;
    @(posedge clk);
    ap_start <= 1'b0;
end
endtask

task automatic clear_matrices;
integer r;
integer c;
begin
    for (r = 0; r < TB_MAX_DIM; r = r + 1) begin
        for (c = 0; c < TB_MAX_DIM; c = c + 1) begin
            mat_a[r][c] = 0;
            mat_b[r][c] = 0;
            mat_exp[r][c] = 0;
        end
    end
end
endtask

task automatic set_case_generated(input integer dim, input integer pat_a, input integer pat_b);
integer r;
integer c;
begin
    clear_matrices();
    for (r = 0; r < dim; r = r + 1) begin
        for (c = 0; c < dim; c = c + 1) begin
            mat_a[r][c] = gen_a_value(dim, r, c, pat_a);
            mat_b[r][c] = gen_b_value(dim, r, c, pat_b);
        end
    end
end
endtask

task automatic set_case_zero(input integer dim);
integer r;
integer c;
begin
    clear_matrices();
    for (r = 0; r < dim; r = r + 1) begin
        for (c = 0; c < dim; c = c + 1) begin
            mat_a[r][c] = 0;
            mat_b[r][c] = 0;
        end
    end
end
endtask

task automatic set_case_identity_left(input integer dim, input integer diag);
integer r;
integer c;
begin
    clear_matrices();
    for (r = 0; r < dim; r = r + 1) begin
        for (c = 0; c < dim; c = c + 1) begin
            if (r == c) begin
                mat_a[r][c] = diag;
            end else begin
                mat_a[r][c] = 0;
            end
            mat_b[r][c] = gen_b_value(dim, r, c, 2);
        end
    end
end
endtask

task automatic set_case_identity_right(input integer dim, input integer diag);
integer r;
integer c;
begin
    clear_matrices();
    for (r = 0; r < dim; r = r + 1) begin
        for (c = 0; c < dim; c = c + 1) begin
            mat_a[r][c] = gen_a_value(dim, r, c, 1);
            if (r == c) begin
                mat_b[r][c] = diag;
            end else begin
                mat_b[r][c] = 0;
            end
        end
    end
end
endtask

task automatic set_case_edge_signed(input integer dim);
integer r;
integer c;
begin
    clear_matrices();
    for (r = 0; r < dim; r = r + 1) begin
        for (c = 0; c < dim; c = c + 1) begin
            if (((r + c) % 2) == 0) begin
                mat_a[r][c] = 1000 - (r * 17) - (c * 9);
                mat_b[r][c] = -900 + (r * 13) + (c * 7);
            end else begin
                mat_a[r][c] = -950 + (r * 11) + (c * 5);
                mat_b[r][c] = 870 - (r * 19) - (c * 3);
            end
        end
    end
end
endtask

task automatic set_case_random(input integer dim, input integer seed_a, input integer seed_b, input integer max_abs);
integer r;
integer c;
integer s_a;
integer s_b;
begin
    clear_matrices();
    s_a = seed_a;
    s_b = seed_b;

    for (r = 0; r < dim; r = r + 1) begin
        for (c = 0; c < dim; c = c + 1) begin
            s_a = lcg_next(s_a);
            s_b = lcg_next(s_b);
            mat_a[r][c] = (s_a % ((2 * max_abs) + 1)) - max_abs;
            mat_b[r][c] = (s_b % ((2 * max_abs) + 1)) - max_abs;
        end
    end
end
endtask

task automatic push_word(input integer signed word, input integer gap_cycles);
integer wait_cycles;
logic signed [31:0] word32;
begin
    word32 = word;

    repeat (gap_cycles) @(posedge clk);

    wait_cycles = 0;
    while (!s_axis_in_tready && wait_cycles < 20000) begin
        @(posedge clk);
        wait_cycles = wait_cycles + 1;
    end

    if (!s_axis_in_tready) begin
        $display("FAIL: push_word timeout waiting for s_axis_in_tready (word=%0d)", word32);
        $fatal(1);
    end

    s_axis_in_tvalid <= 1'b1;
    s_axis_in_tdata <= word32;
    @(posedge clk);
    s_axis_in_tvalid <= 1'b0;
    s_axis_in_tdata <= 32'd0;
end
endtask

task automatic load_case(input integer dim, input integer src_gap_cycles);
integer r;
integer c;
begin
    for (r = 0; r < dim; r = r + 1) begin
        for (c = 0; c < dim; c = c + 1) begin
            push_word(mat_a[r][c], src_gap_cycles);
        end
    end

    for (r = 0; r < dim; r = r + 1) begin
        for (c = 0; c < dim; c = c + 1) begin
            push_word(mat_b[r][c], src_gap_cycles);
        end
    end
end
endtask

task automatic compute_expected(input integer dim);
integer r;
integer c;
integer k;
integer signed sum;
begin
    for (r = 0; r < dim; r = r + 1) begin
        for (c = 0; c < dim; c = c + 1) begin
            sum = 0;
            for (k = 0; k < dim; k = k + 1) begin
                sum = sum + (mat_a[r][k] * mat_b[k][c]);
            end
            mat_exp[r][c] = sum;
        end
    end
end
endtask

task automatic expect_case_output(input integer dim, input integer sink_gap_cycles, input string case_name);
reg seen;
integer wait_cycles;
integer out_idx;
integer r;
integer c;
logic signed [31:0] expected32;
begin
    out_idx = 0;

    for (r = 0; r < dim; r = r + 1) begin
        for (c = 0; c < dim; c = c + 1) begin
            seen = 1'b0;
            wait_cycles = 0;
            expected32 = mat_exp[r][c];

            while (!seen && wait_cycles < 120000) begin
                if (sink_gap_cycles == 0) begin
                    m_axis_out_tready <= 1'b1;
                end else begin
                    m_axis_out_tready <= ((wait_cycles % (sink_gap_cycles + 1)) == 0);
                end

                @(posedge clk);
                wait_cycles = wait_cycles + 1;

                if (m_axis_out_tvalid && m_axis_out_tready) begin
                    if ($signed(m_axis_out_tdata) !== expected32) begin
                        $display("FAIL: case=%s idx=%0d expected=%0d got=%0d",
                                 case_name, out_idx, expected32, $signed(m_axis_out_tdata));
                        error_count = error_count + 1;
                    end
                    seen = 1'b1;
                end
            end

            if (!seen) begin
                $display("FAIL: case=%s output timeout idx=%0d expected=%0d",
                         case_name, out_idx, expected32);
                $fatal(1);
            end

            out_idx = out_idx + 1;
        end
    end
end
endtask

task automatic run_case(input string case_name, input integer dim, input integer src_gap, input integer sink_gap);
begin
    case_count = case_count + 1;
    $display("INFO: running case %0d (%s) dim=%0d src_gap=%0d sink_gap=%0d",
             case_count, case_name, dim, src_gap, sink_gap);

    compute_expected(dim);
    pulse_start(dim[7:0]);
    load_case(dim, src_gap);
    expect_case_output(dim, sink_gap, case_name);

    wait(ap_done);
    @(posedge clk);
    m_axis_out_tready = 1'b0;
end
endtask

initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    ap_start = 1'b0;
    cfg_dim = 8'd0;
    s_axis_in_tvalid = 1'b0;
    s_axis_in_tdata = 32'd0;
    m_axis_out_tready = 1'b0;
    error_count = 0;
    case_count = 0;

    repeat (6) @(posedge clk);
    rst_n = 1'b1;

    // Padding + tiny matrix.
    set_case_generated(1, 0, 0);
    run_case("generated_dim1_tiny", 1, 0, 0);

    set_case_generated(2, 1, 2);
    run_case("generated_dim2_pad", 2, 1, 0);

    // Legacy baseline-style 3x3 behavior.
    set_case_generated(3, 0, 1);
    run_case("generated_dim3_base", 3, 0, 0);

    set_case_generated(3, 1, 3);
    run_case("generated_dim3_signed_bp", 3, 1, 2);

    // Full-array cases (dim == ARRAY_SIZE).
    set_case_edge_signed(4);
    run_case("edge_dim4_full_array", 4, 1, 1);

    set_case_random(4, 123, 456, 15);
    run_case("random_dim4_backpressure", 4, 2, 3);

    // Tiled-path cases (dim > ARRAY_SIZE).
    set_case_zero(5);
    run_case("zero_dim5_tiled", 5, 0, 0);

    set_case_identity_left(5, 1);
    run_case("identity_left_dim5_tiled", 5, 1, 1);

    set_case_identity_right(5, 1);
    run_case("identity_right_dim5_tiled", 5, 1, 2);

    set_case_random(5, 777, 2025, 11);
    run_case("random_dim5_tiled", 5, 1, 1);

    set_case_random(6, 1024, 2048, 9);
    run_case("random_dim6_tiled", 6, 2, 2);

    set_case_generated(7, 2, 3);
    run_case("generated_dim7_tiled", 7, 2, 3);

    set_case_random(8, 31415, 92653, 7);
    run_case("random_dim8_max", 8, 1, 3);

    if (error_count != 0) begin
        $display("FAIL: mmul_sysbase_axis_shell_tb with %0d mismatches", error_count);
        $fatal(1);
    end else begin
        $display("PASS: mmul_sysbase_axis_shell_tb (%0d cases)", case_count);
        $finish;
    end
end

initial begin
    #2500000;
    $display("FAIL: mmul_sysbase_axis_shell_tb timeout");
    $display("DBG state=%0d busy=%0d done=%0d tile_expected=%0d tile_results=%0d feed_step=%0d",
             dut.u_core.state,
             dut.u_core.busy,
             dut.u_core.done,
             dut.u_core.tile_expected,
             dut.u_core.tile_results,
             dut.u_core.feed_step);
    $display("DBG tile_base row=%0d col=%0d k=%0d active row=%0d col=%0d k=%0d",
             dut.u_core.tile_row_base,
             dut.u_core.tile_col_base,
             dut.u_core.tile_k_base,
             dut.u_core.active_rows,
             dut.u_core.active_cols,
             dut.u_core.active_k);
    $display("DBG rcnt=%0d,%0d,%0d,%0d fcnt=%0d,%0d,%0d,%0d",
             dut.u_core.result_count[0], dut.u_core.result_count[1],
             dut.u_core.result_count[2], dut.u_core.result_count[3],
             dut.u_core.flagged_count[0], dut.u_core.flagged_count[1],
             dut.u_core.flagged_count[2], dut.u_core.flagged_count[3]);
    $fatal(1);
end

endmodule
