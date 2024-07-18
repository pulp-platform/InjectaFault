# Copyright 2021 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Author: Luca Rufer (lrufer@student.ethz.ch)

# ============ List of variables that may be passed to this script ============
# Any of these variables may not be changed while the fault injection script
# is running, unless noted otherwise. Changing any of the settings during
# runtime may result in undefined behaviour.
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
#                       To reset the seed and start samping numbers from the
#                       start of the seed, it is in the responsibility of the
#                       user to call 'srand'. This is only done one in this
#                       script when it's sourced.
# 'print_statistics'  : Print statistics about the fault injections at the end
#                       of the fault injection. Which statistics are printed
#                       also depends on other settings below.
#                       0 : Don't print statistics
#                       1 : Print statistics (Default)
# 'script_base_path'  : Base path of all the scripts that are sourced here:
#                       Default is set to './'
# ------------------------------- Timing settings -----------------------------
# 'inject_start_time' : Earliest time of the first fault injection.
# 'inject_stop_time'  : Latest possible time for a fault injection.
#                       Set to 0 for no stop.
# 'injection_clock'   : Absolute path to the net that is used as an injected
#                       trigger and clock. Can be a special trigger clock in
#                       the testbench, or the normal system clock.
#                       If 'injection_clock' is set to an empty string (""),
#                       this script will not perform periodical fault injection.
# 'injection_clock_trigger' : Signal value of 'injection_clock' that triggers
#                       the fault injection. If a normal clock of a rising edge
#                       triggered circuit is used as injection clock, it is
#                       recommended to set the trigger to '0', so injected
#                       flips can clearly be distinguished in the waveforms.
# 'fault_period'      : How many cycles of the `injection_clock` should pass
#                       until the next fault injection is undertaken.
#                       Set to 0 for only a single flip.
# 'rand_initial_injection_phase' : Set the phase relative to the 'fault_period'
#                       to a random initial value between 0 (inclusive) and
#                       'fault_period' (exclusive). If multiple simulation
#                       with different seeds are performed, this option allows
#                       the injected faults to be evenly distributed accross
#                       the 'injection_clock' cycles.
#                       0 : Disable random phase. The first fault injection
#                           is performed at the first injeciton clock trigger
#                           after the 'inject_start_time'. Default.
#                       1 : Enable random phase.
# 'max_num_fault_inject' : Maximum number of faults to be injected. The number
#                       of faults injected may be lower than this if the
#                       simualtion finishes before, or if the 'inject_stop_time'
#                       is reached. If 'max_num_fault_inject' is set to 0, this
#                       setting is ignored (default).
# 'forced_injection_times' : Provide an explicit list of times when faults are
#                       to be injected into the simulation. If an empty
#                       'forced_injection_signals' list is provided, the signals
#                       are selected at random according to the Flip settings.
#                       By default, this list is empty.
#                       Note that flips forced by this list are not bound
#                       by the 'inject_start_time' and 'inject_stop_time'.
#                       Flips forced by this list only count towards the
#                       'max_num_fault_inject' limit if
#                       'include_forced_inj_in_stats' is set to 1.
# 'forced_injection_signals' : Provide an explicit list of signals where faults
#                       are to be injected into the simulation at the
#                       'forced_injection_times'. This list must have the same
#                       length as 'forced_injection_times'. Entries in the list
#                       must have the format {'signal_name' 'is_register}.
#                       For example: {{"tb/data_q" 1} {"tb/enable" 0}}
#                       If this list is empty, the signals to be injected at the
#                       'forced_injection_times' are selected randomly according
#                       to the settings below (default).
#                       Note that listing enums, or signals with a width wider
#                       than one bit will case a random bit to be selected,
#                       which will alter the outcome of the periodic random
#                       fault injection.
# 'include_forced_inj_in_stats' : Select wether the forced injections should be
#                       included in the statistics or not. Including them in the
#                       statistics will also cause them to be logged (if logging
#                       is enabled) and variables like 'last_flipped_net' and
#                       'last_injection_time' to be changed.
#                       0: Don't include forced injections in statistics and
#                          logs (default).
#                       1: Include forced injections in statistics and logs.
# 'signal_fault_duration' : Duration of faults injected into combinatorial
#                       signals, before the original value is restored.
# 'register_fault_duration' : Minumum duration of faults injected into
#                       registers. Faults injected into registers are not
#                       restored after the 'register_fault_duration' and will
#                       persist until overwritten by the circuit under test.
# -------------------------------- Flip settings ------------------------------
# 'allow_multi_bit_upset' : Allow injecting another error in a Register that was
#                       already flipped and not driven to another value yet.
#                       0 : Disable multi bit upsets (default)
#                       1 : Enable multi bit upsets
# 'use_bitwidth_as_weight' : Use the bit width of a net as a weight for the
#                       random fault injection net selection. If this option
#                       is enabled, a N-bit net has an N times higher chance
#                       than a 1-bit net of being selected for fault injection.
#                       0 : Disable using the bitwidth as weight and give every
#                           net the same chance of being picked (Default).
#                       1 : Enable using the bit width of nets as weights.
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
# 'reg_to_sig_ratio'  : Ratio of Registers to combinatorial signals to be
#                       selected for a fault injection. Example: A value of 4
#                       selects a ratio of 4:1, giving an 80% for a Register to
#                       be selected, and a 20% change of a combinatorial signal
#                       to be selected. If the provided
#                       'inject_register_netlist' is empty, or the
#                       'inject_signals_netlist' is empty, this parameter is
#                       ignored and nets are only selected from the non-empty
#                       netlist.
#                       Default value is 1, so the default ratio is 1:1.
# ---------------------------------- Netlists ---------------------------------
# 'inject_register_netlist' : List of absolute paths to Registers to be flipped
#                       in the simulation. This is used to simulate Single
#                       Event Upsets (SEUs). Flips injected in registers are not
#                       removed by the injection script. If the inject netlist
#                       is changed after this script was first called, the proc
#                       'updated_inject_netlist' must be called.
# 'inject_signals_netlist' : List of absolute paths to combinatorial signals to
#                       be flipped in the simulation. This is used to simulate
#                       Single Event Transients (SETs). A fault injection
#                       drives the target signal for a 'fault_duration', and
#                       afterwards returns the signal to its original state.
#                       If the inject netlist is changed after this script was
#                       first called, the proc 'updated_inject_netlist' must be
#                       called.
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
if {![info exists verbosity]}        { set verbosity          2   }
if {![info exists log_injections]}   { set log_injections     0   }
if {![info exists seed]}             { set seed           12345   }
if {![info exists print_statistics]} { set print_statistics   1   }
if {![info exists script_base_path]} { set script_base_path  "./" }
# Timing settings
if {![info exists inject_start_time]}            { set inject_start_time          100ns }
if {![info exists inject_stop_time]}             { set inject_stop_time             0   }
if {![info exists injection_clock]}              { set injection_clock             ""   }
if {![info exists injection_clock_trigger]}      { set injection_clock_trigger      0   }
if {![info exists fault_period]}                 { set fault_period                 0   }
if {![info exists rand_initial_injection_phase]} { set rand_initial_injection_phase 0   }
if {![info exists max_num_fault_inject]}         { set max_num_fault_inject         0   }
if {![info exists forced_injection_times]}       { set forced_injection_times   [list]  }
if {![info exists forced_injection_signals]}     { set forced_injection_signals [list]  }
if {![info exists include_forced_inj_in_stats]}  { set include_forced_inj_in_stats  0   }
if {![info exists signal_fault_duration]}        { set signal_fault_duration        1ns }
if {![info exists register_fault_duration]}      { set register_fault_duration      0ns }
# Flip settings
if {![info exists allow_multi_bit_upset]}              { set allow_multi_bit_upset              0 }
if {![info exists check_core_output_modification]}     { set check_core_output_modification     0 }
if {![info exists check_core_next_state_modification]} { set check_core_next_state_modification 0 }
if {![info exists reg_to_sig_ratio]}                   { set reg_to_sig_ratio                   1 }
if {![info exists use_bitwidth_as_weight]}             { set use_bitwidth_as_weight             0 }
# Netlists
if {![info exists inject_register_netlist]} { set inject_register_netlist [list] }
if {![info exists inject_signals_netlist]}  { set inject_signals_netlist  [list] }
if {![info exists output_netlist]}          { set output_netlist          [list] }
if {![info exists next_state_netlist]}      { set next_state_netlist      [list] }
if {![info exists assertion_disable_list]}  { set assertion_disable_list  [list] }

