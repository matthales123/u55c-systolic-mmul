// load_unit.v: Reads a sequence of words from memory and streams them
// into the systolic array. Uses a valid/ready handshake on both memory
// and stream interfaces.

module load_unit (
  input  wire        clk,            // Global clock
  input  wire        reset,          // Active-high reset
  input  wire        start,          // Pulse to begin operation
  input  wire [31:0] base_addr,      // Starting address in memory
  input  wire [31:0] length,         // Number of words to read

  // Memory read interface
  output reg         memreq_val,     // Request valid
  output reg         memreq_rw,      // Read(0)/Write(1): always 0 here
  output reg [31:0]  memreq_addr,    // Address for read
  output reg [31:0]  memreq_data,    // Unused for reads
  input  wire        memreq_rdy,     // Memory port ready
  input  wire        memresp_val,    // Memory returning data
  input  wire [31:0] memresp_data,   // Data from memory
  output wire        memresp_rdy,    // Always ready to accept data

  // Stream interface to systolic array
  output reg         stream_val,     // Data valid
  input  wire        stream_rdy,     // Systolic array ready
  output reg [32:0]  stream_msg      // {mode, data} message
);

  // We always accept memory responses
  assign memresp_rdy = 1'b1;

  // Internal counters and flags
  reg [31:0] read_count;   // Words fetched so far
  reg        busy;         // Operation in progress

  // Main sequential logic
  always @(posedge clk or posedge reset) begin
    if (reset) begin
      memreq_val   <= 1'b0;
      memreq_rw    <= 1'b0;
      memreq_addr  <= 32'd0;
      memreq_data  <= 32'd0;
      read_count   <= 32'd0;
      busy         <= 1'b0;
      stream_val   <= 1'b0;
      stream_msg   <= 33'd0;
    end else begin
      if (start && !busy) begin
        // Initialize for a new operation
        busy        <= 1'b1;
        read_count  <= 32'd0;
        // Issue first read request
        memreq_val  <= 1'b1;
        memreq_rw   <= 1'b0;             // 0 = read
        memreq_addr <= base_addr;
      end else if (busy) begin
        // Once the request is accepted, deassert memreq_val
        if (memreq_val && memreq_rdy) begin
          memreq_val <= 1'b0;
        end
        
        // On receiving memory data
        if (memresp_val) begin
          // Prepare a stream message: mode=0 (A/B tag), data=memresp_data
          stream_msg <= {1'b0, memresp_data};
          stream_val <= 1'b1;
        end

        // When stream handshake completes, advance
        if (stream_val && stream_rdy) begin
          stream_val <= 1'b0;
          // If more words remain, request next
          if (read_count + 1 < length) begin
            read_count  <= read_count + 1;
            memreq_val  <= 1'b1;
            memreq_addr <= base_addr + (read_count + 1)*4;
          end else begin
            // Done reading all words
            busy <= 1'b0;
          end
        end
      end
    end
  end

endmodule
