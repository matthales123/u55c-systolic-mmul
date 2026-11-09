set script_dir [file dirname [file normalize [info script]]]
set rtl_dir [file normalize [file join $script_dir ".."]]
set root_dir [file normalize [file join $rtl_dir ".." ".."]]

if {[info exists ::env(U55C_EFFECTIVE_BOARD_REPO_PATHS)] && $::env(U55C_EFFECTIVE_BOARD_REPO_PATHS) ne ""} {
  set repo_paths {}
  foreach rp [split $::env(U55C_EFFECTIVE_BOARD_REPO_PATHS) ":"] {
    if {$rp ne "" && [file isdirectory $rp]} {
      lappend repo_paths [file normalize $rp]
    }
  }
  if {[llength $repo_paths] > 0} {
    set_param board.repoPaths $repo_paths
    puts "INFO: Using board.repoPaths=$repo_paths"
  }
}

set project_name "u55c_systolic_mmul_rtl"
if {[info exists ::env(U55C_RTL_PROJECT_NAME)] && $::env(U55C_RTL_PROJECT_NAME) ne ""} {
  set project_name $::env(U55C_RTL_PROJECT_NAME)
}

set part "xcu55c-fsvh2892-2L-e"
if {[info exists ::env(U55C_PART)] && $::env(U55C_PART) ne ""} {
  set part $::env(U55C_PART)
}

set build_dir [file join $root_dir build vivado_rtl]
file mkdir $build_dir

create_project -force $project_name [file join $build_dir $project_name] -part $part
set_property target_language Verilog [current_project]

set rtl_top "mmul_accel_scalable"
if {[info exists ::env(U55C_RTL_TOP)] && $::env(U55C_RTL_TOP) ne ""} {
  set rtl_top $::env(U55C_RTL_TOP)
}

set sim_top "mmul_accel_scalable_tb"
if {[info exists ::env(U55C_RTL_TB_TOP)] && $::env(U55C_RTL_TB_TOP) ne ""} {
  set sim_top $::env(U55C_RTL_TB_TOP)
}

set source_files_cmd [list find [file join $rtl_dir src] -type f "(" -name "*.v" -o -name "*.sv" ")"]
set source_files_raw [string trim [exec {*}$source_files_cmd]]
set source_files {}
if {$source_files_raw ne ""} {
  set source_files [split $source_files_raw "\n"]
}
if {[llength $source_files] == 0} {
  error "No RTL source files found under [file join $rtl_dir src] (*.v/*.sv)"
}
add_files $source_files

set sim_files_cmd [list find [file join $rtl_dir tb] -type f "(" -name "*.v" -o -name "*.sv" ")"]
set sim_files_raw [string trim [exec {*}$sim_files_cmd]]
set sim_files {}
if {$sim_files_raw ne ""} {
  set sim_files [split $sim_files_raw "\n"]
}
if {[llength $sim_files] == 0} {
  error "No simulation files found under [file join $rtl_dir tb] (*.v/*.sv)"
}
add_files -fileset sim_1 $sim_files

set include_dirs [list \
  [file join $rtl_dir src/cornell] \
  [file join $rtl_dir src/cornell/systolic] \
  [file join $rtl_dir src/cornell/proc] \
  [file join $rtl_dir src/cornell/vc] \
]
set_property include_dirs $include_dirs [get_filesets sources_1]
set_property include_dirs $include_dirs [get_filesets sim_1]

foreach src_file $source_files {
  set normalized [file normalize $src_file]
  if {[string first "/src/cornell/" $normalized] >= 0 && [string match "*.v" $normalized]} {
    set_property file_type {SystemVerilog} [get_files -all $normalized]
  }
}

set_property top $rtl_top [get_filesets sources_1]
set_property top $sim_top [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

close_project
exit
