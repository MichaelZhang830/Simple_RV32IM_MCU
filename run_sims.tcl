# Runs the testbenches with the Vivado simulator and reports pass/fail.
#
#   vivado -mode batch -notrace -source run_sims.tcl                          all testbenches
#   vivado -mode batch -notrace -source run_sims.tcl -tclargs rv32im_core_tb  one or more by name
#
# Each testbench is compiled and run in sim/xsim/<name>/, where its xsim.log is
# kept. The Vivado project is not opened or modified. The exit code is the
# number of failed testbenches.

set repo_root [file normalize [file dirname [info script]]]
set rtl_dir   [file join $repo_root RV32IM.srcs sources_1 imports design]
set tb_dir    [file join $repo_root RV32IM.sim sim_1 new]
set glbl      [file join $::env(XILINX_VIVADO) data verilog src glbl.v]

set all_tbs {module_unit_tb muldiv_booth_tb rv32im_core_tb hdmi_controller_tb}
set tbs     [expr {[llength $argv] > 0 ? $argv : $all_tbs}]

# Runs one tool, capturing its console output in a log file. Returns 1 on success.
proc run_tool {log args} {
    return [expr {![catch {exec {*}$args >& $log}]}]
}

# Compiles, elaborates and runs one testbench. Returns PASS, FAIL or a reason.
proc run_tb {tb} {
    global repo_root rtl_dir tb_dir glbl

    set tb_file [file join $tb_dir $tb.v]
    if {![file exists $tb_file]} {
        return "FAIL (no such testbench)"
    }

    set work [file join $repo_root sim xsim $tb]
    file delete -force $work
    file mkdir $work
    cd $work

    set sources [concat [lsort [glob -directory $rtl_dir *.v]] [list $tb_file $glbl]]
    if {![run_tool compile.log xvlog -d SIMULATION {*}$sources]} {
        return "FAIL (compile error, see [file join $work compile.log])"
    }
    if {![run_tool elaborate.log xelab -L unisims_ver -L secureip work.$tb work.glbl -s $tb]} {
        return "FAIL (elaboration error, see [file join $work elaborate.log])"
    }
    run_tool xsim_console.log xsim $tb -runall -log xsim.log

    # A testbench passes only if it printed its PASS line and no error lines.
    set fh [open xsim.log r]
    set log [read $fh]
    close $fh
    if {[regexp {\]\[PASS\]} $log] && ![regexp {\]\[(FAIL|ERROR)\]} $log]} {
        return "PASS"
    }
    return "FAIL (see [file join $work xsim.log])"
}

set failed 0
set summary {}
foreach tb $tbs {
    puts "\[SIM\] running $tb ..."
    set result [run_tb $tb]
    if {$result ne "PASS"} {
        incr failed
    }
    lappend summary [format "\[SIM\] %-20s %s" $tb $result]
}
cd $repo_root

puts ""
puts [join $summary "\n"]
puts "\[SIM\] [expr {[llength $tbs] - $failed}] passed, $failed failed"
exit $failed
