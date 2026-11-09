`timescale 1ns/1ps
interface mmul_if(input logic clk);
  logic rst_n=0, start=0;
  logic [7:0] dim=1;
  logic done, idle, ready, busy;
  logic in_valid=0, in_ready;
  logic [31:0] in_data=0;
  logic out_valid, out_ready=0;
  logic [31:0] out_data;
  // Stimulus classification only; arithmetic prediction never reads these tags.
  int pattern_tag=0, sink_mode=0;
  int sva_failures=0, output_hold_checks=0, input_hold_checks=0;

  ap_output_hold: assert property (@(posedge clk) disable iff (!rst_n)
    out_valid && !out_ready |=> out_valid && $stable(out_data))
    output_hold_checks++;
    else begin sva_failures++; $error("MMUL_SVA_OUTPUT_HOLD"); end
  ap_input_hold: assert property (@(posedge clk) disable iff (!rst_n)
    in_valid && !in_ready |=> in_valid && $stable(in_data))
    input_hold_checks++;
    else begin sva_failures++; $error("MMUL_SVA_INPUT_HOLD"); end
  ap_status: assert property (@(posedge clk) disable iff (!rst_n)
    (idle == !busy) && (ready == !busy))
    else begin sva_failures++; $error("MMUL_SVA_STATUS"); end
  ap_output_busy: assert property (@(posedge clk) disable iff (!rst_n)
    out_valid |-> busy)
    else begin sva_failures++; $error("MMUL_SVA_OUTPUT_BUSY"); end
  ap_done_idle: assert property (@(posedge clk) disable iff (!rst_n)
    done |-> !busy && !out_valid)
    else begin sva_failures++; $error("MMUL_SVA_DONE_IDLE"); end
  ap_reset: assert property (@(posedge clk)
    !rst_n |=> !out_valid && !busy && !done)
    else begin sva_failures++; $error("MMUL_SVA_RESET"); end
endinterface
