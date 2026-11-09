`timescale 1ns/1ps
module mmul_sysbase_axi_tb;
localparam C_S_AXI_CONTROL_ADDR_WIDTH=6,C_S_AXI_CONTROL_DATA_WIDTH=32,C_M_AXI_ADDR_WIDTH=64,
 C_M_AXI_DATA_WIDTH=32,C_M_AXI_ID_WIDTH=1,C_M_AXI_USER_WIDTH=1;
logic  ap_clk;
logic  ap_rst_n;
logic  m_axi_gmem0_AWVALID;
logic  m_axi_gmem0_AWREADY;
logic [C_M_AXI_ADDR_WIDTH-1:0] m_axi_gmem0_AWADDR;
logic [C_M_AXI_ID_WIDTH-1:0] m_axi_gmem0_AWID;
logic [7:0] m_axi_gmem0_AWLEN;
logic [2:0] m_axi_gmem0_AWSIZE;
logic [1:0] m_axi_gmem0_AWBURST;
logic [1:0] m_axi_gmem0_AWLOCK;
logic [3:0] m_axi_gmem0_AWCACHE;
logic [2:0] m_axi_gmem0_AWPROT;
logic [3:0] m_axi_gmem0_AWQOS;
logic [3:0] m_axi_gmem0_AWREGION;
logic [C_M_AXI_USER_WIDTH-1:0] m_axi_gmem0_AWUSER;
logic  m_axi_gmem0_WVALID;
logic  m_axi_gmem0_WREADY;
logic [C_M_AXI_DATA_WIDTH-1:0] m_axi_gmem0_WDATA;
logic [(C_M_AXI_DATA_WIDTH/8)-1:0] m_axi_gmem0_WSTRB;
logic  m_axi_gmem0_WLAST;
logic [C_M_AXI_ID_WIDTH-1:0] m_axi_gmem0_WID;
logic [C_M_AXI_USER_WIDTH-1:0] m_axi_gmem0_WUSER;
logic  m_axi_gmem0_ARVALID;
logic  m_axi_gmem0_ARREADY;
logic [C_M_AXI_ADDR_WIDTH-1:0] m_axi_gmem0_ARADDR;
logic [C_M_AXI_ID_WIDTH-1:0] m_axi_gmem0_ARID;
logic [7:0] m_axi_gmem0_ARLEN;
logic [2:0] m_axi_gmem0_ARSIZE;
logic [1:0] m_axi_gmem0_ARBURST;
logic [1:0] m_axi_gmem0_ARLOCK;
logic [3:0] m_axi_gmem0_ARCACHE;
logic [2:0] m_axi_gmem0_ARPROT;
logic [3:0] m_axi_gmem0_ARQOS;
logic [3:0] m_axi_gmem0_ARREGION;
logic [C_M_AXI_USER_WIDTH-1:0] m_axi_gmem0_ARUSER;
logic  m_axi_gmem0_RVALID;
logic  m_axi_gmem0_RREADY;
logic [C_M_AXI_DATA_WIDTH-1:0] m_axi_gmem0_RDATA;
logic  m_axi_gmem0_RLAST;
logic [C_M_AXI_ID_WIDTH-1:0] m_axi_gmem0_RID;
logic [C_M_AXI_USER_WIDTH-1:0] m_axi_gmem0_RUSER;
logic [1:0] m_axi_gmem0_RRESP;
logic  m_axi_gmem0_BVALID;
logic  m_axi_gmem0_BREADY;
logic [1:0] m_axi_gmem0_BRESP;
logic [C_M_AXI_ID_WIDTH-1:0] m_axi_gmem0_BID;
logic [C_M_AXI_USER_WIDTH-1:0] m_axi_gmem0_BUSER;
logic  m_axi_gmem1_AWVALID;
logic  m_axi_gmem1_AWREADY;
logic [C_M_AXI_ADDR_WIDTH-1:0] m_axi_gmem1_AWADDR;
logic [C_M_AXI_ID_WIDTH-1:0] m_axi_gmem1_AWID;
logic [7:0] m_axi_gmem1_AWLEN;
logic [2:0] m_axi_gmem1_AWSIZE;
logic [1:0] m_axi_gmem1_AWBURST;
logic [1:0] m_axi_gmem1_AWLOCK;
logic [3:0] m_axi_gmem1_AWCACHE;
logic [2:0] m_axi_gmem1_AWPROT;
logic [3:0] m_axi_gmem1_AWQOS;
logic [3:0] m_axi_gmem1_AWREGION;
logic [C_M_AXI_USER_WIDTH-1:0] m_axi_gmem1_AWUSER;
logic  m_axi_gmem1_WVALID;
logic  m_axi_gmem1_WREADY;
logic [C_M_AXI_DATA_WIDTH-1:0] m_axi_gmem1_WDATA;
logic [(C_M_AXI_DATA_WIDTH/8)-1:0] m_axi_gmem1_WSTRB;
logic  m_axi_gmem1_WLAST;
logic [C_M_AXI_ID_WIDTH-1:0] m_axi_gmem1_WID;
logic [C_M_AXI_USER_WIDTH-1:0] m_axi_gmem1_WUSER;
logic  m_axi_gmem1_ARVALID;
logic  m_axi_gmem1_ARREADY;
logic [C_M_AXI_ADDR_WIDTH-1:0] m_axi_gmem1_ARADDR;
logic [C_M_AXI_ID_WIDTH-1:0] m_axi_gmem1_ARID;
logic [7:0] m_axi_gmem1_ARLEN;
logic [2:0] m_axi_gmem1_ARSIZE;
logic [1:0] m_axi_gmem1_ARBURST;
logic [1:0] m_axi_gmem1_ARLOCK;
logic [3:0] m_axi_gmem1_ARCACHE;
logic [2:0] m_axi_gmem1_ARPROT;
logic [3:0] m_axi_gmem1_ARQOS;
logic [3:0] m_axi_gmem1_ARREGION;
logic [C_M_AXI_USER_WIDTH-1:0] m_axi_gmem1_ARUSER;
logic  m_axi_gmem1_RVALID;
logic  m_axi_gmem1_RREADY;
logic [C_M_AXI_DATA_WIDTH-1:0] m_axi_gmem1_RDATA;
logic  m_axi_gmem1_RLAST;
logic [C_M_AXI_ID_WIDTH-1:0] m_axi_gmem1_RID;
logic [C_M_AXI_USER_WIDTH-1:0] m_axi_gmem1_RUSER;
logic [1:0] m_axi_gmem1_RRESP;
logic  m_axi_gmem1_BVALID;
logic  m_axi_gmem1_BREADY;
logic [1:0] m_axi_gmem1_BRESP;
logic [C_M_AXI_ID_WIDTH-1:0] m_axi_gmem1_BID;
logic [C_M_AXI_USER_WIDTH-1:0] m_axi_gmem1_BUSER;
logic  m_axi_gmem2_AWVALID;
logic  m_axi_gmem2_AWREADY;
logic [C_M_AXI_ADDR_WIDTH-1:0] m_axi_gmem2_AWADDR;
logic [C_M_AXI_ID_WIDTH-1:0] m_axi_gmem2_AWID;
logic [7:0] m_axi_gmem2_AWLEN;
logic [2:0] m_axi_gmem2_AWSIZE;
logic [1:0] m_axi_gmem2_AWBURST;
logic [1:0] m_axi_gmem2_AWLOCK;
logic [3:0] m_axi_gmem2_AWCACHE;
logic [2:0] m_axi_gmem2_AWPROT;
logic [3:0] m_axi_gmem2_AWQOS;
logic [3:0] m_axi_gmem2_AWREGION;
logic [C_M_AXI_USER_WIDTH-1:0] m_axi_gmem2_AWUSER;
logic  m_axi_gmem2_WVALID;
logic  m_axi_gmem2_WREADY;
logic [C_M_AXI_DATA_WIDTH-1:0] m_axi_gmem2_WDATA;
logic [(C_M_AXI_DATA_WIDTH/8)-1:0] m_axi_gmem2_WSTRB;
logic  m_axi_gmem2_WLAST;
logic [C_M_AXI_ID_WIDTH-1:0] m_axi_gmem2_WID;
logic [C_M_AXI_USER_WIDTH-1:0] m_axi_gmem2_WUSER;
logic  m_axi_gmem2_ARVALID;
logic  m_axi_gmem2_ARREADY;
logic [C_M_AXI_ADDR_WIDTH-1:0] m_axi_gmem2_ARADDR;
logic [C_M_AXI_ID_WIDTH-1:0] m_axi_gmem2_ARID;
logic [7:0] m_axi_gmem2_ARLEN;
logic [2:0] m_axi_gmem2_ARSIZE;
logic [1:0] m_axi_gmem2_ARBURST;
logic [1:0] m_axi_gmem2_ARLOCK;
logic [3:0] m_axi_gmem2_ARCACHE;
logic [2:0] m_axi_gmem2_ARPROT;
logic [3:0] m_axi_gmem2_ARQOS;
logic [3:0] m_axi_gmem2_ARREGION;
logic [C_M_AXI_USER_WIDTH-1:0] m_axi_gmem2_ARUSER;
logic  m_axi_gmem2_RVALID;
logic  m_axi_gmem2_RREADY;
logic [C_M_AXI_DATA_WIDTH-1:0] m_axi_gmem2_RDATA;
logic  m_axi_gmem2_RLAST;
logic [C_M_AXI_ID_WIDTH-1:0] m_axi_gmem2_RID;
logic [C_M_AXI_USER_WIDTH-1:0] m_axi_gmem2_RUSER;
logic [1:0] m_axi_gmem2_RRESP;
logic  m_axi_gmem2_BVALID;
logic  m_axi_gmem2_BREADY;
logic [1:0] m_axi_gmem2_BRESP;
logic [C_M_AXI_ID_WIDTH-1:0] m_axi_gmem2_BID;
logic [C_M_AXI_USER_WIDTH-1:0] m_axi_gmem2_BUSER;
logic  s_axi_control_AWVALID;
logic  s_axi_control_AWREADY;
logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0] s_axi_control_AWADDR;
logic  s_axi_control_WVALID;
logic  s_axi_control_WREADY;
logic [C_S_AXI_CONTROL_DATA_WIDTH-1:0] s_axi_control_WDATA;
logic [(C_S_AXI_CONTROL_DATA_WIDTH/8)-1:0] s_axi_control_WSTRB;
logic  s_axi_control_ARVALID;
logic  s_axi_control_ARREADY;
logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0] s_axi_control_ARADDR;
logic  s_axi_control_RVALID;
logic  s_axi_control_RREADY;
logic [C_S_AXI_CONTROL_DATA_WIDTH-1:0] s_axi_control_RDATA;
logic [1:0] s_axi_control_RRESP;
logic  s_axi_control_BVALID;
logic  s_axi_control_BREADY;
logic [1:0] s_axi_control_BRESP;
logic  interrupt;
mmul_sysbase dut (.*);
task automatic init_inputs;
begin
ap_clk='0;
ap_rst_n='0;
m_axi_gmem0_AWREADY='0;
m_axi_gmem0_WREADY='0;
m_axi_gmem0_ARREADY='0;
m_axi_gmem0_RVALID='0;
m_axi_gmem0_RDATA='0;
m_axi_gmem0_RLAST='0;
m_axi_gmem0_RID='0;
m_axi_gmem0_RUSER='0;
m_axi_gmem0_RRESP='0;
m_axi_gmem0_BVALID='0;
m_axi_gmem0_BRESP='0;
m_axi_gmem0_BID='0;
m_axi_gmem0_BUSER='0;
m_axi_gmem1_AWREADY='0;
m_axi_gmem1_WREADY='0;
m_axi_gmem1_ARREADY='0;
m_axi_gmem1_RVALID='0;
m_axi_gmem1_RDATA='0;
m_axi_gmem1_RLAST='0;
m_axi_gmem1_RID='0;
m_axi_gmem1_RUSER='0;
m_axi_gmem1_RRESP='0;
m_axi_gmem1_BVALID='0;
m_axi_gmem1_BRESP='0;
m_axi_gmem1_BID='0;
m_axi_gmem1_BUSER='0;
m_axi_gmem2_AWREADY='0;
m_axi_gmem2_WREADY='0;
m_axi_gmem2_ARREADY='0;
m_axi_gmem2_RVALID='0;
m_axi_gmem2_RDATA='0;
m_axi_gmem2_RLAST='0;
m_axi_gmem2_RID='0;
m_axi_gmem2_RUSER='0;
m_axi_gmem2_RRESP='0;
m_axi_gmem2_BVALID='0;
m_axi_gmem2_BRESP='0;
m_axi_gmem2_BID='0;
m_axi_gmem2_BUSER='0;
s_axi_control_AWVALID='0;
s_axi_control_AWADDR='0;
s_axi_control_WVALID='0;
s_axi_control_WDATA='0;
s_axi_control_WSTRB='0;
s_axi_control_ARVALID='0;
s_axi_control_ARADDR='0;
s_axi_control_RREADY='0;
s_axi_control_BREADY='0;
end
endtask
localparam logic [63:0] BASE_A=64'h0000000100001000, BASE_B=64'h0000000200002000, BASE_C=64'h0000000300003000;
logic [31:0] control_readback;
integer cycle=0, dim=0, inject_error=0, tests=0, writes=0,reads=0;
logic [31:0] mem_a[0:63],mem_b[0:63],mem_c[0:63],expected[0:63];
logic aw_seen=0,w_seen=0;
logic [63:0] write_addr;
logic [31:0] write_data;
integer b_delay=0,a_delay=0,read_b_delay=0,control_writes=0;
logic stalled_ar0=0,stalled_ar1=0,stalled_aw=0,stalled_w=0;
logic [63:0] last_ar0,last_ar1,last_aw;
logic [31:0] last_w;
logic irq_expected_after_edge;
always #2.5 ap_clk=~ap_clk;
always @(posedge ap_clk) begin
  irq_expected_after_edge=ap_rst_n && dut.gie_reg && dut.isr_reg[0];
  #1;
  if(interrupt!==irq_expected_after_edge) $fatal(1,"Interrupt must register prior GIE/ISR with reset priority");
end
always @(posedge ap_clk) begin
  cycle<=cycle+1;
  if(cycle>300000) $fatal(1,"AXI_TIMEOUT");
  if(!ap_rst_n) begin
    m_axi_gmem0_RVALID<=0;m_axi_gmem1_RVALID<=0;m_axi_gmem2_BVALID<=0;
    aw_seen<=0;w_seen<=0;b_delay<=0;a_delay<=0;read_b_delay<=0;
    stalled_ar0<=0;stalled_ar1<=0;stalled_aw<=0;stalled_w<=0;
  end else begin
    if(stalled_ar0 && (!m_axi_gmem0_ARVALID || m_axi_gmem0_ARADDR!==last_ar0)) $fatal(1,"A read address changed under stall");
    if(stalled_ar1 && (!m_axi_gmem1_ARVALID || m_axi_gmem1_ARADDR!==last_ar1)) $fatal(1,"B read address changed under stall");
    if(stalled_aw && (!m_axi_gmem2_AWVALID || m_axi_gmem2_AWADDR!==last_aw)) $fatal(1,"C write address changed under stall");
    if(stalled_w && (!m_axi_gmem2_WVALID || m_axi_gmem2_WDATA!==last_w)) $fatal(1,"C data changed under stall");
    stalled_ar0<=m_axi_gmem0_ARVALID&&!m_axi_gmem0_ARREADY; last_ar0<=m_axi_gmem0_ARADDR;
    stalled_ar1<=m_axi_gmem1_ARVALID&&!m_axi_gmem1_ARREADY; last_ar1<=m_axi_gmem1_ARADDR;
    stalled_aw<=m_axi_gmem2_AWVALID&&!m_axi_gmem2_AWREADY; last_aw<=m_axi_gmem2_AWADDR;
    stalled_w<=m_axi_gmem2_WVALID&&!m_axi_gmem2_WREADY; last_w<=m_axi_gmem2_WDATA;
    if(m_axi_gmem0_ARVALID&&m_axi_gmem0_ARREADY) begin
      if(m_axi_gmem0_ARLEN!=0||m_axi_gmem0_ARSIZE!=2||m_axi_gmem0_ARADDR<BASE_A||m_axi_gmem0_ARADDR>=(BASE_A+64'h100))
        $fatal(1,"Bad A transaction");
      reads<=reads+1; m_axi_gmem0_RDATA<=mem_a[(m_axi_gmem0_ARADDR-BASE_A)>>2];
      a_delay<=2; m_axi_gmem0_RRESP<=inject_error==2?2:0;
    end else if(m_axi_gmem0_RVALID&&m_axi_gmem0_RREADY) m_axi_gmem0_RVALID<=0;
    if(m_axi_gmem1_ARVALID&&m_axi_gmem1_ARREADY) begin
      if(m_axi_gmem1_ARLEN!=0||m_axi_gmem1_ARSIZE!=2||m_axi_gmem1_ARADDR<BASE_B||m_axi_gmem1_ARADDR>=(BASE_B+64'h100))
        $fatal(1,"Bad B transaction");
      reads<=reads+1; m_axi_gmem1_RDATA<=mem_b[(m_axi_gmem1_ARADDR-BASE_B)>>2];
      read_b_delay<=4; m_axi_gmem1_RRESP<=inject_error==3?2:0;
    end else if(m_axi_gmem1_RVALID&&m_axi_gmem1_RREADY) m_axi_gmem1_RVALID<=0;
    if(m_axi_gmem2_AWVALID&&m_axi_gmem2_AWREADY) begin
      if(aw_seen||m_axi_gmem2_AWLEN!=0||m_axi_gmem2_AWSIZE!=2) $fatal(1,"Bad C address transaction");
      aw_seen<=1; write_addr<=m_axi_gmem2_AWADDR;
    end
    if(m_axi_gmem2_WVALID&&m_axi_gmem2_WREADY) begin
      if(w_seen||!m_axi_gmem2_WLAST||m_axi_gmem2_WSTRB!=4'hf) $fatal(1,"Bad C data transaction");
      w_seen<=1; write_data<=m_axi_gmem2_WDATA ^ ($test$plusargs("CORRUPT_AXI_OUTPUT")?32'd1:32'd0);
    end
    if(aw_seen&&w_seen&&!m_axi_gmem2_BVALID&&b_delay==0) begin
      if(write_addr<BASE_C||write_addr>=(BASE_C+64'h100)) $fatal(1,"Bad C address");
      mem_c[(write_addr-BASE_C)>>2]<=write_data; writes<=writes+1;
      aw_seen<=0;w_seen<=0;b_delay<=3;
    end
    if(b_delay>0) begin
      b_delay<=b_delay-1;
      if(b_delay==1) begin m_axi_gmem2_BVALID<=1;m_axi_gmem2_BRESP<=inject_error==4?2:0;end
    end
    if(m_axi_gmem2_BVALID&&m_axi_gmem2_BREADY) m_axi_gmem2_BVALID<=0;
    if(a_delay>0) begin a_delay<=a_delay-1;if(a_delay==1)m_axi_gmem0_RVALID<=1;end
    if(read_b_delay>0) begin read_b_delay<=read_b_delay-1;if(read_b_delay==1)m_axi_gmem1_RVALID<=1;end
  end
end
always @(negedge ap_clk) begin
  if(ap_rst_n) begin
    m_axi_gmem0_ARREADY=(cycle%5==0)&&!m_axi_gmem0_RVALID&&a_delay==0;
    m_axi_gmem1_ARREADY=(cycle%7==0)&&!m_axi_gmem1_RVALID&&read_b_delay==0;
    m_axi_gmem2_AWREADY=(cycle%5==0)&&!aw_seen&&!m_axi_gmem2_BVALID;
    m_axi_gmem2_WREADY=(cycle%3==0)&&!w_seen&&!m_axi_gmem2_BVALID;
  end
end
task automatic wr(input logic[5:0] addr,input logic[31:0] data,input logic[3:0] mask=4'hf);
  control_writes=control_writes+1;
  fork
    begin
      repeat(control_writes%2==0?1:3) @(negedge ap_clk);
      s_axi_control_AWADDR=addr;s_axi_control_AWVALID=1;
      do @(posedge ap_clk); while(!s_axi_control_AWREADY);
      @(negedge ap_clk);s_axi_control_AWVALID=0;
    end
    begin
      repeat(control_writes%2==0?3:1) @(negedge ap_clk);s_axi_control_WDATA=data;s_axi_control_WSTRB=mask;s_axi_control_WVALID=1;
      do @(posedge ap_clk); while(!s_axi_control_WREADY);
      @(negedge ap_clk);s_axi_control_WVALID=0;
    end
  join
  repeat(2) @(negedge ap_clk);s_axi_control_BREADY=1;
  do @(posedge ap_clk); while(!s_axi_control_BVALID);
  if(s_axi_control_BRESP!=0) $fatal(1,"Control BRESP");
  @(negedge ap_clk);s_axi_control_BREADY=0;
endtask
task automatic rd(input logic[5:0] addr,output logic[31:0] data);
  @(negedge ap_clk);s_axi_control_ARADDR=addr;s_axi_control_ARVALID=1;
  do @(posedge ap_clk); while(!s_axi_control_ARREADY);
  @(negedge ap_clk);s_axi_control_ARVALID=0;
  repeat(2) @(negedge ap_clk);s_axi_control_RREADY=1;
  do @(posedge ap_clk); while(!s_axi_control_RVALID);
  data=s_axi_control_RDATA;
  @(negedge ap_clk);s_axi_control_RREADY=0;
endtask
task automatic check_case(input integer n,input integer error_code);
  logic [31:0] status,error_value;
  integer before_writes,before_reads;
  dim=n;inject_error=error_code;before_writes=writes;before_reads=reads;
  for(integer i=0;i<64;i=i+1) begin
    mem_a[i]=32'h80000000+i*997;mem_b[i]=(i%3==0)?32'hffffffff:i*73;mem_c[i]=32'hdeadc0de;expected[i]=0;
  end
  if(n>0&&n<=8) for(integer i=0;i<n;i=i+1) for(integer j=0;j<n;j=j+1)
    for(integer k=0;k<n;k=k+1) expected[i*n+j]=expected[i*n+j]+mem_a[i*n+k]*mem_b[k*n+j];
  wr(6'h10,32'h1000);wr(6'h14,1);wr(6'h1c,32'h2000);wr(6'h20,2);
  wr(6'h28,32'h3000);wr(6'h2c,3);wr(6'h34,n);wr(6'h00,1);
  if(n==8 && error_code==0) begin
    wr(6'h04,0);wr(6'h04,1); // XRT may switch polling/interrupt mode during execution.
  end
  status=0;
  while(!status[1]) rd(6'h00,status);
  if(!status[2]||!status[3]) $fatal(1,"Done must report idle and ready");
  rd(6'h38,error_value);
  if(error_value!==error_code) $fatal(1,"Error register got %0d expected %0d",error_value,error_code);
  if(error_code==0) begin
    if(writes-before_writes!=n*n) $fatal(1,"Incorrect output write count");
    for(integer i=0;i<n*n;i=i+1)
      if(mem_c[i]!==expected[i]) $fatal(1,"Mismatch dim=%0d index=%0d got=%h expected=%h",n,i,mem_c[i],expected[i]);
  end
  if(error_code==1 && (writes!=before_writes||reads!=before_reads)) $fatal(1,"Invalid dimension wrote memory");
  rd(6'h00,status);if(status[1]) $fatal(1,"ap_done clear-on-read failed");
  rd(6'h04,status);
  if(status[0]) begin
    if(!interrupt) $fatal(1,"Missing completion interrupt");
    rd(6'h0c,status);if(!status[0])$fatal(1,"Missing ISR status");
    wr(6'h04,0);if(interrupt)$fatal(1,"GIE disable did not suppress registered interrupt");
    rd(6'h0c,status);if(!status[0])$fatal(1,"GIE change must preserve sticky ISR");
    wr(6'h04,1);if(!interrupt)$fatal(1,"GIE re-enable did not restore pending interrupt");
    wr(6'h0c,1);if(interrupt)$fatal(1,"ISR acknowledge did not clear interrupt");
  end
  tests=tests+1;$display("AXI_CASE_PASS dim=%0d error=%0d",n,error_code);
endtask
initial begin
  init_inputs();m_axi_gmem0_RLAST=1;m_axi_gmem1_RLAST=1;
  repeat(5) @(negedge ap_clk);ap_rst_n=1;
  wr(6'h10,32'h11223344);wr(6'h10,32'haabbccdd,4'b0010);rd(6'h10,control_readback);
  if(control_readback!==32'h1122cc44)$fatal(1,"WSTRB write merge failed");
  wr(6'h04,1);wr(6'h08,1);
  check_case(1,0);check_case(3,0);check_case(4,0);check_case(5,0);check_case(8,0);
  check_case(0,1);check_case(9,1);check_case(2,2);check_case(2,3);check_case(2,4);
  check_case(3,0);
  // Abort an active read transfer with a platform reset, then verify a new job.
  inject_error=0;wr(6'h34,8);wr(6'h00,1);
  wait(m_axi_gmem0_ARVALID);@(negedge ap_clk);ap_rst_n=0;
  repeat(5) @(negedge ap_clk);ap_rst_n=1;
  check_case(4,0);
  $display("SYSBASE_AXI_TEST_PASS tests=%0d cycles=%0d writes=%0d",tests,cycle,writes);$finish;
end
endmodule
