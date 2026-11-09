// mmul_xcel.v: Matrix Multiply Accelerator Wrapper
// Top-level module that interfaces with the CPU via CSRs and
// with memory via a simple read/write bus. It instantiates
// a control FSM, two load units, the systolic array (SysBase),
// and a store unit to perform N×N matrix multiplication.

module mmulXcel (
  input  wire        clk,         // Global clock
  input  wire        reset,       // Active-high synchronous reset

  // --------------------------------------------------------------
  // CSR Interface (xcelreq/xcelresp) between CPU and accelerator
  // --------------------------------------------------------------
  input  wire        xcelreq_val,  // CPU has issued a CSR request
  input  wire [31:0] xcelreq_data, // CSR request data (upper bits = index)
  output reg         xcelresp_val, // Accelerator response valid
  output reg  [31:0] xcelresp_data,// Accelerator response data
  output wire        xcelreq_rdy,  // Accelerator ready for next request
  input  wire        xcelresp_rdy, // CPU ready for response

  // --------------------------------------------------------------
  // Memory Interface (read/write requests to Data Cache)
  // --------------------------------------------------------------
  output wire        memreq_val,   // Memory request valid
  output wire        memreq_rw,    // Read(0)/Write(1) flag
  output wire [31:0] memreq_addr,  // Memory request address
  output wire [31:0] memreq_data,  // Write data for store ops
  input  wire        memreq_rdy,   // Memory port ready
  input  wire        memresp_val,  // Memory response valid
  input  wire [31:0] memresp_data, // Data returned from memory
  output wire        memresp_rdy   // Ready to accept response
);

  // ===================================================================
  // 1) CSR-Backed Configuration Registers
  // ===================================================================
  reg [31:0] A_base;   // Base address of matrix A
  reg [31:0] B_base;   // Base address of matrix B
  reg [31:0] C_base;   // Base address for storing result C
  reg [31:0] dim;      // Matrix dimension N (for N×N multiply)
  reg        go;       // Write 1 to start a new operation
  reg        done;     // Read-only flag: 1 when operation completes

  // Always ready to accept CSR requests
  assign xcelreq_rdy = 1'b1;
  // Always ready to accept memory responses
  assign memresp_rdy = 1'b1;

  // ===================================================================
  // 2) CSR Handling: Write/Read to configuration registers
  // ===================================================================
  always @(posedge clk or posedge reset) begin
    if (reset) begin
      // On reset, clear all registers and response signals
      A_base       <= 32'd0;
      B_base       <= 32'd0;
      C_base       <= 32'd0;
      dim          <= 32'd0;
      go           <= 1'b0;
      done         <= 1'b0;
      xcelresp_val <= 1'b0;
      xcelresp_data<= 32'd0;
    end else begin
      // If CPU presents a new CSR request...
      if (xcelreq_val && xcelreq_rdy) begin
        // Decode CSR index from upper bits [31:28]
        case (xcelreq_data[31:28])
          4'h1: A_base <= xcelreq_data;               // CSR1 = A_base
          4'h2: B_base <= xcelreq_data;               // CSR2 = B_base
          4'h3: C_base <= xcelreq_data;               // CSR3 = C_base
          4'h4: dim    <= xcelreq_data;               // CSR4 = dim (N)
          4'h0: begin                                 // CSR0 = GO / STATUS
            go <= xcelreq_data[0];                   // LSB = start flag
            if (xcelreq_data[0]) done <= 1'b0;       // clear done on new GO
          end
          default: ; // ignore other CSRs
        endcase
      end

      // Always respond with the same cycle
      xcelresp_val <= xcelreq_val;
      if (xcelresp_val && xcelresp_rdy) begin
        // Put data back onto bus based on index
        case (xcelreq_data[31:28])
          4'h0: xcelresp_data <= {31'd0, done};     // STATUS in CSR0
          4'h1: xcelresp_data <= A_base;
          4'h2: xcelresp_data <= B_base;
          4'h3: xcelresp_data <= C_base;
          4'h4: xcelresp_data <= dim;
          default: xcelresp_data <= 32'd0;
        endcase
      end
    end
  end

  // ===================================================================
  // 3) Control FSM: Orchestrates Load → Compute → Store → Done
  // ===================================================================
  wire start_loadA, start_loadB, start_compute, start_store, fsm_done;
  control_fsm u_ctrl (
    .clk(clk),
    .reset(reset),
    .go(go),
    .compute_done(fsm_done), // toggles when store finishes
    .start_loadA(start_loadA),
    .start_loadB(start_loadB),
    .start_compute(start_compute),
    .start_store(start_store)
  );

  // Latch done from FSM
  always @(posedge clk or posedge reset) begin
    if (reset) done <= 1'b0;
    else if (fsm_done) done <= 1'b1;
  end

  // ===================================================================
  // 4) Load Units: Stream data for A and B into the systolic array
  // ===================================================================
  // Load Unit for A:
  load_unit u_loadA (
    .clk(clk), .reset(reset),
    .start(start_loadA),
    .base_addr(A_base),
    .length(dim*dim),
    // Memory ports:
    .memreq_val(memreq_val), .memreq_rw(memreq_rw),
    .memreq_addr(memreq_addr), .memreq_data(memreq_data),
    .memreq_rdy(memreq_rdy),
    .memresp_val(memresp_val), .memresp_data(memresp_data),
    .memresp_rdy(memresp_rdy),
    // Stream ports into SysBase:
    .stream_val(istreamA_val), .stream_rdy(istreamA_rdy),
    .stream_msg(istreamA_msg)
  );

  // Load Unit for B (identical interface):
  load_unit u_loadB (
    .clk(clk), .reset(reset),
    .start(start_loadB),
    .base_addr(B_base),
    .length(dim*dim),
    .memreq_val(), .memreq_rw(),
    .memreq_addr(), .memreq_data(),
    .memreq_rdy(memreq_rdy),
    .memresp_val(memresp_val), .memresp_data(memresp_data),
    .memresp_rdy(memresp_rdy),
    .stream_val(istreamB_val), .stream_rdy(istreamB_rdy),
    .stream_msg(istreamB_msg)
  );

  // ===================================================================
  // 5) Systolic Array Core: SysBase (uses MacNew PEs internally)
  // ===================================================================
  SysBase #(.SIZE(/* parameterize as needed */)) u_sa (
    .clk(clk), .reset(reset),
    .istreamA_val(istreamA_val), .istreamA_rdy(istreamA_rdy),
    .istreamA_msg(istreamA_msg),
    .istreamB_val(istreamB_val), .istreamB_rdy(istreamB_rdy),
    .istreamB_msg(istreamB_msg),
    .ostreamA_val(ostreamA_val), .ostreamA_rdy(ostreamA_rdy),
    .ostreamA_msg(ostreamA_msg),
    .ostreamB_val(ostreamB_val), .ostreamB_rdy(ostreamB_rdy),
    .ostreamB_msg(ostreamB_msg)
  );

  // ===================================================================
  // 6) Store Unit: Write results back to memory from systolic array
  // ===================================================================
  store_unit u_store (
    .clk(clk), .reset(reset),
    .start(start_store),
    .base_addr(C_base),
    .length(dim*dim),
    .stream_val(ostreamA_val), .stream_rdy(ostreamA_rdy),
    .stream_msg(ostreamA_msg),
    .memreq_val(), .memreq_rw(),
    .memreq_addr(), .memreq_data(),
    .memreq_rdy(memreq_rdy),
    .memresp_val(memresp_val), .memresp_rdy(memresp_rdy)
  );

endmodule
