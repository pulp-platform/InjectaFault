# Copyright 2021 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Author: Luca Rufer (lrufer@student.ethz.ch)

# Disable transcript
transcript quietly

# == Verbosity if the fault injection script ==
# 0 : No statements at all
# 1 : Only important initializaion information
# 2 : Important information and occurences of bitflips (recommended)
# 3 : All information that is possible
set ::verbosity 2

# Import Netlist procs
source ../scripts/fault_injection/extract_nets.tcl

###################
#  Test Settings  #
###################

# == random seed ==
expr srand(12345)

# == Time of first fault injection
# Note: Faults will be injected on falling clock edges to make the flipped
#       Signals (and their consequences) easier to see in the simulator
set inject_start_time 2500ns

# == Period of Faults (in clk cycles, 0 for no repeat) ==
set fault_period 10

# == Time to force-stop simulation (set to 0 for no stop) ==
set inject_stop_time 0

# == Duration of the fault ==
set fault_duration 0.5ns

# == Cores where faults will be injected ==
set target_cores {{0 0 0} {0 0 1}}

# == Select where to inject faults
set inject_protected_states 0
set inject_unprotected_states 0
set inject_protected_regfile 0
set inject_unprotected_regfile 0
set inject_protected_lsu 1
set inject_unprotected_lsu 0
set inject_combinatorial_logic 0

# == Allow multiple injections in the same net ==
set allow_multi_bit_upset 0

# == Nets that can be flipped ==
# leave empty {} to generate the netlist according to the settings above
set force_flip_nets [list]

########################################
#  Finish setup depending on settings  #
########################################

set inject_netlist $force_flip_nets

# List of combinatorial nets that contain the next state
set next_state_netlist [list]

# List of output nets
set output_netlist [list]

# == Assertions to be disabled to prevent simulation failures ==
# Note: Assertions will only be diabled between the inject start and stop time.
set assertion_disable_list [list]

# Add all targeted cores
foreach target $target_cores {
  foreach {group tile core} $target {}
  set next_state_netlist [concat $next_state_netlist [get_next_state_netlist $group $tile $core]]
  set output_netlist [concat $output_netlist [get_output_netlist $group $tile $core]]
  set assertion_disable_list [concat $assertion_disable_list [get_assertions $group $tile $core]]
}

# check net list selection is forced
if {[llength $inject_netlist] == 0} {
  foreach target $target_cores {
    foreach {group tile core} $target {}
    if {$inject_protected_states} {
      set inject_netlist [concat $inject_netlist [get_protected_state_netlist $group $tile $core]]
    }
    if {$inject_unprotected_states} {
      set inject_netlist [concat $inject_netlist [get_unprotected_state_netlist $group $tile $core]]
    }
    if {$inject_protected_regfile} {
      set inject_netlist [concat $inject_netlist [get_protected_regfile_mem_netlist $group $tile $core]]
    }
    if {$inject_unprotected_regfile} {
      set inject_netlist [concat $inject_netlist [get_unprotected_regfile_mem_netlist $group $tile $core]]
    }
    if {$inject_protected_lsu} {
      set inject_netlist [concat $inject_netlist [get_protected_lsu_state_netlist $group $tile $core]]
    }
    if {$inject_unprotected_lsu} {
      set inject_netlist [concat $inject_netlist [get_unprotected_lsu_state_netlist $group $tile $core]]
    }
  }
}

################
#  Flip a Bit  #
################

# flip a spefific bit of the given net name. returns a 1 if the bit could be flipped
proc flipbit {signal_name} {
  # check if net is an enum
  set success 0
  set old_value [examine -radixenumsymbolic $signal_name]
  if {[examine -radixenumnumeric $signal_name] != [examine -radixenumsymbolic $signal_name]} {
    set old_value_numeric [examine -radix binary,enumnumeric $signal_name]
    set new_value_numeric [expr int(rand()*([expr 2 ** [string length $old_value_numeric]]))]
    while {$old_value_numeric == $new_value_numeric && [string length $old_value_numeric] != 1} {
      set new_value_numeric [expr int(rand()*([expr 2 ** [string length $old_value_numeric]]))]
    }
    force -freeze sim:$signal_name $new_value_numeric -cancel $::fault_duration
    set success 1
  } else {
    set flip_signal_name $signal_name
    set bin_val [examine -radix binary $signal_name]
    set len [string length $bin_val]
    set flip_index 0
    if {$len != 1} {
      set flip_index [expr int(rand()*$len)]
      set flip_signal_name $signal_name\($flip_index\)
    }
    set new_bit_value "1"
    if {[string index $bin_val [expr $len - 1 - $flip_index]] == "1"} {set new_bit_value "0"}
    force -freeze sim:$flip_signal_name $new_bit_value -cancel $::fault_duration
    if {[examine -radix binary $signal_name] != $bin_val} {set success 1}
  }
  set new_value [examine -radixenumsymbolic $signal_name]
  set result [list $success $old_value $new_value]
  return $result
}

##############################
#  Fault injection routine   #
##############################

# Statistics
set stat_num_bitflips 0
set stat_num_outputs_changed 0
set stat_num_state_changed 0
set stat_num_flip_propagated 0

# Start the Error injection script
if {$verbosity >= 1} {
  echo "\[Fault Injection\] Injection script running."
}

