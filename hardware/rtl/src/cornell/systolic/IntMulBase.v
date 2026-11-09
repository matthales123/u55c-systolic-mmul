//========================================================================
// 2 input Integer Multiplier Fixed-Latency Implementation
//========================================================================

`ifndef SYSTOLIC_INT_MUL_BASE_V
`define SYSTOLIC_INT_MUL_BASE_V

`include "../vc/trace.v"
`include "../vc/muxes.v"
`include "../vc/arithmetic.v"

// datapath and control unit defined here
module control_unit(
  input logic clk, 
  input logic reset, 
  input logic b_lsb, 
  input logic istreamA_val,
  input logic istreamB_val,

  input logic ostream_rdy,
  output logic b_mux_sel, 
  output logic a_mux_sel, 
  output logic add_mux_sel, 
  output logic res_mux_sel, 
  output logic ostream_val, 
  output logic istreamA_rdy, 
  output logic istreamB_rdy,
  output logic[1:0] state
);

  
  logic[1:0] next_state;
  logic[6:0] counter;
  localparam IDLE = 2'b00;
  localparam CALC = 2'b01;
  localparam DONE = 2'b10;

  //next state sequential logic
  always @ (posedge clk) begin
    if (reset) state <= IDLE;
    else state <= next_state; 
    if (state == CALC) counter <= counter + 1;
    else counter <= 1'b0;
  end

  //combinational logic to CALCulate next state
  always @ (*) begin
    case(state)
      IDLE: begin
        if(istreamA_val && istreamB_val) next_state = CALC;
        else next_state = IDLE;
      end
      CALC: begin
        if(counter <= 6'b011110) next_state = CALC;
        else next_state = DONE;
      end
      DONE: begin 
        if (ostream_rdy) next_state = IDLE;
        else next_state = DONE;
      end
      default: begin 
      end
    endcase
  end

  //combinational logic to CALCulate output 
  always @ (*) begin
    if (state == DONE) begin 
      ostream_val = 1'b1;
      add_mux_sel = 1'b0;
    end 
    else begin 
      ostream_val = 1'b0;
      if (b_lsb) add_mux_sel = 1'b1;
      else add_mux_sel = 1'b0;
    end 
    if (state == IDLE) begin 
      b_mux_sel = 1'b0;
      a_mux_sel = 1'b0;
      res_mux_sel = 1'b0;
      istreamA_rdy = 1'b1;
      istreamB_rdy = 1'b1;
    end 
    else begin 
      b_mux_sel = 1'b1;
      a_mux_sel = 1'b1;
      res_mux_sel = 1'b1;
      istreamA_rdy = 1'b0;
      istreamB_rdy = 1'b0;
    end 
  end
  

endmodule 

module datapath(
  input  logic clk,
  input  logic reset,
  input  logic [31:0] istreamA_msg,
  input  logic [31:0] istreamB_msg,
  input logic b_mux_sel, 
  input logic a_mux_sel, 
  input logic add_mux_sel, 
  input logic res_mux_sel, 

  output logic [31:0] ostream_msg, 
  output logic b_lsb
);

  logic[31:0] a_reg; 
  logic[31:0] b_reg; 
  logic[31:0] res_reg;
  logic[31:0] input_a = istreamA_msg; 
  logic[31:0] input_b = istreamB_msg;
  logic[31:0] b_shift_out;
  logic[31:0] b_mux_out; 
  logic[31:0] a_mux_out; 
  logic[31:0] a_shift_out; 
  logic[31:0] res_mux_out; 
  logic[31:0] add_mux_out;
  logic[31:0] adder_out;
 
  

  vc_Mux2#(32) bMux(
    .in0(input_b), 
    .in1(b_shift_out), 
    .sel(b_mux_sel),
    .out(b_mux_out)
  );

  vc_Mux2#(32)  aMux(
    .in0(input_a), 
    .in1(a_shift_out), 
    .sel(a_mux_sel),
    .out(a_mux_out)
  );

  vc_Mux2#(32) resultMux(
    .in0(32'b0), 
    .in1(add_mux_out), 
    .sel(res_mux_sel),
    .out(res_mux_out)
  );



  vc_Mux2#(32) addMux(
    .in0(res_reg), 
    .in1(adder_out), 
    .sel(add_mux_sel),
    .out(add_mux_out)
  );

  vc_LeftLogicalShifter#(32)  a_shifter(
    .in(a_reg), 
    .shamt(1'b1), 
    .out(a_shift_out)
  );

  vc_RightLogicalShifter#(32)  b_shifter(
    .in(b_reg), 
    .shamt(1'b1), 
    .out(b_shift_out)
  );

  vc_SimpleAdder#(32)  adder(
    .in0(a_reg), 
    .in1(res_reg), 
    .out(adder_out)
  );

  always @(posedge clk) begin 
    b_reg <= b_mux_out; 
    a_reg <= a_mux_out; 
    res_reg <= res_mux_out;
  end 

  always @(*) begin 
    b_lsb = b_reg[0];
    ostream_msg = res_reg;
  end 

endmodule

//========================================================================
// 2 input Integer Multiplier Fixed-Latency Implementation
//========================================================================

module systolic_IntMulBase
(
  input  logic        clk,
  input  logic        reset,

  input  logic        istreamA_val,
  output logic        istreamA_rdy,
  input  logic [31:0] istreamA_msg,

  input  logic        istreamB_val,
  output logic        istreamB_rdy,
  input  logic [31:0] istreamB_msg,

  output logic        ostream_val,
  input  logic        ostream_rdy,
  output logic [31:0] ostream_msg
);

  // datapath and control models instantiated here

  logic b_lsb; 
  logic a_mux_sel; 
  logic add_mux_sel; 
  logic res_mux_sel; 
  logic b_mux_sel; 
  logic[1:0] state;

  control_unit control(.*);
  datapath data( .* );
  

  //----------------------------------------------------------------------
  // Line Tracing
  //----------------------------------------------------------------------

  `ifndef SYNTHESIS

  logic [`VC_TRACE_NBITS-1:0] str;
  logic [`VC_TRACE_NBITS-1:0] state_str;
  `VC_TRACE_BEGIN
  begin

    vc_trace.append_str( trace_str, "(" );
    $sformat( str, "%x", istreamA_msg );
    vc_trace.append_val_rdy_str( trace_str, istreamA_val, istreamA_rdy, str );
    vc_trace.append_str( trace_str, ")" );
    
    vc_trace.append_str( trace_str, "(" );
    $sformat( str, "%x", istreamB_msg );
    vc_trace.append_val_rdy_str( trace_str, istreamB_val, istreamB_rdy, str );
    vc_trace.append_str( trace_str, ")" );

    vc_trace.append_str( trace_str, "(" );

    $sformat( state_str, "%x", state); 
    vc_trace.append_str( state_str, "!" );

    vc_trace.append_str( trace_str, ")" );

    $sformat( str, "%x", ostream_msg );
    vc_trace.append_val_rdy_str( trace_str, ostream_val, ostream_rdy, str );

  end
  `VC_TRACE_END

  `endif /* SYNTHESIS */

endmodule

`endif /* SYSTOLIC_INT_MUL_BASE_V */

