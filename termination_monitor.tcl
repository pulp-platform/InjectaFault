# Copyright 2023 ETH Zurich and University of Bologna.
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
#                       2 : Important information and termination status of
#                           the running programm (Recommended). Default
#                       3 : All information that is possible
# ----------------------------- Suscepitbility Test ---------------------------
# 'termination_signal_list' : A list containing the information for all
#                       termination signals to be monitored. The list has has
#                       entries of the format {id source display_name}.
#                       The parameters for each entry are defined as follows:
#                       'id' : a positive integer holding the unique id of
#                         monitor by which the monitor is identified.
#                       'source' : The termination signal can have two sources.
#                         If the termination signal is determined by a signal
#                         in the testbench, the 'source' is the path to that
#                         signal. The signal must be a single bit.
#                         If the termination signal is a timeout, than 'source'
#                         is set as the timeout time.
#                       'display_name' : Unique name if the termination
#                         condition used to identify the condition in print
#                         statments and internal identification. Note that the
#                         'display_name' is used to create labeled 'when'
#                         statements, so the display name has to be chosen
#                         carefully and should not contain spaces.
#                       Note that if multiple termination conditions are met
#                       simultaneously, only the cause with the highest ID is
#                       reported.
#                       An example for a 'termination_signal_list' is below:
#                       {{2 "/tb/exception" "Exception"} \
#                        {1 "100 ns"        "Timeout"  } \
#                        {0 "/tb/eoc"       "EOC"      }}
#                       The termination signals are an Exception and a EOC
#                       signal, and a timeout set as 100 ns.
# 'termination_report_x_as_id' : If any of the termination signals are evaluated
#                       as 'x' or 'z', this script will report a termination
#                       with 'termination_report_x_as_id' as termination ID.
#                       If 'termination_report_x_as_id' is set to -1 (default),
#                       Reading an 'x' or 'Z' will not be reported and are
#                       treated as 0. Note that ids are reported as described
#                       below.
# 'termination_report_proc' : User-defined procedure to be called when a
#                       termination cause is detected. When a termination cause
#                       is detected, this script calls 'termination_report_proc'
#                       with the 'id' of the termination cause as the single
#                       argument.
#                       If multiple termination signals or conditions are
#                       active, only the termination cause with the highest 'id'
#                       will be reported.
# 'termination_post_report_proc' : A procedure without arguments to be called
#                       after 'termination_report_proc' was called. For example,
#                       this can be 'stop' (default), which causes the
#                       to stop. If the simulation should be repeated multiple
#                       times, a powerful combination is setting
#                       'termination_post_report_proc' to 'stop' and calling
#                       the simulation with the arguments
#                         -do "run -all; while {1} {restart -f; run -all;}"
#                       which will cause the simulation to automatically
#                       restart and run again from the beginning.
# ================ List of procs that may be called externally ================
# 'termination_reset_monitors' : Stop all monitors and create new monitors.
#                       This proc may be called after the above settings were
#                       changed. When this script is sourced, this proc
#                       is called automatically
# 'termination_stop_monitors' : Proc without arguments that will disable any
#                       currently running monitors. This proc should be called
#                       if the termination monitors are no longer needed, or
#                       the 'termination_signal_list' changed and this script
#                       is sourced again.


##################################
#  Set default parameter values  #
##################################

# General
if {![info exists ::verbosity]} { set ::verbosity 2 }

# Suscepitbility Test
if {![info exists ::termination_signal_list]}      { set ::termination_signal_list     [list] }
if {![info exists ::termination_report_x_as_id]}   { set ::termination_report_x_as_id     -1  }
if {![info exists ::termination_report_proc]}      { set ::termination_report_proc      echo  }
if {![info exists ::termination_post_report_proc]} { set ::termination_post_report_proc stop  }

########################################
#  Finish setup depending on settings  #
########################################

set ::termination_timeout_regex "\\s*\\d+\\s*(hr|min|sec|ms|us|ns|ps|fs)?\\s*"

set ::termination_active_monitors [list]

