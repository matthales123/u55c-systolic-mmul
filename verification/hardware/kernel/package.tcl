if {$argc != 2} {error "usage: package.tcl <source_snapshot> <output_dir>"}
set snapshot [file normalize [lindex $argv 0]]
set output [file normalize [lindex $argv 1]]
set rtl [file join $snapshot hardware rtl src]
set here [file join $snapshot verification hardware kernel]
set_param general.maxThreads 8
create_project -force sysbase_package [file join $output package_project] -part xcu55c-fsvh2892-2L-e
set sources [list [file join $rtl cornell systolic SysBase.v] [file join $rtl mmul_row_sdp_ram.sv] \
    [file join $rtl mmul_sysbase_core.sv] [file join $rtl mmul_sysbase_axis_shell.sv] [file join $here mmul_sysbase.sv]]
add_files -norecurse $sources
set_property file_type SystemVerilog [get_files *.v]
set_property include_dirs [list [file join $rtl cornell]] [current_fileset]
set_property top mmul_sysbase [current_fileset]
update_compile_order -fileset sources_1
synth_design -top mmul_sysbase -part xcu55c-fsvh2892-2L-e -flatten_hierarchy none
set evidence [open [file join $output synthesis_hierarchy.txt] w]
puts $evidence "TOP mmul_sysbase MAX_DIM=8 ARRAY_SIZE=4"
foreach cell [get_cells -hierarchical] {
    puts $evidence "[get_property NAME $cell] [get_property REF_NAME $cell] [get_property ORIG_REF_NAME $cell]"
}
close $evidence
report_utilization -file [file join $output packaged_utilization.rpt]
write_checkpoint -force [file join $output packaged_synth.dcp]
close_design
set ip_dir [file join $output kernel_ip]
ipx::package_project -root_dir $ip_dir -vendor user.org -library rtl -taxonomy /KernelIP -import_files -set_current true
set core [ipx::current_core]
# IP packager's automatic import flattens include headers. Reconstruct a
# self-contained relative tree so the exported IP never depends on the snapshot.
foreach subdirectory {vc systolic} {
    file mkdir [file join $ip_dir src $subdirectory]
}
set headers {vc/trace.v vc/muxes.v vc/arithmetic.v vc/regs.v vc/queues.v vc/regfiles.v systolic/IntMulBase.v systolic/MacNew.v}
foreach header $headers {
    file copy -force [file join $rtl cornell $header] [file join $ip_dir src $header]
}
foreach group_name {xilinx_anylanguagesynthesis xilinx_anylanguagebehavioralsimulation} {
    set group [ipx::get_file_groups $group_name -of_objects $core]
    foreach imported [ipx::get_files -of_objects $group] {
        ipx::remove_file [get_property name $imported] $group
    }
    set_property model_name mmul_sysbase $group
    set_property dependency {src} $group
    foreach header $headers {
        set item [ipx::add_file src/$header $group]
        set_property type systemVerilogSource $item
        set_property is_include true $item
    }
    foreach name {SysBase.v mmul_row_sdp_ram.sv mmul_sysbase_core.sv mmul_sysbase_axis_shell.sv mmul_sysbase.sv} {
        set item [ipx::add_file src/$name $group]
        set_property type systemVerilogSource $item
    }
}
set_property name mmul_sysbase $core
set_property display_name mmul_sysbase $core
set_property description "SysBase RTL pilot with checked AXI memory transport" $core
set_property sdx_kernel true $core
set_property sdx_kernel_type rtl $core
set_property core_revision 1 $core
ipx::infer_bus_interface ap_clk xilinx.com:signal:clock_rtl:1.0 $core
ipx::infer_bus_interface ap_rst_n xilinx.com:signal:reset_rtl:1.0 $core
foreach bus_if {m_axi_gmem0 m_axi_gmem1 m_axi_gmem2 s_axi_control} {
    if {[llength [ipx::get_bus_interfaces $bus_if -of_objects $core]] == 0} {error "Missing bus interface $bus_if"}
    ipx::associate_bus_interfaces -busif $bus_if -clock ap_clk $core
}
set clk_if [ipx::get_bus_interfaces ap_clk -of_objects $core]
set assoc [ipx::add_bus_parameter ASSOCIATED_BUSIF $clk_if]
set_property value "m_axi_gmem0:m_axi_gmem1:m_axi_gmem2:s_axi_control" $assoc
ipx::create_xgui_files $core
ipx::update_checksums $core
ipx::save_core $core
ipx::check_integrity $core
close_project
package_xo -xo_path [file join $output mmul_sysbase.xo] -kernel_name mmul_sysbase \
    -kernel_xml [file join $here kernel.xml] -ip_directory $ip_dir
puts "SYSBASE_PACKAGE_COMPLETE"
