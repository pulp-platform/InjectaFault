# Copyright 2023 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Author: Luca Rufer (lrufer@student.ethz.ch)

# This script configures and runs the vulnerable net analysis for the snitch core

# Disable transcript
transcript quietly

# Import Netlist procs
source ../scripts/fault_injection/snitch_extract_nets.tcl

# === General settings for Snitch ==

set target_cores {{0 0 0} {0 0 1}}

# === Configure the settings for the vulnerable net analysis ===

# General
set ::verbosity 2
set ::initial_run_proc snitch_vulnerable_net_analysis_initial_run_proc
set ::script_base_path "../scripts/fault_injection/"

proc snitch_vulnerable_net_analysis_initial_run_proc {} {
  # Log
  log "/mempool_tb/*"
  log -r "[base_path 0 0 0]/*"
  log -r "[base_path 0 0 1]/*"
  log -r "[tile_path 0 0]/gen_dmr_ctrl\[0\]/i_dmr_ctrl/*"
  # Waves
  quietly WaveActivateNextPane {} 0
  add wave /mempool_tb/wfi
  do ../scripts/questa/wave_core.tcl 0 0 0
  do ../scripts/questa/wave_core.tcl 0 0 1
  do ../scripts/questa/wave_dmr.tcl 0 0 0
  # Run
  run -all
}

# Vulnerabile Net Analysis
set ::initial_seed    12345
set ::max_num_tests       0
set ::internal_state [list]

foreach target $target_cores {
  foreach {group tile core} $target {}
  # Add all states
  set state_netlist [get_snitch_state_netlist $group $tile $core]
  # Add saved registers of regfiles (zero, ra, sp, gp, tp, s0-s11, a0, a1)
  set save_registers { 0 1 2 3 4 \
                       8 9 18 19 20 21 22 23 24 25 26 27 \
                       10 11 }
  set regfile_mem_netlist [list]
  foreach r $save_registers {
    set mem_path [regfile_path $group $tile $core]/mem\[$r\]
    lappend regfile_mem_netlist $mem_path
  }
  # Add ID available of LSU.
  # As all IDs should be available after termination, metadata is irrelevant.
  set lsu_state_netlist [lsu_id_path $group $tile $core]
  # Combine all lists
  set all_states [concat $state_netlist $regfile_mem_netlist $lsu_state_netlist]
  set ::internal_state [concat $::internal_state $all_states]
}

# Termination Monitor Signals

set ::correct_termination_signal   "/mempool_tb/terminated_no_error"
set ::incorrect_termination_signal "/mempool_tb/terminated_error"
set ::exception_termination_signal "/mempool_tb/terminated_exception"

# == Configure the settings for the fault injection script

# General Settings
set ::verbosity $::verbosity
set ::log_injections 1
set ::seed $::initial_seed
set ::print_statistics 0

# Time settings
set ::inject_start_time         634ns
set ::inject_stop_time             0
set ::injection_clock             "/mempool_tb/clk"
set ::injection_clock_trigger      0
set ::fault_period                50
set ::rand_initial_injection_phase 1
set ::max_num_fault_inject         0
set ::forced_injection_times   [list]
set ::forced_injection_signals [list]
set ::include_forced_inj_in_stats  0
set ::signal_fault_duration        2ns
set ::register_fault_duration      0ns

# Injection Settings
set ::allow_multi_bit_upset              0
set ::check_core_output_modification     0
set ::check_core_next_state_modification 0
set ::reg_to_sig_ratio                   1
set ::use_bitwidth_as_weight             1

# Select where to inject faults
set inject_registers 0
set inject_combinatorial_logic 1

set ::assertion_disable_list [list]
set ::inject_register_netlist [list]
set ::inject_signals_netlist [list]

# Create the netlists
foreach target $::target_cores {
  foreach {group tile core} $target {}
  set ::assertion_disable_list [concat $::assertion_disable_list [::get_snitch_assertions $group $tile $core]]
  if {$inject_registers} {
    set ::inject_register_netlist [concat $::inject_register_netlist [::get_snitch_all_protected_reg_netlist $group $tile $core]]
  }
  if {$inject_combinatorial_logic} {
    set ::inject_signals_netlist [concat $::inject_signals_netlist [::get_all_core_nets $group $tile $core]]
  }
}

# Finally, source the vulnerable net analysis

source ${::script_base_path}vulnerable_net_analysis.tcl

# Automatically find the first vulnerable net
vulnerable_net_analysis_find_next_vulnerable_net

# Quit
quit
