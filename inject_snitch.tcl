# Copyright 2023 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Author: Luca Rufer (lrufer@student.ethz.ch)

# This configures the fault injection for the snitch core and then calls
# the fault injection script

# Disable transcript
transcript quietly

###################
#  Test Settings  #
###################

set verbosity      3
set log_injections 1
set seed       12345

set inject_start_time         2500ns
set inject_stop_time             0
set injection_clock          "clk"
set injection_clock_trigger      0
set fault_period                10
set rand_initial_injection_phase 0
set max_num_fault_inject         0
set signal_fault_duration        2ns
set register_fault_duration      0ns

set allow_multi_bit_upset              0
set check_core_output_modification     0
set check_core_next_state_modification 0
set reg_to_sig_ratio                   1
set use_bitwidth_as_weight             1

######################
#  Netlist Settings  #
######################

# == Cores where faults will be injected ==
set target_cores {{0 0 0} {0 0 1}}

# == Select where to inject faults
set inject_protected_states 0
set inject_unprotected_states 0
set inject_protected_regfile 0
set inject_unprotected_regfile 0
set inject_protected_lsu 0
set inject_unprotected_lsu 0
set inject_combinatorial_logic 1

######################
#  Extract Netlists  #
######################

# Import Netlist procs
source ../scripts/fault_injection/extract_snitch_nets.tcl

set next_state_netlist     [list]
set output_netlist         [list]
set assertion_disable_list [list]

# Add all targeted cores
foreach target $target_cores {
  foreach {group tile core} $target {}
  set next_state_netlist [concat $next_state_netlist [get_snitch_next_state_netlist $group $tile $core]]
  set output_netlist [concat $output_netlist [get_snitch_output_netlist $group $tile $core]]
  set assertion_disable_list [concat $assertion_disable_list [get_snitch_assertions $group $tile $core]]
}

# == Nets that can be flipped ==
# leave empty {} to generate the netlist according to the settings above
set force_register_netlist [list]
set force_signals_netlist [list]

set inject_register_netlist $force_register_netlist
set inject_signals_netlist $force_signals_netlist

# check net list selection is forced
if {[llength $force_register_netlist] == 0} {
  foreach target $target_cores {
    foreach {group tile core} $target {}
    if {$inject_protected_states} {
      set inject_register_netlist [concat $inject_register_netlist [get_snitch_protected_state_netlist $group $tile $core]]
    }
    if {$inject_unprotected_states} {
      set inject_register_netlist [concat $inject_register_netlist [get_snitch_unprotected_state_netlist $group $tile $core]]
    }
    if {$inject_protected_regfile} {
      set inject_register_netlist [concat $inject_register_netlist [get_snitch_protected_regfile_mem_netlist $group $tile $core]]
    }
    if {$inject_unprotected_regfile} {
      set inject_register_netlist [concat $inject_register_netlist [get_snitch_unprotected_regfile_mem_netlist $group $tile $core]]
    }
    if {$inject_protected_lsu} {
      set inject_register_netlist [concat $inject_register_netlist [get_snitch_protected_lsu_state_netlist $group $tile $core]]
    }
    if {$inject_unprotected_lsu} {
      set inject_register_netlist [concat $inject_register_netlist [get_snitch_unprotected_lsu_state_netlist $group $tile $core]]
    }
  }
}

# get all combinatorial nets of the core
if {$inject_combinatorial_logic} {
  foreach target $target_cores {
    foreach {group tile core} $target {}
    set inject_signals_netlist [concat $inject_signals_netlist [get_all_core_nets $group $tile $core]]
  }
}

# Source the fault injection script to start fault injection
source ../scripts/fault_injection/inject_fault.tcl