if {[llength $::termination_signal_list] == 0 && $::verbosity >= 1} {
  echo "\[Termination Monitor\] Warning: No monitors selected!"
}

set ::termination_report_backoff 0

#######################
#  Helper Procedures  #
#######################

proc ::termination_find_cause {} {
  # Check if this is a redundant call
  if {$::termination_report_backoff != 0} {
    incr ::termination_report_backoff -1
    return
  }
  set termination_cause_id -1
  # Check all termination signals
  foreach termination_signal $::termination_signal_list {
    set termination_signal_active 0
    # Unpack termination signal information
    foreach {id signal_path display_name} $termination_signal {}
    # Test if the signal cause is a time
    if {[regexp $::termination_timeout_regex $signal_path]} {
      set termination_signal_active [gteTime $::now $signal_path]
    } else {
      # Examine the termination signal
      set termination_signal_active [examine -radix binary $signal_path]
      # Report The extracted signal
      if {$::verbosity >= 3} {
        echo "\[Termination Monitor\] Evaluated Signal '$display_name' to $termination_signal_active."
      }
      # Cleanup signal
      if { $termination_signal_active == "x" || $termination_signal_active == "X" || \
           $termination_signal_active == "z" || $termination_signal_active == "Z" } {
        # Cleanup required
        if {$::termination_report_x_as_id == -1} {
          # Reporting x and z is disabled
          set termination_signal_active 0
        } else {
          # Report x and z with special ID
          if {$::verbosity >= 3} {
            echo "\[Termination Monitor\] Detected $termination_signal_active on Monitor '$display_name'. \
                  This will be reported as termination with id $::termination_report_x_as_id."
          }
          set termination_signal_active 1
          set id $::termination_report_x_as_id
        }
      }
    }
    if {$termination_signal_active} {
      # Check if multiple termination conditions are active
      if {$termination_cause_id != -1} {
        incr ::termination_report_backoff
        if {$::termination_report_backoff == 1 && $::verbosity >= 2} {
          echo "\[Termination Monitor\] Warning: Multiple Termination causes active!"
        }
      }
      if {$::verbosity >= 2} {
        echo "\[Termination Monitor\] Detected Termination cause: '$display_name' ($id)."
      }
      # Report the termination signal with the highest ID.
      if {$id > $termination_cause_id} {
        set termination_cause_id $id
      }
    }
  }
  # Report the termination
  $::termination_report_proc $termination_cause_id
  # Run the post termination proc
  $::termination_post_report_proc
}

proc termination_stop_monitors {} {
  # Stop all active monitors
  foreach monitor $::termination_active_monitors {
    catch {nowhen $monitor}
  }
  # Clear the active monitor list
  set ::termination_active_monitors [list]
  set ::termination_report_backoff 0

  if {$::verbosity >= 2} {
    echo "\[Termination Monitor\] Disabled all Monitors."
  }
}

proc termination_reset_monitors {} {
  # Create monitors for all selected termination signals
  foreach termination_signal $::termination_signal_list {
    # Unpack information for termination signal
    foreach {id signal_path display_name} $termination_signal {}

    # Test if the signal cause is a time
    if {[regexp $::termination_timeout_regex $signal_path]} {
      set monitor_type "Timeout Monitor"
      set term_condition "\$now >= $signal_path"
    } else {
      set monitor_type "Signal Monitor"
      if {$::termination_report_x_as_id == -1} {
        set term_condition "$signal_path == 1"
      } else {
        set term_condition "$signal_path != 0"
      }
    }

    # Print the individual monitors
    if {$::verbosity >= 3} {
      echo "\[Termination Monitor\] Creating $monitor_type at '$signal_path' with ID $id using display name '$display_name'."
    }

    # Create the monitor
    when -label $display_name $term_condition {
      ::termination_find_cause
    }

    # Add the mmonitor to the active monitors
    lappend termination_active_monitors $display_name
  }
}

##################
#  Initial Call  #
##################

# Create all monitors
termination_reset_monitors
