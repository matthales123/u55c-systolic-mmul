`timescale 1ns/1ps

module mmul_sysbase_xcel #(
    parameter int DATA_WIDTH = 32,
    parameter int DIM_WIDTH = 8,
    parameter int ARRAY_SIZE = 4,
    parameter int MAX_DIM = 8
) (
    input  logic                    clk,
    input  logic                    reset,

    // --------------------------------------------------------------
    // CSR interface (processor-style control plane)
    // --------------------------------------------------------------
    input  logic                    csr_req_valid,
    input  logic                    csr_req_write,
    input  logic [3:0]              csr_req_addr,
    input  logic [31:0]             csr_req_wdata,
    output logic                    csr_req_ready,
    output logic                    csr_resp_valid,
    output logic [31:0]             csr_resp_rdata,
    input  logic                    csr_resp_ready,

    // --------------------------------------------------------------
    // Memory interface (single-port request/response)
    // --------------------------------------------------------------
    output logic                    memreq_val,
    output logic                    memreq_rw,
    output logic [31:0]             memreq_addr,
    output logic [31:0]             memreq_data,
    input  logic                    memreq_rdy,
    input  logic                    memresp_val,
    input  logic [31:0]             memresp_data,
    output logic                    memresp_rdy
);

// ==================================================================
// 1) CSR-backed configuration/state registers
// ==================================================================

logic [31:0] reg_a_base;
logic [31:0] reg_b_base;
logic [31:0] reg_c_base;
logic [31:0] reg_dim;
logic [31:0] reg_error;

logic op_busy;
logic op_done;
logic op_go_pulse;

// One response slot: accept a request only when the slot is empty or its
// current response is being consumed. This also permits consume-and-replace
// in one cycle while preserving responses and write side effects under stall.
assign csr_req_ready = !csr_resp_valid || csr_resp_ready;
assign memresp_rdy = 1'b1;

// ==================================================================
// 2) SysBase shell instance (datapath)
// ==================================================================

logic                    core_start;
logic [DIM_WIDTH-1:0]    core_dim;
logic                    core_in_valid;
logic                    core_in_ready;
logic [DATA_WIDTH-1:0]   core_in_data;
logic                    core_out_valid;
logic                    core_out_ready;
logic [DATA_WIDTH-1:0]   core_out_data;
logic                    core_done;
logic                    core_busy;
logic                    core_idle;
logic                    core_ready;

mmul_sysbase_axis_shell #(
    .DATA_WIDTH(DATA_WIDTH),
    .DIM_WIDTH(DIM_WIDTH),
    .ARRAY_SIZE(ARRAY_SIZE),
    .MAX_DIM(MAX_DIM)
) u_shell (
    .ap_clk(clk),
    .ap_rst_n(~reset),
    .ap_start(core_start),
    .cfg_dim(core_dim),
    .ap_done(core_done),
    .ap_idle(core_idle),
    .ap_ready(core_ready),
    .ap_busy(core_busy),
    .s_axis_in_tvalid(core_in_valid),
    .s_axis_in_tready(core_in_ready),
    .s_axis_in_tdata(core_in_data),
    .m_axis_out_tvalid(core_out_valid),
    .m_axis_out_tready(core_out_ready),
    .m_axis_out_tdata(core_out_data)
);

assign core_dim = reg_dim[DIM_WIDTH-1:0];

// ==================================================================
// 3) Processor-style memory/load/store scheduler
// ==================================================================

typedef enum logic [3:0] {
    ST_IDLE         = 4'd0,
    ST_LOAD_A_REQ   = 4'd1,
    ST_LOAD_A_WAIT  = 4'd2,
    ST_LOAD_A_PUSH  = 4'd3,
    ST_LOAD_B_REQ   = 4'd4,
    ST_LOAD_B_WAIT  = 4'd5,
    ST_LOAD_B_PUSH  = 4'd6,
    ST_STORE_WAIT   = 4'd7,
    ST_STORE_REQ    = 4'd8,
    ST_DONE         = 4'd9
} sched_state_t;

sched_state_t state;

logic [31:0] total_words;
logic [31:0] load_count;
logic [31:0] store_count;
logic [31:0] rd_data_hold;
logic [31:0] wr_data_hold;

assign total_words = reg_dim * reg_dim;
assign core_out_ready = (state == ST_STORE_WAIT);

// ==================================================================
// 4) Main control logic
// ==================================================================

always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        reg_a_base <= 32'd0;
        reg_b_base <= 32'd0;
        reg_c_base <= 32'd0;
        reg_dim <= 32'd0;
        reg_error <= 32'd0;

        csr_resp_valid <= 1'b0;
        csr_resp_rdata <= 32'd0;

        op_busy <= 1'b0;
        op_done <= 1'b0;
        op_go_pulse <= 1'b0;

        memreq_val <= 1'b0;
        memreq_rw <= 1'b0;
        memreq_addr <= 32'd0;
        memreq_data <= 32'd0;

        core_start <= 1'b0;
        core_in_valid <= 1'b0;
        core_in_data <= 32'd0;

        state <= ST_IDLE;
        load_count <= 32'd0;
        store_count <= 32'd0;
        rd_data_hold <= 32'd0;
        wr_data_hold <= 32'd0;
    end else begin
        // Defaults each cycle.
        op_go_pulse <= 1'b0;
        core_start <= 1'b0;
        core_in_valid <= 1'b0;

        if (csr_resp_valid && csr_resp_ready) begin
            csr_resp_valid <= 1'b0;
        end

        // ------------------------------------------------------------
        // CSR request handling (mirrors original processor workflow)
        // ------------------------------------------------------------
        if (csr_req_valid && csr_req_ready) begin
            if (csr_req_write) begin
                case (csr_req_addr)
                    4'h0: begin
                        if (csr_req_wdata[0] && !op_busy) begin
                            op_go_pulse <= 1'b1;
                            op_done <= 1'b0;
                        end
                    end
                    4'h1: reg_a_base <= csr_req_wdata;
                    4'h2: reg_b_base <= csr_req_wdata;
                    4'h3: reg_c_base <= csr_req_wdata;
                    4'h4: reg_dim <= csr_req_wdata;
                    4'h7: reg_error <= csr_req_wdata;
                    default: ;
                endcase
            end

            csr_resp_valid <= 1'b1;
            case (csr_req_addr)
                4'h0: csr_resp_rdata <= {29'd0, op_busy, op_done, op_go_pulse};
                4'h1: csr_resp_rdata <= reg_a_base;
                4'h2: csr_resp_rdata <= reg_b_base;
                4'h3: csr_resp_rdata <= reg_c_base;
                4'h4: csr_resp_rdata <= reg_dim;
                4'h5: csr_resp_rdata <= ARRAY_SIZE;
                4'h6: csr_resp_rdata <= MAX_DIM;
                4'h7: csr_resp_rdata <= reg_error;
                default: csr_resp_rdata <= 32'd0;
            endcase
        end

        // ------------------------------------------------------------
        // Scheduler FSM: load A, load B, then store core output C.
        // ------------------------------------------------------------
        case (state)
            ST_IDLE: begin
                memreq_val <= 1'b0;
                memreq_rw <= 1'b0;
                memreq_addr <= 32'd0;
                memreq_data <= 32'd0;
                load_count <= 32'd0;
                store_count <= 32'd0;

                if (op_go_pulse) begin
                    if ((reg_dim == 0) || (reg_dim > MAX_DIM)) begin
                        reg_error <= 32'h0000_0001;
                        op_busy <= 1'b0;
                        op_done <= 1'b1;
                        state <= ST_DONE;
                    end else begin
                        reg_error <= 32'd0;
                        op_busy <= 1'b1;
                        op_done <= 1'b0;
                        core_start <= 1'b1;
                        state <= ST_LOAD_A_REQ;
                    end
                end
            end

            ST_LOAD_A_REQ: begin
                if (!memreq_val) begin
                    memreq_val <= 1'b1;
                    memreq_rw <= 1'b0;
                    memreq_addr <= reg_a_base + (load_count << 2);
                    memreq_data <= 32'd0;
                end

                if (memreq_val && memreq_rdy) begin
                    memreq_val <= 1'b0;
                    state <= ST_LOAD_A_WAIT;
                end
            end

            ST_LOAD_A_WAIT: begin
                if (memresp_val) begin
                    rd_data_hold <= memresp_data;
                    state <= ST_LOAD_A_PUSH;
                end
            end

            ST_LOAD_A_PUSH: begin
                if (core_in_ready) begin
                    core_in_valid <= 1'b1;
                    core_in_data <= rd_data_hold;

                    if (load_count + 1 < total_words) begin
                        load_count <= load_count + 1;
                        state <= ST_LOAD_A_REQ;
                    end else begin
                        load_count <= 32'd0;
                        state <= ST_LOAD_B_REQ;
                    end
                end
            end

            ST_LOAD_B_REQ: begin
                if (!memreq_val) begin
                    memreq_val <= 1'b1;
                    memreq_rw <= 1'b0;
                    memreq_addr <= reg_b_base + (load_count << 2);
                    memreq_data <= 32'd0;
                end

                if (memreq_val && memreq_rdy) begin
                    memreq_val <= 1'b0;
                    state <= ST_LOAD_B_WAIT;
                end
            end

            ST_LOAD_B_WAIT: begin
                if (memresp_val) begin
                    rd_data_hold <= memresp_data;
                    state <= ST_LOAD_B_PUSH;
                end
            end

            ST_LOAD_B_PUSH: begin
                if (core_in_ready) begin
                    core_in_valid <= 1'b1;
                    core_in_data <= rd_data_hold;

                    if (load_count + 1 < total_words) begin
                        load_count <= load_count + 1;
                        state <= ST_LOAD_B_REQ;
                    end else begin
                        load_count <= 32'd0;
                        store_count <= 32'd0;
                        state <= ST_STORE_WAIT;
                    end
                end
            end

            ST_STORE_WAIT: begin
                if (core_out_valid && core_out_ready) begin
                    wr_data_hold <= core_out_data;
                    state <= ST_STORE_REQ;
                end
            end

            ST_STORE_REQ: begin
                if (!memreq_val) begin
                    memreq_val <= 1'b1;
                    memreq_rw <= 1'b1;
                    memreq_addr <= reg_c_base + (store_count << 2);
                    memreq_data <= wr_data_hold;
                end

                if (memreq_val && memreq_rdy) begin
                    memreq_val <= 1'b0;
                    if (store_count + 1 < total_words) begin
                        store_count <= store_count + 1;
                        state <= ST_STORE_WAIT;
                    end else begin
                        state <= ST_DONE;
                    end
                end
            end

            ST_DONE: begin
                op_busy <= 1'b0;
                op_done <= 1'b1;
                state <= ST_IDLE;
            end

            default: begin
                state <= ST_IDLE;
            end
        endcase
    end
end

endmodule
