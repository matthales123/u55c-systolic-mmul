// control_fsm.v: Control finite-state machine for mmul_xcel accelerator
// This FSM sequences the operations: LOAD_A → LOAD_B → COMPUTE → STORE → DONE
// Signals:
// - go: input pulse from CSR to start a new operation
// - compute_done: input from systolic array/store unit indicating compute/store completion
// - start_loadA, start_loadB, start_compute, start_store: one-cycle pulses to submodules
// - done_flag: pulses high one cycle when entire operation finishes

module control_fsm (
  input  wire clk,             // Global clock
  input  wire reset,           // Active-high asynchronous reset
  input  wire go,              // Start signal from CSR
  input  wire compute_done,    // Indicates compute/store stage completion
  output reg  start_loadA,     // Pulse: start reading A operands
  output reg  start_loadB,     // Pulse: start reading B operands
  output reg  start_compute,   // Pulse: enable systolic array compute
  output reg  start_store,     // Pulse: start writing results
  output reg  done_flag        // Pulse: operation finished
);

  // Define states for the FSM
  typedef enum logic [2:0] {
    IDLE      = 3'd0,
    LOAD_A    = 3'd1,
    LOAD_B    = 3'd2,
    COMPUTE   = 3'd3,
    STORE     = 3'd4,
    DONE      = 3'd5
  } state_t;

  state_t curr_state, next_state;

  // State register: update on clock or reset
  always @(posedge clk or posedge reset) begin
    if (reset) curr_state <= IDLE;  // Return to IDLE on reset
    else        curr_state <= next_state;
  end

  // Next-state and output logic
  always @(*) begin
    // Default: deassert all start pulses and done
    start_loadA  = 1'b0;
    start_loadB  = 1'b0;
    start_compute= 1'b0;
    start_store  = 1'b0;
    done_flag    = 1'b0;

    case (curr_state)
      IDLE: begin
        if (go) next_state = LOAD_A;
        else     next_state = IDLE;
      end

      LOAD_A: begin
        start_loadA  = 1'b1; // Tell load_unit A to begin
        next_state   = LOAD_B;
      end

      LOAD_B: begin
        start_loadB  = 1'b1; // Tell load_unit B to begin
        next_state   = COMPUTE;
      end

      COMPUTE: begin
        start_compute  = 1'b1;       // Enable compute stage
        // Wait for systolic array to finish
        if (compute_done) next_state = STORE;
        else              next_state = COMPUTE;
      end

      STORE: begin
        start_store   = 1'b1;        // Begin storing results
        // Wait for final results written
        if (compute_done) next_state = DONE;
        else              next_state = STORE;
      end

      DONE: begin
        done_flag    = 1'b1;         // Indicate operation complete
        next_state   = IDLE;         // Return to idle afterwards
      end

      default: begin
        // Should never happen: reset to IDLE
        next_state = IDLE;
      end
    endcase
  end

endmodule
