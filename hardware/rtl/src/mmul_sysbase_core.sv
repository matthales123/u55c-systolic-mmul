`timescale 1ns/1ps

module mmul_sysbase_core #(
    parameter int DATA_WIDTH = 32,
    parameter int DIM_WIDTH = 8,
    parameter int ARRAY_SIZE = 4,
    parameter int MAX_DIM = 8
) (
    input  logic                     clk,
    input  logic                     rst_n,
    input  logic                     start,
    input  logic [DIM_WIDTH-1:0]     cfg_dim,
    input  logic                     in_valid,
    output logic                     in_ready,
    input  logic [DATA_WIDTH-1:0]    in_data,
    output logic                     out_valid,
    input  logic                     out_ready,
    output logic [DATA_WIDTH-1:0]    out_data,
    output logic                     busy,
    output logic                     done
);

localparam int COUNT_WIDTH = (2 * DIM_WIDTH);
localparam int FEED_CYCLES = (2 * ARRAY_SIZE);

typedef enum logic [3:0] {
    ST_IDLE       = 4'd0,
    ST_LOAD_A     = 4'd1,
    ST_LOAD_B     = 4'd2,
    ST_PREP_TILE  = 4'd3,
    ST_FEED_PRIME = 4'd4,
    ST_FEED       = 4'd5,
    ST_COLLECT    = 4'd6,
    ST_ADV_TILE   = 4'd7,
    ST_STORE_TILE = 4'd8,
    ST_STREAM_C   = 4'd9,
    ST_DONE       = 4'd10
} state_t;

state_t state;

logic [DIM_WIDTH-1:0] dim_latched;
logic [DIM_WIDTH-1:0] load_row;
logic [DIM_WIDTH-1:0] load_col;

logic [DIM_WIDTH-1:0] tile_row_base;
logic [DIM_WIDTH-1:0] tile_col_base;
logic [DIM_WIDTH-1:0] tile_k_base;

logic [DIM_WIDTH-1:0] active_rows;
logic [DIM_WIDTH-1:0] active_cols;
logic [DIM_WIDTH-1:0] active_k;

logic [DIM_WIDTH-1:0] feed_step;
logic [DIM_WIDTH-1:0] out_row;
logic [DIM_WIDTH-1:0] out_col;
logic [DIM_WIDTH-1:0] store_row;
logic [DIM_WIDTH-1:0] store_col;

logic [COUNT_WIDTH-1:0] tile_expected;
logic [COUNT_WIDTH-1:0] tile_results;
logic [DIM_WIDTH-1:0]   result_count [0:ARRAY_SIZE-1];
logic [DIM_WIDTH-1:0]   flagged_count [0:ARRAY_SIZE-1];

(* ram_style = "block" *) logic signed [DATA_WIDTH-1:0] c_mem [0:MAX_DIM-1][0:MAX_DIM-1];
logic signed [DATA_WIDTH-1:0] tile_accum [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];

logic a_bank_we [0:MAX_DIM-1];
logic b_bank_we [0:MAX_DIM-1];
logic a_bank_re [0:MAX_DIM-1];
logic b_bank_re [0:MAX_DIM-1];
logic [DIM_WIDTH-1:0] a_bank_waddr [0:MAX_DIM-1];
logic [DIM_WIDTH-1:0] b_bank_waddr [0:MAX_DIM-1];
logic [DIM_WIDTH-1:0] a_bank_raddr [0:MAX_DIM-1];
logic [DIM_WIDTH-1:0] b_bank_raddr [0:MAX_DIM-1];
logic signed [DATA_WIDTH-1:0] a_bank_wdata [0:MAX_DIM-1];
logic signed [DATA_WIDTH-1:0] b_bank_wdata [0:MAX_DIM-1];
logic signed [DATA_WIDTH-1:0] a_bank_rdata [0:MAX_DIM-1];
logic signed [DATA_WIDTH-1:0] b_bank_rdata [0:MAX_DIM-1];

logic sa_istreamA_val [0:ARRAY_SIZE-1];
logic sa_istreamA_rdy [0:ARRAY_SIZE-1];
logic [32:0] sa_istreamA_msg [0:ARRAY_SIZE-1];
logic sa_istreamB_val [0:ARRAY_SIZE-1];
logic sa_istreamB_rdy [0:ARRAY_SIZE-1];
logic [32:0] sa_istreamB_msg [0:ARRAY_SIZE-1];
logic sa_ostreamA_val [0:ARRAY_SIZE-1];
logic sa_ostreamA_rdy [0:ARRAY_SIZE-1];
logic [32:0] sa_ostreamA_msg [0:ARRAY_SIZE-1];
logic sa_ostreamB_val [0:ARRAY_SIZE-1];
logic sa_ostreamB_rdy [0:ARRAY_SIZE-1];
logic [32:0] sa_ostreamB_msg [0:ARRAY_SIZE-1];

logic [DIM_WIDTH-1:0] dim_safe;
logic                 all_feed_ready;

assign dim_safe = (cfg_dim == '0) ? DIM_WIDTH'(1) :
                  (cfg_dim > DIM_WIDTH'(MAX_DIM)) ? DIM_WIDTH'(MAX_DIM) :
                  cfg_dim;

genvar gi;
generate
    for (gi = 0; gi < ARRAY_SIZE; gi = gi + 1) begin : g_sa_ready
        assign sa_ostreamA_rdy[gi] = 1'b1;
        assign sa_ostreamB_rdy[gi] = 1'b1;
    end
endgenerate

genvar gb;
generate
    for (gb = 0; gb < MAX_DIM; gb = gb + 1) begin : g_mem_banks
        mmul_row_sdp_ram #(
            .DATA_WIDTH(DATA_WIDTH),
            .ADDR_WIDTH(DIM_WIDTH),
            .DEPTH(MAX_DIM)
        ) u_a_bank (
            .clk(clk),
            .we(a_bank_we[gb]),
            .waddr(a_bank_waddr[gb]),
            .wdata(a_bank_wdata[gb]),
            .re(a_bank_re[gb]),
            .raddr(a_bank_raddr[gb]),
            .rdata(a_bank_rdata[gb])
        );

        mmul_row_sdp_ram #(
            .DATA_WIDTH(DATA_WIDTH),
            .ADDR_WIDTH(DIM_WIDTH),
            .DEPTH(MAX_DIM)
        ) u_b_bank (
            .clk(clk),
            .we(b_bank_we[gb]),
            .waddr(b_bank_waddr[gb]),
            .wdata(b_bank_wdata[gb]),
            .re(b_bank_re[gb]),
            .raddr(b_bank_raddr[gb]),
            .rdata(b_bank_rdata[gb])
        );
    end
endgenerate

always_comb begin : proc_bank_ctrl
    int b;
    int r;
    int row_idx;
    int col_idx;
    logic prefetch_now;
    logic [DIM_WIDTH-1:0] prefetch_step;

    for (b = 0; b < MAX_DIM; b = b + 1) begin
        a_bank_we[b] = 1'b0;
        b_bank_we[b] = 1'b0;
        a_bank_re[b] = 1'b0;
        b_bank_re[b] = 1'b0;

        a_bank_waddr[b] = '0;
        b_bank_waddr[b] = '0;
        a_bank_raddr[b] = '0;
        b_bank_raddr[b] = '0;

        a_bank_wdata[b] = '0;
        b_bank_wdata[b] = '0;
    end

    if ((state == ST_LOAD_A) && in_valid && in_ready) begin
        a_bank_we[load_row] = 1'b1;
        a_bank_waddr[load_row] = load_col;
        a_bank_wdata[load_row] = $signed(in_data);
    end

    if ((state == ST_LOAD_B) && in_valid && in_ready) begin
        // Store B transposed so feed path can issue row-parallel dot products.
        b_bank_we[load_col] = 1'b1;
        b_bank_waddr[load_col] = load_row;
        b_bank_wdata[load_col] = $signed(in_data);
    end

    prefetch_now = 1'b0;
    prefetch_step = '0;

    if (state == ST_FEED_PRIME) begin
        prefetch_now = 1'b1;
        prefetch_step = '0;
    end else if ((state == ST_FEED) && all_feed_ready && (feed_step + 1 < DIM_WIDTH'(ARRAY_SIZE))) begin
        prefetch_now = 1'b1;
        prefetch_step = feed_step + 1'b1;
    end

    if (prefetch_now && (prefetch_step < active_k)) begin
        for (r = 0; r < ARRAY_SIZE; r = r + 1) begin
            row_idx = tile_row_base + r;
            col_idx = tile_col_base + r;

            if (row_idx < dim_latched) begin
                a_bank_re[row_idx] = 1'b1;
                a_bank_raddr[row_idx] = tile_k_base + prefetch_step;
            end

            if (col_idx < dim_latched) begin
                b_bank_re[col_idx] = 1'b1;
                b_bank_raddr[col_idx] = tile_k_base + prefetch_step;
            end
        end
    end
end

always_comb begin : proc_sa_inputs
    int r;
    int row_idx;
    int col_idx;
    logic feed_fire;

    all_feed_ready = 1'b0;
    feed_fire = 1'b0;

    for (r = 0; r < ARRAY_SIZE; r = r + 1) begin
        sa_istreamA_val[r] = 1'b0;
        sa_istreamB_val[r] = 1'b0;
        sa_istreamA_msg[r] = '0;
        sa_istreamB_msg[r] = '0;
    end

    if (state == ST_FEED) begin
        all_feed_ready = 1'b1;
        for (r = 0; r < ARRAY_SIZE; r = r + 1) begin
            all_feed_ready &= sa_istreamA_rdy[r] & sa_istreamB_rdy[r];
        end

        feed_fire = all_feed_ready;

        for (r = 0; r < ARRAY_SIZE; r = r + 1) begin
            row_idx = tile_row_base + r;
            col_idx = tile_col_base + r;

            // Keep streams aligned by only issuing tokens when all rows are ready.
            sa_istreamA_val[r] = feed_fire;
            sa_istreamB_val[r] = feed_fire;

            if (feed_step < DIM_WIDTH'(ARRAY_SIZE)) begin
                if ((feed_step < active_k) &&
                    (r < active_rows) &&
                    (row_idx < dim_latched) &&
                    ((tile_k_base + feed_step) < dim_latched)) begin
                    sa_istreamA_msg[r] = {1'b0, a_bank_rdata[row_idx]};
                end else begin
                    // Zero-pad data phase so edge tiles still obey fixed pipeline timing.
                    sa_istreamA_msg[r] = {1'b0, {DATA_WIDTH{1'b0}}};
                end

                if ((feed_step < active_k) &&
                    (r < active_cols) &&
                    (col_idx < dim_latched) &&
                    ((tile_k_base + feed_step) < dim_latched)) begin
                    sa_istreamB_msg[r] = {1'b0, b_bank_rdata[col_idx]};
                end else begin
                    // Zero-pad data phase so edge tiles still obey fixed pipeline timing.
                    sa_istreamB_msg[r] = {1'b0, {DATA_WIDTH{1'b0}}};
                end
            end else begin
                // Flush tokens after data phase.
                sa_istreamA_msg[r] = {1'b1, {DATA_WIDTH{1'b0}}};
                sa_istreamB_msg[r] = {1'b1, {DATA_WIDTH{1'b0}}};
            end
        end
    end
end

systolic_SysBase #(
    .SIZE(ARRAY_SIZE)
) u_sysbase (
    .clk(clk),
    .reset(~rst_n),
    .istreamA_val(sa_istreamA_val),
    .istreamA_rdy(sa_istreamA_rdy),
    .istreamA_msg(sa_istreamA_msg),
    .istreamB_val(sa_istreamB_val),
    .istreamB_rdy(sa_istreamB_rdy),
    .istreamB_msg(sa_istreamB_msg),
    .ostreamA_val(sa_ostreamA_val),
    .ostreamA_rdy(sa_ostreamA_rdy),
    .ostreamA_msg(sa_ostreamA_msg),
    .ostreamB_val(sa_ostreamB_val),
    .ostreamB_rdy(sa_ostreamB_rdy),
    .ostreamB_msg(sa_ostreamB_msg)
);

always_ff @(posedge clk) begin : proc_fsm
    int r;
    int c;
    int row_local;
    int row_global;
    int col_global;
    int captured_now;

    if (!rst_n) begin
        state <= ST_IDLE;

        dim_latched <= '0;
        load_row <= '0;
        load_col <= '0;

        tile_row_base <= '0;
        tile_col_base <= '0;
        tile_k_base <= '0;

        active_rows <= '0;
        active_cols <= '0;
        active_k <= '0;

        feed_step <= '0;
        out_row <= '0;
        out_col <= '0;

        tile_expected <= '0;
        tile_results <= '0;

        in_ready <= 1'b0;
        out_valid <= 1'b0;
        out_data <= '0;
        busy <= 1'b0;
        done <= 1'b0;

        for (r = 0; r < ARRAY_SIZE; r = r + 1) begin
            result_count[r] <= '0;
            flagged_count[r] <= '0;
            for (c = 0; c < ARRAY_SIZE; c = c + 1) begin
                tile_accum[r][c] <= '0;
            end
        end

        store_row <= '0;
        store_col <= '0;
    end else begin
        captured_now = 0;

        // Capture and accumulate tile outputs from SysBase flagged B-stream tokens.
        if ((state == ST_FEED) || (state == ST_COLLECT)) begin
            for (r = 0; r < ARRAY_SIZE; r = r + 1) begin
                if ((r < active_cols) &&
                    sa_ostreamB_val[r] &&
                    sa_ostreamB_msg[r][32] &&
                    (flagged_count[r] < ARRAY_SIZE)) begin

                    // For partial row tiles, earliest flagged tokens correspond to
                    // padding; capture only the final active_rows flagged tokens.
                    if ((flagged_count[r] >= (ARRAY_SIZE - active_rows)) &&
                        (result_count[r] < active_rows)) begin

                        row_local = active_rows - 1 - result_count[r];
                        row_global = tile_row_base + row_local;
                        col_global = tile_col_base + r;

                        if ((row_global < dim_latched) && (col_global < dim_latched)) begin
                            tile_accum[row_local][r] <= tile_accum[row_local][r] +
                                                        $signed(sa_ostreamB_msg[r][DATA_WIDTH-1:0]);
                        end

                        result_count[r] <= result_count[r] + 1'b1;
                        captured_now = captured_now + 1;
                    end

                    flagged_count[r] <= flagged_count[r] + 1'b1;
                end
            end

            if (captured_now != 0) begin
                tile_results <= tile_results + captured_now;
            end
        end

        case (state)
            ST_IDLE: begin
                in_ready <= 1'b0;
                out_valid <= 1'b0;
                out_data <= '0;
                busy <= 1'b0;
                done <= 1'b0;

                if (start) begin
                    dim_latched <= dim_safe;

                    load_row <= '0;
                    load_col <= '0;

                    tile_row_base <= '0;
                    tile_col_base <= '0;
                    tile_k_base <= '0;

                    active_rows <= '0;
                    active_cols <= '0;
                    active_k <= '0;

                    feed_step <= '0;
                    out_row <= '0;
                    out_col <= '0;

                    tile_expected <= '0;
                    tile_results <= '0;

                    store_row <= '0;
                    store_col <= '0;

                    for (r = 0; r < ARRAY_SIZE; r = r + 1) begin
                        result_count[r] <= '0;
                        flagged_count[r] <= '0;
                        for (c = 0; c < ARRAY_SIZE; c = c + 1) begin
                            tile_accum[r][c] <= '0;
                        end
                    end

                    busy <= 1'b1;
                    in_ready <= 1'b1;
                    state <= ST_LOAD_A;
                end
            end

            ST_LOAD_A: begin
                in_ready <= 1'b1;
                out_valid <= 1'b0;

                if (in_valid && in_ready) begin
                    if (load_col + 1 < dim_latched) begin
                        load_col <= load_col + 1'b1;
                    end else begin
                        load_col <= '0;
                        if (load_row + 1 < dim_latched) begin
                            load_row <= load_row + 1'b1;
                        end else begin
                            load_row <= '0;
                            load_col <= '0;
                            state <= ST_LOAD_B;
                        end
                    end
                end
            end

            ST_LOAD_B: begin
                in_ready <= 1'b1;
                out_valid <= 1'b0;

                if (in_valid && in_ready) begin
                    if (load_col + 1 < dim_latched) begin
                        load_col <= load_col + 1'b1;
                    end else begin
                        load_col <= '0;
                        if (load_row + 1 < dim_latched) begin
                            load_row <= load_row + 1'b1;
                        end else begin
                            load_row <= '0;
                            load_col <= '0;
                            in_ready <= 1'b0;
                            tile_row_base <= '0;
                            tile_col_base <= '0;
                            tile_k_base <= '0;
                            state <= ST_PREP_TILE;
                        end
                    end
                end
            end

            ST_PREP_TILE: begin
                in_ready <= 1'b0;
                out_valid <= 1'b0;

                if ((dim_latched - tile_row_base) > ARRAY_SIZE) begin
                    active_rows <= DIM_WIDTH'(ARRAY_SIZE);
                end else begin
                    active_rows <= dim_latched - tile_row_base;
                end

                if ((dim_latched - tile_col_base) > ARRAY_SIZE) begin
                    active_cols <= DIM_WIDTH'(ARRAY_SIZE);
                end else begin
                    active_cols <= dim_latched - tile_col_base;
                end

                if ((dim_latched - tile_k_base) > ARRAY_SIZE) begin
                    active_k <= DIM_WIDTH'(ARRAY_SIZE);
                end else begin
                    active_k <= dim_latched - tile_k_base;
                end

                tile_expected <= ((dim_latched - tile_row_base) > ARRAY_SIZE ? DIM_WIDTH'(ARRAY_SIZE) : (dim_latched - tile_row_base)) *
                                 ((dim_latched - tile_col_base) > ARRAY_SIZE ? DIM_WIDTH'(ARRAY_SIZE) : (dim_latched - tile_col_base));
                tile_results <= '0;
                feed_step <= '0;
                store_row <= '0;
                store_col <= '0;

                for (r = 0; r < ARRAY_SIZE; r = r + 1) begin
                    result_count[r] <= '0;
                    flagged_count[r] <= '0;
                    if (tile_k_base == '0) begin
                        for (c = 0; c < ARRAY_SIZE; c = c + 1) begin
                            tile_accum[r][c] <= '0;
                        end
                    end
                end

                // Read first systolic feed column from banked RAMs.
                state <= ST_FEED_PRIME;
            end

            ST_FEED_PRIME: begin
                in_ready <= 1'b0;
                out_valid <= 1'b0;
                state <= ST_FEED;
            end

            ST_FEED: begin
                in_ready <= 1'b0;
                out_valid <= 1'b0;

                if (all_feed_ready) begin
                    if (feed_step + 1 < DIM_WIDTH'(FEED_CYCLES)) begin
                        feed_step <= feed_step + 1'b1;
                    end else begin
                        state <= ST_COLLECT;
                    end
                end
            end

            ST_COLLECT: begin
                in_ready <= 1'b0;
                out_valid <= 1'b0;

                if ((tile_results + captured_now) >= tile_expected) begin
                    state <= ST_ADV_TILE;
                end
            end

            ST_ADV_TILE: begin
                in_ready <= 1'b0;
                out_valid <= 1'b0;

                if ((tile_k_base + active_k) < dim_latched) begin
                    tile_k_base <= tile_k_base + active_k;
                    state <= ST_PREP_TILE;
                end else begin
                    store_row <= '0;
                    store_col <= '0;
                    state <= ST_STORE_TILE;
                end
            end

            ST_STORE_TILE: begin
                in_ready <= 1'b0;
                out_valid <= 1'b0;

                c_mem[tile_row_base + store_row][tile_col_base + store_col] <= tile_accum[store_row][store_col];

                if (store_col + 1 < active_cols) begin
                    store_col <= store_col + 1'b1;
                end else begin
                    store_col <= '0;
                    if (store_row + 1 < active_rows) begin
                        store_row <= store_row + 1'b1;
                    end else begin
                        store_row <= '0;
                        tile_k_base <= '0;

                        if ((tile_col_base + active_cols) < dim_latched) begin
                            tile_col_base <= tile_col_base + active_cols;
                            state <= ST_PREP_TILE;
                        end else begin
                            tile_col_base <= '0;

                            if ((tile_row_base + active_rows) < dim_latched) begin
                                tile_row_base <= tile_row_base + active_rows;
                                state <= ST_PREP_TILE;
                            end else begin
                                out_row <= '0;
                                out_col <= '0;
                                out_valid <= 1'b0;
                                state <= ST_STREAM_C;
                            end
                        end
                    end
                end
            end

            ST_STREAM_C: begin
                in_ready <= 1'b0;

                if (!out_valid) begin
                    out_data <= c_mem[out_row][out_col];
                    out_valid <= 1'b1;
                end else if (out_ready) begin
                    if (out_col + 1 < dim_latched) begin
                        out_col <= out_col + 1'b1;
                        out_data <= c_mem[out_row][out_col + 1];
                    end else begin
                        out_col <= '0;
                        if (out_row + 1 < dim_latched) begin
                            out_row <= out_row + 1'b1;
                            out_data <= c_mem[out_row + 1][0];
                        end else begin
                            out_valid <= 1'b0;
                            busy <= 1'b0;
                            done <= 1'b1;
                            state <= ST_DONE;
                        end
                    end
                end
            end

            ST_DONE: begin
                in_ready <= 1'b0;
                out_valid <= 1'b0;
                busy <= 1'b0;

                if (!start) begin
                    done <= 1'b0;
                    state <= ST_IDLE;
                end
            end

            default: begin
                state <= ST_IDLE;
            end
        endcase
    end
end

endmodule
