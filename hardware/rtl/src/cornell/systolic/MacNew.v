//========================================================================
// Multiply accumalate unit with single cycle multiplier using input queues
//========================================================================

`ifndef SYSTOLIC_MACNEW_V
`define SYSTOLIC_MACNEW_V

`include "../vc/trace.v"
`include "../vc/muxes.v"
`include "../vc/arithmetic.v"
`include "../vc/regs.v"
`include "../vc/queues.v"


`include "systolic/IntMulBase.v"

module systolic_MacNew
(
  input  logic        clk,
  input  logic        reset,
  // input  logic        giveresult_msg,
  // input  logic        giveresult_val,
  // output  logic       giveresult_rdy,

  input  logic        istreamA_val,
  output logic        istreamA_rdy,
  input  logic [32:0] istreamA_msg,

  input  logic        istreamB_val,
  output logic        istreamB_rdy,
  input  logic [32:0] istreamB_msg,

  output  logic        ostreamA_val,
  input   logic        ostreamA_rdy,
  output  logic [32:0] ostreamA_msg,

  output  logic        ostreamB_val,
  input   logic        ostreamB_rdy,
  output  logic [32:0] ostreamB_msg

  // output logic        ostream_val,
  // input  logic        ostream_rdy,
  // output logic [31:0] ostream_msg
);

  logic [32:0] istreamA_deq_msg;
  logic        istreamA_deq_val;
  logic        istreamA_deq_rdy;

  logic [32:0] istreamB_deq_msg;
  logic        istreamB_deq_val;
  logic        istreamB_deq_rdy;

  logic        istream_giveresult_deq_msg;
  logic        istream_giveresult_deq_val;
  logic        istream_giveresult_deq_rdy;





  vc_Queue#(`VC_QUEUE_NORMAL,33,2) west_input_queue
  (
      .clk     (clk),
      .reset   (reset),
      .num_free_entries(),
  
      .enq_msg (istreamA_msg),
      .enq_val (istreamA_val),
      .enq_rdy (istreamA_rdy),
  
      .deq_msg (istreamA_deq_msg),
      .deq_val (istreamA_deq_val),
      .deq_rdy (istreamA_deq_rdy)
  );

  vc_Queue#(`VC_QUEUE_NORMAL,33,2) north_input_queue
  (
      .clk     (clk),
      .reset   (reset),
      .num_free_entries(),
  
      .enq_msg (istreamB_msg),
      .enq_val (istreamB_val),
      .enq_rdy (istreamB_rdy),
  
      .deq_msg (istreamB_deq_msg),
      .deq_val (istreamB_deq_val),
      .deq_rdy (istreamB_deq_rdy)
  );
  //   vc_Queue#(`VC_QUEUE_NORMAL,32,2) giveresult_queue
  // (
  //     .clk     (clk),
  //     .reset   (reset),
  //     .num_free_entries(),
  
  //     .enq_msg (giveresult_msg),
  //     .enq_val (giveresult_val),
  //     .enq_rdy (giveresult_rdy),
  
  //     .deq_msg (istream_giveresult_deq_msg),
  //     .deq_val (istream_giveresult_deq_val),
  //     .deq_rdy (istream_giveresult_deq_rdy)

  
  // );
  logic [31:0] accumalator_in;
  logic [31:0] accumalator_out;
  logic [31:0] tempA;
  logic [31:0] tempB;
  logic        result_en;
  logic        tempA_val;
  logic        tempB_val;
  
  logic        temp_val;
  logic        temp_rdy;
  logic        temp_result;
  logic [31:0] product;
  logic        go;
  logic        temp_give_result;






logic [31:0] mul_accum;
assign product = istreamA_deq_msg[31:0] * istreamB_deq_msg[31:0];
assign mul_accum = accumalator_out + product;
assign go = (ostreamB_rdy && ostreamA_rdy && istreamA_deq_val && istreamB_deq_val);

logic sel_result;
assign sel_result = istreamA_deq_msg[32] && istreamB_deq_msg[32];
// assign go = (ostreamB_rdy && ostreamA_rdy);


