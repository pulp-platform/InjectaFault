# Copyright 2021 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Author: Luca Rufer (lrufer@student.ethz.ch)

# ============ List of variables that may be passed to this script ============
# ----------------------------------- General ---------------------------------
# 'verbosity'         : Controls the amount of information printed during script
#                       execution. Possible values are:
#                       0 : No statements at all
#                       1 : Only important initializaion information
#                       2 : Important information and occurences of bitflips
#                           (Recommended). Default
#                       3 : All information that is possible
# 'log_injections'    : Create a logfile of all injected faults, including
#                       timestamps, the absolute path of the flipped net, the
#                       value before the flip, the value after the flip and
#                       more.
#                       The logfile is named "fault_injection_<time_stamp>.log".
#                       0 : Disable logging (Default)
#                       1 : Enable logging
# 'seed'              : Set the seed for the number generator. Default: 12345
# ------------------------------- Timing settings -----------------------------
# 'inject_start_time' : Earliest time of the first fault injection.
# 'inject_stop_time'  : Latest possible time for a fault injection.
#                       Set to 0 for no stop.
# 'injection_clock'   : Absolute path to the net that is used as an injected
#                       trigger and clock. Can be a special trigger clock in
#                       the testbench, or the normal system clock.
# 'injection_clock_trigger' : Signal value of 'injection_clock' that triggers
#                       the fault injection. If a normal clock of a rising edge
#                       triggered circuit is used as injection clock, it is
#                       recommended to set the trigger to '0', so injected
#                       flips can clearly be distinguished in the waveforms.
# 'fault_period'      : Period of the fault injection in clock cycles of the
#                      injection clock. Set to 0 for only a single flip.
# 'fault_duration'    : Duration of injected faults.
# -------------------------------- Flip settings ------------------------------
# 'allow_multi_bit_upset' : Allow injecting another error in a net that was
#                       already flipped and not driven to another value yet.
#                       0 : Disable multi bit upsets
#                       1 : Enable multi bit upsets
# 'check_core_output_modification' : Check if an injected fault changes the
#                       output of the circuit under test. All nets in
#                       'output_netlist' are checked. The result of the check
#                       is printed after every flip (if verbosity high enough),
#                       and logged to the logfile.
#                       0 : Disable output modification checks. The check will
#                           be logged as 'x'.
#                       1 : Enable output modification checks.
# 'check_core_next_state_modification' : Check if an injected fault changes the
#                       next state of the circuit under test. All nets in
#                       'next_state_netlist' are checked. The result of the
#                       check is printed after every flip (if verbosity high
#                       enough), and logged to the logfile.
#                       0 : Disable next state modification checks. The check
#                           will be logged as 'x'.
#                       1 : Enable next state modification checks.
# ---------------------------------- Netlists ---------------------------------
# 'inject_netlist'    : List of absolute net or register paths to be flipped
#                       in the simulation. If the inject netlist is changed
#                       after this script was first called, the proc
#                       'updated_inject_netlist' must be called.
# 'output_netlist'    : List of absolute net or register paths to be used for
#                       the output modification check.
# 'next_state_netlist' : List of absolute net or register paths to be used for
#                       the next state modification check.
# 'assertion_disable_list' : List of absolute paths to named assertions that
#                       need to be disabled for during fault injecton.
#                       Assertions are enabled again after the simulation stop
#                       time.

##################################
#  Set default parameter values  #
##################################

# General
if {![info exists verbosity]}      { set verbosity          2 }
if {![info exists log_injections]} { set log_injections     0 }
if {![info exists seed]}           { set seed           12345 }
# Timing settings
if {![info exists inject_start_time]}       { set inject_start_time 100ns   }
if {![info exists inject_stop_time]}        { set inject_stop_time    0     }
if {![info exists injection_clock]}         { set injection_clock   "clk"   }
if {![info exists injection_clock_trigger]} { set injection_clock_trigger 0 }
if {![info exists fault_period]}            { set fault_period        0     }
if {![info exists fault_duration]}          { set fault_duration      1ns   }
# Flip settings
if {![info exists allow_multi_bit_upset]}              { set allow_multi_bit_upset              0 }
if {![info exists check_core_output_modification]}     { set check_core_output_modification     0 }
if {![info exists check_core_next_state_modification]} { set check_core_next_state_modification 0 }
# Netlists
if {![info exists inject_netlist]}         { set inject_netlist         [list] }
if {![info exists output_netlist]}         { set output_netlist         [list] }
if {![info exists next_state_netlist]}     { set next_state_netlist     [list] }
if {![info exists assertion_disable_list]} { set assertion_disable_list [list] }

