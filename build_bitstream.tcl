set script_dir [file dirname [info script]]
set repo_root [file normalize $script_dir]
set project_path [file join $repo_root "RV32IM.xpr"]

if {![file exists $project_path]} {
    puts "ERROR: RV32IM.xpr not found at $project_path"
    return -code error
}

open_project $project_path

reset_run synth_1
reset_run impl_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

set bit_file [file join $repo_root "RV32IM.runs/impl_1/a7_lite_top.bit"]
if {[file exists $bit_file]} {
    puts {[BITGEN][PASS]}
    puts $bit_file
} else {
    puts {[BITGEN][FAIL] bitstream not found}
    return -code error
}

close_project
exit
