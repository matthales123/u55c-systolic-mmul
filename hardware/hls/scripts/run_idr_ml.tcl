if {$argc < 1} {
  puts "USAGE: run_idr_ml.tcl <project.xpr> ?reference_run? ?jobs?"
  exit 1
}

set xpr      [lindex $argv 0]
set ref_run  [expr {$argc >= 2 ? [lindex $argv 1] : "impl_1"}]
set jobs     [expr {$argc >= 3 ? [lindex $argv 2] : 3}]

if {![file exists $xpr]} {
  puts "ERROR: project file does not exist: $xpr"
  exit 1
}

open_project $xpr

set ref [get_runs -quiet $ref_run]
if {[llength $ref] == 0} {
  puts "ERROR: reference run '$ref_run' not found in project"
  exit 1
}

set ref_status [get_property STATUS $ref]
puts [format {[idr] reference_run=%s status=%s} $ref_run $ref_status]
if {![string match "*Complete*" $ref_status]} {
  puts "ERROR: reference run must be complete before generating ML strategies"
  exit 1
}

if {[catch {open_run $ref_run} open_err]} {
  puts [format {ERROR: failed to open reference run '%s'} $ref_run]
  puts $open_err
  exit 1
}
puts [format {[idr] opened reference design from run=%s} $ref_run]

set strategy_dir [file join [get_property DIRECTORY $ref] MLStrategy]
file mkdir $strategy_dir
puts [format {[idr] strategy_dir=%s} $strategy_dir]

puts {[idr] generate_ml_strategies...}
set gen_rc [catch {generate_ml_strategies $ref -suggestions_filter {APPLIED || Category==Strategy}} gen_msg]
if {$gen_rc} {
  # Some VPL projects report impl_1 as complete but still reject strategy generation
  # on route-step metadata checks. Try to refresh route state and then fall back to
  # the documented report_qor_suggestions/write_qor_suggestions flow.
  if {[string match "*route_design*must be completed*" $gen_msg]} {
    puts [format {[idr] run=%s is missing routed-step metadata; forcing route_design then retrying} $ref_run]
    set route_launch_rc [catch {launch_runs $ref_run -to_step route_design -jobs $jobs} route_launch_err]
    if {$route_launch_rc} {
      if {[string match "*already run and up to date*" $route_launch_err]} {
        puts [format {[idr] run=%s route_design already up to date} $ref_run]
      } else {
        puts "ERROR: failed to launch route_design on reference run"
        puts $route_launch_err
        exit 1
      }
    }
    if {!$route_launch_rc} {
      if {[catch {wait_on_run $ref_run} route_wait_err]} {
        puts "ERROR: wait_on_run failed for reference run"
        puts $route_wait_err
        exit 1
      }
    }
    set ref [get_runs -quiet $ref_run]
    set ref_status [get_property STATUS $ref]
    puts [format {[idr] post-route reference_run=%s status=%s} $ref_run $ref_status]
    if {[catch {open_run $ref_run} reopen_err]} {
      puts [format {ERROR: failed to reopen reference run '%s' after route_design} $ref_run]
      puts $reopen_err
      exit 1
    }
    set ref [current_run -implementation]
    puts [format {[idr] retrying generate_ml_strategies with current implementation run=%s} $ref]
    set gen_rc [catch {generate_ml_strategies $ref -suggestions_filter {APPLIED || Category==Strategy}} gen_msg]
  }
}
if {$gen_rc} {
  puts {[idr] generate_ml_strategies did not produce strategy files; trying report_qor_suggestions fallback}
  puts [string trim $gen_msg]
  if {[catch {report_qor_suggestions} rqs_report_msg]} {
    puts "ERROR: report_qor_suggestions failed"
    puts $rqs_report_msg
    exit 1
  }
  set qs [get_qor_suggestions -filter {APPLIED || Category == Strategy}]
  set qs_count [llength $qs]
  puts [format {[idr] strategy_suggestions=%s} $qs_count]
  if {$qs_count == 0} {
    puts {[idr] no ML strategy suggestions available (design likely already meets timing); skipping IDR run creation}
    exit 0
  }
  if {[catch {write_qor_suggestions -strategy_dir $strategy_dir -force -of_objects $qs} write_msg]} {
    puts "ERROR: write_qor_suggestions failed"
    puts $write_msg
    exit 1
  }
}

set strategy_files [glob -nocomplain -directory $strategy_dir *.rqs]
puts [format {[idr] strategy_files=%s dir=%s} [llength $strategy_files] $strategy_dir]
if {[llength $strategy_files] == 0} {
  puts {[idr] no .rqs strategy files were found; skipping IDR run creation}
  exit 0
}

puts {[idr] create_rqs_runs...}
if {[catch {create_rqs_runs -reference_run $ref} create_msg]} {
  puts "ERROR: create_rqs_runs failed"
  puts $create_msg
  exit 1
}

set idr_runs [lsort [get_runs -quiet "i_${ref_run}_*"]]
if {[llength $idr_runs] == 0} {
  set idr_runs [lsort [get_runs -quiet "i_impl_*"]]
}
if {[llength $idr_runs] == 0} {
  puts "ERROR: no IDR runs were created"
  exit 1
}

puts [format {[idr] launching runs=%s jobs=%s} $idr_runs $jobs]
launch_runs $idr_runs -to_step write_bitstream -jobs $jobs
wait_on_run $idr_runs

set failed 0
foreach r $idr_runs {
  set s [get_property STATUS $r]
  puts [format {[idr] run=%s status=%s} $r $s]
  if {![string match "*Complete*" $s]} {
    set failed 1
  }
}

if {$failed} {
  puts "ERROR: one or more IDR runs did not complete successfully"
  exit 2
}

puts {[idr] completed successfully}
exit