# Open the log file
set time_stamp [exec date +%Y%m%d_%H%M%S]
set injection_log [open "fault_injection_$time_stamp.log" w+]
puts $injection_log "timestamp,netname,pre_flip_value,post_flip_value,output_changed,new_state_changed"

# After the simulation start, get all the nets of the core
when { $now == 10ns } {
  if {$inject_combinatorial_logic} {
    foreach target $target_cores {
      foreach {group tile core} $target {}
      set inject_netlist [concat $inject_netlist [get_all_core_nets $group $tile $core]]
    }
  }
}

# start fault injection
when "\$now == $inject_start_time" {
  if {$verbosity >= 1} {
    echo "\[Fault Injection\] Starting fault injection."
    echo "\[Fault Injection\] Selected [llength $inject_netlist] nets for fault injection"
  }
  foreach assertion $assertion_disable_list {
    assertion enable -off $assertion
  }
}

# Dictionary to keep track of injections
set inject_dict [dict create]

# periodically inject faults
set prescaler [expr $fault_period - 1]
when "\$now >= $inject_start_time and clk == \"1'h0\"" {
  incr prescaler
  if {$prescaler == $fault_period && [llength $inject_netlist] != 0} {
    set prescaler 0

    # record the output before the flip
    set pre_flip_out_val [list]
    foreach net $output_netlist {
      lappend pre_flip_out_val [examine $net]
    }
    # record the new state before the flip
    set pre_flip_next_state_val [list]
    foreach net $next_state_netlist {
      lappend pre_flip_next_state_val [examine $net]
    }

    # Questa currently has a bug that it won't force certain nets. So we retry
    # until we successfully flip a net.
    # The bug primarily affects arrays of structs:
    # If you try to force a member/field of a struct in an array, QuestaSim will
    # flip force that member/field in the struct/record with index 0 in the
    # array, not at the array index that was specified.
    set success 0
    set attempts 0
    while {!$success && [incr attempts] < 50} {
      # get a random net
      set idx [expr int(rand()*[llength $inject_netlist])]
      set net_to_flip [lindex $inject_netlist $idx]

      # Check if the selected net is allowed to be flipped
      set allow_flip 1
      if {!$allow_multi_bit_upset} {
        set net_value [examine -radixenumsymbolic $net_to_flip]
        if {[dict exists $inject_dict $net_to_flip] && [dict get $inject_dict $net_to_flip] == $net_value} {
          set allow_flip 0
          if {$verbosity >= 3} {
            echo "\[Fault Injection\] Tried to flip $net_to_flip, but was already flipped."
          }
        }
      }
      # flip the random net
      if {$allow_flip} {
        set flip_return [flipbit $net_to_flip]
        if {[lindex $flip_return 0]} {
          set success 1
          if {!$allow_multi_bit_upset} {
            # save the new value to the dict
            dict set inject_dict $net_to_flip [examine -radixenumsymbolic $net_to_flip]
          }
        } else {
          if {$::verbosity >= 3} {
            echo "\[Fault Injection\] Failed to flip $net_to_flip. Choosing another one."
          }
        }
      }
    }
    if {$success} {
      incr stat_num_bitflips

      # record the output after the flip
      set post_flip_out_val [list]
      foreach net $output_netlist {
        lappend post_flip_out_val [examine $net]
      }
      # record the new state before the flip
      set post_flip_next_state_val [list]
      foreach net $next_state_netlist {
        lappend post_flip_next_state_val [examine $net]
      }
      # check if the output changed
      set output_state "not modified"
      set output_changed [expr ![string equal $pre_flip_out_val $post_flip_out_val]]
      if {$output_changed} {
        set output_state "changed"
        incr stat_num_outputs_changed
      }
      # check if the new state changed
      set new_state_state "not modified"
      set new_state_changed [expr ![string equal $pre_flip_next_state_val $post_flip_next_state_val]]
      if {$new_state_changed} {
        set new_state_state "changed"
        incr stat_num_state_changed
      }
      if {$output_changed || $new_state_changed} {
        incr stat_num_flip_propagated
      }
      # display the result
      if {$verbosity >= 2} {
        echo "\[Fault Injection\] Time: [RealToTime $now]. Flipped net $net_to_flip from [lindex $flip_return 1] to [lindex $flip_return 2]. Output signals $output_state. New state $new_state_state."
      }
      # Log the result
      puts $injection_log "$now,$net_to_flip,[lindex $flip_return 1],[lindex $flip_return 2],$output_changed,$new_state_changed"
    }
  }
}

# stop the simulation and output statistics
when "\$now >= $inject_stop_time" {
  if { $inject_stop_time != 0 } {
    # Stop the simulation
    stop
    # Enable Assertions again
    foreach assertion $assertion_disable_list {
      assertion enable -on $assertion
    }
    # Output simulation Statistics
    if {$verbosity >= 1} {
      echo " ========== Fault Injection Statistics ========== "
      echo " Number of Bitflips : $stat_num_bitflips"
      echo " Number of Bitflips propagated to outputs : $stat_num_outputs_changed"
      echo " Number of Bitflips propagated to new state : $stat_num_state_changed"
      echo " Number of Bitflips propagated : $stat_num_flip_propagated"
      echo ""
    }
    # Close the logfile
    close $injection_log
  }
}
