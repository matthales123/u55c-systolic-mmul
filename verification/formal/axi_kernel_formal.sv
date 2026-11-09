// Real packaged kernel control proof. The axis shell alone is explicitly
// over-approximated by abstract_axis_shell.sv; no arithmetic claim is made.
// All external inputs are unrestricted after the initial asserted reset.
// This strengthens hold/reset safety; no eventual-completion claim is made.
module axi_kernel_formal #(parameter C_S_AXI_CONTROL_ADDR_WIDTH=6,
    C_S_AXI_CONTROL_DATA_WIDTH=32, C_M_AXI_ADDR_WIDTH=64,
    C_M_AXI_DATA_WIDTH=32, C_M_AXI_ID_WIDTH=1, C_M_AXI_USER_WIDTH=1) (
    input  ap_clk,
    input  ap_rst_n,
    input  m_axi_gmem0_AWREADY,
    input  m_axi_gmem0_WREADY,
    input  m_axi_gmem0_ARREADY,
    input  m_axi_gmem0_RVALID,
    input [C_M_AXI_DATA_WIDTH-1:0] m_axi_gmem0_RDATA,
    input  m_axi_gmem0_RLAST,
    input [C_M_AXI_ID_WIDTH-1:0] m_axi_gmem0_RID,
    input [C_M_AXI_USER_WIDTH-1:0] m_axi_gmem0_RUSER,
    input [1:0] m_axi_gmem0_RRESP,
    input  m_axi_gmem0_BVALID,
    input [1:0] m_axi_gmem0_BRESP,
    input [C_M_AXI_ID_WIDTH-1:0] m_axi_gmem0_BID,
    input [C_M_AXI_USER_WIDTH-1:0] m_axi_gmem0_BUSER,
    input  m_axi_gmem1_AWREADY,
    input  m_axi_gmem1_WREADY,
    input  m_axi_gmem1_ARREADY,
    input  m_axi_gmem1_RVALID,
    input [C_M_AXI_DATA_WIDTH-1:0] m_axi_gmem1_RDATA,
    input  m_axi_gmem1_RLAST,
    input [C_M_AXI_ID_WIDTH-1:0] m_axi_gmem1_RID,
    input [C_M_AXI_USER_WIDTH-1:0] m_axi_gmem1_RUSER,
    input [1:0] m_axi_gmem1_RRESP,
    input  m_axi_gmem1_BVALID,
    input [1:0] m_axi_gmem1_BRESP,
    input [C_M_AXI_ID_WIDTH-1:0] m_axi_gmem1_BID,
    input [C_M_AXI_USER_WIDTH-1:0] m_axi_gmem1_BUSER,
    input  m_axi_gmem2_AWREADY,
    input  m_axi_gmem2_WREADY,
    input  m_axi_gmem2_ARREADY,
    input  m_axi_gmem2_RVALID,
    input [C_M_AXI_DATA_WIDTH-1:0] m_axi_gmem2_RDATA,
    input  m_axi_gmem2_RLAST,
    input [C_M_AXI_ID_WIDTH-1:0] m_axi_gmem2_RID,
    input [C_M_AXI_USER_WIDTH-1:0] m_axi_gmem2_RUSER,
    input [1:0] m_axi_gmem2_RRESP,
    input  m_axi_gmem2_BVALID,
    input [1:0] m_axi_gmem2_BRESP,
    input [C_M_AXI_ID_WIDTH-1:0] m_axi_gmem2_BID,
    input [C_M_AXI_USER_WIDTH-1:0] m_axi_gmem2_BUSER,
    input  s_axi_control_AWVALID,
    input [C_S_AXI_CONTROL_ADDR_WIDTH-1:0] s_axi_control_AWADDR,
    input  s_axi_control_WVALID,
    input [C_S_AXI_CONTROL_DATA_WIDTH-1:0] s_axi_control_WDATA,
    input [(C_S_AXI_CONTROL_DATA_WIDTH/8)-1:0] s_axi_control_WSTRB,
    input  s_axi_control_ARVALID,
    input [C_S_AXI_CONTROL_ADDR_WIDTH-1:0] s_axi_control_ARADDR,
    input  s_axi_control_RREADY,
    input  s_axi_control_BREADY
);
    (* keep *) wire  m_axi_gmem0_AWVALID;
    (* keep *) wire [C_M_AXI_ADDR_WIDTH-1:0] m_axi_gmem0_AWADDR;
    (* keep *) wire [C_M_AXI_ID_WIDTH-1:0] m_axi_gmem0_AWID;
    (* keep *) wire [7:0] m_axi_gmem0_AWLEN;
    (* keep *) wire [2:0] m_axi_gmem0_AWSIZE;
    (* keep *) wire [1:0] m_axi_gmem0_AWBURST;
    (* keep *) wire [1:0] m_axi_gmem0_AWLOCK;
    (* keep *) wire [3:0] m_axi_gmem0_AWCACHE;
    (* keep *) wire [2:0] m_axi_gmem0_AWPROT;
    (* keep *) wire [3:0] m_axi_gmem0_AWQOS;
    (* keep *) wire [3:0] m_axi_gmem0_AWREGION;
    (* keep *) wire [C_M_AXI_USER_WIDTH-1:0] m_axi_gmem0_AWUSER;
    (* keep *) wire  m_axi_gmem0_WVALID;
    (* keep *) wire [C_M_AXI_DATA_WIDTH-1:0] m_axi_gmem0_WDATA;
    (* keep *) wire [(C_M_AXI_DATA_WIDTH/8)-1:0] m_axi_gmem0_WSTRB;
    (* keep *) wire  m_axi_gmem0_WLAST;
    (* keep *) wire [C_M_AXI_ID_WIDTH-1:0] m_axi_gmem0_WID;
    (* keep *) wire [C_M_AXI_USER_WIDTH-1:0] m_axi_gmem0_WUSER;
    (* keep *) wire  m_axi_gmem0_ARVALID;
    (* keep *) wire [C_M_AXI_ADDR_WIDTH-1:0] m_axi_gmem0_ARADDR;
    (* keep *) wire [C_M_AXI_ID_WIDTH-1:0] m_axi_gmem0_ARID;
    (* keep *) wire [7:0] m_axi_gmem0_ARLEN;
    (* keep *) wire [2:0] m_axi_gmem0_ARSIZE;
    (* keep *) wire [1:0] m_axi_gmem0_ARBURST;
    (* keep *) wire [1:0] m_axi_gmem0_ARLOCK;
    (* keep *) wire [3:0] m_axi_gmem0_ARCACHE;
    (* keep *) wire [2:0] m_axi_gmem0_ARPROT;
    (* keep *) wire [3:0] m_axi_gmem0_ARQOS;
    (* keep *) wire [3:0] m_axi_gmem0_ARREGION;
    (* keep *) wire [C_M_AXI_USER_WIDTH-1:0] m_axi_gmem0_ARUSER;
    (* keep *) wire  m_axi_gmem0_RREADY;
    (* keep *) wire  m_axi_gmem0_BREADY;
    (* keep *) wire  m_axi_gmem1_AWVALID;
    (* keep *) wire [C_M_AXI_ADDR_WIDTH-1:0] m_axi_gmem1_AWADDR;
    (* keep *) wire [C_M_AXI_ID_WIDTH-1:0] m_axi_gmem1_AWID;
    (* keep *) wire [7:0] m_axi_gmem1_AWLEN;
    (* keep *) wire [2:0] m_axi_gmem1_AWSIZE;
    (* keep *) wire [1:0] m_axi_gmem1_AWBURST;
    (* keep *) wire [1:0] m_axi_gmem1_AWLOCK;
    (* keep *) wire [3:0] m_axi_gmem1_AWCACHE;
    (* keep *) wire [2:0] m_axi_gmem1_AWPROT;
    (* keep *) wire [3:0] m_axi_gmem1_AWQOS;
    (* keep *) wire [3:0] m_axi_gmem1_AWREGION;
    (* keep *) wire [C_M_AXI_USER_WIDTH-1:0] m_axi_gmem1_AWUSER;
    (* keep *) wire  m_axi_gmem1_WVALID;
    (* keep *) wire [C_M_AXI_DATA_WIDTH-1:0] m_axi_gmem1_WDATA;
    (* keep *) wire [(C_M_AXI_DATA_WIDTH/8)-1:0] m_axi_gmem1_WSTRB;
    (* keep *) wire  m_axi_gmem1_WLAST;
    (* keep *) wire [C_M_AXI_ID_WIDTH-1:0] m_axi_gmem1_WID;
    (* keep *) wire [C_M_AXI_USER_WIDTH-1:0] m_axi_gmem1_WUSER;
    (* keep *) wire  m_axi_gmem1_ARVALID;
    (* keep *) wire [C_M_AXI_ADDR_WIDTH-1:0] m_axi_gmem1_ARADDR;
    (* keep *) wire [C_M_AXI_ID_WIDTH-1:0] m_axi_gmem1_ARID;
    (* keep *) wire [7:0] m_axi_gmem1_ARLEN;
    (* keep *) wire [2:0] m_axi_gmem1_ARSIZE;
    (* keep *) wire [1:0] m_axi_gmem1_ARBURST;
    (* keep *) wire [1:0] m_axi_gmem1_ARLOCK;
    (* keep *) wire [3:0] m_axi_gmem1_ARCACHE;
    (* keep *) wire [2:0] m_axi_gmem1_ARPROT;
    (* keep *) wire [3:0] m_axi_gmem1_ARQOS;
    (* keep *) wire [3:0] m_axi_gmem1_ARREGION;
    (* keep *) wire [C_M_AXI_USER_WIDTH-1:0] m_axi_gmem1_ARUSER;
    (* keep *) wire  m_axi_gmem1_RREADY;
    (* keep *) wire  m_axi_gmem1_BREADY;
    (* keep *) wire  m_axi_gmem2_AWVALID;
    (* keep *) wire [C_M_AXI_ADDR_WIDTH-1:0] m_axi_gmem2_AWADDR;
    (* keep *) wire [C_M_AXI_ID_WIDTH-1:0] m_axi_gmem2_AWID;
    (* keep *) wire [7:0] m_axi_gmem2_AWLEN;
    (* keep *) wire [2:0] m_axi_gmem2_AWSIZE;
    (* keep *) wire [1:0] m_axi_gmem2_AWBURST;
    (* keep *) wire [1:0] m_axi_gmem2_AWLOCK;
    (* keep *) wire [3:0] m_axi_gmem2_AWCACHE;
    (* keep *) wire [2:0] m_axi_gmem2_AWPROT;
    (* keep *) wire [3:0] m_axi_gmem2_AWQOS;
    (* keep *) wire [3:0] m_axi_gmem2_AWREGION;
    (* keep *) wire [C_M_AXI_USER_WIDTH-1:0] m_axi_gmem2_AWUSER;
    (* keep *) wire  m_axi_gmem2_WVALID;
    (* keep *) wire [C_M_AXI_DATA_WIDTH-1:0] m_axi_gmem2_WDATA;
    (* keep *) wire [(C_M_AXI_DATA_WIDTH/8)-1:0] m_axi_gmem2_WSTRB;
    (* keep *) wire  m_axi_gmem2_WLAST;
    (* keep *) wire [C_M_AXI_ID_WIDTH-1:0] m_axi_gmem2_WID;
    (* keep *) wire [C_M_AXI_USER_WIDTH-1:0] m_axi_gmem2_WUSER;
    (* keep *) wire  m_axi_gmem2_ARVALID;
    (* keep *) wire [C_M_AXI_ADDR_WIDTH-1:0] m_axi_gmem2_ARADDR;
    (* keep *) wire [C_M_AXI_ID_WIDTH-1:0] m_axi_gmem2_ARID;
    (* keep *) wire [7:0] m_axi_gmem2_ARLEN;
    (* keep *) wire [2:0] m_axi_gmem2_ARSIZE;
    (* keep *) wire [1:0] m_axi_gmem2_ARBURST;
    (* keep *) wire [1:0] m_axi_gmem2_ARLOCK;
    (* keep *) wire [3:0] m_axi_gmem2_ARCACHE;
    (* keep *) wire [2:0] m_axi_gmem2_ARPROT;
    (* keep *) wire [3:0] m_axi_gmem2_ARQOS;
    (* keep *) wire [3:0] m_axi_gmem2_ARREGION;
    (* keep *) wire [C_M_AXI_USER_WIDTH-1:0] m_axi_gmem2_ARUSER;
    (* keep *) wire  m_axi_gmem2_RREADY;
    (* keep *) wire  m_axi_gmem2_BREADY;
    (* keep *) wire  s_axi_control_AWREADY;
    (* keep *) wire  s_axi_control_WREADY;
    (* keep *) wire  s_axi_control_ARREADY;
    (* keep *) wire  s_axi_control_RVALID;
    (* keep *) wire [C_S_AXI_CONTROL_DATA_WIDTH-1:0] s_axi_control_RDATA;
    (* keep *) wire [1:0] s_axi_control_RRESP;
    (* keep *) wire  s_axi_control_BVALID;
    (* keep *) wire [1:0] s_axi_control_BRESP;
    (* keep *) wire  interrupt;
    mmul_sysbase #(.MAX_DIM(8), .ARRAY_SIZE(4)) dut (.*);
    // Slang resolves these references against the actual kernel registers.
    // Observe private architectural state without changing or abstracting it.
    (* keep *) wire f_irq_gie = dut.gie_reg;
    (* keep *) wire f_irq_status = dut.isr_reg[0];
    (* keep *) wire f_irq_busy = !dut.ap_idle_reg;
    (* keep *) wire f_irq_ack = dut.aw_captured && dut.w_captured &&
        !s_axi_control_BVALID && dut.wr_addr == 6'h0c &&
        dut.wr_strb[0] && dut.wr_data[0];
    reg f_past_valid = 0;
    (* keep *) reg [1:0] f_irq_ack_cover = 0;
    reg f_read_a_pending = 0, f_read_b_pending = 0;
    reg f_write_addr_pending = 0, f_write_data_pending = 0;
    always @(posedge ap_clk) begin
        f_past_valid <= 1;
        if (!f_past_valid) assume(!ap_rst_n);
        if (!ap_rst_n) f_irq_ack_cover <= 0;
        else begin
            case (f_irq_ack_cover)
                0: if (interrupt) f_irq_ack_cover <= 1;
                1: if (f_irq_ack) f_irq_ack_cover <= 2;
                2: if (!interrupt && !f_irq_status) f_irq_ack_cover <= 3;
            endcase
        end
