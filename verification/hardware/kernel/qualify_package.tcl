if {$argc != 2} {error "usage: qualify_package.tcl <unpacked_xo> <output_dir>"}
set unpacked [file normalize [lindex $argv 0]]
set output [file normalize [lindex $argv 1]]
set_param general.maxThreads 8
create_project -force package_qualification [file join $output project] -part xcu55c-fsvh2892-2L-e
set_property ip_cache_permissions {} [current_project]
set_property ip_repo_paths [list [file join $unpacked ip_repo]] [current_project]
update_ip_catalog
create_ip -vlnv user.org:rtl:mmul_sysbase:1.0 -module_name qualified_sysbase
generate_target all [get_ips qualified_sysbase]
foreach source [get_files -all] {
    set path [file normalize [get_property NAME $source]]
    if {![string match "$unpacked/*" $path] && ![string match "$output/*" $path]} {
        error "Qualification source escapes unpacked IP/project: $path"
    }
}
if {[get_property include_dirs [current_fileset]] ne ""} {error "Unexpected project include fallback"}
synth_ip [get_ips qualified_sysbase]
set evidence [open [file join $output qualification.txt] w]
puts $evidence "Unpacked XO IP synthesis completed with no project include directories."
puts $evidence "[get_property include_dirs [current_fileset]]"
foreach source [get_files -all] {puts $evidence [get_property NAME $source]}
close $evidence
close_project
puts "SYSBASE_PACKAGE_QUALIFICATION_PASS"
