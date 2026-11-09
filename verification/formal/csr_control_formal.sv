// Formal harness for the real mmul_sysbase_xcel.sv CSR/scheduler boundary.
// Environment assumption: reset is asserted at the first sampled clock only.
// Thereafter reset, CSR requests/backpressure, memory ready/responses and the
// abstract datapath outputs are unrestricted. In particular, no assumption
// suppresses a new CSR request while an earlier response is stalled.
module csr_control_formal(input clk);
    (* anyseq *) reg reset;
    (* anyseq *) reg csr_req_valid, csr_req_write;
    (* anyseq *) reg [3:0] csr_req_addr;
    (* anyseq *) reg [31:0] csr_req_wdata;
    wire csr_req_ready, csr_resp_valid;
    wire [31:0] csr_resp_rdata;
    (* anyseq *) reg csr_resp_ready;
    wire memreq_val, memreq_rw;
    wire [31:0] memreq_addr, memreq_data;
    (* anyseq *) reg memreq_rdy, memresp_val;
    (* anyseq *) reg [31:0] memresp_data;
    wire memresp_rdy;

    mmul_sysbase_xcel #(.DATA_WIDTH(32), .DIM_WIDTH(8), .ARRAY_SIZE(4), .MAX_DIM(8)) dut (
        .clk(clk), .reset(reset),
        .csr_req_valid(csr_req_valid), .csr_req_write(csr_req_write),
        .csr_req_addr(csr_req_addr), .csr_req_wdata(csr_req_wdata),
        .csr_req_ready(csr_req_ready), .csr_resp_valid(csr_resp_valid),
        .csr_resp_rdata(csr_resp_rdata), .csr_resp_ready(csr_resp_ready),
        .memreq_val(memreq_val), .memreq_rw(memreq_rw),
        .memreq_addr(memreq_addr), .memreq_data(memreq_data),
        .memreq_rdy(memreq_rdy), .memresp_val(memresp_val),
        .memresp_data(memresp_data), .memresp_rdy(memresp_rdy)
    );

    reg f_past_valid = 0;
    reg [1:0] f_read_cover = 0;
    reg f_pending = 0;
    reg [31:0] f_a_base = 0, f_b_base = 0, f_c_base = 0, f_dim = 0;
    always @(posedge clk) begin
        f_past_valid <= 1;
        if (!f_past_valid) assume(reset);
`ifdef READONLY_COUNTEREXAMPLE
        // Restrict the historical-defect witness to two *valid* read-only
        // registers. This restriction is NOT applied to the production proof.
        assume(!csr_req_write);
        assume(csr_req_addr == 5 || csr_req_addr == 6);
`endif

        if (reset) begin
            f_pending <= 0;
            f_a_base <= 0;
            f_b_base <= 0;
            f_c_base <= 0;
            f_dim <= 0;
        end else begin
            if (csr_resp_valid && csr_resp_ready) f_pending <= 0;
            if (csr_req_valid && csr_req_ready) begin
                f_pending <= 1;
                if (csr_req_write) begin
                    case (csr_req_addr)
                        1: f_a_base <= csr_req_wdata;
                        2: f_b_base <= csr_req_wdata;
                        3: f_c_base <= csr_req_wdata;
                        4: f_dim <= csr_req_wdata;
                    endcase
                end
            end
        end

`ifdef CHECK_RESET_READBACK
        if (f_past_valid && $past(reset)) begin
            assert(!csr_resp_valid);
            assert(!memreq_val);
        end
        if (f_past_valid && !reset && !$past(reset) &&
            $past(csr_req_valid && csr_req_ready && csr_req_addr == 5)) begin
            assert(csr_resp_valid);
            assert(csr_resp_rdata == 4);
        end
        if (f_past_valid && !reset && !$past(reset) &&
            $past(csr_req_valid && csr_req_ready && csr_req_addr == 6)) begin
            assert(csr_resp_valid);
            assert(csr_resp_rdata == 8);
        end
`endif

`ifdef CHECK_CSR_TRANSACTIONS
        if (f_past_valid && !reset) begin
            assert(csr_resp_valid == f_pending);
            if (csr_req_valid && csr_req_ready)
                assert(!f_pending || (csr_resp_valid && csr_resp_ready));
        end
`endif
`ifdef CHECK_CSR_REGISTERS
        if (f_past_valid && !reset && !$past(reset) &&
            $past(csr_req_valid && csr_req_ready)) begin
            // Reads and writes both respond with the pre-write register value.
            case ($past(csr_req_addr))
                1: assert(csr_resp_rdata == $past(f_a_base));
                2: assert(csr_resp_rdata == $past(f_b_base));
                3: assert(csr_resp_rdata == $past(f_c_base));
                4: assert(csr_resp_rdata == $past(f_dim));
            endcase
        end
`endif

`ifdef CHECK_MEMORY_HOLD
        if (f_past_valid && !reset && !$past(reset) &&
            $past(memreq_val && !memreq_rdy)) begin
            assert(memreq_val);
            assert({memreq_rw, memreq_addr, memreq_data} ==
                   $past({memreq_rw, memreq_addr, memreq_data}));
        end
`endif

`ifdef CHECK_CSR_HOLD
        if (f_past_valid && !reset && !$past(reset) &&
            $past(csr_resp_valid && !csr_resp_ready)) begin
            assert(csr_resp_valid);
            assert(csr_resp_rdata == $past(csr_resp_rdata));
        end
`endif

`ifdef NEGATIVE_CONTROL
        // Deliberately false: actual read-only ARRAY_SIZE is 4, not 5.
        // A counterexample here checks that the engine, assertion and stimulus
        // paths are active. It is separate from the real CSR hold defect.
        if (f_past_valid && !reset && !$past(reset) &&
            $past(csr_req_valid && csr_req_ready && csr_req_addr == 5))
            assert(csr_resp_rdata == 5);
`endif

        if (reset) f_read_cover <= 0;
        else begin
            case (f_read_cover)
                0: if (csr_req_valid && csr_req_ready && !csr_req_write && csr_req_addr == 5)
                    f_read_cover <= 1;
                1: if (csr_resp_valid && csr_resp_rdata == 4 && !csr_resp_ready)
                    f_read_cover <= 2;
                2: if (csr_resp_valid && csr_resp_rdata == 4 && csr_resp_ready)
                    f_read_cover <= 3;
            endcase
        end
`ifdef COVER_CONTROL
        cover(!reset && f_read_cover == 3);
        cover(!reset && memreq_val && !memreq_rdy && !memreq_rw);
        cover(f_past_valid && !reset && !$past(reset) &&
              $past(csr_resp_valid && csr_resp_ready && csr_req_valid && csr_req_ready && csr_req_addr == 5) &&
              csr_resp_valid && csr_resp_rdata == 4);
`endif
    end
endmodule