vc_Mux2#(32) feed_accum_mux(
  .in0(mul_accum),
  .in1(istreamB_deq_msg[31:0]),
  .sel(sel_result),
  .out(accumalator_in)
);


  
  vc_EnResetReg#(32) accum_reg
  (
    .clk   (clk),
    .reset (reset),
    .d     (accumalator_in),
    .en    (go),
    .q     (accumalator_out)
  );

  logic [32:0] ostreamA_msg_raw;
  logic [32:0] ostreamB_msg_raw;





  
  // output stream assignment logic
  
  vc_Mux2#(33) output_result_muxB(
      .in0({sel_result, istreamB_deq_msg[31:0]}),
      .in1({sel_result, accumalator_out}),
      .sel(sel_result),
      .out(ostreamB_msg_raw)

  );

    vc_Mux2#(33) output_result_muxA(
      .in0({sel_result, istreamA_deq_msg[31:0]}),
      .in1({sel_result, 32'b0}),
      .sel(sel_result),
      .out(ostreamA_msg_raw)

  );
  // assign ostreamA_msg = istreamA_deq_msg;

  // fix for 4 state simulation
  assign ostreamA_msg = ostreamA_msg_raw & {33{ostreamA_val}};
  assign ostreamB_msg = ostreamB_msg_raw & {33{ostreamB_val}};

  //Valid Ready signal assignments
  assign ostreamA_val                = istreamA_deq_val && istreamB_deq_val && ostreamB_rdy; 
  assign ostreamB_val                = istreamA_deq_val && istreamB_deq_val && ostreamA_rdy;
  assign istreamA_deq_rdy            = istreamB_deq_val && ostreamA_rdy && ostreamB_rdy;
  assign istreamB_deq_rdy            = istreamA_deq_val && ostreamA_rdy && ostreamB_rdy;
  // assign istream_giveresult_deq_rdy  = go;


// istreamA_deq_val && istreamB_deq_val && ostreamA_rdy && ostreamB_rdy;
// istreamA_deq_val && istreamB_deq_val && ostreamA_rdy && ostreamB_rdy;
// ostreamA_rdy && ostreamB_rdy &&ostreamA_val && ostreamB_val;
// ostreamA_rdy && ostreamB_rdy &&ostreamA_val && ostreamB_val;
// ostreamA_rdy && ostreamB_rdy && ostreamA_val && ostreamB_val ;
  //----------------------------------------------------------------------
  // Line Tracing
  //----------------------------------------------------------------------

  `ifndef SYNTHESIS

  logic [`VC_TRACE_NBITS-1:0] str;
  logic [`VC_TRACE_NBITS-1:0] state_str;
  `VC_TRACE_BEGIN
  begin

    vc_trace.append_str( trace_str, "(" );
    $sformat( str, "%x", istreamA_deq_msg );
    vc_trace.append_val_rdy_str( trace_str, istreamA_deq_val, istreamA_deq_rdy, str );
    vc_trace.append_str( trace_str, ")" );
    
    vc_trace.append_str( trace_str, "(" );
    $sformat( str, "%x", istreamB_deq_msg );
    vc_trace.append_val_rdy_str( trace_str, istreamB_deq_val, istreamB_deq_rdy, str );
    vc_trace.append_str( trace_str, ")" );


    // vc_trace.append_str( trace_str, "(" );
    // $sformat( str, "%x", a_reg_out );
    // vc_trace.append_str( trace_str, str );
    // vc_trace.append_str( trace_str, ")" );
    
    // vc_trace.append_str( trace_str, "(" );
    // $sformat( str, "%x", b_reg_out );
    // vc_trace.append_str( trace_str, str );
    // vc_trace.append_str( trace_str, ")" );

    // vc_trace.append_str( trace_str, "(" );
    // $sformat( str, "%x", temp_val );
    // vc_trace.append_str( trace_str, str );
    // $sformat( str, " %x", mul_val_out );
    // vc_trace.append_str( trace_str, str );
// 
    // vc_trace.append_str( trace_str, ")" );

    // $sformat( str, "%x ", ostream_msg );
    // vc_trace.append_val_rdy_str( trace_str, ostream_val, ostream_rdy, str );


    // vc_trace.append_str( trace_str, "(" );
    // $sformat( str, "%x", istream_giveresult_deq_msg );
    // vc_trace.append_val_rdy_str( trace_str, istream_giveresult_deq_val, istream_giveresult_deq_rdy, str );
    // vc_trace.append_str( trace_str, ")" );


    $sformat( str, "%x ", ostreamA_msg );
    vc_trace.append_val_rdy_str( trace_str, ostreamA_val, ostreamA_rdy, str );

    $sformat( str, "%x ", ostreamB_msg );
    vc_trace.append_val_rdy_str( trace_str, ostreamB_val, ostreamB_rdy, str );


  end
  `VC_TRACE_END

  `endif /* SYNTHESIS */

endmodule

`endif /* SYSTOLIC_MACNEW_V */

