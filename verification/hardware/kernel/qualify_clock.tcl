if {$argc != 1} {error "usage: qualify_clock.tcl <kernel_helpers_dir>"}
set helpers [file normalize [lindex $argv 0]]
source /tools/Xilinx/2025.1/Vitis/scripts/ocl/ocl_util.tcl
source [file join $helpers clock_api_compat.tcl]
create_project -in_memory -part xcu55c-fsvh2892-2L-e
::ocl_util::initialize_clkwiz_debug false xcu55c-fsvh2892-2L-e
::ocl_util::set_clkwiz_prop 100 150
set m [::ocl_util::get_clkwiz_prop ChosenM]
set d [::ocl_util::get_clkwiz_prop ChosenD]
set o [::ocl_util::get_clkwiz_prop ChosenDiv0]
if {$m != 12 || $d != 1 || $o != 8} {error "Unexpected qualified 100-to-150 MHz divider solution"}
::ocl_util::uninitialize_clkwiz_debug false xcu55c-fsvh2892-2L-e
puts "SYSBASE_CLOCK_QUALIFICATION_PASS"
