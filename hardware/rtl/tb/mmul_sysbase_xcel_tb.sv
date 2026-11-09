`timescale 1ns/1ps

module mmul_sysbase_xcel_tb;

logic clk;
logic reset;

logic        csr_req_valid;
logic        csr_req_write;
logic [3:0]  csr_req_addr;
logic [31:0] csr_req_wdata;
logic        csr_req_ready;
logic        csr_resp_valid;
logic [31:0] csr_resp_rdata;
logic        csr_resp_ready;

logic        memreq_val;
logic        memreq_rw;
logic [31:0] memreq_addr;
logic [31:0] memreq_data;
logic        memreq_rdy;
logic        memresp_val;
logic [31:0] memresp_data;
logic        memresp_rdy;

localparam int TB_ARRAY_SIZE = 4;
localparam int TB_MAX_DIM = 8;
localparam int MEM_WORDS = 16384;

localparam int BASE_A = 32'h0000_0000;
localparam int BASE_B = 32'h0000_2000;
localparam int BASE_C = 32'h0000_4000;

integer error_count;
integer case_count;
integer cycle_count;
integer stall_mod;

logic [31:0] mem_model [0:MEM_WORDS-1];
logic        pending_read_valid;
logic [31:0] pending_read_data;

integer signed mat_a [0:TB_MAX_DIM-1][0:TB_MAX_DIM-1];
integer signed mat_b [0:TB_MAX_DIM-1][0:TB_MAX_DIM-1];
integer signed mat_exp [0:TB_MAX_DIM-1][0:TB_MAX_DIM-1];

mmul_sysbase_xcel #(
    .DATA_WIDTH(32),
    .DIM_WIDTH(8),
    .ARRAY_SIZE(TB_ARRAY_SIZE),
    .MAX_DIM(TB_MAX_DIM)
) dut (
    .clk(clk),
    .reset(reset),
    .csr_req_valid(csr_req_valid),
    .csr_req_write(csr_req_write),
    .csr_req_addr(csr_req_addr),
    .csr_req_wdata(csr_req_wdata),
    .csr_req_ready(csr_req_ready),
    .csr_resp_valid(csr_resp_valid),
    .csr_resp_rdata(csr_resp_rdata),
    .csr_resp_ready(csr_resp_ready),
    .memreq_val(memreq_val),
    .memreq_rw(memreq_rw),
    .memreq_addr(memreq_addr),
    .memreq_data(memreq_data),
    .memreq_rdy(memreq_rdy),
    .memresp_val(memresp_val),
    .memresp_data(memresp_data),
    .memresp_rdy(memresp_rdy)
);

always #5 clk = ~clk;

function automatic integer lcg_next(input integer cur);
begin
    lcg_next = ((cur * 1103515245) + 12345) & 32'h7fffffff;
end
endfunction

function automatic integer signed gen_val(input integer dim, input integer r, input integer c, input integer pat);
begin
    case (pat)
        0: gen_val = (r * dim) + c + 1;
        1: gen_val = (((r * 3) + (c * 7) + dim + 1) % 17) - 8;
        2: gen_val = ((r - c) * 3) + 2;
        3: gen_val = (((r + 2) * (c + 5)) % 19) - 9;
        default: gen_val = ((r + c) % 7) - 3;
    endcase
end
endfunction

task automatic csr_write(input [3:0] addr, input [31:0] data);
begin
    csr_req_valid <= 1'b1;
    csr_req_write <= 1'b1;
    csr_req_addr <= addr;
    csr_req_wdata <= data;
    @(posedge clk);
    csr_req_valid <= 1'b0;
    csr_req_write <= 1'b0;
    csr_req_addr <= 4'd0;
    csr_req_wdata <= 32'd0;
end
endtask

task automatic csr_read(input [3:0] addr, output [31:0] data_out);
integer wait_cycles;
begin
    csr_req_valid <= 1'b1;
    csr_req_write <= 1'b0;
    csr_req_addr <= addr;
    csr_req_wdata <= 32'd0;
    @(posedge clk);
    csr_req_valid <= 1'b0;
    csr_req_addr <= 4'd0;

    wait_cycles = 0;
    while (!csr_resp_valid && wait_cycles < 1000) begin
        @(posedge clk);
        wait_cycles = wait_cycles + 1;
    end

    if (!csr_resp_valid) begin
        $display("FAIL: csr_read timeout addr=%0d", addr);
        $fatal(1);
    end

    data_out = csr_resp_rdata;
    @(posedge clk);
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
            mat_a[r][c] = gen_val(dim, r, c, pat_a);
            mat_b[r][c] = gen_val(dim, r, c, pat_b);
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

task automatic set_case_identity_left(input integer dim);
integer r;
integer c;
begin
    clear_matrices();
    for (r = 0; r < dim; r = r + 1) begin
        for (c = 0; c < dim; c = c + 1) begin
            mat_a[r][c] = (r == c) ? 1 : 0;
            mat_b[r][c] = gen_val(dim, r, c, 3);
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

task automatic preload_memory(input integer dim);
integer r;
integer c;
integer idx;
begin
    for (r = 0; r < dim; r = r + 1) begin
        for (c = 0; c < dim; c = c + 1) begin
            idx = r * dim + c;
            mem_model[(BASE_A >> 2) + idx] = mat_a[r][c];
            mem_model[(BASE_B >> 2) + idx] = mat_b[r][c];
            mem_model[(BASE_C >> 2) + idx] = 32'hDEAD_BEEF;
        end
    end
end
endtask

task automatic verify_output_memory(input integer dim, input string case_name);
integer r;
integer c;
integer idx;
integer signed got;
integer signed exp;
begin
    for (r = 0; r < dim; r = r + 1) begin
        for (c = 0; c < dim; c = c + 1) begin
            idx = r * dim + c;
            got = $signed(mem_model[(BASE_C >> 2) + idx]);
            exp = mat_exp[r][c];
            if (got !== exp) begin
                $display("FAIL: case=%s r=%0d c=%0d expected=%0d got=%0d", case_name, r, c, exp, got);
                error_count = error_count + 1;
            end
        end
    end
end
endtask

task automatic run_case(
    input string case_name,
    input integer dim,
    input integer local_stall_mod
);
logic [31:0] status;
integer wait_cycles;
begin
    case_count = case_count + 1;
    stall_mod = local_stall_mod;

    $display("INFO: running xcel case %0d (%s) dim=%0d stall_mod=%0d", case_count, case_name, dim, stall_mod);

    compute_expected(dim);
    preload_memory(dim);

    csr_write(4'h1, BASE_A);
    csr_write(4'h2, BASE_B);
    csr_write(4'h3, BASE_C);
    csr_write(4'h4, dim[31:0]);
    csr_write(4'h0, 32'h1);

    // Wait for launch: busy should assert after GO is accepted.
    wait_cycles = 0;
    while (wait_cycles < 500000) begin
        csr_read(4'h0, status);
        if (status[2]) begin
            break;
        end
        wait_cycles = wait_cycles + 1;
    end

    if (wait_cycles >= 500000) begin
        $display("FAIL: case=%s launch timeout (busy never asserted)", case_name);
        $fatal(1);
    end

    // Wait for completion: done asserted and busy deasserted.
    wait_cycles = 0;
    while (wait_cycles < 500000) begin
        csr_read(4'h0, status);
        if (status[1] && !status[2]) begin
            break;
        end
        wait_cycles = wait_cycles + 1;
    end

    if (wait_cycles >= 500000) begin
        $display("FAIL: case=%s completion timeout", case_name);
        $fatal(1);
    end

    verify_output_memory(dim, case_name);
end
endtask

always_ff @(posedge clk) begin
    integer word_addr;

    cycle_count <= cycle_count + 1;

    // Configurable request-ready stall model.
    if (stall_mod <= 0) begin
        memreq_rdy <= 1'b1;
    end else begin
        memreq_rdy <= ((cycle_count % stall_mod) != 0);
    end

    // One-cycle delayed read response model.
    memresp_val <= pending_read_valid;
    memresp_data <= pending_read_data;
    pending_read_valid <= 1'b0;

    if (memreq_val && memreq_rdy) begin
        word_addr = memreq_addr[31:2];

        if (word_addr >= MEM_WORDS) begin
            $display("FAIL: memory address out of range addr=%h", memreq_addr);
            $fatal(1);
        end

        if (!memreq_rw) begin
            pending_read_valid <= 1'b1;
            pending_read_data <= mem_model[word_addr];
        end else begin
            mem_model[word_addr] <= memreq_data;
        end
    end
end

initial begin
    integer i;
    logic [31:0] status;

    clk = 1'b0;
    reset = 1'b1;

    csr_req_valid = 1'b0;
    csr_req_write = 1'b0;
    csr_req_addr = 4'd0;
    csr_req_wdata = 32'd0;
    csr_resp_ready = 1'b1;

    memreq_rdy = 1'b1;
    memresp_val = 1'b0;
    memresp_data = 32'd0;
    pending_read_valid = 1'b0;
    pending_read_data = 32'd0;

    error_count = 0;
    case_count = 0;
    cycle_count = 0;
    stall_mod = 0;

    for (i = 0; i < MEM_WORDS; i = i + 1) begin
        mem_model[i] = 32'd0;
    end

    repeat (8) @(posedge clk);
    reset = 1'b0;

    csr_read(4'h5, status);
    if (status != TB_ARRAY_SIZE) begin
        $display("FAIL: ARRAY_SIZE CSR mismatch expected=%0d got=%0d", TB_ARRAY_SIZE, status);
        $fatal(1);
    end

    csr_read(4'h6, status);
    if (status != TB_MAX_DIM) begin
        $display("FAIL: MAX_DIM CSR mismatch expected=%0d got=%0d", TB_MAX_DIM, status);
        $fatal(1);
    end

    set_case_generated(1, 0, 0);
    run_case("xcel_dim1_tiny", 1, 0);

    set_case_generated(2, 1, 2);
    run_case("xcel_dim2_signed", 2, 3);

    set_case_generated(4, 0, 1);
    run_case("xcel_dim4_full", 4, 0);

    set_case_zero(5);
    run_case("xcel_dim5_zero_tiled", 5, 4);

    set_case_identity_left(5);
    run_case("xcel_dim5_identity_left", 5, 2);

    set_case_random(6, 4444, 8888, 12);
    run_case("xcel_dim6_random_tiled", 6, 3);

    set_case_random(8, 13579, 24680, 8);
    run_case("xcel_dim8_random_max", 8, 5);

    if (error_count != 0) begin
        $display("FAIL: mmul_sysbase_xcel_tb with %0d mismatches", error_count);
        $fatal(1);
    end else begin
        $display("PASS: mmul_sysbase_xcel_tb (%0d cases)", case_count);
        $finish;
    end
end

initial begin
    #5000000;
    $display("FAIL: mmul_sysbase_xcel_tb timeout");
    $display("DBG state=%0d op_busy=%0d op_done=%0d load_count=%0d store_count=%0d", 
             dut.state, dut.op_busy, dut.op_done, dut.load_count, dut.store_count);
    $fatal(1);
end

endmodule