# Source generic netlist extraction procs
source ../scripts/fault_injection/extract_nets.tcl

########################################
#  Finish setup depending on settings  #
########################################

# Set the seed
expr srand($seed)

# Common path sections of all nets where errors can be injected
set netlist_common_path_sections [list]

#######################
#  Helper Procedures  #
#######################

proc time_ns {time_ps} {
  set time_str ""
  append time_str "[expr $time_ps / 1000]"
  set remainder [expr $time_ps % 1000]
  if {$remainder != 0} {
    append time_str "."
    if {$remainder < 100} {append time_str "0"}
    if {$remainder < 10} {append time_str "0"}
    append time_str "$remainder"
  }
  append time_str " ns"
  return $time_str
}

proc find_common_path_sections {netlist} {
  # Safety check if the list has any elements
  if {[llength $netlist] == 0} {
    return [list]
  }
  # Extract the first net as reference
  set first_net [lindex $netlist 0]
  set first_net_sections [split $first_net "/"]
  # Determine the minimal number of sections in the netlist
  set min_num_sections 9999
  foreach net $netlist {
    set cur_path_sections [split $net "/"]
    set num_sections [llength $cur_path_sections]
    if {$num_sections < $min_num_sections} {set min_num_sections $num_sections}
  }
  # Create a match list
  set match_list [list]
  for {set i 0} {$i < $min_num_sections} {incr i} {lappend match_list 1}
  # Test for every net which sections in its path matches the first net path
  foreach net $netlist {
    set cur_path_sections [split $net "/"]
    # Test every section
    for {set i 0} {$i < $min_num_sections} {incr i} {
      # prevent redundant checking for speedup
      if {[lindex $match_list $i] != 0} {
        # check if the sections matches the first net section
        if {[lindex $first_net_sections $i] != [lindex $cur_path_sections $i]} {
          lset match_list $i 0
        }
      }
    }
  }
  return $match_list
}

proc net_print_str {net_name} {
  # Check if the list exists
  if {[llength $::netlist_common_path_sections] == 0} {
    return $net_name
  }
  # Split the netname path
  set cur_path_sections [split $net_name "/"]
  set print_str ""
  set printed_dots 0
  # check sections individually
  for {set i 0} {$i < [llength $cur_path_sections]} {incr i} {
    # check if the section at the current index is a common to all paths
    if {$i < [llength $::netlist_common_path_sections] && [lindex $::netlist_common_path_sections $i] == 1} {
      # Do not print the dots if multiple sections match in sequence
      if {!$printed_dots} {
        # Print dots to indicate the path was shortened
        append print_str "\[...\]"
        if {$i != [llength $cur_path_sections] - 1} {append print_str "/"}
        set printed_dots 1
      }
    } else {
      # Sections don't match, print the path section
      append print_str "[lindex $cur_path_sections $i]"
      if {$i != [llength $cur_path_sections] - 1} {append print_str "/"}
      set printed_dots 0
    }
  }
  return $print_str
}

proc updated_inject_netlist {} {
  # print how many nets were found
  set num_nets [llength $::inject_netlist]
  if {$::verbosity >= 1} {
    echo "\[Fault Injection\] Selected $num_nets nets for fault injection."
  }
  # print all nets that were found
  if {$::verbosity >= 3} {
    foreach net $::inject_netlist {
      echo " - [get_net_reg_width $net]-bit [get_net_type $net] : $net"
    }
    echo ""
  }
  # determine the common sections
  set ::netlist_common_path_sections [find_common_path_sections $::inject_netlist]
}

##########################
#  Random Net Selection  #
##########################

proc select_random_net { netlist } {
  set idx [expr int(rand()*[llength $netlist])]
  return [lindex $netlist $idx]
}

################
#  Flip a Bit  #
################