# Additional checks
if {[llength $forced_injection_times] != [llength $forced_injection_signals] && \
    [llength $forced_injection_times] != 0 && \
    [llength $forced_injection_signals] != 0} {
  if {$::verbosity >= 1} {
    echo "\[Fault Injection\] Error: 'forced_injection_times' and \
         'forced_injection_signals' don't have the same non-zero length!"
  }
  exit
}

# Source generic netlist extraction procs
source [file join ${::script_base_path} extract_nets.tcl]

########################################
#  Finish setup depending on settings  #
########################################

# Common path sections of all nets where errors can be injected
set ::netlist_common_path_sections [list]

proc restart_fault_injection {} {
  # Start the Error injection script
  if {$::verbosity >= 1} {
    echo "\[Fault Injection\] Info: Injection script running."
  }

  # cleanup from previous runs
  if {[info exists ::forced_injection_when_labels]} {
    foreach l $::forced_injection_when_labels {
      catch {nowhen $l}
    }
  }

  # Last net that was flipped
  set ::last_flipped_net ""
  set ::last_injection_time -1

  # Open the log file
  if {$::log_injections} {
    set time_stamp [exec date +%Y%m%d_%H%M%S]
    set ::injection_log [open "fault_injection_$time_stamp.log" w+]
    puts $::injection_log "timestamp,netname,pre_flip_value,post_flip_value,output_changed,new_state_changed"
  } else {
    set ::injection_log ""
  }

  # Dictionary to keep track of injections
  set ::inject_dict [dict create]

  # determine the phase for the initial fault injection
  if {$::rand_initial_injection_phase} {
    set ::prescaler [expr int(rand() * $::fault_period)]
  } else {
    set ::prescaler [expr $::fault_period - 1]
  }

  # List of when-statement labels of forced injection times
  set ::forced_injection_when_labels [list]

  # determine the first injection time
  set start_time [earliest_time [concat $::forced_injection_times $::inject_start_time]]

  # determine the injection stop time
  if {$::inject_stop_time == 0 && ![string equal $::injection_clock ""]} {
    set stop_time 0
  } else {
    set stop_time [latest_time [concat $::forced_injection_times $::inject_stop_time]]
  }

  # Create all When statements

  # start fault injection
  when -label inject_start "\$now == @$start_time" {
    ::start_fault_injection
    nowhen inject_start
  }

  # periodically inject faults
  if {![string equal $::injection_clock ""]} {
    when -label inject_fault "\$now >= @$::inject_start_time and $::injection_clock == $::injection_clock_trigger" {
      ::inject_trigger
    }
  }

  # forced injection times
  for {set i 0} { $i < [llength $::forced_injection_times] } { incr i } {
    set label "forced_injection_$i"
    set t [lindex $::forced_injection_times $i]
    if {[llength $::forced_injection_signals] == 0} {
      set cmd "::inject_fault $::include_forced_inj_in_stats"
    } else {
      # Extract the signal infos
      set signal_info [lindex $::forced_injection_signals $i]
      foreach {signal_name is_register} $signal_info {}
      if {$::include_forced_inj_in_stats} {
        set cmd "fault_injection_pre_flip_statistics; \
                 set flip_return \[::flipbit $signal_name $is_register\]; \
                 fault_injection_post_flip_statistics $signal_name \$flip_return"
      } else {
        set cmd "::flipbit $signal_name $is_register"
      }
    }
    # Create the when statement to flip the bit
    when -label $label "\$now == @$t" "$cmd"
    # Store the label
    lappend ::forced_injection_when_labels $label
  }

  # stop the simulation and output statistics
  if {$stop_time != 0} {
    when -label inject_stop "\$now > @$stop_time" {
      ::stop_fault_injection
      nowhen inject_stop
    }
  }
}

