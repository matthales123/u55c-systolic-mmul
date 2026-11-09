`timescale 1ns/1ns

module mmul_sysbase #(
    parameter integer C_S_AXI_CONTROL_ADDR_WIDTH = 6,
    parameter integer C_S_AXI_CONTROL_DATA_WIDTH = 32,
    parameter integer C_M_AXI_ADDR_WIDTH         = 64,
    parameter integer C_M_AXI_DATA_WIDTH         = 32,
    parameter integer C_M_AXI_ID_WIDTH           = 1,
    parameter integer C_M_AXI_USER_WIDTH         = 1,
    parameter integer MAX_DIM                    = 8,
    parameter integer ARRAY_SIZE                 = 4
)(
    input  logic ap_clk,
    input  logic ap_rst_n,

    output logic                                m_axi_gmem0_AWVALID,
    input  logic                                m_axi_gmem0_AWREADY,
    output logic [C_M_AXI_ADDR_WIDTH-1:0]       m_axi_gmem0_AWADDR,
    output logic [C_M_AXI_ID_WIDTH-1:0]         m_axi_gmem0_AWID,
    output logic [7:0]                          m_axi_gmem0_AWLEN,
    output logic [2:0]                          m_axi_gmem0_AWSIZE,
    output logic [1:0]                          m_axi_gmem0_AWBURST,
    output logic [1:0]                          m_axi_gmem0_AWLOCK,
    output logic [3:0]                          m_axi_gmem0_AWCACHE,
    output logic [2:0]                          m_axi_gmem0_AWPROT,
    output logic [3:0]                          m_axi_gmem0_AWQOS,
    output logic [3:0]                          m_axi_gmem0_AWREGION,
    output logic [C_M_AXI_USER_WIDTH-1:0]       m_axi_gmem0_AWUSER,
    output logic                                m_axi_gmem0_WVALID,
    input  logic                                m_axi_gmem0_WREADY,
    output logic [C_M_AXI_DATA_WIDTH-1:0]       m_axi_gmem0_WDATA,
    output logic [(C_M_AXI_DATA_WIDTH/8)-1:0]   m_axi_gmem0_WSTRB,
    output logic                                m_axi_gmem0_WLAST,
    output logic [C_M_AXI_ID_WIDTH-1:0]         m_axi_gmem0_WID,
    output logic [C_M_AXI_USER_WIDTH-1:0]       m_axi_gmem0_WUSER,
    output logic                                m_axi_gmem0_ARVALID,
    input  logic                                m_axi_gmem0_ARREADY,
    output logic [C_M_AXI_ADDR_WIDTH-1:0]       m_axi_gmem0_ARADDR,
    output logic [C_M_AXI_ID_WIDTH-1:0]         m_axi_gmem0_ARID,
    output logic [7:0]                          m_axi_gmem0_ARLEN,
    output logic [2:0]                          m_axi_gmem0_ARSIZE,
    output logic [1:0]                          m_axi_gmem0_ARBURST,
    output logic [1:0]                          m_axi_gmem0_ARLOCK,
    output logic [3:0]                          m_axi_gmem0_ARCACHE,
    output logic [2:0]                          m_axi_gmem0_ARPROT,
    output logic [3:0]                          m_axi_gmem0_ARQOS,
    output logic [3:0]                          m_axi_gmem0_ARREGION,
    output logic [C_M_AXI_USER_WIDTH-1:0]       m_axi_gmem0_ARUSER,
    input  logic                                m_axi_gmem0_RVALID,
    output logic                                m_axi_gmem0_RREADY,
    input  logic [C_M_AXI_DATA_WIDTH-1:0]       m_axi_gmem0_RDATA,
    input  logic                                m_axi_gmem0_RLAST,
    input  logic [C_M_AXI_ID_WIDTH-1:0]         m_axi_gmem0_RID,
    input  logic [C_M_AXI_USER_WIDTH-1:0]       m_axi_gmem0_RUSER,
    input  logic [1:0]                          m_axi_gmem0_RRESP,
    input  logic                                m_axi_gmem0_BVALID,
    output logic                                m_axi_gmem0_BREADY,
    input  logic [1:0]                          m_axi_gmem0_BRESP,
    input  logic [C_M_AXI_ID_WIDTH-1:0]         m_axi_gmem0_BID,
    input  logic [C_M_AXI_USER_WIDTH-1:0]       m_axi_gmem0_BUSER,

    output logic                                m_axi_gmem1_AWVALID,
    input  logic                                m_axi_gmem1_AWREADY,
    output logic [C_M_AXI_ADDR_WIDTH-1:0]       m_axi_gmem1_AWADDR,
    output logic [C_M_AXI_ID_WIDTH-1:0]         m_axi_gmem1_AWID,
    output logic [7:0]                          m_axi_gmem1_AWLEN,
    output logic [2:0]                          m_axi_gmem1_AWSIZE,
    output logic [1:0]                          m_axi_gmem1_AWBURST,
    output logic [1:0]                          m_axi_gmem1_AWLOCK,
    output logic [3:0]                          m_axi_gmem1_AWCACHE,
    output logic [2:0]                          m_axi_gmem1_AWPROT,
    output logic [3:0]                          m_axi_gmem1_AWQOS,
    output logic [3:0]                          m_axi_gmem1_AWREGION,
    output logic [C_M_AXI_USER_WIDTH-1:0]       m_axi_gmem1_AWUSER,
    output logic                                m_axi_gmem1_WVALID,
    input  logic                                m_axi_gmem1_WREADY,
    output logic [C_M_AXI_DATA_WIDTH-1:0]       m_axi_gmem1_WDATA,
    output logic [(C_M_AXI_DATA_WIDTH/8)-1:0]   m_axi_gmem1_WSTRB,
    output logic                                m_axi_gmem1_WLAST,
    output logic [C_M_AXI_ID_WIDTH-1:0]         m_axi_gmem1_WID,
    output logic [C_M_AXI_USER_WIDTH-1:0]       m_axi_gmem1_WUSER,
    output logic                                m_axi_gmem1_ARVALID,
    input  logic                                m_axi_gmem1_ARREADY,
    output logic [C_M_AXI_ADDR_WIDTH-1:0]       m_axi_gmem1_ARADDR,
    output logic [C_M_AXI_ID_WIDTH-1:0]         m_axi_gmem1_ARID,
    output logic [7:0]                          m_axi_gmem1_ARLEN,
    output logic [2:0]                          m_axi_gmem1_ARSIZE,
    output logic [1:0]                          m_axi_gmem1_ARBURST,
    output logic [1:0]                          m_axi_gmem1_ARLOCK,
    output logic [3:0]                          m_axi_gmem1_ARCACHE,
    output logic [2:0]                          m_axi_gmem1_ARPROT,
    output logic [3:0]                          m_axi_gmem1_ARQOS,
    output logic [3:0]                          m_axi_gmem1_ARREGION,
    output logic [C_M_AXI_USER_WIDTH-1:0]       m_axi_gmem1_ARUSER,
    input  logic                                m_axi_gmem1_RVALID,
    output logic                                m_axi_gmem1_RREADY,
    input  logic [C_M_AXI_DATA_WIDTH-1:0]       m_axi_gmem1_RDATA,
    input  logic                                m_axi_gmem1_RLAST,
    input  logic [C_M_AXI_ID_WIDTH-1:0]         m_axi_gmem1_RID,
    input  logic [C_M_AXI_USER_WIDTH-1:0]       m_axi_gmem1_RUSER,
    input  logic [1:0]                          m_axi_gmem1_RRESP,
    input  logic                                m_axi_gmem1_BVALID,
    output logic                                m_axi_gmem1_BREADY,
    input  logic [1:0]                          m_axi_gmem1_BRESP,
    input  logic [C_M_AXI_ID_WIDTH-1:0]         m_axi_gmem1_BID,
    input  logic [C_M_AXI_USER_WIDTH-1:0]       m_axi_gmem1_BUSER,

    output logic                                m_axi_gmem2_AWVALID,
    input  logic                                m_axi_gmem2_AWREADY,
    output logic [C_M_AXI_ADDR_WIDTH-1:0]       m_axi_gmem2_AWADDR,
    output logic [C_M_AXI_ID_WIDTH-1:0]         m_axi_gmem2_AWID,
    output logic [7:0]                          m_axi_gmem2_AWLEN,
    output logic [2:0]                          m_axi_gmem2_AWSIZE,
    output logic [1:0]                          m_axi_gmem2_AWBURST,
    output logic [1:0]                          m_axi_gmem2_AWLOCK,
    output logic [3:0]                          m_axi_gmem2_AWCACHE,
    output logic [2:0]                          m_axi_gmem2_AWPROT,
    output logic [3:0]                          m_axi_gmem2_AWQOS,
    output logic [3:0]                          m_axi_gmem2_AWREGION,
    output logic [C_M_AXI_USER_WIDTH-1:0]       m_axi_gmem2_AWUSER,
    output logic                                m_axi_gmem2_WVALID,
    input  logic                                m_axi_gmem2_WREADY,
    output logic [C_M_AXI_DATA_WIDTH-1:0]       m_axi_gmem2_WDATA,
    output logic [(C_M_AXI_DATA_WIDTH/8)-1:0]   m_axi_gmem2_WSTRB,
    output logic                                m_axi_gmem2_WLAST,
    output logic [C_M_AXI_ID_WIDTH-1:0]         m_axi_gmem2_WID,
    output logic [C_M_AXI_USER_WIDTH-1:0]       m_axi_gmem2_WUSER,
    output logic                                m_axi_gmem2_ARVALID,
    input  logic                                m_axi_gmem2_ARREADY,
    output logic [C_M_AXI_ADDR_WIDTH-1:0]       m_axi_gmem2_ARADDR,
    output logic [C_M_AXI_ID_WIDTH-1:0]         m_axi_gmem2_ARID,
    output logic [7:0]                          m_axi_gmem2_ARLEN,
    output logic [2:0]                          m_axi_gmem2_ARSIZE,
    output logic [1:0]                          m_axi_gmem2_ARBURST,
    output logic [1:0]                          m_axi_gmem2_ARLOCK,
    output logic [3:0]                          m_axi_gmem2_ARCACHE,
    output logic [2:0]                          m_axi_gmem2_ARPROT,
    output logic [3:0]                          m_axi_gmem2_ARQOS,
    output logic [3:0]                          m_axi_gmem2_ARREGION,
    output logic [C_M_AXI_USER_WIDTH-1:0]       m_axi_gmem2_ARUSER,
    input  logic                                m_axi_gmem2_RVALID,
    output logic                                m_axi_gmem2_RREADY,
    input  logic [C_M_AXI_DATA_WIDTH-1:0]       m_axi_gmem2_RDATA,
    input  logic                                m_axi_gmem2_RLAST,
    input  logic [C_M_AXI_ID_WIDTH-1:0]         m_axi_gmem2_RID,
    input  logic [C_M_AXI_USER_WIDTH-1:0]       m_axi_gmem2_RUSER,
    input  logic [1:0]                          m_axi_gmem2_RRESP,
    input  logic                                m_axi_gmem2_BVALID,
    output logic                                m_axi_gmem2_BREADY,
    input  logic [1:0]                          m_axi_gmem2_BRESP,
    input  logic [C_M_AXI_ID_WIDTH-1:0]         m_axi_gmem2_BID,
    input  logic [C_M_AXI_USER_WIDTH-1:0]       m_axi_gmem2_BUSER,

    input  logic                                s_axi_control_AWVALID,
    output logic                                s_axi_control_AWREADY,
    input  logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0] s_axi_control_AWADDR,
    input  logic                                s_axi_control_WVALID,
    output logic                                s_axi_control_WREADY,
    input  logic [C_S_AXI_CONTROL_DATA_WIDTH-1:0] s_axi_control_WDATA,
    input  logic [(C_S_AXI_CONTROL_DATA_WIDTH/8)-1:0] s_axi_control_WSTRB,
    input  logic                                s_axi_control_ARVALID,
    output logic                                s_axi_control_ARREADY,
    input  logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0] s_axi_control_ARADDR,
    output logic                                s_axi_control_RVALID,
    input  logic                                s_axi_control_RREADY,
    output logic [C_S_AXI_CONTROL_DATA_WIDTH-1:0] s_axi_control_RDATA,
    output logic [1:0]                          s_axi_control_RRESP,
    output logic                                s_axi_control_BVALID,
    input  logic                                s_axi_control_BREADY,
    output logic [1:0]                          s_axi_control_BRESP,
    output logic                                interrupt
);

    // Single-beat AXI transactions deliberately favor a small, auditable pilot.
    // AXI-Lite and port declarations adapted from the repository's boids RTL kernel.
    localparam integer STRB_W = C_S_AXI_CONTROL_DATA_WIDTH / 8;
    localparam logic [5:0] ADDR_AP_CTRL=6'h00, ADDR_GIE=6'h04,
        ADDR_IER=6'h08, ADDR_ISR=6'h0c, ADDR_A_0=6'h10, ADDR_A_1=6'h14,
        ADDR_B_0=6'h1c, ADDR_B_1=6'h20, ADDR_C_0=6'h28, ADDR_C_1=6'h2c,
        ADDR_DIM=6'h34, ADDR_ERROR=6'h38;
    typedef enum logic [3:0] {KS_IDLE, KS_START, KS_A_AR, KS_A_R, KS_A_FEED,
        KS_B_AR, KS_B_R, KS_B_FEED, KS_C_CAPTURE, KS_C_WRITE, KS_C_B, KS_DONE} state_t;
    state_t kernel_state;
    logic rst;
    logic [63:0] reg_a, reg_b, reg_c, base_a, base_b, base_c;
    logic [31:0] reg_dim, error_reg;
    logic [7:0] active_dim;
    logic [15:0] count, idx;
    logic gie_reg;
    logic [0:0] ier_reg, isr_reg;
    logic ap_start_reg, auto_restart_reg, ap_done_reg, ap_idle_reg, ap_ready_reg;
    logic aw_captured, w_captured;
    logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0] wr_addr, rd_addr;
    logic [31:0] wr_data;
    logic [STRB_W-1:0] wr_strb;
    logic m0_arvalid, m0_rready, m1_arvalid, m1_rready;
    logic [C_M_AXI_ADDR_WIDTH-1:0] m0_araddr, m1_araddr, m2_awaddr;
    logic m2_awvalid, m2_wvalid, m2_bready;
    logic [31:0] m2_wdata;
    logic core_reset, core_start, core_done, core_in_valid, core_in_ready;
    logic [31:0] core_in_data, core_out_data;
    logic core_out_valid, core_out_ready;

    function automatic logic [31:0] apply_wstrb(input logic [31:0] prior,
        input logic [31:0] incoming, input logic [STRB_W-1:0] strobe);
        apply_wstrb = prior;
        for (int i=0; i<4; i=i+1)
            if (strobe[i]) apply_wstrb[8*i +: 8] = incoming[8*i +: 8];
    endfunction
    function automatic logic [31:0] read_reg(input logic [5:0] addr);
        case (addr)
            ADDR_AP_CTRL: read_reg = {24'd0,auto_restart_reg,3'd0,ap_ready_reg,ap_idle_reg,ap_done_reg,ap_start_reg};
            ADDR_GIE: read_reg = {31'd0,gie_reg};
            ADDR_IER: read_reg = {31'd0,ier_reg};
            ADDR_ISR: read_reg = {31'd0,isr_reg};
            ADDR_A_0: read_reg = reg_a[31:0];
            ADDR_A_1: read_reg = reg_a[63:32];
            ADDR_B_0: read_reg = reg_b[31:0];
            ADDR_B_1: read_reg = reg_b[63:32];
            ADDR_C_0: read_reg = reg_c[31:0];
            ADDR_C_1: read_reg = reg_c[63:32];
            ADDR_DIM: read_reg = reg_dim;
            ADDR_ERROR: read_reg = error_reg;
            default: read_reg = 0;
        endcase
    endfunction
    assign rst = ~ap_rst_n;
    assign s_axi_control_BRESP = 2'b00;
    assign s_axi_control_RRESP = 2'b00;
    // Register the source before the platform interrupt CDC. XRT may change GIE
    // while a command is active; completion and software gating must not form
    // combinational logic at the asynchronous boundary. One clock of latency.
    always_ff @(posedge ap_clk) begin
        if (rst) interrupt <= 1'b0;
        else interrupt <= gie_reg & isr_reg[0];
    end
    assign s_axi_control_AWREADY = ~aw_captured & ~s_axi_control_BVALID;
    assign s_axi_control_WREADY = ~w_captured & ~s_axi_control_BVALID;
    assign s_axi_control_ARREADY = ~s_axi_control_RVALID;
    assign core_out_ready = kernel_state == KS_C_CAPTURE;

    mmul_sysbase_axis_shell #(.DATA_WIDTH(32), .DIM_WIDTH(8),
        .ARRAY_SIZE(ARRAY_SIZE), .MAX_DIM(MAX_DIM)) u_sysbase (
        .ap_clk(ap_clk), .ap_rst_n(~core_reset), .ap_start(core_start), .cfg_dim(active_dim),
        .ap_done(core_done), .ap_idle(), .ap_ready(), .ap_busy(),
        .s_axis_in_tvalid(core_in_valid), .s_axis_in_tready(core_in_ready), .s_axis_in_tdata(core_in_data),
        .m_axis_out_tvalid(core_out_valid), .m_axis_out_tready(core_out_ready), .m_axis_out_tdata(core_out_data));

    assign m_axi_gmem0_AWVALID = 1'b0;
    assign m_axi_gmem0_AWADDR  = '0;
    assign m_axi_gmem0_AWID    = '0;
    assign m_axi_gmem0_AWLEN   = 8'd0;
    assign m_axi_gmem0_AWSIZE  = 3'd2;
    assign m_axi_gmem0_AWBURST = 2'b01;
    assign m_axi_gmem0_AWLOCK  = 2'b00;
    assign m_axi_gmem0_AWCACHE = 4'b0011;
    assign m_axi_gmem0_AWPROT  = 3'b000;
    assign m_axi_gmem0_AWQOS   = 4'b0000;
    assign m_axi_gmem0_AWREGION = 4'b0000;
    assign m_axi_gmem0_AWUSER   = '0;
    assign m_axi_gmem0_WVALID = 1'b0;
    assign m_axi_gmem0_WDATA  = '0;
    assign m_axi_gmem0_WSTRB  = {(C_M_AXI_DATA_WIDTH/8){1'b1}};
    assign m_axi_gmem0_WLAST  = 1'b1;
    assign m_axi_gmem0_WID    = '0;
    assign m_axi_gmem0_WUSER  = '0;
    assign m_axi_gmem0_ARVALID = m0_arvalid;
    assign m_axi_gmem0_ARADDR  = m0_araddr;
    assign m_axi_gmem0_ARID    = '0;
    assign m_axi_gmem0_ARLEN   = 8'd0;
    assign m_axi_gmem0_ARSIZE  = 3'd2;
    assign m_axi_gmem0_ARBURST = 2'b01;
    assign m_axi_gmem0_ARLOCK  = 2'b00;
    assign m_axi_gmem0_ARCACHE = 4'b0011;
    assign m_axi_gmem0_ARPROT  = 3'b000;
    assign m_axi_gmem0_ARQOS   = 4'b0000;
    assign m_axi_gmem0_ARREGION = 4'b0000;
    assign m_axi_gmem0_ARUSER   = '0;
    assign m_axi_gmem0_RREADY = m0_rready;
    assign m_axi_gmem0_BREADY = 1'b0;

    assign m_axi_gmem1_AWVALID = 1'b0;
    assign m_axi_gmem1_AWADDR  = '0;
    assign m_axi_gmem1_AWID    = '0;
    assign m_axi_gmem1_AWLEN   = 8'd0;
    assign m_axi_gmem1_AWSIZE  = 3'd2;
    assign m_axi_gmem1_AWBURST = 2'b01;
    assign m_axi_gmem1_AWLOCK  = 2'b00;
    assign m_axi_gmem1_AWCACHE = 4'b0011;
    assign m_axi_gmem1_AWPROT  = 3'b000;
    assign m_axi_gmem1_AWQOS   = 4'b0000;
    assign m_axi_gmem1_AWREGION = 4'b0000;
    assign m_axi_gmem1_AWUSER   = '0;
    assign m_axi_gmem1_WVALID = 1'b0;
    assign m_axi_gmem1_WDATA  = '0;
    assign m_axi_gmem1_WSTRB  = {(C_M_AXI_DATA_WIDTH/8){1'b1}};
    assign m_axi_gmem1_WLAST  = 1'b1;
    assign m_axi_gmem1_WID    = '0;
    assign m_axi_gmem1_WUSER  = '0;
    assign m_axi_gmem1_ARVALID = m1_arvalid;
    assign m_axi_gmem1_ARADDR  = m1_araddr;
    assign m_axi_gmem1_ARID    = '0;
    assign m_axi_gmem1_ARLEN   = 8'd0;
    assign m_axi_gmem1_ARSIZE  = 3'd2;
    assign m_axi_gmem1_ARBURST = 2'b01;
    assign m_axi_gmem1_ARLOCK  = 2'b00;
    assign m_axi_gmem1_ARCACHE = 4'b0011;
    assign m_axi_gmem1_ARPROT  = 3'b000;
    assign m_axi_gmem1_ARQOS   = 4'b0000;
    assign m_axi_gmem1_ARREGION = 4'b0000;
    assign m_axi_gmem1_ARUSER   = '0;
    assign m_axi_gmem1_RREADY = m1_rready;
    assign m_axi_gmem1_BREADY = 1'b0;

    assign m_axi_gmem2_AWVALID = m2_awvalid;
    assign m_axi_gmem2_AWADDR  = m2_awaddr;
    assign m_axi_gmem2_AWID    = '0;
    assign m_axi_gmem2_AWLEN   = 8'd0;
    assign m_axi_gmem2_AWSIZE  = 3'd2;
    assign m_axi_gmem2_AWBURST = 2'b01;
    assign m_axi_gmem2_AWLOCK  = 2'b00;
    assign m_axi_gmem2_AWCACHE = 4'b0011;
    assign m_axi_gmem2_AWPROT  = 3'b000;
    assign m_axi_gmem2_AWQOS   = 4'b0000;
    assign m_axi_gmem2_AWREGION = 4'b0000;
    assign m_axi_gmem2_AWUSER   = '0;
    assign m_axi_gmem2_WVALID = m2_wvalid;
    assign m_axi_gmem2_WDATA  = m2_wdata;
    assign m_axi_gmem2_WSTRB  = {(C_M_AXI_DATA_WIDTH/8){1'b1}};
    assign m_axi_gmem2_WLAST  = 1'b1;
    assign m_axi_gmem2_WID    = '0;
    assign m_axi_gmem2_WUSER  = '0;
    assign m_axi_gmem2_ARVALID = 1'b0;
    assign m_axi_gmem2_ARADDR  = '0;
    assign m_axi_gmem2_ARID    = '0;
    assign m_axi_gmem2_ARLEN   = 8'd0;
    assign m_axi_gmem2_ARSIZE  = 3'd2;
    assign m_axi_gmem2_ARBURST = 2'b01;
    assign m_axi_gmem2_ARLOCK  = 2'b00;
    assign m_axi_gmem2_ARCACHE = 4'b0011;
    assign m_axi_gmem2_ARPROT  = 3'b000;
    assign m_axi_gmem2_ARQOS   = 4'b0000;
    assign m_axi_gmem2_ARREGION = 4'b0000;
    assign m_axi_gmem2_ARUSER   = '0;
    assign m_axi_gmem2_RREADY = 1'b0;
    assign m_axi_gmem2_BREADY = m2_bready;


    always_ff @(posedge ap_clk) begin
        if (rst) begin
            reg_a<=0; reg_b<=0; reg_c<=0; reg_dim<=0;
            base_a<=0; base_b<=0; base_c<=0; active_dim<=0; count<=0; idx<=0;
            error_reg<=0; gie_reg<=0; ier_reg<=0; isr_reg<=0;
            ap_start_reg<=0; auto_restart_reg<=0; ap_done_reg<=0; ap_idle_reg<=1; ap_ready_reg<=1;
            aw_captured<=0; w_captured<=0; wr_addr<=0; rd_addr<=0; wr_data<=0; wr_strb<=0;
            s_axi_control_BVALID<=0; s_axi_control_RVALID<=0; s_axi_control_RDATA<=0;
            kernel_state<=KS_IDLE; core_reset<=1; core_start<=0; core_in_valid<=0; core_in_data<=0;
            m0_arvalid<=0; m0_araddr<=0; m0_rready<=0;
            m1_arvalid<=0; m1_araddr<=0; m1_rready<=0;
            m2_awvalid<=0; m2_awaddr<=0; m2_wvalid<=0; m2_wdata<=0; m2_bready<=0;
        end else begin
            core_start <= 0;
            if (!aw_captured && s_axi_control_AWVALID && s_axi_control_AWREADY) begin
                aw_captured <= 1'b1;
                wr_addr <= s_axi_control_AWADDR;
            end

            if (!w_captured && s_axi_control_WVALID && s_axi_control_WREADY) begin
                w_captured <= 1'b1;
                wr_data <= s_axi_control_WDATA;
                wr_strb <= s_axi_control_WSTRB;
            end

            if (aw_captured && w_captured && !s_axi_control_BVALID) begin
                case (wr_addr)
                    ADDR_AP_CTRL: begin
                        if (wr_strb[0]) begin
                            if (wr_data[0]) begin
                                ap_start_reg <= 1'b1;
                            end
                            auto_restart_reg <= wr_data[7];
                        end
                    end
                    ADDR_GIE: begin
                        if (wr_strb[0]) begin
                            gie_reg <= wr_data[0];
                        end
                    end
                    ADDR_IER: begin
                        if (wr_strb[0]) begin
                            ier_reg[0] <= wr_data[0];
                        end
                    end
                    ADDR_ISR: begin
                        if (wr_strb[0] && wr_data[0]) begin
                            isr_reg[0] <= 1'b0;
                        end
                    end
                    ADDR_A_0: begin
                        reg_a[31:0] <= apply_wstrb(reg_a[31:0], wr_data, wr_strb);
                    end
                    ADDR_A_1: begin
                        reg_a[63:32] <= apply_wstrb(reg_a[63:32], wr_data, wr_strb);
                    end
                    ADDR_B_0: begin
                        reg_b[31:0] <= apply_wstrb(reg_b[31:0], wr_data, wr_strb);
                    end
                    ADDR_B_1: begin
                        reg_b[63:32] <= apply_wstrb(reg_b[63:32], wr_data, wr_strb);
                    end
                    ADDR_C_0: begin
                        reg_c[31:0] <= apply_wstrb(reg_c[31:0], wr_data, wr_strb);
                    end
                    ADDR_C_1: begin
                        reg_c[63:32] <= apply_wstrb(reg_c[63:32], wr_data, wr_strb);
                    end
                    ADDR_DIM: begin
                        reg_dim <= apply_wstrb(reg_dim, wr_data, wr_strb);
                    end
                    default: begin
                    end
                endcase

                aw_captured <= 1'b0;
                w_captured <= 1'b0;
                s_axi_control_BVALID <= 1'b1;
            end
            else if (s_axi_control_BVALID && s_axi_control_BREADY) begin
                s_axi_control_BVALID <= 1'b0;
            end

            if (!s_axi_control_RVALID && s_axi_control_ARVALID && s_axi_control_ARREADY) begin
                rd_addr <= s_axi_control_ARADDR;
                s_axi_control_RDATA <= read_reg(s_axi_control_ARADDR);
                s_axi_control_RVALID <= 1'b1;
                if (s_axi_control_ARADDR == ADDR_AP_CTRL) begin
                    ap_done_reg <= 1'b0;
                end
            end
            else if (s_axi_control_RVALID && s_axi_control_RREADY) begin
                s_axi_control_RVALID <= 1'b0;
            end


            case (kernel_state)
                KS_IDLE: begin
                    core_reset <= 1;
                    if (ap_start_reg) begin
                        base_a<=reg_a; base_b<=reg_b; base_c<=reg_c;
                        active_dim<=reg_dim[7:0]; count<=reg_dim[7:0]*reg_dim[7:0]; idx<=0;
                        error_reg<=0; ap_start_reg<=0; ap_done_reg<=0; ap_idle_reg<=0; ap_ready_reg<=0;
                        if (reg_dim == 0 || reg_dim > MAX_DIM || |reg_a[1:0] || |reg_b[1:0] || |reg_c[1:0]) begin
                            error_reg<=1; kernel_state<=KS_DONE;
                        end else begin
                            core_reset<=0; kernel_state<=KS_START;
                        end
                    end
                end
                KS_START: begin core_start<=1; kernel_state<=KS_A_AR; end
                KS_A_AR: begin
                    if (!m0_arvalid) begin m0_araddr<=base_a+({48'd0,idx}<<2); m0_arvalid<=1; end
                    if (m0_arvalid && m_axi_gmem0_ARREADY) begin
                        m0_arvalid<=0; m0_rready<=1; kernel_state<=KS_A_R;
                    end
                end
                KS_A_R: if (m_axi_gmem0_RVALID && m0_rready) begin
                    m0_rready<=0;
                    if (m_axi_gmem0_RRESP != 0 || !m_axi_gmem0_RLAST) begin
                        error_reg<=2; core_reset<=1; kernel_state<=KS_DONE;
                    end else begin core_in_data<=m_axi_gmem0_RDATA; core_in_valid<=1; kernel_state<=KS_A_FEED; end
                end
                KS_A_FEED: if (core_in_valid && core_in_ready) begin
                    core_in_valid<=0;
                    if (idx+1 == count) begin idx<=0; kernel_state<=KS_B_AR; end
                    else begin idx<=idx+1; kernel_state<=KS_A_AR; end
                end
                KS_B_AR: begin
                    if (!m1_arvalid) begin m1_araddr<=base_b+({48'd0,idx}<<2); m1_arvalid<=1; end
                    if (m1_arvalid && m_axi_gmem1_ARREADY) begin
                        m1_arvalid<=0; m1_rready<=1; kernel_state<=KS_B_R;
                    end
                end
                KS_B_R: if (m_axi_gmem1_RVALID && m1_rready) begin
                    m1_rready<=0;
                    if (m_axi_gmem1_RRESP != 0 || !m_axi_gmem1_RLAST) begin
                        error_reg<=3; core_reset<=1; kernel_state<=KS_DONE;
                    end else begin core_in_data<=m_axi_gmem1_RDATA; core_in_valid<=1; kernel_state<=KS_B_FEED; end
                end
                KS_B_FEED: if (core_in_valid && core_in_ready) begin
                    core_in_valid<=0;
                    if (idx+1 == count) begin idx<=0; kernel_state<=KS_C_CAPTURE; end
                    else begin idx<=idx+1; kernel_state<=KS_B_AR; end
                end
                KS_C_CAPTURE: if (core_out_valid && core_out_ready) begin
                    m2_awaddr<=base_c+({48'd0,idx}<<2); m2_wdata<=core_out_data;
                    m2_awvalid<=1; m2_wvalid<=1; kernel_state<=KS_C_WRITE;
                end
                KS_C_WRITE: begin
                    if (m2_awvalid && m_axi_gmem2_AWREADY) m2_awvalid<=0;
                    if (m2_wvalid && m_axi_gmem2_WREADY) m2_wvalid<=0;
                    if ((!m2_awvalid || m_axi_gmem2_AWREADY) && (!m2_wvalid || m_axi_gmem2_WREADY)) begin
                        m2_bready<=1; kernel_state<=KS_C_B;
                    end
                end
                KS_C_B: if (m_axi_gmem2_BVALID && m2_bready) begin
                    m2_bready<=0;
                    if (m_axi_gmem2_BRESP != 0) begin error_reg<=4; core_reset<=1; kernel_state<=KS_DONE; end
                    else if (idx+1 == count) kernel_state<=KS_DONE;
                    else begin idx<=idx+1; kernel_state<=KS_C_CAPTURE; end
                end
                KS_DONE: begin
                    core_reset<=1; core_in_valid<=0;
                    ap_done_reg<=1; ap_idle_reg<=1; ap_ready_reg<=1; isr_reg[0]<=ier_reg[0];
                    if (auto_restart_reg && error_reg==0) ap_start_reg<=1;
                    kernel_state<=KS_IDLE;
                end
                default: begin error_reg<=5; kernel_state<=KS_DONE; end
            endcase
        end
    end
endmodule
