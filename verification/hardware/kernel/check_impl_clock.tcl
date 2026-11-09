# Runs after VPL's generated post-init clock constraints, before placement.
update_timing -full
set clocks [get_clocks clk_kernel_00_unbuffered_net]
if {[llength $clocks] != 1} {error "Expected exactly one primary kernel clock"}
set period [get_property PERIOD $clocks]
if {![string is double -strict $period] || abs($period - 1000.0/150.0) > 0.001} {
    error "Primary implementation clock is not the requested 150 MHz: period=$period"
}
puts "SYSBASE_IMPLEMENTATION_CLOCK_PASS period_ns=$period requested_mhz=150"
# Vitis's generated SDX_KERNEL selector loses its user attribute through this
# RTL OOC checkpoint. Restore the same intended inner kernel instance's flag
# explicitly after link, before opt_design/place_design; never match a subtree.
set kernel [get_cells -hierarchical -filter {NAME == "level0_i/ulp/mmul_sysbase_1/inst"}]
if {[llength $kernel]!=1 || [get_property ORIG_REF_NAME $kernel] ne "mmul_sysbase" ||
    [get_property REF_NAME $kernel] ne "ulp_mmul_sysbase_1_0_mmul_sysbase" ||
    [get_property IS_PRIMITIVE $kernel] || [get_property IS_BLACKBOX $kernel]} {
    error "Actual kernel instance does not match the qualified partition-control target"
}
set_property DONT_PARTITION true $kernel
if {![get_property DONT_PARTITION $kernel]} {error "Kernel DONT_PARTITION restoration failed"}
puts "SYSBASE_KERNEL_DONT_PARTITION_PASS cell=$kernel orig_ref=mmul_sysbase ref=ulp_mmul_sysbase_1_0_mmul_sysbase value=1"
