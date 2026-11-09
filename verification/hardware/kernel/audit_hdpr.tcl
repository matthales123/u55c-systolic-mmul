# Disposable preflight analysis of the generated HDPR-5 severity change.
if {$argc != 3} {error "usage: audit_hdpr.tcl <linked_checkpoint> <helpers> <output>"}
proc quote_json {value} {
    return "\"[string map [list "\\" "\\\\" "\"" "\\\"" "\n" "\\n" "\r" "\\r" "\t" "\\t"] $value]\""
}
set output [file normalize [lindex $argv 2]]
file mkdir $output
set_param general.maxThreads 8
open_checkpoint [file normalize [lindex $argv 0]]
set kernel [get_cells -hierarchical -filter {NAME == "level0_i/ulp/mmul_sysbase_1/inst"}]
if {[llength $kernel]!=1} {error "Expected exact actual SysBase kernel instance"}
reset_property DONT_PARTITION $kernel
report_property $kernel -file [file join $output kernel_before_hook.rpt]
source [file join [file normalize [lindex $argv 1]] check_impl_clock.tcl]
report_property $kernel -file [file join $output kernel_after_hook.rpt]
set check [get_drc_checks HDPR-5]
set loaded_severity [get_property SEVERITY $check]
# Reproduce precisely the generated _vpl_pre_place.tcl change, then independently
# restore factory checks. These analysis settings are never saved to a DCP.
set_property SEVERITY Warning $check
set effective_severity [get_property SEVERITY $check]
report_drc -no_waivers -file [file join $output drc_effective.rpt]
set effective_findings [llength [get_drc_violations -filter {CHECK == "HDPR-5"}]]
reset_drc_check [get_drc_checks]
set default_severity [get_property SEVERITY $check]
report_drc -no_waivers -file [file join $output drc_default.rpt]
set default_findings [get_drc_violations -filter {CHECK == "HDPR-5"}]
set status FAIL
if {$default_severity eq "Error" && [get_property IS_ENABLED $check] && [llength $default_findings] == 0} {set status PASS}
set fp [open [file join $output result.json] w]
puts $fp "\{\"status\":[quote_json $status],\"scope\":\"Linked-design HDPR-5 diagnostic only; not routed implementation signoff\",\"loaded_severity\":[quote_json $loaded_severity],\"effective_severity\":[quote_json $effective_severity],\"default_severity\":[quote_json $default_severity],\"effective_hdpr5_findings\":$effective_findings,\"default_hdpr5_findings\":[llength $default_findings],\"default_enabled\":[get_property IS_ENABLED $check]\}"
close $fp
if {$status ne "PASS"} {error "Default HDPR-5 check has actual violations or is not enabled at Error severity"}
puts "SYSBASE_HDPR_DEFAULT_PREFLIGHT_PASS"