`ifdef CHECK_AXI_KERNEL
`define CHECK_REGISTERED_IRQ
`endif
`ifdef CHECK_AXI_IRQ_ONLY
`define CHECK_REGISTERED_IRQ
`endif
`ifdef CHECK_REGISTERED_IRQ
        if (f_past_valid) begin
            if ($past(!ap_rst_n)) assert(!interrupt);
            else assert(interrupt == $past(f_irq_gie && f_irq_status));
        end
`undef CHECK_REGISTERED_IRQ
`endif
`ifdef COVER_AXI_KERNEL
        // Cover witnesses use a legal single-outstanding memory responder.
        // These restrictions are NOT used by the stronger safety proof.
        if (!ap_rst_n) begin
            f_read_a_pending <= 0;
            f_read_b_pending <= 0;
            f_write_addr_pending <= 0;
            f_write_data_pending <= 0;
        end else begin
            if (m_axi_gmem0_ARVALID && m_axi_gmem0_ARREADY) f_read_a_pending <= 1;
            if (m_axi_gmem0_RVALID && m_axi_gmem0_RREADY) f_read_a_pending <= 0;
            if (m_axi_gmem1_ARVALID && m_axi_gmem1_ARREADY) f_read_b_pending <= 1;
            if (m_axi_gmem1_RVALID && m_axi_gmem1_RREADY) f_read_b_pending <= 0;
            if (m_axi_gmem2_AWVALID && m_axi_gmem2_AWREADY) f_write_addr_pending <= 1;
            if (m_axi_gmem2_WVALID && m_axi_gmem2_WREADY) f_write_data_pending <= 1;
            if (m_axi_gmem2_BVALID && m_axi_gmem2_BREADY) begin
                f_write_addr_pending <= 0;
                f_write_data_pending <= 0;
            end
            if (m_axi_gmem0_RVALID) begin
                assume(f_read_a_pending);
                assume(m_axi_gmem0_RLAST && m_axi_gmem0_RRESP == 0 && m_axi_gmem0_RID == 0);
            end
            if (m_axi_gmem1_RVALID) begin
                assume(f_read_b_pending);
                assume(m_axi_gmem1_RLAST && m_axi_gmem1_RRESP == 0 && m_axi_gmem1_RID == 0);
            end
            if (m_axi_gmem2_BVALID) begin
                assume(f_write_addr_pending && f_write_data_pending);
                assume(m_axi_gmem2_BRESP == 0 && m_axi_gmem2_BID == 0);
            end
        end
        if (f_past_valid && ap_rst_n && $past(ap_rst_n)) begin
            if ($past(s_axi_control_AWVALID && !s_axi_control_AWREADY)) begin
                assume(s_axi_control_AWVALID);
                assume(s_axi_control_AWADDR == $past(s_axi_control_AWADDR));
            end
            if ($past(s_axi_control_WVALID && !s_axi_control_WREADY)) begin
                assume(s_axi_control_WVALID);
                assume({s_axi_control_WDATA, s_axi_control_WSTRB} == $past({s_axi_control_WDATA, s_axi_control_WSTRB}));
            end
            if ($past(s_axi_control_ARVALID && !s_axi_control_ARREADY)) begin
                assume(s_axi_control_ARVALID);
                assume(s_axi_control_ARADDR == $past(s_axi_control_ARADDR));
            end
            if ($past(m_axi_gmem0_RVALID && !m_axi_gmem0_RREADY)) begin
                assume(m_axi_gmem0_RVALID);
                assume({m_axi_gmem0_RDATA, m_axi_gmem0_RRESP, m_axi_gmem0_RLAST, m_axi_gmem0_RID, m_axi_gmem0_RUSER} ==
                       $past({m_axi_gmem0_RDATA, m_axi_gmem0_RRESP, m_axi_gmem0_RLAST, m_axi_gmem0_RID, m_axi_gmem0_RUSER}));
            end
            if ($past(m_axi_gmem1_RVALID && !m_axi_gmem1_RREADY)) begin
                assume(m_axi_gmem1_RVALID);
                assume({m_axi_gmem1_RDATA, m_axi_gmem1_RRESP, m_axi_gmem1_RLAST, m_axi_gmem1_RID, m_axi_gmem1_RUSER} ==
                       $past({m_axi_gmem1_RDATA, m_axi_gmem1_RRESP, m_axi_gmem1_RLAST, m_axi_gmem1_RID, m_axi_gmem1_RUSER}));
            end
            if ($past(m_axi_gmem2_BVALID && !m_axi_gmem2_BREADY)) begin
                assume(m_axi_gmem2_BVALID);
                assume({m_axi_gmem2_BRESP, m_axi_gmem2_BID, m_axi_gmem2_BUSER} ==
                       $past({m_axi_gmem2_BRESP, m_axi_gmem2_BID, m_axi_gmem2_BUSER}));
            end
        end
