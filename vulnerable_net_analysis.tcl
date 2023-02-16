# Copyright 2023 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Author: Luca Rufer (lrufer@student.ethz.ch)

# Description: This script uses the fault injection script and the termination
#              monitor to find which nets from a given list are vulnerable
#              to injected faults (bit flips).
#              The script first runs the testbench without an injected error
#              to get a 'golden model' for the execution time and the final
#              internal state.
#              After creating the golden model, the script resets the simulation
#              and starts the testbench again, but with periodical fault
#              injection. The vulnerable net analysis uses the
#              'inject_fault.tcl' script to inject faults. ***It is in the
#              responsibility of the user to configure the settings for the
#              fault injection***.
#              While the simulation is running and more errors are
#              injected, the script checks for the following 5 termination
#              causes using the termination monitor:
#               0) The termination monitor reports that the simulation
#                  terminated without errors and the internal state of the
#                  simulation with fault injections matches the internal state
#                  of the golden model. This case is the 'Correct' case.
#               1) The termination monitor reports that the simulation
#                  terminated without errors, but the internal state of the
#                  is not the same as the golden model. This case is the
#                  'Latent' case, as it terminated corretly, but more errors
#                  migth occur if the programm is allowed to continue running
#               2) The termination monitor reports a program termination with an
#                  'Incorrect' signal.
#               3) The termination motitor reports an exception, or an invalid
#                  state ('x' or 'z') is detected on any other termination
#                  monitor signal.
#               4) The simulation takes more than 20% longer to finish the
#                  simulation compared to the golden model, indicating that
#                  the simulation is stuck in an infinite (or very long) loop,
#                  or encountered a dead-lock.
#              As an injected error may not lead to an error immediately, a
#              non-correct termination might not be caused by the last error
#              that was injected, but by an earlier error. To determine the
#              fault which caused the programm to terminate non-correctly,
#              this script runs the testbench again with the same random seed,
#              but with a different amount of injected errors. A binary search
#              is performed until the earliest injected fault is found that
#              causes the program to terminate non-correctly, even if the
#              termination cause is not the same as in the fist simulation with
#              injected faults.
#              When a vulnerable net was found using the above binary search
#              algorithm, the net name, the seed and more information is logged
#              to allow for the error to be re-created.

# ============ List of variables that may be passed to this script ============
# Any of these variables may not be changed while the vulnerable net analysis
# is running, unless noted otherwise. Changing any of the settings during
# runtime may result in undefined behaviour.
# ---------------------------------- General ----------------------------------
# 'verbosity'         : Controls the amount of information printed during script
#                       execution. Possible values are:
#                       0 : No statements at all
#                       1 : Only important initializaion information
#                       2 : Important information and termination status of
#                           the running programm (Recommended). Default
#                       3 : All information that is possible
# 'initial_run_script' : Script (including path) to be sourced before the
#                       execution of the golden model. The script should end
#                       with some form of the 'run' command to start running
#                       the simulation. If this setting is not provided by the
#                       user, or it is an empty string, then this script simply
#                       executes 'run -all'
# 'script_base_path'  : Base path of all the scripts that are sourced here:
#                        - termination_monitor.tcl
#                        - inject_fault.tcl
#                       Default is set to './'
# --------------------------- Vulnerabile Net Analysis --------------------------
# 'initial_seed'      : The first random seed that is used for the random
#                       fault injection. The rand() function is never used in
#                       this script directly, only in the fault injection
#                       script. The default value is 12345.
# 'max_num_tests'     : Maximum number of seeds to be tested. Default is 1
# 'internal_state'    : A list of signals that compose the internal state of
#                       the simulated circuit. This list of signals is used
#                       to check for latent erorrs in simulations with injected
#                       errors. If internal state check is not required, leave
#                       this list empty (default).
# ------------------------ Termination Monitor Signals ------------------------
# 'correct_termination_signal' : Path to the testbench signal that indicates
#                       a correct termination of the simulation. Note that an
#                       'x' or 'z' on this signal is interpreted as an
#                       exception. This parameter MUST be provided by the user
#                       and has no default value.
# 'incorrect_termination_signal : Path to the testbench signal that indicates
#                       an incorrect termination of the simulation. Note that an
#                       'x' or 'z' on this signal is interpreted as an
#                       exception. If no net is given for this signal, the same
#                       signal as for the exception monitoring is used.
# 'exception_termination_signal : Path to the testbench signal that indicates
#                       an exception occured in the simulation. Note that an
#                       'x' or 'z' on this signal is also interpreted as an
#                       exception. This parameter MUST be provided by the user
#                       and has no default value.