# flip a spefific bit of the given net name. returns a 1 if the bit could be flipped
proc flipbit {signal_name} {
  set success 0
  set old_value [examine -radixenumsymbolic $signal_name]
  # check if net is an enum
  if {[examine -radixenumnumeric $signal_name] != [examine -radixenumsymbolic $signal_name]} {
    set old_value_numeric [examine -radix binary,enumnumeric $signal_name]
    set new_value_numeric [expr int(rand()*([expr 2 ** [string length $old_value_numeric]]))]
    while {$old_value_numeric == $new_value_numeric && [string length $old_value_numeric] != 1} {
      set new_value_numeric [expr int(rand()*([expr 2 ** [string length $old_value_numeric]]))]
    }
    force -freeze sim:$signal_name $new_value_numeric, $old_value_numeric $::fault_duration -cancel $::fault_duration
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
    set old_bit_value "0"
    set new_bit_value "1"
    if {[string index $bin_val [expr $len - 1 - $flip_index]] == "1"} {
      set new_bit_value "0"
      set old_bit_value "1"
    }
    force -freeze sim:$flip_signal_name $new_bit_value, $old_bit_value $::fault_duration -cancel $::fault_duration
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
if {$log_injections} {
  set time_stamp [exec date +%Y%m%d_%H%M%S]
  set injection_log [open "fault_injection_$time_stamp.log" w+]
  puts $injection_log "timestamp,netname,pre_flip_value,post_flip_value,output_changed,new_state_changed"
}

# Update the inject netlist
updated_inject_netlist

# start fault injection
when "\$now == $inject_start_time" {
  if {$verbosity >= 1} {
    echo "$inject_start_time: \[Fault Injection\] Starting fault injection."
  }
  foreach assertion $assertion_disable_list {
    assertion enable -off $assertion
  }
}

# Dictionary to keep track of injections
set inject_dict [dict create]

# periodically inject faults
set prescaler [expr $fault_period - 1]
when "\$now >= $inject_start_time and $injection_clock == $injection_clock_trigger" {
  incr prescaler
  if {$prescaler == $fault_period && [llength $inject_netlist] != 0} {
    set prescaler 0

    # record the output before the flip
    set pre_flip_out_val [list]
    if {$check_core_output_modification} {
      foreach net $output_netlist {
        lappend pre_flip_out_val [examine $net]
      }
    }
    # record the new state before the flip
    set pre_flip_next_state_val [list]
    if {$check_core_next_state_modification} {
      foreach net $next_state_netlist {
        lappend pre_flip_next_state_val [examine $net]
      }
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
      set net_to_flip [select_random_net $inject_netlist]

      # Check if the selected net is allowed to be flipped
      set allow_flip 1
      if {!$allow_multi_bit_upset} {
        set net_value [examine -radixenumsymbolic $net_to_flip]
        if {[dict exists $inject_dict $net_to_flip] && [dict get $inject_dict $net_to_flip] == $net_value} {
          set allow_flip 0
          if {$verbosity >= 3} {
            echo "[time_ns $now]: \[Fault Injection\] Tried to flip [net_print_str $net_to_flip], but was already flipped."
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
            echo "[time_ns $now]: \[Fault Injection\] Failed to flip [net_print_str $net_to_flip]. Choosing another one."
          }
        }
      }
    }
    if {$success} {
      incr stat_num_bitflips

      set flip_propagated 0
      # record the output after the flip
      set post_flip_out_val [list]
      if {$check_core_output_modification} {
        foreach net $output_netlist {
          lappend post_flip_out_val [examine $net]
        }
        # check if the output changed
        set output_state "not modified"
        set output_changed [expr ![string equal $pre_flip_out_val $post_flip_out_val]]
        if {$output_changed} {
          set output_state "changed"
          incr stat_num_outputs_changed
          set flip_propagated 1
        }
      } else {
        set output_changed "x"
      }
      # record the new state before the flip
      set post_flip_next_state_val [list]
      if {$check_core_next_state_modification} {
        foreach net $next_state_netlist {
          lappend post_flip_next_state_val [examine $net]
        }
        # check if the new state changed
        set new_state_state "not modified"
        set new_state_changed [expr ![string equal $pre_flip_next_state_val $post_flip_next_state_val]]
        if {$new_state_changed} {
          set new_state_state "changed"
          incr stat_num_state_changed
          set flip_propagated 1
        }
      } else {
        set new_state_changed "x"
      }

      if {$flip_propagated} {
        incr stat_num_flip_propagated
      }
      # display the result
      if {$verbosity >= 2} {
        set print_str "[time_ns $now]: \[Fault Injection\] "
        append print_str "Flipped net [net_print_str $net_to_flip] from [lindex $flip_return 1] to [lindex $flip_return 2]. "
        if {$check_core_output_modification} {
          append print_str "Output signals $output_state. "
        }
        if {$check_core_next_state_modification} {
          append print_str "New state $new_state_state. "
        }
        echo $print_str
      }
      # Log the result
      if {$log_injections} {
        puts $injection_log "$now,$net_to_flip,[lindex $flip_return 1],[lindex $flip_return 2],$output_changed,$new_state_changed"
        flush $injection_log
      }
    }
  }
}

# stop the simulation and output statistics
when "\$now >= $inject_stop_time" {
  if { $inject_stop_time != 0 } {
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
    if {$log_injections} {
      close $injection_log
    }
  }
}