proc start_fault_injection {} {
  if {$::verbosity >= 1} {
    echo "[time_ns $::now]: \[Fault Injection\] Starting fault injection."
  }
  # Disable Assertions
  foreach assertion $::assertion_disable_list {
    assertion enable -off $assertion
  }
  # Reset statistics
  set ::stat_num_bitflips 0
  set ::stat_num_outputs_changed 0
  set ::stat_num_state_changed 0
  set ::stat_num_flip_propagated 0
}

################
#  User Procs  #
################

proc stop_fault_injection {} {
  # Stop fault injection
  catch {nowhen inject_fault}
  # Enable Assertions again
  foreach assertion $::assertion_disable_list {
    assertion enable -on $assertion
  }
  # Output simulation Statistics
  if {$::verbosity >= 1 && $::print_statistics} {
    echo " ========== Fault Injection Statistics ========== "
    echo " Number of Bitflips : $::stat_num_bitflips"
    if {$::check_core_output_modification} {
      echo " Number of Bitflips propagated to outputs : $::stat_num_outputs_changed"
    }
    if {$::check_core_next_state_modification} {
      echo " Number of Bitflips propagated to new state : $::stat_num_state_changed"
    }
    if {$::check_core_output_modification && $::check_core_next_state_modification} {
      echo " Number of Bitflips propagated : $::stat_num_flip_propagated"
    }
    echo ""
  }
  # Close the logfile
  if {$::log_injections} {
    close $::injection_log
  }
  return $::stat_num_bitflips
}