##################################
#  Set default parameter values  #
##################################

# General
if {![info exists ::verbosity]}          { set ::verbosity             2 }
if {![info exists ::initial_run_script]} { set ::initial_run_script   "" }
if {![info exists ::script_base_path]}   { set ::script_base_path   "./" }

# Vulnerabile Net Analysis
if {![info exists ::initial_seed]}   { set ::initial_seed    12345 }
if {![info exists ::max_num_tests]}  { set ::max_num_tests       1 }
if {![info exists ::internal_state]} { set ::internal_state [list] }

# Termination Monitor Signals
if {![info exists ::correct_termination_signal] || \
    ![info exists ::exception_termination_signal]} {
  echo "\[Vulnerabile Net Analysis\] Error: some mandatory variables were not set."
  quit -code 1
}
if {![info exists ::incorrect_termination_signal]} \
  { set ::incorrect_termination_signal $::exception_termination_signal }

###################
#  Utility procs  #
###################

proc reset_bisection {} {
  # reset the bisection variables
  set ::bisect_low 0
  set ::bisect_high 0

  # Remove the limit to the number of injected faults.
  set ::max_num_fault_inject 0
}

######################################
#  Termination monitor return procs  #
######################################

# Post-process the id that was returned from the fault monitor
proc vulnerable_net_process_termination_id {id} {
  # If terminated correctly, check internal state
  if {$id == 0} {
    # Examine the final state
    set final_state [list]
    foreach net $::internal_state {
      set reg_val [examine $net]
      lappend final_state $reg_val
    }
    # Check for any mismatches compared to the golden model and save the
    # indexes to a list
    set state_mismatches [list]
    for {set i 0} { $i < [llength $::internal_state] } { incr i } {
      if {[lindex $::golden_model_final_state $i] != [lindex $final_state $i]} {
        lappend state_mismatches $i
      }
    }
    # Report if mismatches were found
    if {[llength $state_mismatches] != 0} {
      # Change id if state mismatches were found
      set id 1
      if {$::verbosity >= 2} {
        echo "\[Vulnerabile Net Analysis\] Internal state check failed:"
        foreach i $state_mismatches {
          set final_state_net_val [lindex $final_state $i]
          set golden_model_net_val [lindex $::golden_model_final_state $i]
          echo " - [lindex $::internal_state $i] : expected $golden_model_net_val, got $final_state_net_val."
        }
      }
    } else {
      if {$::verbosity >= 2} {
        echo "\[Vulnerabile Net Analysis\] State check successful."
      }
    }
  }
  return $id
}

# Termination proc for the golden model (called by Termination Monitor)
proc golden_model_termination_report {id} {
  # Check that the golden model finished correctly
  if {$id != 0} {
    if {$::verbosity >= 2} {
      echo "\[Vulnerabile Net Analysis\] Error: Golden Model did not terminate correctly."
    }
    quit -code 1
    exit
  } else {
    # Record the execution time of the golden model
    set ::golden_model_execution_time $::now
    if {$::verbosity >= 2} {
      echo "\[Vulnerabile Net Analysis\] Golden model finished within $::golden_model_execution_time ps."
    }
    # Record the final state of the golden model
    set ::golden_model_final_state [list]
    foreach net $::internal_state {
      set reg_val [examine $net]
      lappend ::golden_model_final_state $reg_val
    }
  }
  # Indicate that the monitor was triggered (helps to rule out assertions)
  set ::monitor_triggered 1
}

