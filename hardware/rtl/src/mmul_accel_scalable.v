`timescale 1ns/1ps

module mmul_accel_scalable #(
    parameter DATA_WIDTH = 32,
    parameter ACC_WIDTH = 64,
    parameter MAX_DIM = 10,
    parameter DIM_WIDTH = 8
) (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     start,
    input  wire [DIM_WIDTH-1:0]     cfg_dim,
    input  wire                     in_valid,
    output reg                      in_ready,
    input  wire [DATA_WIDTH-1:0]    in_data,
    output reg                      out_valid,
    input  wire                     out_ready,
    output reg  [DATA_WIDTH-1:0]    out_data,
    output reg                      busy,
    output reg                      done
);

localparam integer MAX_ELEMS = MAX_DIM * MAX_DIM;

localparam [2:0] ST_IDLE    = 3'd0;
localparam [2:0] ST_LOAD_A  = 3'd1;
localparam [2:0] ST_LOAD_B  = 3'd2;
localparam [2:0] ST_COMPUTE = 3'd3;
localparam [2:0] ST_STORE   = 3'd4;
localparam [2:0] ST_DONE    = 3'd5;

reg [2:0] state;

reg [DIM_WIDTH-1:0] dim_latched;

reg [DIM_WIDTH-1:0] load_row;
reg [DIM_WIDTH-1:0] load_col;

reg [DIM_WIDTH-1:0] row_idx;
reg [DIM_WIDTH-1:0] col_idx;
reg [DIM_WIDTH-1:0] k_idx;

reg [DIM_WIDTH-1:0] out_row;
reg [DIM_WIDTH-1:0] out_col;

reg signed [ACC_WIDTH-1:0] accum;

reg signed [DATA_WIDTH-1:0] a_mem [0:MAX_ELEMS-1];
reg signed [DATA_WIDTH-1:0] b_mem [0:MAX_ELEMS-1];
reg signed [DATA_WIDTH-1:0] c_mem [0:MAX_ELEMS-1];

wire [31:0] load_addr = (load_row * MAX_DIM) + load_col;
wire [31:0] a_addr = (row_idx * MAX_DIM) + k_idx;
wire [31:0] b_addr = (k_idx * MAX_DIM) + col_idx;
wire [31:0] c_addr = (row_idx * MAX_DIM) + col_idx;
wire [31:0] out_addr = (out_row * MAX_DIM) + out_col;

wire signed [ACC_WIDTH-1:0] mult_term = $signed(a_mem[a_addr]) * $signed(b_mem[b_addr]);
wire signed [ACC_WIDTH-1:0] accum_next = (k_idx == 0) ? mult_term : (accum + mult_term);

wire [DIM_WIDTH-1:0] dim_safe = (cfg_dim == 0) ? {{(DIM_WIDTH-1){1'b0}},1'b1} :
                                (cfg_dim > MAX_DIM) ? MAX_DIM[DIM_WIDTH-1:0] :
                                cfg_dim;

always @(posedge clk) begin
    if (!rst_n) begin
        state <= ST_IDLE;
        in_ready <= 1'b0;
        out_valid <= 1'b0;
        out_data <= {DATA_WIDTH{1'b0}};
        busy <= 1'b0;
        done <= 1'b0;

        dim_latched <= {DIM_WIDTH{1'b0}};
        load_row <= {DIM_WIDTH{1'b0}};
        load_col <= {DIM_WIDTH{1'b0}};
        row_idx <= {DIM_WIDTH{1'b0}};
        col_idx <= {DIM_WIDTH{1'b0}};
        k_idx <= {DIM_WIDTH{1'b0}};
        out_row <= {DIM_WIDTH{1'b0}};
        out_col <= {DIM_WIDTH{1'b0}};
        accum <= {ACC_WIDTH{1'b0}};
    end else begin
        case (state)
            ST_IDLE: begin
                in_ready <= 1'b0;
                out_valid <= 1'b0;
                busy <= 1'b0;
                done <= 1'b0;
                accum <= {ACC_WIDTH{1'b0}};

                if (start) begin
                    dim_latched <= dim_safe;
                    load_row <= {DIM_WIDTH{1'b0}};
                    load_col <= {DIM_WIDTH{1'b0}};
                    row_idx <= {DIM_WIDTH{1'b0}};
                    col_idx <= {DIM_WIDTH{1'b0}};
                    k_idx <= {DIM_WIDTH{1'b0}};
                    out_row <= {DIM_WIDTH{1'b0}};
                    out_col <= {DIM_WIDTH{1'b0}};
                    busy <= 1'b1;
                    in_ready <= 1'b1;
                    state <= ST_LOAD_A;
                end
            end

            ST_LOAD_A: begin
                in_ready <= 1'b1;
                if (in_valid && in_ready) begin
                    a_mem[load_addr] <= in_data;
                    if (load_col + 1 < dim_latched) begin
                        load_col <= load_col + 1;
                    end else begin
                        load_col <= {DIM_WIDTH{1'b0}};
                        if (load_row + 1 < dim_latched) begin
                            load_row <= load_row + 1;
                        end else begin
                            load_row <= {DIM_WIDTH{1'b0}};
                            load_col <= {DIM_WIDTH{1'b0}};
                            state <= ST_LOAD_B;
                        end
                    end
                end
            end

            ST_LOAD_B: begin
                in_ready <= 1'b1;
                if (in_valid && in_ready) begin
                    b_mem[load_addr] <= in_data;
                    if (load_col + 1 < dim_latched) begin
                        load_col <= load_col + 1;
                    end else begin
                        load_col <= {DIM_WIDTH{1'b0}};
                        if (load_row + 1 < dim_latched) begin
                            load_row <= load_row + 1;
                        end else begin
                            load_row <= {DIM_WIDTH{1'b0}};
                            load_col <= {DIM_WIDTH{1'b0}};
                            in_ready <= 1'b0;
                            row_idx <= {DIM_WIDTH{1'b0}};
                            col_idx <= {DIM_WIDTH{1'b0}};
                            k_idx <= {DIM_WIDTH{1'b0}};
                            accum <= {ACC_WIDTH{1'b0}};
                            state <= ST_COMPUTE;
                        end
                    end
                end
            end

            ST_COMPUTE: begin
                in_ready <= 1'b0;
                if (k_idx + 1 < dim_latched) begin
                    accum <= accum_next;
                    k_idx <= k_idx + 1;
                end else begin
                    c_mem[c_addr] <= accum_next[DATA_WIDTH-1:0];
                    accum <= {ACC_WIDTH{1'b0}};
                    k_idx <= {DIM_WIDTH{1'b0}};

                    if (col_idx + 1 < dim_latched) begin
                        col_idx <= col_idx + 1;
                    end else begin
                        col_idx <= {DIM_WIDTH{1'b0}};
                        if (row_idx + 1 < dim_latched) begin
                            row_idx <= row_idx + 1;
                        end else begin
                            row_idx <= {DIM_WIDTH{1'b0}};
                            out_row <= {DIM_WIDTH{1'b0}};
                            out_col <= {DIM_WIDTH{1'b0}};
                            out_valid <= 1'b1;
                            out_data <= c_mem[0];
                            state <= ST_STORE;
                        end
                    end
                end
            end

            ST_STORE: begin
                out_valid <= 1'b1;
                out_data <= c_mem[out_addr];
                if (out_ready) begin
                    if (out_col + 1 < dim_latched) begin
                        out_col <= out_col + 1;
                    end else begin
                        out_col <= {DIM_WIDTH{1'b0}};
                        if (out_row + 1 < dim_latched) begin
                            out_row <= out_row + 1;
                        end else begin
                            out_valid <= 1'b0;
                            done <= 1'b1;
                            busy <= 1'b0;
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