#######################
#  Helper Procedures  #
#######################

proc earliest_time {time_list} {
  if {[llength $time_list] == 0} {
    return 0
  }
  set earliest [lindex $time_list 0]
  foreach t $time_list {
    if {[ltTime $t $earliest]} {
      set earliest $t
    }
  }
  return $earliest
}

proc latest_time {time_list} {
  if {[llength $time_list] == 0} {
    return -1
  }
  set latest [lindex $time_list 0]
  foreach t $time_list {
    if {[gtTime $t $latest]} {
      set latest $t
    }
  }
  return $latest
}

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

proc calculate_weight_by_width {netlist} {
  set total_weight 0
  set group_weight_dict [dict create]
  set group_net_dict [dict create]
  foreach net $netlist {
    # determine the width of a net (used as weight)
    set width [get_net_reg_width $net]
    if {![dict exists $group_weight_dict $width]} {
      # New width discovered, add new entry
      dict set group_weight_dict $width $width
      dict set group_net_dict $width [list $net]
    } else {
      dict incr group_weight_dict $width $width
      dict lappend group_net_dict $width $net
    }
  }
  # Sum weights of all groups
  foreach group_weight [dict values $group_weight_dict] {
    set total_weight [expr $total_weight + $group_weight]
  }
  return [list $total_weight $group_weight_dict $group_net_dict]
}

proc updated_inject_netlist {} {
  # print how many nets were found
  set num_reg_nets [llength $::inject_register_netlist]
  set num_comb_nets [llength $::inject_signals_netlist]
  if {$::verbosity >= 1} {
    echo "\[Fault Injection\] Selected $num_reg_nets Registers for fault injection."
    echo "\[Fault Injection\] Selected $num_comb_nets combinatorial Signals for fault injection."
  }
  # print all nets that were found
  if {$::verbosity >= 3} {
    echo "Registers: "
    foreach net $::inject_register_netlist {
      echo " - [get_net_reg_width $net]-bit [get_net_type $net] : $net"
    }
    echo "Combinatorial Signals: "
    foreach net $::inject_signals_netlist {
      echo " - [get_net_reg_width $net]-bit [get_net_type $net] : $net"
    }
    echo ""
  }
  # determine the common sections
  set combined_inject_netlist [concat $::inject_register_netlist $::inject_signals_netlist]
  set ::netlist_common_path_sections [find_common_path_sections $combined_inject_netlist]
  # determine the distribution of the nets
  if {$::use_bitwidth_as_weight} {
    set ::inject_register_distibrution_info [calculate_weight_by_width $::inject_register_netlist]
    set ::inject_signals_distibrution_info  [calculate_weight_by_width $::inject_signals_netlist]
  }
}

##########################
#  Random Net Selection  #
##########################