# Termination proc for the injected simulation (called by Termination Monitor)
proc injection_termination_report {id} {
  # Post-process the id
  set id [vulnerable_net_process_termination_id $id]

  if {$::verbosity >= 2} {
    echo "\[Vulnerabile Net Analysis\] Injection terminated with id $id. \
          Flipped $::stat_num_bitflips nets, \
          maximum number of flips was set to $::max_num_fault_inject."
  }

  # Check if the current seed has finished testing
  set finished_seed 0
  if {$id == 0 && $::max_num_fault_inject == 0} {
    # Simulation ended first try or first flip caused a problem
    set finished_seed 1
    set log_string "$::seed,$id,$::stat_num_bitflips,$::last_flipped_net"
  } elseif { $::stat_num_bitflips == 1} {
    # the first flip caused a problem
    set finished_seed 1
  } else {
    # Simulation fault source not determined yet. Run bisection.
    # Test if first bisection step
    if { $::max_num_fault_inject == 0} {
      set ::bisect_high $::stat_num_bitflips
    }
    # Test if last bisection step
    if {$::bisect_high - $::bisect_low == 1} {
      # Termination condition reached.
      # Check if bisection was successful
      if {$::stat_num_bitflips == $::bisect_low} {
        if {$id == 0} {
          # Bisection successful, continue with next seed
          set finished_seed 1
          set log_string $::last_failing_log_string
        } else {
          # Bisection failed, another error exists at a lower position
          set ::bisect_low 0
        }
      } else {
        if {$id == 0} {
          # This should not be happening, something failed
          echo "\[Vulnerabile Net Analysis\] Bisection failed. This should not be happening..."
        } else {
          # Run the simulation again with the lower boundary to make sure everything is ok.
        }
      }
    } else {
      if {$id == 0} {
        # Error not encountered. Error is higher, first num_bitflips are not the source
        set ::bisect_low $::stat_num_bitflips
      } else {
        # Error encountered. Error source is lower.
        set ::bisect_high $::stat_num_bitflips
      }
    }
  }

  # record a log string if simulation terminated non-correctly
  if {$id != 0} {
    set ::last_failing_log_string "$::seed,$id,$::stat_num_bitflips,$::last_flipped_net"
  }

  # calulate the next bisection step
  set ::max_num_fault_inject [expr ($::bisect_low + $::bisect_high) / 2]

  if {$finished_seed} {
    # Log the results
    puts $::vulnerable_net_log $log_string
    flush $::vulnerable_net_log

    # Print the results
    if {$::verbosity >= 2} {
      echo "\[Vulnerabile Net Analysis\] Finished Testing Seed: $::seed."
    }

    # Continue with the next seed and reset the bisection parameters
    incr ::seed
    expr srand($::seed)
    
    reset_bisection

  } else {
    if {$::verbosity >= 2} {
      echo "\[Vulnerabile Net Analysis\] Bisection Info: \
        Seed: $::seed, Lower Bound: $::bisect_low, Upper Bound: $::bisect_high, \
        Next Try: $::max_num_fault_inject."
    }
  }
  # Indicate that the monitor was triggered (helps to rule out assertions)
  set ::monitor_triggered 1
}

###############################################
#  Main Thread of the Vulnerabile Net Analysis  #
###############################################

# Create the log file
set time_stamp [exec date +%Y%m%d_%H%M%S]
set file_name "vulnerable_net_$time_stamp.log"
set ::vulnerable_net_log [open $file_name w+]
puts $::vulnerable_net_log "seed,termination_cause,num_faults_injected,last_injected_net_name"

# Create the monitor triggered variable
set ::monitor_triggered 0

# === Step 1: Configure the golden model ===

# Configure the monitor settings for the golden model
set ::termination_signal_list [subst { \
  {3 $::exception_termination_signal "Exception" } \
  {2 $::incorrect_termination_signal "Incorrect" } \
  {0 $::correct_termination_signal   "Correct"   }}]

# Report x and z as exception
set ::termination_report_x_as_id 3

# Set the termination callback proc
set ::termination_report_proc golden_model_termination_report

# Setup the monitors
source [subst ${::script_base_path}termination_monitor.tcl]

# Source the run script
if ([string equal $::initial_run_script ""]) {
  run -all
} else {
  source $::initial_run_script
}

# --- wait for the golden model to finish ---

# check that the stop after the run was triggered by a monitor
if {!$::monitor_triggered} { exit }
set ::monitor_triggered 0

##########################
#  Find vulnerable nets  #
##########################

# Initialize the bisection
reset_bisection

# update the termination monitor with an appropriate timeout
set timeout_monitor [expr round($::golden_model_execution_time * 1.2)]
lappend ::termination_signal_list [subst {4 $timeout_monitor "Timeout"}]
set ::termination_report_proc injection_termination_report
termination_reset_monitors

# Source the fault injection script to start fault injection
# The parameters for the fault injection script have to be set up by the user.
source [subst ${::script_base_path}inject_fault.tcl]

# Loop forever
while {$::seed < $::initial_seed + $::max_num_tests} {
  # Restart the simulation
  if {$::verbosity >= 1} {
    echo "\[Vulnerabile Net Analysis\] Reached End of simulation. Restarting..."
  }
  restart -f

  # Restart the fault injection script
  restart_fault_injection

  # Run the simulation
  while {[eqTime $now 0]} {run -all}

  # --- Wait for the simulation to finish ---

  # Make sure the stop was triggered by a monitor, otherwise end the script
  # and let the user take over
  if {!$::monitor_triggered} { exit }
  set ::monitor_triggered 0
}

if {$::verbosity >= 1} {
  echo "\[Vulnerabile Net Analysis\] Reached the end of the vulnerable net analysis."
}
