`timescale 1ns/1ps

module mmul_accel_scalable_tb;

reg clk;
reg rst_n;
reg start;
reg [7:0] cfg_dim;
reg in_valid;
wire in_ready;
reg [31:0] in_data;
wire out_valid;
reg out_ready;
wire [31:0] out_data;
wire busy;
wire done;
integer error_count;

mmul_accel_scalable #(
    .DATA_WIDTH(32),
    .ACC_WIDTH(64),
    .MAX_DIM(10),
    .DIM_WIDTH(8)
) dut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .cfg_dim(cfg_dim),
    .in_valid(in_valid),
    .in_ready(in_ready),
    .in_data(in_data),
    .out_valid(out_valid),
    .out_ready(out_ready),
    .out_data(out_data),
    .busy(busy),
    .done(done)
);

always #5 clk = ~clk;

task automatic push_word(input [31:0] w);
begin
    while (!in_ready) @(posedge clk);
    in_valid <= 1'b1;
    in_data <= w;
    @(posedge clk);
    in_valid <= 1'b0;
    in_data <= 32'd0;
end
endtask

task automatic expect_word(input integer idx, input [31:0] exp);
reg seen;
begin
    seen = 1'b0;
    while (!seen) begin
        @(posedge clk);
        if (out_valid) begin
            #1;
            if (out_data !== exp) begin
                $display("FAIL: idx=%0d expected=%0d got=%0d", idx, exp, out_data);
                error_count = error_count + 1;
            end
            seen = 1'b1;
        end
    end
end
endtask

task automatic run_case_2x2;
begin
    cfg_dim <= 8'd2;
    start <= 1'b1;
    @(posedge clk);
    start <= 1'b0;

    // Matrix A (row-major): [1 2; 3 4]
    push_word(32'd1);
    push_word(32'd2);
    push_word(32'd3);
    push_word(32'd4);

    // Matrix B (row-major): [5 6; 7 8]
    push_word(32'd5);
    push_word(32'd6);
    push_word(32'd7);
    push_word(32'd8);

    // Expected C: [19 22; 43 50]
    expect_word(0, 32'd19);
    expect_word(1, 32'd22);
    expect_word(2, 32'd43);
    expect_word(3, 32'd50);

    wait(done);
    @(posedge clk);
end
endtask

task automatic run_case_3x3;
begin
    cfg_dim <= 8'd3;
    start <= 1'b1;
    @(posedge clk);
    start <= 1'b0;

    // Matrix A (row-major): [1 2 3; 4 5 6; 7 8 9]
    push_word(32'd1);
    push_word(32'd2);
    push_word(32'd3);
    push_word(32'd4);
    push_word(32'd5);
    push_word(32'd6);
    push_word(32'd7);
    push_word(32'd8);
    push_word(32'd9);

    // Matrix B (row-major): [9 8 7; 6 5 4; 3 2 1]
    push_word(32'd9);
    push_word(32'd8);
    push_word(32'd7);
    push_word(32'd6);
    push_word(32'd5);
    push_word(32'd4);
    push_word(32'd3);
    push_word(32'd2);
    push_word(32'd1);

    // Expected C: [30 24 18; 84 69 54; 138 114 90]
    expect_word(0, 32'd30);
    expect_word(1, 32'd24);
    expect_word(2, 32'd18);
    expect_word(3, 32'd84);
    expect_word(4, 32'd69);
    expect_word(5, 32'd54);
    expect_word(6, 32'd138);
    expect_word(7, 32'd114);
    expect_word(8, 32'd90);

    wait(done);
    @(posedge clk);
end
endtask

initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    start = 1'b0;
    cfg_dim = 8'd0;
    in_valid = 1'b0;
    in_data = 32'd0;
    out_ready = 1'b1;
    error_count = 0;

    repeat (5) @(posedge clk);
    rst_n = 1'b1;

    run_case_2x2();
    repeat (4) @(posedge clk);

    run_case_3x3();
    repeat (4) @(posedge clk);

    if (error_count != 0) begin
        $display("FAIL: mmul_accel_scalable_tb with %0d mismatches", error_count);
        $fatal(1);
    end else begin
        $display("PASS: mmul_accel_scalable_tb");
        $finish;
    end
end

endmodule