proc select_random_net {} {
  # Choose between Register and Signal
  if {[llength $::inject_register_netlist] != 0 && \
     ([llength $::inject_signals_netlist] == 0 || \
      rand() * ($::reg_to_sig_ratio + 1) >= 1)} {
    set is_register 1
    set selected_list $::inject_register_netlist
  } else {
    set is_register 0
    set selected_list $::inject_signals_netlist
  }
  # Select the distribution
  if {$::use_bitwidth_as_weight} {
    # select the distribution
    if {$is_register} {
      set distibrution_info $::inject_register_distibrution_info
    } else {
      set distibrution_info $::inject_signals_distibrution_info
    }
    # unpack the distribution
    set distribution_total_weight [lindex $distibrution_info 0]
    set distribution_weight_dict  [lindex $distibrution_info 1]
    set distribution_net_dict     [lindex $distibrution_info 2]
    # determine the group
    set selec [expr rand() * $distribution_total_weight]
    dict for {group group_weight} $distribution_weight_dict {
      if {$selec <= $group_weight} {
        break
      } else {
        set selec [expr $selec - $group_weight]
      }
    }
    set selected_list [dict get $distribution_net_dict $group]
  }
  set idx [expr int(rand()*[llength $selected_list])]
  set selected_net [lindex $selected_list $idx]
  return [list $selected_net $is_register]
}

################
#  Flip a Bit  #
################

