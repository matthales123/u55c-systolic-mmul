// store_unit.v: Collects streamed results from the systolic array and
// writes them back to memory. Uses valid/ready handshake on both sides.

module store_unit (
  input  wire        clk,            // Global clock
  input  wire        reset,          // Active-high reset
  input  wire        start,          // Pulse to begin store operation
  input  wire [31:0] base_addr,      // Starting address for results
  input  wire [31:0] length,         // Number of words to write

  // Stream interface from systolic array
  input  wire        stream_val,     // Data valid
  output reg         stream_rdy,     // Ready to accept data
  input  wire [32:0] stream_msg,     // {mode, data}

  // Memory write interface
  output reg         memreq_val,     // Request valid
  output reg         memreq_rw,      // Read(0)/Write(1): always 1 here
  output reg [31:0]  memreq_addr,    // Address to write
  output reg [31:0]  memreq_data,    // Data to write
  input  wire        memreq_rdy,     // Memory ready
  input  wire        memresp_val,    // Write acknowledge (if any)
  output wire        memresp_rdy     // We always accept response
);

  // Always ready for memory responses
  assign memresp_rdy = 1'b1;

  // Internal counters and flags
  reg [31:0] write_count;  // Words written so far
  reg        busy;         // Operation in progress

  // Sequential logic
  always @(posedge clk or posedge reset) begin
    if (reset) begin
      write_count  <= 32'd0;
      busy         <= 1'b0;
      stream_rdy   <= 1'b0;
      memreq_val   <= 1'b0;
      memreq_rw    <= 1'b0;
      memreq_addr  <= 32'd0;
      memreq_data  <= 32'd0;
    end else begin
      if (start && !busy) begin
        // Initialize for new store operation
        busy        <= 1'b1;
        write_count <= 32'd0;
        stream_rdy  <= 1'b1;   // ready to accept first result
      end else if (busy) begin
        // When a result arrives
        if (stream_val && stream_rdy) begin
          // Capture data and issue memory write
          memreq_val  <= 1'b1;
          memreq_rw   <= 1'b1;             // 1 = write
          memreq_addr <= base_addr + write_count*4;
          memreq_data <= stream_msg[31:0]; // lower 32 bits = result data
          stream_rdy  <= 1'b0;             // pause stream until written
        end

        // Once memory accepts write, advance
        if (memreq_val && memreq_rdy) begin
          memreq_val <= 1'b0;
          write_count <= write_count + 1;
          // If more remain, be ready for next stream
          if (write_count + 1 < length) begin
            stream_rdy <= 1'b1;
          end else begin
            // Done writing all
            busy <= 1'b0;
          end
        end
      end
    end
  end

endmodule
