# Read-only reconstruction of a retained full design before another long build.
# No implementation, saved project, or source checkpoint is modified.
if {$argc != 3} {error "usage: qualify_implementation.tcl <retained_build> <helpers> <output>"}
set build [file normalize [lindex $argv 0]]
set helpers [file normalize [lindex $argv 1]]
set output [file normalize [lindex $argv 2]]
set vpl [file join $build _x/link/vivado/vpl]
file mkdir $output
set_param general.maxThreads 8
set_param project.enablePRFlowIPI 1
set_param project.loadTopLevelOOCConstrs 1
create_project -in_memory -part xcu55c-fsvh2892-2L-e
set_property design_mode GateLvl [current_fileset]
set_property ip_repo_paths [list [file join $build _x/link/int/xo/ip_repo/user_org_rtl_mmul_sysbase_1_0] [file join $vpl .local/hw_platform/iprepo] /tools/Xilinx/2025.1/Vitis/data/cache/xilinx /tools/Xilinx/2025.1/Vitis/data/vitis/ip] [current_project]
set_property ip_output_repo [file join $output ip_cache] [current_project]
set_property ip_cache_permissions {} [current_project]
set_property XPM_LIBRARIES {XPM_CDC XPM_FIFO XPM_MEMORY} [current_project]
update_ip_catalog
add_files [file join $vpl .local/hw_platform/hw_bb_locked.dcp]
read_ip [file join $vpl prj/prj.srcs/my_rm/bd/ulp/ip/ulp_mmul_sysbase_1_0/ulp_mmul_sysbase_1_0.xci]
set_param project.isImplRun true
add_files [file join $vpl prj/prj.srcs/my_rm/bd/ulp/ulp.bd]
set_param project.isImplRun false
set ulp_dcp [file join $vpl prj/prj.runs/my_rm_synth_1/ulp.dcp]
add_files $ulp_dcp
set_property SCOPED_TO_CELLS level0_i/ulp [get_files $ulp_dcp]
read_xdc [file join $vpl .local/hw_platform/tcl_hooks/impl.xdc]
set ooc [file join $vpl output/ulp_ooc_copy.xdc]
read_xdc -mode out_of_context -cells level0_i/ulp $ooc
set_property processing_order LATE [get_files $ooc]
link_design -part xcu55c-fsvh2892-2L-e -reconfig_partitions level0_i/ulp
update_timing -full
write_checkpoint [file join $output linked_before_clock_probe.dcp]
report_clocks -file [file join $output clocks_before_bad_constraint.rpt]
read_xdc [file join $vpl output/_user_impl_clk.xdc]
update_timing -full
set bad_period [get_property PERIOD [get_clocks clk_kernel_00_unbuffered_net]]
puts "SYSBASE_RETAINED_BAD_CLOCK_PERIOD_NS=$bad_period"
report_clocks -file [file join $output clocks_after_bad_constraint.rpt]
set bp [open [file join $output bad_clock_period.txt] w];puts $bp $bad_period;close $bp
if {abs($bad_period-1000.0/150.0)<=0.001} {error "Retained generated clock did not reproduce a non-150 MHz constraint"}
if {![catch {source [file join $helpers check_impl_clock.tcl]} rejection]} {
    error "Negative control failed: non-150 MHz implementation clock was accepted"
}
puts "SYSBASE_BAD_IMPLEMENTATION_CLOCK_REJECTED period_ns=$bad_period reason=$rejection"
source /tools/Xilinx/2025.1/Vitis/scripts/ocl/ocl_util.tcl
source [file join $helpers clock_api_compat.tcl]
set frequency [dict create ulp_ucs/aclk_kernel_00 [dict create is_user_set true instance ulp_ucs port aclk_kernel_00 clk_id 0 freq 150]]
::ocl_util::write_user_impl_clock_constraint level0_i/ulp $frequency "" $output false
source [file join $helpers check_impl_clock.tcl]
set kernel [get_cells -hierarchical -filter {NAME == "level0_i/ulp/mmul_sysbase_1/inst"}]
if {[llength $kernel]!=1} {error "Expected exactly one actual retained SysBase kernel cell"}
report_property $kernel -file [file join $output kernel_properties_before.rpt]
set_property DONT_PARTITION true $kernel
if {![get_property DONT_PARTITION $kernel]} {error "Exact-kernel DONT_PARTITION did not take effect"}
report_property $kernel -file [file join $output kernel_properties_after.rpt]
report_clocks -file [file join $output clocks.rpt]
write_checkpoint [file join $output qualified_linked.dcp]
puts "SYSBASE_FULL_IMPLEMENTATION_PREFLIGHT_PASS"
