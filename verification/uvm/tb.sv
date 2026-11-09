`timescale 1ns/1ps
module mmul_uvm_tb;
  import uvm_pkg::*;
  import mmul_pkg::*;
  logic clk=0;
  always #5 clk=~clk;
  mmul_if bus(clk);
  logic[31:0] raw_out_data;
  bit break_protocol;
  int cycle_id=0;
  initial break_protocol=$test$plusargs("BREAK_PROTOCOL");
  always @(negedge clk) cycle_id<=cycle_id+1;
  // Negative control perturbs only the observation boundary, never the RTL source.
  assign bus.out_data=raw_out_data ^ ((break_protocol && bus.out_valid && !bus.out_ready && cycle_id[0])?32'b1:32'b0);
  mmul_sysbase_axis_shell #(.DATA_WIDTH(32),.DIM_WIDTH(8),.ARRAY_SIZE(4),.MAX_DIM(8)) dut(
    .ap_clk(clk),.ap_rst_n(bus.rst_n),.ap_start(bus.start),.cfg_dim(bus.dim),
    .ap_done(bus.done),.ap_idle(bus.idle),.ap_ready(bus.ready),.ap_busy(bus.busy),
    .s_axis_in_tvalid(bus.in_valid),.s_axis_in_tready(bus.in_ready),.s_axis_in_tdata(bus.in_data),
    .m_axis_out_tvalid(bus.out_valid),.m_axis_out_tready(bus.out_ready),.m_axis_out_tdata(raw_out_data));
  initial begin
    uvm_config_db#(virtual mmul_if)::set(null,"*","vif",bus);
    run_test("matrix_test");
  end
  initial begin #10000000;$fatal(1,"MMUL_WATCHDOG_TIMEOUT");end
endmodule
