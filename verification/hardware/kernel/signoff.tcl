if {$argc != 2} {error "usage: signoff.tcl <routed_dcp> <output_dir>"}
proc quote_json {value} {
    return "\"[string map [list "\\" "\\\\" "\"" "\\\"" "\n" "\\n" "\r" "\\r" "\t" "\\t"] $value]\""
}
proc strings_json {values} {
    set encoded {}
    foreach value $values {lappend encoded [quote_json $value]}
    return "\[[join $encoded ,]\]"
}
proc irq_launch_outputs {startpoints} {
    # Vivado timing startpoints for sequential launches are clock pins. Keep
    # those raw pins separately, then resolve the same FDRE's logical Q output.
    set outputs {}
    foreach startpoint $startpoints {
        set pin [get_pins -hierarchical -filter [format {NAME == "%s"} $startpoint]]
        set cell [get_cells -of_objects $pin]
        if {[llength $pin]!=1 || [llength $cell]!=1 || [get_property REF_NAME $cell] ne "FDRE" || [get_property REF_PIN_NAME $pin] ne "C"} {
            error "IRQ timing launch is not an exact FDRE clock pin: $startpoint"
        }
        set q [get_pins -of_objects $cell -filter {REF_PIN_NAME == Q}]
        if {[llength $q]!=1} {error "Expected one FDRE Q output for IRQ launch: $cell"}
        lappend outputs $q
    }
    return [lsort -unique $outputs]
}
set output [file normalize [lindex $argv 1]]
file mkdir $output
set_param general.maxThreads 8
open_checkpoint [file normalize [lindex $argv 0]]
set drc_effective {}
foreach check [get_drc_checks] {
    dict set drc_effective [get_property NAME $check] [list [get_property SEVERITY $check] [get_property IS_ENABLED $check]]
}
report_drc -no_waivers -file [file join $output drc_effective.rpt]
# Reset analysis check settings in this disposable session only.  A generated
# implementation hook's severity reduction must not hide a factory Error.
reset_drc_check [get_drc_checks]
set drc_defaults {}
set df [open [file join $output drc_checks.json] w]
puts $df "\["
set first 1
foreach check [get_drc_checks] {
    set name [get_property NAME $check]
    set severity [get_property SEVERITY $check]
    set enabled [get_property IS_ENABLED $check]
    dict set drc_defaults $name [list $severity $enabled]
    if {![dict exists $drc_effective $name]} {error "DRC check set changed during reset"}
    lassign [dict get $drc_effective $name] effective_severity effective_enabled
    if {!$first} {puts $df ","}
    set first 0
    puts -nonewline $df "\{\"name\":[quote_json $name],\"default_severity\":[quote_json $severity],\"effective_severity\":[quote_json $effective_severity],\"default_enabled\":$enabled,\"effective_enabled\":$effective_enabled\}"
}
puts $df "\n\]"
close $df
report_drc -no_waivers -file [file join $output drc.rpt]
report_methodology -file [file join $output methodology_initial.rpt]
update_timing -full
check_timing -verbose -file [file join $output check_timing.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose -file [file join $output timing_summary.rpt]
# Preserve exact worst setup paths and both clock trees for diagnosis; a
# negative path must be understood before any new implementation is selected.
report_timing -delay_type max -max_paths 20 -nworst 2 -path_type full_clock_expanded -append -file [file join $output timing_summary.rpt]
report_clocks -file [file join $output clocks.rpt]
report_clock_interaction -delay_type min_max -file [file join $output clock_interaction.rpt]
report_exceptions -coverage -file [file join $output exception_coverage.rpt]
set pcie_coreclk [get_pins -hierarchical -filter {NAME == "level0_i/blp/blp_i/ss_hif/inst/pcie/inst/bd_39ab_pcie_0_pcie_4_0_pipe_inst/pcie_4_c_e4_inst/CORECLK"}]
set dma_link_down [get_pins -hierarchical -filter {NAME == "level0_i/blp/blp_i/PLP/ss_dma/inst/dma/inst/chain_cfg_phy_link_down/with_ff_chain.ff_chain_gen[0].sync_rst.ff_chain_reg[1][0]/D"}]
if {[llength $pcie_coreclk] != 1 || [llength $dma_link_down] != 1} {error "Expected exact platform PCIe/DMA timing-review pins"}
report_timing -from $pcie_coreclk -to $dma_link_down -delay_type min_max -max_paths 10 -path_type full_clock_expanded -file [file join $output targeted_pcie_timing.rpt]
report_timing -to $dma_link_down -delay_type min_max -max_paths 10 -path_type full_clock_expanded -file [file join $output dma_link_down_endpoint_timing.rpt]
report_timing -from [get_clocks io_clk_pcie_00_clk_p] -to [get_clocks dma_ip_axi_aclk_1] -delay_type min_max -max_paths 10 -path_type full_clock_expanded -file [file join $output pcie_ref_to_dma_timing.rpt]
set targeted_setup [get_timing_paths -from $pcie_coreclk -to $dma_link_down -delay_type max -max_paths 1]
set targeted_slack null
if {[llength $targeted_setup] == 1} {set targeted_slack [get_property SLACK $targeted_setup]}
reset_methodology
report_methodology -no_waivers -file [file join $output methodology.rpt]
report_route_status -file [file join $output route_status.rpt]
report_bus_skew -delay_type min_max -warn_on_violation -file [file join $output bus_skew.rpt]
report_cdc -details -all_checks_per_endpoint -file [file join $output cdc.rpt]
report_utilization -file [file join $output utilization.rpt]
set vf [open [file join $output violations.json] w]
puts $vf "\["
set first 1
foreach kind {drc cdc methodology} {
    if {$kind eq "cdc"} {set findings [get_cdc_violations]} elseif {$kind eq "drc"} {
        set findings [get_drc_violations]
    } else {set findings [get_methodology_violations]}
    foreach finding $findings {
        if {!$first} {puts $vf ","}
        set first 0
        puts -nonewline $vf "\{\"kind\":[quote_json $kind],\"properties\":\{"
        set first_property 1
        foreach property [lsort [list_property $finding]] {
            if {!$first_property} {puts -nonewline $vf ","}
            set first_property 0
            puts -nonewline $vf "[quote_json $property]:[quote_json [get_property $property $finding]]"
        }
        if {$kind eq "drc"} {
            set check [get_property CHECK $finding]
            lassign [dict get $drc_defaults $check] default_severity default_enabled
            lassign [dict get $drc_effective $check] effective_severity effective_enabled
            foreach {property value} [list DEFAULT_RULE_SEVERITY $default_severity EFFECTIVE_RULE_SEVERITY $effective_severity DEFAULT_RULE_ENABLED $default_enabled EFFECTIVE_RULE_ENABLED $effective_enabled] {
                puts -nonewline $vf ",[quote_json $property]:[quote_json $value]"
            }
            set sites [lsort -unique [get_sites -of_objects $finding]]
            set affected_cells [get_cells -of_objects $finding]
            set cell_pblocks {}
            if {[llength $affected_cells]} {set cell_pblocks [lsort -unique [get_pblocks -of_objects $affected_cells]]}
            puts -nonewline $vf ",\"ASSOCIATED_SITES\":[quote_json $sites],\"ASSOCIATED_CELL_PBLOCKS\":[quote_json $cell_pblocks]"
        }
        if {$kind eq "methodology" || $kind eq "drc"} {
            foreach {property getter} {ASSOCIATED_CELLS get_cells ASSOCIATED_PINS get_pins ASSOCIATED_NETS get_nets ASSOCIATED_PORTS get_ports} {
                if {!$first_property} {puts -nonewline $vf ","}
                set first_property 0
                set objects [lsort -unique [$getter -of_objects $finding]]
                puts -nonewline $vf "[quote_json $property]:[quote_json $objects]"
            }
        }
        puts -nonewline $vf "\}\}"
    }
}
puts $vf "\n\]"
close $vf
set irq_cells {}
set irq_records {}
set irq_output [get_pins -hierarchical -filter {NAME == "level0_i/ulp/mmul_sysbase_1/inst/interrupt"}]
if {[llength $irq_output] != 1} {error "Expected the exact implemented kernel interrupt output"}
set irq_startpoints [lsort -unique [all_fanin -flat -startpoints_only -to $irq_output]]
set irq_sources [irq_launch_outputs $irq_startpoints]
if {[llength $irq_sources] != 1} {error "Kernel interrupt must have exactly one registered launch point: $irq_sources"}
set irq_source_cells [get_cells -of_objects $irq_sources]
if {[llength $irq_source_cells] != 1} {error "Expected one registered interrupt source cell"}
set irq_source_net_pins [get_pins -of_objects [get_nets -segments -of_objects $irq_sources]]
set irq_output_on_source_net [expr {[lsearch -exact $irq_source_net_pins $irq_output] >= 0}]
set irq_stages [list \
    {level0_i/ii_level0_pipe/inst/pxi_ii_core/inst/ip_irq_cu_00/inst/q_i_reg[1]} \
    {level0_i/blp/blp_i/PLP/ss_ert/inst/user_peripherals/intc_hierarchy/axi_intc_cu_bank_00/U0/INTC_CORE_I/INTR_DETECT_GEN[1].ASYNC_GEN.intr_ff_reg[0]} \
    {level0_i/blp/blp_i/PLP/ss_ert/inst/user_peripherals/intc_hierarchy/axi_intc_cu_bank_00/U0/INTC_CORE_I/INTR_DETECT_GEN[1].ASYNC_GEN.intr_ff_reg[1]}]
set irq_cells [concat $irq_source_cells $irq_stages]
foreach finding [get_cdc_violations] {
    set source_pin [get_property STARTPOINT_PIN $finding]
    set destination_pin [get_property ENDPOINT_PIN $finding]
    if {[string match "level0_i/ulp/mmul_sysbase_1/*" $source_pin] || [string match "level0_i/ulp/mmul_sysbase_1/*" $destination_pin]} {
        lappend irq_records [get_property NAME $finding]
        foreach pin_name [list $source_pin $destination_pin] {
            set pin [get_pins -hierarchical -filter [format {NAME == "%s"} $pin_name]]
            foreach cell [get_cells -of_objects $pin] {lappend irq_cells $cell}
        }
        foreach cell [get_property SYNCHRONIZER $finding] {lappend irq_cells $cell}
    }
}
set iq [open [file join $output irq_structure.json] w]
set kernel_cell [get_cells -hierarchical -filter {NAME == "level0_i/ulp/mmul_sysbase_1/inst"}]
set kernel_ref ""
set kernel_orig_ref ""
set kernel_dont_partition 0
if {[llength $kernel_cell] == 1} {
    set kernel_ref [get_property REF_NAME $kernel_cell]
    set kernel_orig_ref [get_property ORIG_REF_NAME $kernel_cell]
    if {[lsearch -exact [list_property $kernel_cell] DONT_PARTITION] >= 0} {
        set kernel_dont_partition [get_property DONT_PARTITION $kernel_cell]
    }
}
set irq_exception_pins [lsort -unique [get_pins -hierarchical -filter {NAME=~level0_i/ulp/*lp_s_irq_cu_00*}]]
set hbm_reset_exception_pins [lsort -unique [get_pins -hierarchical -regexp {.*mss_0/inst/hbm_inst/inst/.*_STACK.*/AXI_.*_ARESET_N.*}]]
if {[llength $irq_exception_pins] == 0 || [llength $hbm_reset_exception_pins] == 0} {
    error "Expected inherited IRQ/HBM reset constraint selectors to match actual pins"
}
puts $iq "\{\"kernel_partition_control\":\{\"count\":[llength $kernel_cell],\"name\":[quote_json $kernel_cell],\"ref_name\":[quote_json $kernel_ref],\"orig_ref_name\":[quote_json $kernel_orig_ref],\"dont_partition\":$kernel_dont_partition\},\"cdc_records\":[quote_json [lsort -unique $irq_records]],\"irq_exception_pins\":[quote_json $irq_exception_pins],\"hbm_reset_exception_pins\":[quote_json $hbm_reset_exception_pins],\"registered_source\":\{\"output_pin\":[quote_json $irq_output],\"source_pins\":[strings_json $irq_sources],\"source_cells\":[strings_json $irq_source_cells],\"timing_startpoints\":[strings_json $irq_startpoints],\"output_on_source_net\":$irq_output_on_source_net\},\"destination_stages\":[strings_json $irq_stages],\"connections\":\["
set previous_pin [lindex $irq_sources 0]
set index 0
foreach stage $irq_stages {
    set destination [get_pins -hierarchical -filter [format {NAME == "%s/D"} $stage]]
    if {[llength $destination] != 1} {error "Missing exact interrupt destination pin: $stage/D"}
    set start [get_pins -hierarchical -filter [format {NAME == "%s"} $previous_pin]]
    if {[llength $start] != 1} {error "Missing exact interrupt source pin: $previous_pin"}
    set fanin_startpoints [lsort -unique [all_fanin -flat -startpoints_only -to $destination]]
    set fanin [irq_launch_outputs $fanin_startpoints]
    set segments [lsort -unique [get_nets -segments -of_objects $start]]
    set net_pins [get_pins -of_objects $segments]
    set destination_on_source_net [expr {[lsearch -exact $net_pins $destination] >= 0}]
    set selector_intersection {}
    foreach pin $irq_exception_pins {
        if {[lsearch -exact $net_pins $pin] >= 0} {lappend selector_intersection $pin}
    }
    if {$index != 0} {puts $iq ","}
    puts -nonewline $iq "\{\"from_pin\":[quote_json $previous_pin],\"to_pin\":[quote_json $destination],\"fanin_pins\":[strings_json $fanin],\"fanin_startpoints\":[strings_json $fanin_startpoints],\"net_segments\":[strings_json $segments],\"destination_on_source_net\":$destination_on_source_net,\"exception_selector_intersection\":[strings_json $selector_intersection],\"timing\":\{"
    set first_timing 1
    foreach {kind delay} {setup max hold min} {
        set paths {}
        # The source crossing is asynchronous. The vendor cuts the input to
        # intr_ff[0]; preserve its null slack and explicit exception. Only
        # intr_ff[0] -> intr_ff[1] is the marked, timed synchronizer pair.
        if {$index != 0} {
            set launch_clock_pin [get_pins -hierarchical -filter [format {NAME == "%s/C"} [file dirname $previous_pin]]]
            set paths [get_timing_paths -from $launch_clock_pin -to $destination -delay_type $delay -max_paths 1]
        }
        set slack null
        if {[llength $paths] == 1} {
            set reported_slack [get_property SLACK $paths]
            if {[regexp {^[+-]?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?$} $reported_slack]} {
                set slack [format %.9g $reported_slack]
            }
        }
        if {!$first_timing} {puts -nonewline $iq ","}
        set first_timing 0
        puts -nonewline $iq "[quote_json $kind]:\{\"count\":[llength $paths],\"slack_ns\":$slack,\"properties\":\{"
        set first_path_property 1
        if {[llength $paths] == 1} {
            foreach property [lsort [list_property $paths]] {
                if {!$first_path_property} {puts -nonewline $iq ","}
                set first_path_property 0
                puts -nonewline $iq "[quote_json $property]:[quote_json [get_property $property $paths]]"
            }
        }
        puts -nonewline $iq "\}\}"
    }
    puts -nonewline $iq "\}\}"
    set previous_pin "$stage/Q"
    incr index
}
puts $iq "\],\"cells\":\["
set first 1
foreach cell_name [lsort -unique $irq_cells] {
    set cell [get_cells -hierarchical -filter [format {NAME == "%s"} $cell_name]]
    if {[llength $cell] != 1} {error "Expected exact IRQ source/synchronizer cell: $cell_name"}
    if {!$first} {puts $iq ","}
    set first 0
    set clocks [lsort -unique [get_clocks -of_objects [get_pins -of_objects $cell -filter {REF_PIN_NAME == C}]]]
    puts -nonewline $iq "\{\"name\":[quote_json $cell_name],\"clocks\":[quote_json $clocks],\"properties\":\{"
    set first_property 1
    foreach property [lsort -unique [concat [list_property $cell] {ASYNC_REG}]] {
        if {!$first_property} {puts -nonewline $iq ","}
        set first_property 0
        puts -nonewline $iq "[quote_json $property]:[quote_json [get_property $property $cell]]"
    }
    puts -nonewline $iq "\}\}"
}
puts $iq "\n\]\}"
close $iq
set pf [open [file join $output targeted_paths.json] w]
puts $pf "\["
set first 1
foreach kind {global_setup exact_pin_setup endpoint_setup} {
    if {$kind eq "exact_pin_setup"} {
        set paths [get_timing_paths -from $pcie_coreclk -to $dma_link_down -delay_type max -max_paths 1]
    } elseif {$kind eq "global_setup"} {
        set paths [get_timing_paths -delay_type max -max_paths 20 -nworst 2]
    } else {set paths [get_timing_paths -to $dma_link_down -delay_type max -max_paths 10]}
    foreach path $paths {
        if {!$first} {puts $pf ","}
        set first 0
        puts -nonewline $pf "\{\"kind\":[quote_json $kind],\"properties\":\{"
        set first_property 1
        foreach property [lsort [list_property $path]] {
            if {!$first_property} {puts -nonewline $pf ","}
            set first_property 0
            puts -nonewline $pf "[quote_json $property]:[quote_json [get_property $property $path]]"
        }
        puts -nonewline $pf "\}\}"
    }
}
puts $pf "\n\]"
close $pf
set targeted_setup [get_timing_paths -from $pcie_coreclk -to $dma_link_down -delay_type max -max_paths 1]
set targeted_slack null
if {[llength $targeted_setup] == 1} {set targeted_slack [get_property SLACK $targeted_setup]}
set setup [get_timing_paths -delay_type max -max_paths 1]
set hold [get_timing_paths -delay_type min -max_paths 1]
if {[llength $setup] != 1 || [llength $hold] != 1} {error "Missing routed setup/hold timing paths"}
set fp [open [file join $output metrics.json] w]
set wns [get_property SLACK $setup]
set whs [get_property SLACK $hold]
set drc_errors [llength [get_drc_violations -filter {SEVERITY == Error}]]
set drc_critical [llength [get_drc_violations -filter {SEVERITY == "Critical Warning"}]]
set drc_warnings [llength [get_drc_violations -filter {SEVERITY == Warning}]]
set full_version [version]
if {![regexp {SW Build ([0-9]+)} $full_version unused tool_build]} {error "Missing Vivado tool build identity"}
set tool_version [version -short]
puts -nonewline $fp "{\"setup_wns_ns\":$wns,\"hold_whs_ns\":$whs,\"drc_errors\":$drc_errors,\"drc_critical_warnings\":$drc_critical,\"drc_warnings\":$drc_warnings,\"drc_default_settings_applied\":true,\"drc_waivers_ignored\":true,\"targeted_pcie_setup_paths\":[llength $targeted_setup],\"targeted_pcie_setup_slack_ns\":$targeted_slack,\"tool\":{\"vivado_version\":[quote_json $tool_version],\"vivado_sw_build\":[quote_json $tool_build]},\"pblocks\":\["
set first 1
foreach pblock [get_pblocks] {
    if {!$first} {puts -nonewline $fp ","}
    set first 0
    puts -nonewline $fp "\{\"name\":[quote_json $pblock],\"properties\":\{"
    set first_property 1
    foreach property [lsort [list_property $pblock]] {
        if {!$first_property} {puts -nonewline $fp ","}
        set first_property 0
        puts -nonewline $fp "[quote_json $property]:[quote_json [get_property $property $pblock]]"
    }
    puts -nonewline $fp "\}\}"
}
puts $fp "\]\}"
close $fp
close_design
puts "SYSBASE_SIGNOFF_REPORTS_COMPLETE"
