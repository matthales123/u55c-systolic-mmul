//========================================================================
// Multiply accumalate unit with single cycle multiplier
//========================================================================

`ifndef SYSTOLIC_SYSBASE_V
`define SYSTOLIC_SYSBASE_V

`include "vc/trace.v"
`include "vc/muxes.v"
`include "vc/arithmetic.v"
`include "vc/regs.v"

`include "systolic/IntMulBase.v"
`include "systolic/MacNew.v"


module systolic_SysBase #( parameter SIZE = 5 )
(
  input  logic        clk,
  input  logic        reset,

  // input  logic        give_result,

  input  logic         istreamA_val [SIZE],
  output logic         istreamA_rdy [SIZE],
  input  logic [32:0]  istreamA_msg [SIZE],
 
  input  logic         istreamB_val [SIZE],
  output logic         istreamB_rdy [SIZE],
  input  logic [32:0]  istreamB_msg [SIZE],

  output  logic        ostreamA_val [SIZE],
  input   logic        ostreamA_rdy [SIZE],
  output  logic [32:0] ostreamA_msg [SIZE],

  output  logic        ostreamB_val [SIZE],
  input   logic        ostreamB_rdy [SIZE],
  output  logic [32:0] ostreamB_msg [SIZE] 

);

  logic [32:0] west2east_msg       [SIZE:0][SIZE+1:0];
  logic        west2east_rdy       [SIZE:0][SIZE+1:0];
  logic        west2east_val       [SIZE:0][SIZE+1:0];

  logic [32:0] north2south_msg     [SIZE+1:0][SIZE:0];
  logic        north2south_rdy     [SIZE+1:0][SIZE:0];
  logic        north2south_val     [SIZE+1:0][SIZE:0];


  genvar i, j;
  for (i = 0; i < SIZE; i++) begin
    for (j = 0; j < SIZE; j++) begin
      systolic_MacNew pe
      (
        .clk              (clk),
        .reset            (reset),

        // .give_result     (  give_result                ),

        .istreamA_val    (  west2east_val[i][j]        ),
        .istreamA_rdy    (  west2east_rdy[i][j]        ),
        .istreamA_msg    (  west2east_msg[i][j]        ),
 
        .istreamB_val    (  north2south_val[i][j]      ),
        .istreamB_rdy    (  north2south_rdy[i][j]      ),
        .istreamB_msg    (  north2south_msg[i][j]      ),
 
        .ostreamA_val    (  west2east_val[i][j+1]      ),
        .ostreamA_rdy    (  west2east_rdy[i][j+1]      ),
        .ostreamA_msg    (  west2east_msg[i][j+1]      ),

        .ostreamB_val    (  north2south_val[i+1][j]    ),
        .ostreamB_rdy    (  north2south_rdy[i+1][j]    ),
        .ostreamB_msg    (  north2south_msg[i+1][j]    )

      );
    end
  end

  // Generate block for A inputs
  generate
    for (i = 0; i < SIZE; i++) begin
      assign west2east_msg[i][0] = istreamA_msg[i];
      assign west2east_val[i][0] = istreamA_val[i];
      assign istreamA_rdy[i] = west2east_rdy[i][0];
    end
  endgenerate
  
  // Generate block for B inputs
  generate
    for (i = 0; i < SIZE; i++) begin 
      assign north2south_msg[0][i] = istreamB_msg[i];
      assign north2south_val[0][i] = istreamB_val[i];
      assign istreamB_rdy[i] = north2south_rdy[0][i];
    end
  endgenerate
  
  
  // Generate block for output stream A connections
  generate
    for (i = 0; i < SIZE; i++) begin
      assign ostreamA_msg[i] = west2east_msg[i][SIZE];
      assign ostreamA_val[i] = west2east_val[i][SIZE];
      assign west2east_rdy[i][SIZE] = ostreamA_rdy[i];
    end
  endgenerate
  
  // Generate block for output stream B connections
  generate
      for (i = 0; i < SIZE; i++) begin
          assign ostreamB_msg[i] = north2south_msg[SIZE][i];
          assign ostreamB_val[i] = north2south_val[SIZE][i];
          assign north2south_rdy[SIZE][i] = ostreamB_rdy[i];
      end
  endgenerate



  `ifndef SYNTHESIS

  logic [`VC_TRACE_NBITS-1:0] str;
  logic [`VC_TRACE_NBITS-1:0] state_str;
  `VC_TRACE_BEGIN
  begin

    vc_trace.append_str( trace_str, "(" );
    $sformat( str, "%x", west2east_msg[0][1] );
    vc_trace.append_val_rdy_str( trace_str, west2east_val[0][1], west2east_rdy[0][1], str );
    // vc_trace.append_str( trace_str, ")" );

    vc_trace.append_str( trace_str, "(" );
    $sformat( str, "%x", west2east_msg[0][2] );
    vc_trace.append_val_rdy_str( trace_str, west2east_val[0][2], west2east_rdy[0][2], str );
    // vc_trace.append_str( trace_str, ")" );

    vc_trace.append_str( trace_str, "(" );
    $sformat( str, "%x", west2east_msg[0][3] );
    vc_trace.append_val_rdy_str( trace_str, west2east_val[0][3], west2east_rdy[0][3], str );
    // vc_trace.append_str( trace_str, ")" );

    vc_trace.append_str( trace_str, "||" );
    vc_trace.append_str( trace_str, "(" );
    $sformat( str, "%x", ostreamA_msg[0] );
    vc_trace.append_val_rdy_str( trace_str, ostreamA_val[0], ostreamA_rdy[0], str );
    vc_trace.append_str( trace_str, "||" );


    // vc_trace.append_str( trace_str, "(" );
    $sformat( str, " %x", north2south_msg[1][0] );
    vc_trace.append_val_rdy_str( trace_str, north2south_val[1][0], north2south_rdy[1][0], str );
    vc_trace.append_str( trace_str, ")" );

    // vc_trace.append_str( trace_str, "(" );
    $sformat( str, " %x", north2south_msg[2][0] );
    vc_trace.append_val_rdy_str( trace_str, north2south_val[2][0], north2south_rdy[2][0], str );
    vc_trace.append_str( trace_str, ")" );

    // vc_trace.append_str( trace_str, "(" );
    $sformat( str, " %x", north2south_msg[3][0] );
    vc_trace.append_val_rdy_str( trace_str, north2south_val[3][0], north2south_rdy[3][0], str );
    vc_trace.append_str( trace_str, ")" );

    vc_trace.append_str( trace_str, "||" );
    $sformat( str, " %x", ostreamB_msg[0] );
    vc_trace.append_val_rdy_str( trace_str, ostreamB_val[0], ostreamB_rdy[0], str );
    vc_trace.append_str( trace_str, "||" );
  


  end
  `VC_TRACE_END

  `endif /* SYNTHESIS */

endmodule

`endif /* SYSTOLIC_SYSBASE_V */

