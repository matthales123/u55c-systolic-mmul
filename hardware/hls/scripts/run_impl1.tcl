if {$argc < 1} {
  puts "USAGE: run_impl1.tcl <project.xpr> ?run_name? ?jobs? ?to_step? ?reset(0|1)?"
  exit 1
}

set xpr     [lindex $argv 0]
set runname [expr {$argc >= 2 ? [lindex $argv 1] : "impl_1"}]
set jobs    [expr {$argc >= 3 ? [lindex $argv 2] : 44}]
set to_step [expr {$argc >= 4 ? [lindex $argv 3] : "write_bitstream"}]
set do_reset [expr {$argc >= 5 ? [lindex $argv 4] : 0}]

if {![file exists $xpr]} {
  puts "ERROR: project file does not exist: $xpr"
  exit 1
}

open_project $xpr

set r [get_runs -quiet $runname]
if {[llength $r] == 0} {
  puts "ERROR: run '$runname' not found in project"
  exit 1
}

set status_before [get_property STATUS $r]
puts [format {[impl] run=%s status_before=%s} $runname $status_before]
puts [format {[impl] jobs=%s to_step=%s} $jobs $to_step]
puts [format {[impl] reset=%s} $do_reset]

# Allow Vivado to use more worker threads internally when possible.
# Vivado 2025.1 caps general.maxThreads at 32.
set max_threads $jobs
if {$max_threads < 1} {
  set max_threads 1
}
if {$max_threads > 32} {
  set max_threads 32
}
if {[catch {set_param general.maxThreads $max_threads} maxthreads_err]} {
  puts [format {[impl] warning: could not set general.maxThreads=%s (%s)} $max_threads $maxthreads_err]
} else {
  puts [format {[impl] general.maxThreads=%s} $max_threads]
}

if {$do_reset} {
  puts [format {[impl] resetting run=%s} $runname]
  if {[catch {reset_runs $runname} reset_msg]} {
    puts "ERROR: reset_runs failed"
    puts $reset_msg
    exit 1
  }
}

set launch_rc [catch {launch_runs $runname -to_step $to_step -jobs $jobs} launch_msg]
if {$launch_rc} {
  if {[string match "*already run and up to date*" $launch_msg]} {
    puts [format {[impl] run=%s already up to date for step=%s} $runname $to_step]
  } else {
    puts "ERROR: launch_runs failed"
    puts $launch_msg
    exit 1
  }
} else {
  if {[catch {wait_on_run $runname} wait_msg]} {
    puts "ERROR: wait_on_run failed"
    puts $wait_msg
    exit 1
  }
}

set r [get_runs -quiet $runname]
set status_after [get_property STATUS $r]
puts [format {[impl] run=%s status_after=%s} $runname $status_after]

if {![string match "*Complete*" $status_after]} {
  puts "ERROR: implementation run did not complete successfully"
  exit 2
}

puts {[impl] completed successfully}
exit 0