`endif
`ifdef CHECK_AXI_KERNEL
        if (f_past_valid && $past(!ap_rst_n)) begin
            assert(!m_axi_gmem0_ARVALID);
            assert(!m_axi_gmem0_AWVALID);
            assert(!m_axi_gmem0_WVALID);
            assert(!m_axi_gmem1_ARVALID);
            assert(!m_axi_gmem1_AWVALID);
            assert(!m_axi_gmem1_WVALID);
            assert(!m_axi_gmem2_ARVALID);
            assert(!m_axi_gmem2_AWVALID);
            assert(!m_axi_gmem2_WVALID);
            assert(!s_axi_control_RVALID);
            assert(!s_axi_control_BVALID);
        end
        if (f_past_valid && ap_rst_n && $past(ap_rst_n && m_axi_gmem0_ARVALID && !m_axi_gmem0_ARREADY)) begin
            assert(m_axi_gmem0_ARVALID);
            assert({m_axi_gmem0_ARADDR, m_axi_gmem0_ARID, m_axi_gmem0_ARLEN, m_axi_gmem0_ARSIZE, m_axi_gmem0_ARBURST, m_axi_gmem0_ARLOCK, m_axi_gmem0_ARCACHE, m_axi_gmem0_ARPROT, m_axi_gmem0_ARQOS, m_axi_gmem0_ARREGION, m_axi_gmem0_ARUSER} == $past({m_axi_gmem0_ARADDR, m_axi_gmem0_ARID, m_axi_gmem0_ARLEN, m_axi_gmem0_ARSIZE, m_axi_gmem0_ARBURST, m_axi_gmem0_ARLOCK, m_axi_gmem0_ARCACHE, m_axi_gmem0_ARPROT, m_axi_gmem0_ARQOS, m_axi_gmem0_ARREGION, m_axi_gmem0_ARUSER}));
        end
        if (f_past_valid && ap_rst_n && $past(ap_rst_n && m_axi_gmem0_AWVALID && !m_axi_gmem0_AWREADY)) begin
            assert(m_axi_gmem0_AWVALID);
            assert({m_axi_gmem0_AWADDR, m_axi_gmem0_AWID, m_axi_gmem0_AWLEN, m_axi_gmem0_AWSIZE, m_axi_gmem0_AWBURST, m_axi_gmem0_AWLOCK, m_axi_gmem0_AWCACHE, m_axi_gmem0_AWPROT, m_axi_gmem0_AWQOS, m_axi_gmem0_AWREGION, m_axi_gmem0_AWUSER} == $past({m_axi_gmem0_AWADDR, m_axi_gmem0_AWID, m_axi_gmem0_AWLEN, m_axi_gmem0_AWSIZE, m_axi_gmem0_AWBURST, m_axi_gmem0_AWLOCK, m_axi_gmem0_AWCACHE, m_axi_gmem0_AWPROT, m_axi_gmem0_AWQOS, m_axi_gmem0_AWREGION, m_axi_gmem0_AWUSER}));
        end
        if (f_past_valid && ap_rst_n && $past(ap_rst_n && m_axi_gmem0_WVALID && !m_axi_gmem0_WREADY)) begin
            assert(m_axi_gmem0_WVALID);
            assert({m_axi_gmem0_WDATA, m_axi_gmem0_WSTRB, m_axi_gmem0_WLAST, m_axi_gmem0_WID, m_axi_gmem0_WUSER} == $past({m_axi_gmem0_WDATA, m_axi_gmem0_WSTRB, m_axi_gmem0_WLAST, m_axi_gmem0_WID, m_axi_gmem0_WUSER}));
        end
        if (f_past_valid && ap_rst_n && $past(ap_rst_n && m_axi_gmem1_ARVALID && !m_axi_gmem1_ARREADY)) begin
            assert(m_axi_gmem1_ARVALID);
            assert({m_axi_gmem1_ARADDR, m_axi_gmem1_ARID, m_axi_gmem1_ARLEN, m_axi_gmem1_ARSIZE, m_axi_gmem1_ARBURST, m_axi_gmem1_ARLOCK, m_axi_gmem1_ARCACHE, m_axi_gmem1_ARPROT, m_axi_gmem1_ARQOS, m_axi_gmem1_ARREGION, m_axi_gmem1_ARUSER} == $past({m_axi_gmem1_ARADDR, m_axi_gmem1_ARID, m_axi_gmem1_ARLEN, m_axi_gmem1_ARSIZE, m_axi_gmem1_ARBURST, m_axi_gmem1_ARLOCK, m_axi_gmem1_ARCACHE, m_axi_gmem1_ARPROT, m_axi_gmem1_ARQOS, m_axi_gmem1_ARREGION, m_axi_gmem1_ARUSER}));
        end
        if (f_past_valid && ap_rst_n && $past(ap_rst_n && m_axi_gmem1_AWVALID && !m_axi_gmem1_AWREADY)) begin
            assert(m_axi_gmem1_AWVALID);
            assert({m_axi_gmem1_AWADDR, m_axi_gmem1_AWID, m_axi_gmem1_AWLEN, m_axi_gmem1_AWSIZE, m_axi_gmem1_AWBURST, m_axi_gmem1_AWLOCK, m_axi_gmem1_AWCACHE, m_axi_gmem1_AWPROT, m_axi_gmem1_AWQOS, m_axi_gmem1_AWREGION, m_axi_gmem1_AWUSER} == $past({m_axi_gmem1_AWADDR, m_axi_gmem1_AWID, m_axi_gmem1_AWLEN, m_axi_gmem1_AWSIZE, m_axi_gmem1_AWBURST, m_axi_gmem1_AWLOCK, m_axi_gmem1_AWCACHE, m_axi_gmem1_AWPROT, m_axi_gmem1_AWQOS, m_axi_gmem1_AWREGION, m_axi_gmem1_AWUSER}));
        end
        if (f_past_valid && ap_rst_n && $past(ap_rst_n && m_axi_gmem1_WVALID && !m_axi_gmem1_WREADY)) begin
            assert(m_axi_gmem1_WVALID);
            assert({m_axi_gmem1_WDATA, m_axi_gmem1_WSTRB, m_axi_gmem1_WLAST, m_axi_gmem1_WID, m_axi_gmem1_WUSER} == $past({m_axi_gmem1_WDATA, m_axi_gmem1_WSTRB, m_axi_gmem1_WLAST, m_axi_gmem1_WID, m_axi_gmem1_WUSER}));
        end
        if (f_past_valid && ap_rst_n && $past(ap_rst_n && m_axi_gmem2_ARVALID && !m_axi_gmem2_ARREADY)) begin
            assert(m_axi_gmem2_ARVALID);
            assert({m_axi_gmem2_ARADDR, m_axi_gmem2_ARID, m_axi_gmem2_ARLEN, m_axi_gmem2_ARSIZE, m_axi_gmem2_ARBURST, m_axi_gmem2_ARLOCK, m_axi_gmem2_ARCACHE, m_axi_gmem2_ARPROT, m_axi_gmem2_ARQOS, m_axi_gmem2_ARREGION, m_axi_gmem2_ARUSER} == $past({m_axi_gmem2_ARADDR, m_axi_gmem2_ARID, m_axi_gmem2_ARLEN, m_axi_gmem2_ARSIZE, m_axi_gmem2_ARBURST, m_axi_gmem2_ARLOCK, m_axi_gmem2_ARCACHE, m_axi_gmem2_ARPROT, m_axi_gmem2_ARQOS, m_axi_gmem2_ARREGION, m_axi_gmem2_ARUSER}));
        end
        if (f_past_valid && ap_rst_n && $past(ap_rst_n && m_axi_gmem2_AWVALID && !m_axi_gmem2_AWREADY)) begin
            assert(m_axi_gmem2_AWVALID);
            assert({m_axi_gmem2_AWADDR, m_axi_gmem2_AWID, m_axi_gmem2_AWLEN, m_axi_gmem2_AWSIZE, m_axi_gmem2_AWBURST, m_axi_gmem2_AWLOCK, m_axi_gmem2_AWCACHE, m_axi_gmem2_AWPROT, m_axi_gmem2_AWQOS, m_axi_gmem2_AWREGION, m_axi_gmem2_AWUSER} == $past({m_axi_gmem2_AWADDR, m_axi_gmem2_AWID, m_axi_gmem2_AWLEN, m_axi_gmem2_AWSIZE, m_axi_gmem2_AWBURST, m_axi_gmem2_AWLOCK, m_axi_gmem2_AWCACHE, m_axi_gmem2_AWPROT, m_axi_gmem2_AWQOS, m_axi_gmem2_AWREGION, m_axi_gmem2_AWUSER}));
        end
        if (f_past_valid && ap_rst_n && $past(ap_rst_n && m_axi_gmem2_WVALID && !m_axi_gmem2_WREADY)) begin
            assert(m_axi_gmem2_WVALID);
            assert({m_axi_gmem2_WDATA, m_axi_gmem2_WSTRB, m_axi_gmem2_WLAST, m_axi_gmem2_WID, m_axi_gmem2_WUSER} == $past({m_axi_gmem2_WDATA, m_axi_gmem2_WSTRB, m_axi_gmem2_WLAST, m_axi_gmem2_WID, m_axi_gmem2_WUSER}));
        end
        if (f_past_valid && ap_rst_n && $past(ap_rst_n && s_axi_control_RVALID && !s_axi_control_RREADY)) begin
            assert(s_axi_control_RVALID);
            assert({s_axi_control_RDATA, s_axi_control_RRESP} == $past({s_axi_control_RDATA, s_axi_control_RRESP}));
        end
        if (f_past_valid && ap_rst_n && $past(ap_rst_n && s_axi_control_BVALID && !s_axi_control_BREADY)) begin
            assert(s_axi_control_BVALID);
            assert({s_axi_control_BRESP} == $past({s_axi_control_BRESP}));
        end
`endif
`ifdef COVER_AXI_KERNEL
        cover(ap_rst_n && m_axi_gmem0_ARVALID && !m_axi_gmem0_ARREADY);
        cover(ap_rst_n && m_axi_gmem1_ARVALID && !m_axi_gmem1_ARREADY);
        cover(ap_rst_n && m_axi_gmem2_AWVALID && !m_axi_gmem2_AWREADY && !m_axi_gmem2_WVALID);
        cover(ap_rst_n && m_axi_gmem2_WVALID && !m_axi_gmem2_WREADY && !m_axi_gmem2_AWVALID);
        cover(ap_rst_n && s_axi_control_RVALID && !s_axi_control_RREADY);
        cover(ap_rst_n && s_axi_control_BVALID && !s_axi_control_BREADY);
        cover(ap_rst_n && interrupt);
        cover(ap_rst_n && interrupt && !f_irq_gie && f_irq_status);
        cover(ap_rst_n && f_irq_ack_cover == 3);
        cover(f_past_valid && ap_rst_n && $past(ap_rst_n) &&
              f_irq_busy && f_irq_gie != $past(f_irq_gie));
`endif
    end
endmodule
