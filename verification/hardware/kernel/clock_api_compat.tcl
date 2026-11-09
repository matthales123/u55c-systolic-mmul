# Vivado/Vitis 2025.1 use different native clock-solver keys.  Install through
# the supported implementation INIT_DESIGN.TCL.PRE hook after VPL imports
# ocl_util.  No installed tool, platform constraint, or RTL file is modified.
if {[version -short] ne "2025.1" || ![regexp {SW Build 6140274\M} [version]]} {
    error "Clock API compatibility shim requires reviewed Vivado 2025.1 build 6140274"
}
foreach name {initialize_clkwiz_debug uninitialize_clkwiz_debug get_clkwiz_prop set_clkwiz_prop} {
    if {[llength [info procs ::ocl_util::$name]] != 1 ||
        [string first {[current_project] test1} [info body ::ocl_util::$name]] < 0} {
        error "Unexpected Vitis clock helper or hook order: $name"
    }
}
namespace eval ::ocl_util {
    variable sysbase_clkwiz_part ""
    proc initialize_clkwiz_debug {is_versal partinfo} {
        variable sysbase_clkwiz_part
        if {$is_versal || $partinfo ne "xcu55c-fsvh2892-2L-e"} {
            error "Clock API shim is qualified only for this U55C part"
        }
        set sysbase_clkwiz_part $partinfo
        load librdi_iptasks[info sharedlibextension]
        Init_Clkwiz $sysbase_clkwiz_part test1 $partinfo
    }
    proc uninitialize_clkwiz_debug {is_versal partinfo} {
        variable sysbase_clkwiz_part
        if {$is_versal || $partinfo ne $sysbase_clkwiz_part} {error "Clock solver part changed"}
        UnInit_Clkwiz $sysbase_clkwiz_part test1
    }
    proc get_clkwiz_prop {prop} {
        variable sysbase_clkwiz_part
        return [GetClkwizProperty $sysbase_clkwiz_part test1 $prop]
    }
    proc set_clkwiz_prop {clock_freq_orig clock_freq} {
        variable sysbase_clkwiz_part
        SetClkwizProperty $sysbase_clkwiz_part test1 UseFinePS true
        set result [GetClosestSolution $sysbase_clkwiz_part test1 $clock_freq 0 50 $clock_freq_orig 0 1 false false false false false false]
        # The broken native call returns Tcl success with an error string, so
        # catch/return-code checking alone is insufficient.
        if {$result ne "1"} {error "Native clock solver did not succeed: $result"}
        foreach name {ChosenM ChosenD ChosenDiv0} {
            set value [get_clkwiz_prop $name]
            if {![string is double -strict $value] || !($value > 0 && $value < 1000000) || $value != floor($value)} {
                error "Unsupported or invalid native clock divider: $name=$value"
            }
            set values($name) $value
        }
        set actual [expr {$clock_freq_orig * double($values(ChosenM)) / ($values(ChosenD) * $values(ChosenDiv0))}]
        if {abs($actual - $clock_freq) > 0.00001} {error "Native clock solution differs from requested frequency"}
        puts "SYSBASE_CLOCK_SOLVER_PASS input_mhz=$clock_freq_orig output_mhz=$actual M=$values(ChosenM) D=$values(ChosenD) Div0=$values(ChosenDiv0)"
    }
}
puts "SYSBASE_CLOCK_API_COMPAT_INSTALLED"