# flip a spefific bit of the given net name. returns [success, old_value, new_value] if the bit could be flipped
proc flipbit {signal_name is_register} {
  # Get the current value in binary format e.g. "6'b101010" - this works both for enums and normal signals
  set old_value_string [examine -radixenumnumeric -binary $signal_name]

  # Split it up into length and bits e.g. length="6", old_value_binary="101010"
  # We set defaults here for the rare case that we get an enum which is outside of the enumerated names
  # In that case, it might be that Questasim can't propperly output the binary representation and the regex fails
  # We will then always flip the enum back into enum case 0 - for this it should always have an enumerated name.
  set length 1
  set old_value_binary "1"
  regexp {(\d*)'b(\d*)} $old_value_string -> length old_value_binary

  # Decide which bit to flip e.g. we choose 3 out of 0 to 5
  set flip_index [expr int(rand()*$length)]

  # Find the opposite bit value at the index e.g. 3 is "1" so new_value_binary is "0"
  # String is MSB first (index 0) so we have to covert the index
  set flip_index_string [expr $length - $flip_index - 1]
  set old_bit [string index $old_value_binary $flip_index_string]
  set new_bit [expr {$old_bit == "1"} ? "0" : "1"]

  # In case there are only Xs in the value we just give up and return no success.
  if {[string length $old_bit] == 0} {
    return [list 0 "" ""]
  }

  # Get information about the signal. How it looks depends on the signal quite a bit
  set describe_string [describe $signal_name]

  # Check if the signal is an enum e.g. describe_string has "enum" in it.
  switch -glob -- $describe_string {
    *enum* {
      # In case we have an enum, we need to set the entire thing at once TODO: Maybe it can be done anyway?
      # So in this case the flip_signal_name is just the name of the signal
      # And we expand the new_value_binary to have the same width as the old_value_binary, but the one bit flipped
      set flip_signal_name $signal_name
      set flip_value_binary [string replace $old_value_binary $flip_index_string $flip_index_string $new_bit]
      set unflip_value_binary $old_value_binary
    }
    default {
      # In the case that it is not an enum, we only force the one bit that we want changed
      # So in this case we index into our signal and only force that one bit. 
      # To make sure for non-zero indexed signals, we can look at describe in ther there should be [<max_index>:<min_index>] for arrays. 
      # If regex doesnt max it we just assume it is 0-indexed.
      # Sometimes setting an index is not good on non-arrays and force gets confused, so only set it if necessary
      if {$length > 1} {
        set lower_index 0
        regexp {\[\d+:(\d+)\]} $describe_string -> lower_index
        set flip_index_with_offset [expr $flip_index + $lower_index]
        set flip_signal_name $signal_name\[$flip_index_with_offset\]    
      } else {
        set flip_signal_name $signal_name
      }
      set flip_value_binary $new_bit
      set unflip_value_binary $old_bit
    }
  }

  # Get the current value in a nicer way just for the output
  set old_value_string_out [examine -radixenumsymbolic $signal_name]

  # Depending on if the thing is a register inject differently
  # 2# here defines the format as binary, so we are sure we have the same format in and out.
  if {$is_register} {
    force -freeze $flip_signal_name "2#$flip_value_binary" -cancel $::register_fault_duration
  } else {
    # Figure out if the signal is an Enum or Register. In that case it might not return
    # to the previous value alone when force is cancelled and we need to manually check it
    switch -glob -- $describe_string {
      *Register* {
        # Registers always need a manual unflip
        set manual_unflip 1   
      }
      *enum* {
        # For enums, we can't tell if they are a register or not, unflip to be save
        set manual_unflip 1   
      }
      default {
        set manual_unflip 0   
      }
    }

    if {$manual_unflip == 0} {
      # We don't need a manual unflip -> force directly with the wanted duration
      force -freeze $flip_signal_name "2#$flip_value_binary" -cancel $::signal_fault_duration
    } else {
      # We need a manual unflip -> deposit the new signal, then go back and fix it after some
      force -deposit $flip_signal_name "2#$flip_value_binary"

      set unflip_time [expr $::now + $::signal_fault_duration]
      set unflip_command "::unflip_bit $signal_name $flip_signal_name $flip_value_binary $unflip_value_binary"
      when -label unflip "\$now == @$unflip_time" "$unflip_command"
    }
  }

  # Get the value back after the force command, also in the nice representation
  set new_value_string_out [examine -radixenumsymbolic $signal_name]

  # Check that it actually changed and set success if it did
  set success [expr {[string equal $old_value_string_out $new_value_string_out]} ? 0 : 1] 
  set result [list $success $old_value_string_out $new_value_string_out]
  return $result
}

proc unflip_bit {signal_name flip_signal_name flip_value_binary unflip_value_binary} {
  # Get the current value in binary format e.g. "6'b101010" - this works both for enums and normal signals
  set current_value_string [examine -radixenumnumeric -binary $flip_signal_name]

  # Split it up into length and bits e.g. length="6", old_value_binary="101010"
  # We set defaults here for the rare case that we get an enum which is outside of the enumerated names
  # In that case we assume the value did not change and we need to unflip it.
  set current_value_binary $flip_value_binary
  regexp {\d*'b(\d*)} $current_value_string -> current_value_binary

  # Get the current value in a nicer way just for the output
  set old_value_string_out [examine -radixenumsymbolic $signal_name]

  # If the signal is still in the flipped state, unflip it
  if {[string equal $flip_value_binary $current_value_binary]} {
    force -freeze $flip_signal_name "2#$unflip_value_binary" -cancel 0

    # Get the value back after the force command, also in the nice representation
    set new_value_string_out [examine -radixenumsymbolic $signal_name]
    echo "[time_ns $::now]: \[Fault Injection\] Unflipped $flip_signal_name from $old_value_string_out to $new_value_string_out."
  } else {
    echo "[time_ns $::now]: \[Fault Injection\] Unflip on $flip_signal_name aborted because it changed to $old_value_string_out."
  }

  nowhen unflip
}

################################
#  Fault Injection Statistics  #
################################

proc fault_injection_pre_flip_statistics {} {
  # record the output before the flip
  set ::pre_flip_out_val [list]
  if {$::check_core_output_modification} {
    foreach net $::output_netlist {
      lappend ::pre_flip_out_val [examine $net]
    }
  }
  # record the new state before the flip
  set ::pre_flip_next_state_val [list]
  if {$::check_core_next_state_modification} {
    foreach net $::next_state_netlist {
      lappend ::pre_flip_next_state_val [examine $net]
    }
  }
}

proc fault_injection_post_flip_statistics {flipped_net flip_return} {
  incr ::stat_num_bitflips
  set ::last_flipped_net $flipped_net
  set ::last_injection_time $::now

  set flip_propagated 0
  # record the output after the flip
  set post_flip_out_val [list]
  if {$::check_core_output_modification} {
    foreach net $::output_netlist {
      lappend post_flip_out_val [examine $net]
    }
    # check if the output changed
    set output_state "not modified"
    set output_changed [expr ![string equal $::pre_flip_out_val $post_flip_out_val]]
    if {$output_changed} {
      set output_state "changed"
      incr ::stat_num_outputs_changed
      set flip_propagated 1
    }
  } else {
    set output_changed "x"
  }
  # record the new state before the flip
  set post_flip_next_state_val [list]
  if {$::check_core_next_state_modification} {
    foreach net $::next_state_netlist {
      lappend post_flip_next_state_val [examine $net]
    }
    # check if the new state changed
    set new_state_state "not modified"
    set new_state_changed [expr ![string equal $::pre_flip_next_state_val $post_flip_next_state_val]]
    if {$new_state_changed} {
      set new_state_state "changed"
      incr ::stat_num_state_changed
      set flip_propagated 1
    }
  } else {
    set new_state_changed "x"
  }

  if {$flip_propagated} {
    incr ::stat_num_flip_propagated
  }
  # display the result
  if {$::verbosity >= 2} {
    set print_str "[time_ns $::now]: \[Fault Injection\] "
    append print_str "Flipped net [net_print_str $flipped_net] from [lindex $flip_return 1] to [lindex $flip_return 2]. "
    if {$::check_core_output_modification} {
      append print_str "Output signals $output_state. "
    }
    if {$::check_core_next_state_modification} {
      append print_str "New state $new_state_state. "
    }
    echo $print_str
  }
  # Log the result
  if {$::log_injections} {
    puts $::injection_log "$::now,$flipped_net,[lindex $flip_return 1],[lindex $flip_return 2],$output_changed,$new_state_changed"
    flush $::injection_log
  }
}

##############################
#  Fault injection routine   #
##############################

proc inject_fault {include_in_statistics} {
  # If enabled, prepare the statistics for the flip
  if {$include_in_statistics} { fault_injection_pre_flip_statistics }

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
    set net_selc_info [::select_random_net]
    set net_to_flip [lindex $net_selc_info 0]
    set is_register [lindex $net_selc_info 1]
    # Check if the selected net is allowed to be flipped
    set allow_flip 1
    if {$is_register && !$::allow_multi_bit_upset} {
      set net_value [examine -radixenumsymbolic $net_to_flip]
      if {[dict exists $::inject_dict $net_to_flip] && [dict get $::inject_dict $net_to_flip] == $net_value} {
        set allow_flip 0
        if {$::verbosity >= 3} {
          echo "[time_ns $::now]: \[Fault Injection\] Tried to flip [net_print_str $net_to_flip], but was already flipped."
        }
      }
    }
    # flip the random net
    if {$allow_flip} {
      if {[catch {set flip_return [::flipbit $net_to_flip $is_register]}]} {
        set flip_return {0 "x" "x"}
      }
      if {[lindex $flip_return 0]} {
        set success 1
        if {$is_register && !$::allow_multi_bit_upset} {
          # save the new value to the dict
          dict set ::inject_dict $net_to_flip [examine -radixenumsymbolic $net_to_flip]
        }
      } else {
        if {$::verbosity >= 3} {
          echo "[time_ns $::now]: \[Fault Injection\] Failed to flip [net_print_str $net_to_flip]. Choosing another one."
        }
      }
    }
  }
  if {$success && !$include_in_statistics} {
    if {$::verbosity >= 2} {
      echo "[time_ns $::now]: \[Fault Injection\] \
            Flipped net [net_print_str $net_to_flip] \
            from [lindex $flip_return 1] \
            to [lindex $flip_return 2]. "
    }
  }
  if {$success && $include_in_statistics} {
    fault_injection_post_flip_statistics $net_to_flip $flip_return
  }
}

proc ::inject_trigger {} {
  # check if any nets are selected for injection
  if {[llength $::inject_register_netlist] == 0 && \
      [llength $::inject_signals_netlist] == 0} {
    return
  }
  # check if we reached the injection limit
  if {($::max_num_fault_inject != 0) && ($::stat_num_bitflips >= $::max_num_fault_inject)} {
    # Stop the simulation
    if {$::verbosity >= 2} {
      echo "\[Fault Injection\] Injection limit ($::max_num_fault_inject) reached. Stopping error injection..."
    }
    # Disable the trigger (if not already done so)
    catch {nowhen inject_fault}
    return
  }
  # increase prescaler
  incr ::prescaler
  if {$::prescaler == $::fault_period} {
    set ::prescaler 0
    # inject a fault
    ::inject_fault 1
  }
}

# Set the seed for the first time
expr srand($::seed)

# Update the inject netlist
updated_inject_netlist

# Reset the fault injection
restart_fault_injection
