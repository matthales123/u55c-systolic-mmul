`timescale 1ns/1ps
package mmul_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  typedef enum int {EV_START,EV_INPUT,EV_OUTPUT,EV_DONE,EV_RESET} event_kind;

  class matrix_item extends uvm_sequence_item;
    rand int unsigned dim, pattern, source_gaps, sink_mode;
    int abort_phase=0;
    bit [31:0] a[64], b[64];
    constraint legal_config {dim inside {[1:8]}; pattern inside {[0:6]};
      source_gaps inside {[0:1]}; sink_mode inside {[0:2]};}
    `uvm_object_utils(matrix_item)
    function new(string name="matrix_item"); super.new(name); endfunction
    function void fill();
      for (int i=0;i<64;i++) begin
        a[i]=$urandom(); b[i]=$urandom();
        case(pattern)
          0: begin a[i]=0;b[i]=0;end
          1: begin a[i]=(i/dim==i%dim);b[i]=i+1;end
          2: begin a[i]=i+1;b[i]=(i/dim==i%dim);end
          3: begin a[i]=i+1;b[i]=i+3;end
          4: begin a[i]=-(i+1);b[i]=-(i+3);end
          5: begin
            case(i%4)
              0:begin a[i]=32'h80000000;b[i]=32'h7fffffff;end
              1:begin a[i]=32'hffffffff;b[i]=32'hffffffff;end
              2:begin a[i]=32'h7fffffff;b[i]=32'h80000000;end
              3:begin a[i]=32'h00000001;b[i]=32'h00000002;end
            endcase
          end
        endcase
      end
    endfunction
  endclass

  class matrix_sequence extends uvm_sequence #(matrix_item);
    `uvm_object_utils(matrix_sequence)
    function new(string name="matrix_sequence");super.new(name);endfunction
    task one(int n,int p,int gap,int sink,int abort_at=0);
      matrix_item t=matrix_item::type_id::create("matrix");
      start_item(t);
      if(!t.randomize() with {dim==local::n;pattern==local::p;
        source_gaps==local::gap;sink_mode==local::sink;})
        `uvm_fatal("RANDOMIZE","Configuration randomization failed")
      t.abort_phase=abort_at;t.fill();finish_item(t);
    endtask
    task body();
      if($test$plusargs("CORRUPT_RESULT") || $test$plusargs("BREAK_PROTOCOL")) begin
        one(4,5,1,2);return;
      end
      // Full explicit 8 dimension x 7 pattern cross, including partial tiles.
      for(int n=1;n<=8;n++) for(int p=0;p<=6;p++) one(n,p,p%2,p%3);
      repeat(8) begin
        matrix_item t=matrix_item::type_id::create("random_matrix");
        start_item(t);if(!t.randomize()) `uvm_fatal("RANDOMIZE","Random case failed")
        t.fill();finish_item(t);
      end
      // Abort A loading, B loading, computation and output, each followed by recovery.
      for(int phase_id=1;phase_id<=4;phase_id++) begin
        one(4,5,1,2,phase_id);one(5,6,1,2);
      end
    endtask
  endclass

  class matrix_driver extends uvm_driver #(matrix_item);
    `uvm_component_utils(matrix_driver)
    virtual mmul_if vif;
    function new(string name,uvm_component parent);super.new(name,parent);endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if(!uvm_config_db#(virtual mmul_if)::get(this,"","vif",vif)) `uvm_fatal("VIF","Missing interface")
    endfunction
    task reset_dut();
      @(negedge vif.clk);vif.rst_n=0;vif.start=0;vif.in_valid=0;vif.in_data=0;
      repeat(3) @(negedge vif.clk);
      vif.rst_n=1;
      @(posedge vif.clk);#1;
    endtask
    task send_word(bit [31:0] value,bit gaps);
      if(gaps) repeat($urandom_range(0,3)) @(negedge vif.clk);
      @(negedge vif.clk);vif.in_data=value;vif.in_valid=1;
      do @(posedge vif.clk); while(!vif.in_ready);
      @(negedge vif.clk);vif.in_valid=0;
    endtask
    task drive(matrix_item t);
      int count;
      // ap_ready also rises during ST_DONE. Wait until done clears before restart.
      while(!vif.idle || !vif.ready || vif.done) begin @(posedge vif.clk);#1;end
      @(negedge vif.clk);
      vif.dim=t.dim;vif.pattern_tag=t.pattern;vif.sink_mode=t.sink_mode;vif.start=1;
      @(negedge vif.clk);vif.start=0;
      for(int i=0;i<t.dim*t.dim;i++) begin
        send_word(t.a[i],t.source_gaps);
        if(t.abort_phase==1 && i==1) begin reset_dut();return;end
      end
      for(int i=0;i<t.dim*t.dim;i++) begin
        send_word(t.b[i],t.source_gaps);
        if(t.abort_phase==2 && i==1) begin reset_dut();return;end
      end
      if(t.abort_phase==3) begin repeat(3) @(negedge vif.clk);reset_dut();return;end
      if(t.abort_phase==4) begin
        do @(posedge vif.clk);while(!(vif.out_valid && vif.out_ready));
        reset_dut();return;
      end
      count=0;
      while(!vif.done) begin
        @(posedge vif.clk);#1;count++;
        if(count>20000) `uvm_fatal("TIMEOUT","Matrix operation did not finish")
      end
      do begin @(posedge vif.clk);#1;end while(vif.done || !vif.idle);
    endtask
    task run_phase(uvm_phase phase);
      matrix_item t;
      reset_dut();
      forever begin seq_item_port.get_next_item(t);drive(t);seq_item_port.item_done();end
    endtask
  endclass

  class matrix_sink extends uvm_component;
    `uvm_component_utils(matrix_sink)
    virtual mmul_if vif;
    function new(string name,uvm_component parent);super.new(name,parent);endfunction
    function void build_phase(uvm_phase phase);
      if(!uvm_config_db#(virtual mmul_if)::get(this,"","vif",vif)) `uvm_fatal("VIF","Missing interface")
    endfunction
    task run_phase(uvm_phase phase);
      int cycle_id=0;
      forever begin
        @(negedge vif.clk);cycle_id++;
        if(!vif.rst_n) vif.out_ready=0;
        else case(vif.sink_mode)
          0:vif.out_ready=1;
          1:vif.out_ready=(cycle_id%3==0);
          2:vif.out_ready=(cycle_id%16>=10);
          default:vif.out_ready=0;
        endcase
      end
    endtask
  endclass

  class matrix_event extends uvm_sequence_item;
    `uvm_object_utils(matrix_event)
    event_kind kind;
    logic [31:0] data;
    int dim,pattern,source_gaps,sink_stalls,cycle_id;
    function new(string name="matrix_event");super.new(name);endfunction
  endclass

  class matrix_monitor extends uvm_component;
    `uvm_component_utils(matrix_monitor)
    virtual mmul_if vif;
    uvm_analysis_port#(matrix_event) observed;
    bit active=0,previous_start=0,previous_reset=1,corrupted=0;
    int source_gaps=0,sink_stalls=0,cycle_id=0;
    function new(string name,uvm_component parent);super.new(name,parent);observed=new("observed",this);endfunction
    function void build_phase(uvm_phase phase);
      if(!uvm_config_db#(virtual mmul_if)::get(this,"","vif",vif)) `uvm_fatal("VIF","Missing interface")
    endfunction
    function void emit(event_kind k,logic[31:0] data=0);
      matrix_event e=matrix_event::type_id::create("observed_event");
      e.kind=k;e.data=data;e.dim=vif.dim;e.pattern=vif.pattern_tag;
      e.source_gaps=source_gaps;e.sink_stalls=sink_stalls;e.cycle_id=cycle_id;
      observed.write(e);
    endfunction
    task run_phase(uvm_phase phase);
      forever begin
        @(posedge vif.clk);cycle_id++;
        if(!vif.rst_n) begin
          if(previous_reset) emit(EV_RESET);
          active=0;previous_start=0;
        end else begin
          if(vif.start && !previous_start && vif.idle && !vif.done) begin
            active=1;source_gaps=0;sink_stalls=0;emit(EV_START);
          end
          if(active && vif.in_ready && !vif.in_valid) source_gaps++;
          if(active && vif.out_valid && !vif.out_ready) sink_stalls++;
          if(vif.in_valid && vif.in_ready) emit(EV_INPUT,vif.in_data);
          if(vif.out_valid && vif.out_ready) begin
            if($test$plusargs("CORRUPT_RESULT") && !corrupted) begin
              emit(EV_OUTPUT,vif.out_data^32'b1);corrupted=1;
            end else emit(EV_OUTPUT,vif.out_data);
          end
          if(vif.done) begin emit(EV_DONE);active=0;end
          previous_start=vif.start;
        end
        previous_reset=vif.rst_n;
      end
    endtask
  endclass

  class matrix_scoreboard extends uvm_component;
    `uvm_component_utils(matrix_scoreboard)
    uvm_analysis_imp#(matrix_event,matrix_scoreboard) input_events;
    logic[31:0] a[64],b[64];
    bit active=0;
    int dim,pattern,input_count=0,output_count=0;
    int completed=0,aborted=0,words_checked=0,mismatches=0,transfer_errors=0;
    int source_gap_cycles=0,sink_stall_cycles=0,back_to_back=0,last_done_cycle=-100;
    int dimension_mask=0,pattern_mask=0,sign_mask=0,tile_mask=0,reset_mask=0;
    int dimension_sample,pattern_sample,sign_sample,tile_sample,stall_sample,reset_sample;
    covergroup operation_coverage;
      option.per_instance=1;
      dims:coverpoint dimension_sample {bins values[]={[1:8]};}
      patterns:coverpoint pattern_sample {bins values[]={[0:6]};}
      signs:coverpoint sign_sample {bins zero={0};bins nonnegative={1};bins negative={2};bins mixed={3};}
      tiles:coverpoint tile_sample {bins partial_single={0};bins full_single={1};bins partial_multi={2};bins full_multi={3};}
      stalls:coverpoint stall_sample {bins none={0};bins observed={1};}
      dims_patterns:cross dims,patterns;
    endgroup
    covergroup reset_coverage;
      option.per_instance=1;
      reset_phase:coverpoint reset_sample {bins idle={0};bins load_a={1};bins load_b={2};bins compute={3};bins output_phase={4};}
    endgroup
    function new(string name,uvm_component parent);
      super.new(name,parent);input_events=new("input_events",this);
      operation_coverage=new();reset_coverage=new();
    endfunction
    function void transfer_error(string message);
      transfer_errors++;`uvm_error("TRANSFER",message)
    endfunction
    function void sample_operation(matrix_event e);
      bit has_negative=0,has_positive=0,has_nonzero=0;
      for(int i=0;i<dim*dim;i++) begin
        if(a[i]!=0 || b[i]!=0) has_nonzero=1;
        if(a[i][31] || b[i][31]) has_negative=1;
        if((a[i]!=0 && !a[i][31]) || (b[i]!=0 && !b[i][31])) has_positive=1;
      end
      dimension_sample=dim;pattern_sample=pattern;
      sign_sample=!has_nonzero?0:has_negative?(has_positive?3:2):1;
      tile_sample=dim<4?0:dim==4?1:dim<8?2:3;
      stall_sample=e.sink_stalls!=0;
      dimension_mask|=1<<(dim-1);pattern_mask|=1<<pattern;
      sign_mask|=1<<sign_sample;tile_mask|=1<<tile_sample;
      source_gap_cycles+=e.source_gaps;sink_stall_cycles+=e.sink_stalls;
      operation_coverage.sample();
    endfunction
    function void write(matrix_event e);
      int row,col,phase_id;
      logic[63:0] product;
      logic[31:0] expected_word;
      case(e.kind)
        EV_START:begin
          if(active) transfer_error("New operation while a previous operation is active");
          if(e.cycle_id-last_done_cycle<=2) back_to_back++;
          active=1;dim=e.dim;pattern=e.pattern;input_count=0;output_count=0;
          if(dim<1 || dim>8) transfer_error("Pilot only supports legal dimensions 1..8");
        end
        EV_INPUT:begin
          if(!active || input_count>=2*dim*dim) transfer_error("Unexpected or excess input transfer");
          else begin
            if(input_count<dim*dim) a[input_count]=e.data;
            else b[input_count-dim*dim]=e.data;
            input_count++;
          end
        end
        EV_OUTPUT:begin
          if(!active || input_count!=2*dim*dim || output_count>=dim*dim)
            transfer_error("Unexpected, early or excess output transfer");
          else begin
            row=output_count/dim;col=output_count%dim;expected_word=0;
            // Each product and accumulated sum are reduced modulo 2^32.
            // This is bit-identical for signed/unsigned two's-complement operands.
            for(int k=0;k<dim;k++) begin
              product={32'b0,a[row*dim+k]}*{32'b0,b[k*dim+col]};
              expected_word=expected_word+product[31:0];
            end
            if(e.data!==expected_word) begin
              mismatches++;`uvm_error("MATRIX_MISMATCH",$sformatf("dim=%0d word=%0d expected=%08x observed=%08x",dim,output_count,expected_word,e.data))
            end
            output_count++;words_checked++;
          end
        end
        EV_DONE:begin
          if(!active || input_count!=2*dim*dim || output_count!=dim*dim)
            transfer_error("Done without exactly 2*N*N inputs and N*N outputs");
          else begin completed++;sample_operation(e);end
          active=0;last_done_cycle=e.cycle_id;
        end
        EV_RESET:begin
          phase_id=0;
          if(active) begin
            aborted++;
            phase_id=input_count<dim*dim?1:input_count<2*dim*dim?2:output_count==0?3:4;
          end
          reset_sample=phase_id;reset_mask|=1<<phase_id;reset_coverage.sample();
          active=0;input_count=0;output_count=0;
        end
      endcase
    endfunction
  endclass

  class matrix_agent extends uvm_agent;
    `uvm_component_utils(matrix_agent)
    uvm_sequencer#(matrix_item) sequencer;
    matrix_driver driver;matrix_sink sink;matrix_monitor monitor;
    function new(string name,uvm_component parent);super.new(name,parent);endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      sequencer=uvm_sequencer#(matrix_item)::type_id::create("sequencer",this);
      driver=matrix_driver::type_id::create("driver",this);
      sink=matrix_sink::type_id::create("sink",this);
      monitor=matrix_monitor::type_id::create("monitor",this);
    endfunction
    function void connect_phase(uvm_phase phase);driver.seq_item_port.connect(sequencer.seq_item_export);endfunction
  endclass

  class matrix_env extends uvm_env;
    `uvm_component_utils(matrix_env)
    matrix_agent agent;matrix_scoreboard scoreboard;
    function new(string name,uvm_component parent);super.new(name,parent);endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      agent=matrix_agent::type_id::create("agent",this);
      scoreboard=matrix_scoreboard::type_id::create("scoreboard",this);
    endfunction
    function void connect_phase(uvm_phase phase);agent.monitor.observed.connect(scoreboard.input_events);endfunction
  endclass

  class matrix_test extends uvm_test;
    `uvm_component_utils(matrix_test)
    matrix_env env;virtual mmul_if vif;
    function new(string name,uvm_component parent);super.new(name,parent);endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);env=matrix_env::type_id::create("env",this);
      if(!uvm_config_db#(virtual mmul_if)::get(this,"","vif",vif)) `uvm_fatal("VIF","Missing interface")
    endfunction
    task run_phase(uvm_phase phase);
      matrix_sequence seq=matrix_sequence::type_id::create("seq");
      phase.raise_objection(this);seq.start(env.agent.sequencer);
      repeat(4) @(posedge vif.clk);phase.drop_objection(this);
    endtask
    function void report_phase(uvm_phase phase);
      matrix_scoreboard s=env.scoreboard;
      uvm_report_server rs=uvm_report_server::get_server();
      $display("MMUL_METRICS completed=%0d aborted=%0d words=%0d mismatches=%0d transfer_errors=%0d sva_failures=%0d hold_checks=%0d input_hold_checks=%0d uvm_errors=%0d uvm_fatals=%0d dimension_mask=%0d pattern_mask=%0d sign_mask=%0d tile_mask=%0d reset_mask=%0d source_gap_cycles=%0d sink_stall_cycles=%0d back_to_back=%0d operation_coverage=%0.2f reset_coverage=%0.2f active=%0d",
        s.completed,s.aborted,s.words_checked,s.mismatches,s.transfer_errors,vif.sva_failures,
        vif.output_hold_checks,vif.input_hold_checks,rs.get_severity_count(UVM_ERROR),rs.get_severity_count(UVM_FATAL),
        s.dimension_mask,s.pattern_mask,s.sign_mask,s.tile_mask,s.reset_mask,s.source_gap_cycles,s.sink_stall_cycles,s.back_to_back,
        s.operation_coverage.get_inst_coverage(),s.reset_coverage.get_inst_coverage(),s.active);
      $display("MMUL_TEST_COMPLETE");
    endfunction
  endclass
endpackage
