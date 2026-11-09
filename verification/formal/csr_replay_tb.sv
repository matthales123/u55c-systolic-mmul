`timescale 1ns/1ps
// Independent event-driven replay of the CSR counterexample and its fix.
// The runner compiles this with the real complete RTL hierarchy. No abstract
// datapath model or formal assertions are used in this replay.
module csr_replay_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset = 1;
    reg csr_req_valid = 0, csr_req_write = 0;
    reg [3:0] csr_req_addr = 0;
    reg [31:0] csr_req_wdata = 0;
    wire csr_req_ready, csr_resp_valid;
    wire [31:0] csr_resp_rdata;
    reg csr_resp_ready = 1;
    wire memreq_val, memreq_rw, memresp_rdy;
    wire [31:0] memreq_addr, memreq_data;
    mmul_sysbase_xcel dut (
        .clk(clk), .reset(reset),
        .csr_req_valid(csr_req_valid), .csr_req_write(csr_req_write),
        .csr_req_addr(csr_req_addr), .csr_req_wdata(csr_req_wdata),
        .csr_req_ready(csr_req_ready), .csr_resp_valid(csr_resp_valid),
        .csr_resp_rdata(csr_resp_rdata), .csr_resp_ready(csr_resp_ready),
        .memreq_val(memreq_val), .memreq_rw(memreq_rw),
        .memreq_addr(memreq_addr), .memreq_data(memreq_data),
        .memreq_rdy(1'b1), .memresp_val(1'b0), .memresp_data(32'd0), .memresp_rdy(memresp_rdy)
    );
    task tick;
        begin @(posedge clk); #1; end
    endtask
    initial begin
        $dumpfile("replay.vcd");
        $dumpvars(0, csr_replay_tb);
        repeat (2) tick();
        @(negedge clk); reset = 0;
        csr_req_valid = 1; csr_req_addr = 5;
        tick();
        if (!csr_resp_valid || csr_resp_rdata !== 4) $fatal(1, "ARRAY_SIZE read failed");
        @(negedge clk); csr_resp_ready = 0; csr_req_addr = 6;
        tick();
`ifdef EXPECT_HISTORICAL_BUG
        if (!csr_resp_valid || csr_resp_rdata !== 8)
            $fatal(1, "historical CSR response-overwrite defect did not reproduce");
        $display("PASS: historical CSR defect independently reproduced (4 overwritten by 8 while stalled)");
`else
        if (!csr_resp_valid || csr_resp_rdata !== 4 || csr_req_ready !== 0)
            $fatal(1, "stalled CSR response was not preserved");
        repeat (3) begin
            tick();
            if (!csr_resp_valid || csr_resp_rdata !== 4 || csr_req_ready !== 0)
                $fatal(1, "stalled response changed");
        end
        @(negedge clk); csr_resp_ready = 1;
        tick();
        if (!csr_resp_valid || csr_resp_rdata !== 8)
            $fatal(1, "consume-and-replace read failed");

        // A blocked write must not change the pre-write value returned when
        // that same request is eventually accepted.
        @(negedge clk); csr_req_write = 1; csr_req_addr = 1; csr_req_wdata = 32'h1111;
        tick();
        if (csr_resp_rdata !== 0) $fatal(1, "first write pre-value mismatch");
        @(negedge clk); csr_resp_ready = 0; csr_req_wdata = 32'h2222;
        repeat (3) begin
            tick();
            if (csr_resp_rdata !== 0 || csr_req_ready !== 0)
                $fatal(1, "blocked write replaced pending response");
        end
        @(negedge clk); csr_resp_ready = 1;
        tick();
        if (csr_resp_rdata !== 32'h1111) $fatal(1, "blocked write had premature side effects");
        @(negedge clk); csr_req_write = 0;
        tick();
        if (csr_resp_rdata !== 32'h2222) $fatal(1, "accepted write readback mismatch");
        @(negedge clk); csr_req_valid = 0;
        tick();
        if (csr_resp_valid) $fatal(1, "response duplicated after consumption");
        $display("PASS: corrected CSR hold, consume-and-replace, and accepted-write semantics");
`endif
        if (memreq_val) $fatal(1, "CSR-only replay unexpectedly launched memory traffic");
        $finish;
    end
    initial begin
        #10000;
        $fatal(1, "CSR replay timeout");
    end
endmodule
