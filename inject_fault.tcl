# Copyright 2021 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Author: Luca Rufer (lrufer@student.ethz.ch)

# Disable transcript
transcript quietly

##############
#  Settings  #
##############

# == Verbosity if the fault injection script ==
# 0 : No statements at all
# 1 : Only important initializaion information
# 2 : Important information and occurences of bitflips (recommended)
# 3 : All information that is possible
set ::verbosity 2

# == Base Path for the Simulations ==
proc base_path {group tile core} {return "/mempool_tb/dut/i_mempool_cluster/gen_groups\[$group\]/i_group/gen_tiles\[$tile\]/i_tile/gen_cores\[$core\]/gen_mempool_cc/riscv_core/i_snitch"}

# == List of nets that contain the state ==
set state_netlist [list]
# Regfile
lappend state_netlist [base_path 0 0 0]/gen_dmr_master_regfile/i_snitch_regfile/mem
lappend state_netlist [base_path 0 0 1]/gen_regfile/i_snitch_regfile/mem
# LSU state
set lsu_state_netlist [find signal [base_path 0 0 0]/i_snitch_lsu/*_q]
set state_netlist [concat $state_netlist $lsu_state_netlist]
# Snitch state
set snitch_state_netlist [find signal [base_path 0 0 0]/*_q]
set state_netlist [concat $state_netlist $snitch_state_netlist]

# == List of combinatorial nets that contain the next state ==
set next_state_netlist [list]
# Regfile
#lappend next_state_netlist [base_path 0 0 0]/gen_dmr_master_regfile/i_snitch_regfile/waddr_i
#lappend next_state_netlist [base_path 0 0 0]/gen_dmr_master_regfile/i_snitch_regfile/wdata_i
#lappend next_state_netlist [base_path 0 0 0]/gen_dmr_master_regfile/i_snitch_regfile/we_i
# LSU
set lsu_next_state_netlist [find signal [base_path 0 0 0]/i_snitch_lsu/*_d]
set next_state_netlist [concat $next_state_netlist $lsu_next_state_netlist]
# Snitch state
# Note: CSRs currently not included
set snitch_next_state_netlist [find signal [base_path 0 0 0]/*_d]
set next_state_netlist [concat $next_state_netlist $snitch_next_state_netlist]

# == List of output nets ==
set output_netlist [list]
# Snitch outputs
set snitch_output_netlist [find signal [base_path 0 0 0]/*_o]
set output_netlist [concat $output_netlist $snitch_output_netlist]

# == Nets to ignore for transient bit flips ==
# nets used for debugging
lappend core_netlist_ignore *gen_stack_overflow_check*
# nets that would crash the simulation if flipped
lappend core_netlist_ignore *dmr*
lappend core_netlist_ignore *hart_id*
lappend core_netlist_ignore *clk_i
lappend core_netlist_ignore *rst_i
lappend core_netlist_ignore *wfi_d
lappend core_netlist_ignore *wake_up_d
# registers/memories
lappend core_netlist_ignore *mem
lappend core_netlist_ignore *_q
# Others
# - none -

# == Nets that can be flipped (empty list {} for any random net within the core) ==
set force_flip_nets [list]

# == random seed ==
expr srand(12345)

# == Time of first fault injection
# Note: Faults will be injected on falling clock edges to make the flipped
#       Signals (and their consequences) easier to see in the simulator
set inject_start_time 2500ns

# == Period of Faults (in clk cycles, 0 for no repeat) ==
set fault_period 10

# == Time to force-stop simulation (set to 0 for no stop) ==
set inject_stop_time 3500ns

# == Assertions to be disabled to prevent simulation failures ==
# Note: Assertions will only be diabled between the inject start and stop time.
set assertion_disable_list [list]
lappend assertion_disable_list [base_path 0 0 0]/InstructionInterfaceStable
lappend assertion_disable_list [base_path 0 0 1]/InstructionInterfaceStable
lappend assertion_disable_list [base_path 0 0 0]/i_snitch_lsu/invalid_resp_id
lappend assertion_disable_list [base_path 0 0 1]/i_snitch_lsu/invalid_resp_id
lappend assertion_disable_list [base_path 0 0 0]/i_snitch_lsu/invalid_req_id
lappend assertion_disable_list [base_path 0 0 1]/i_snitch_lsu/invalid_req_id

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
    force -freeze sim:$signal_name $new_value_numeric -cancel 2ns
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
    force -freeze sim:$flip_signal_name $new_bit_value -cancel 2ns
    if {[examine -radix binary $signal_name] != $bin_val} {set success 1}
  }
  set new_value [examine -radixenumsymbolic $signal_name]
  set result [list $success $old_value $new_value]
  return $result
}

##################################
#  Net extraction utility procs  #
##################################

proc get_net_type {signal_name} {
  set sig_description [examine -describe $signal_name]
  set type_string [string trim [string range $sig_description 1 [string wordend $sig_description 1]] " \n\r()\[\]{}"]
  if { $type_string == "Verilog" } { set type_string "Enum"}
  return $type_string
}

proc get_net_array_length {signal_name} {
  set sig_description [examine -describe $signal_name]
  regexp "\\\[length (\\d+)\\\]" $sig_description -> match
  return $match
}

proc get_net_reg_width {signal_name} {
  set sig_description [examine -describe $signal_name]
  set length 1
  if {[regexp "\\\[(\\d+):(\\d+)\\\]" $sig_description -> up_lim low_lim]} {
    set length [expr $up_lim - $low_lim + 1]
  }
  return $length
}

proc get_record_field_names {signal_name} {
  set sig_description [examine -describe $signal_name]
  set matches [regexp -all -inline "Element #\\d* \"\[a-zA-Z_\]\[a-zA-Z0-9_\]*\"" $sig_description]
  set field_names {}
  foreach match $matches { lappend field_names [lindex [split $match \"] 1] }
  return $field_names
}

###########################################
#  Recursevely extract all nets and enums #
###########################################

proc extract_netlists {item_list} {
  set extract_list [list]
  foreach item $item_list {
    set item_type [get_net_type $item]
    if {$item_type == "Register" || $item_type == "Net" || $item_type == "Enum"} {
      lappend extract_list $item
    } elseif { $item_type == "Array"} {
      set array_length [get_net_array_length $item]
      for {set i 0}  {$i < $array_length} {incr i} {
        set new_net "$item\[$i\]"
        set extract_list [concat $extract_list [extract_netlists $new_net]]
      }
    } elseif { $item_type == "Record"} {
      set fields [get_record_field_names $item]
      foreach field $fields {
        set new_net $item.$field
        set extract_list [concat $extract_list [extract_netlists $new_net]]
      }
    } elseif { $item_type == "int"} {
      # Ignore
    } else {
      if { $::verbosity >= 2 } {
        echo "\[Fault Injection\] Unknown Type $item_type of net $item. Skipping..."
      }
    }
  }
  return $extract_list
}

##############################
#  Get all nets from a core  #
##############################

proc get_all_core_nets {group tile core} {

  # Path of the core
  set core_path [base_path $group $tile $core]/*

  # extract all signals from the core
  set core_netlist [find signal -r $core_path];

  # filter and sort the signals
  set core_netlist_filtered [list];
  foreach core_net $core_netlist {
    set ignore_net 0
    # ignore any net that matches any ignore pattern
    foreach ignore_pattern $::core_netlist_ignore {
      if {[string match $ignore_pattern $core_net]} {
        set ignore_net 1
      }
    }
    # add all nets that are not ignored
    if {$ignore_net == 0} {
      lappend core_netlist_filtered $core_net
    }
  }

  # sort the filtered nets alphabetically
  set core_netlist_filtered [lsort -dictionary $core_netlist_filtered]

  # recursively extract all nets and enums from arrays and structs
  set core_netlist_extracted [extract_netlists $core_netlist_filtered]

  set num_extracted [llength $core_netlist_extracted]
  if {$::verbosity >= 1} {
    echo "\[Fault Injection\] There are $num_extracted nets where faults can be injected in this simulation."
  }

  # print all nets that were found
  if {$::verbosity >= 3} {
    foreach core_net $core_netlist_extracted {
      echo " - [get_net_reg_width $core_net] bit [get_net_type $core_net] : $core_net"
    }
    echo ""
  }

  return $core_netlist_extracted
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
  if {[llength $force_flip_nets] == 0} {
    set all_nets_core_0 [get_all_core_nets 0 0 0]
  }
}

# start fault injection
when "\$now == $inject_start_time" {
  if {$verbosity >= 1} {
    echo "\[Fault Injection\] Starting fault injection."
  }
  foreach assertion $assertion_disable_list {
    assertion enable -off $assertion
  }
}

# periodically inject faults
set prescaler [expr $fault_period - 1]
when "\$now >= $inject_start_time and clk == \"1'h0\"" {
  incr prescaler
  if {$prescaler == $fault_period} {
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
    while {!$success} {
      # get a random net
      set net_to_flip ""
      if {[llength $force_flip_nets] == 0} {
        set idx [expr int(rand()*[llength $all_nets_core_0])]
        set net_to_flip [lindex $all_nets_core_0 $idx]
      } else {
        set idx [expr int(rand()*[llength $force_flip_nets])]
        set net_to_flip [lindex $force_flip_nets $idx]
      }
      # flip the random net
      set flip_return [flipbit $net_to_flip]
      if {[lindex $flip_return 0]} {
        set success 1
      } else {
        if {$::verbosity >= 3} {
          echo "\[Fault Injection\] Failed to flip $net_to_flip. Choosing another one."
        }
      }
    }
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
