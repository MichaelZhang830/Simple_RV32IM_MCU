open_hw_manager
connect_hw_server
open_hw_target

set script_dir [file dirname [info script]]
set repo_root [file normalize $script_dir]
set bit_file [file join $repo_root "RV32IM.runs/impl_1/a7_lite_top.bit"]

if {![file exists $bit_file]} {
    puts "ERROR: bitstream not found at $bit_file"
    close_hw_manager
    exit 1
}

set hw_device [lindex [get_hw_devices xc7a35t_0] 0]
current_hw_device $hw_device
refresh_hw_device -update_hw_probes false $hw_device
set_property PROGRAM.FILE $bit_file $hw_device
program_hw_devices $hw_device
refresh_hw_device $hw_device
puts "PROGRAMMED: $bit_file"

close_hw_manager
exit
