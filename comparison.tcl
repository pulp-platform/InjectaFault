# Copyright 2023 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Author: Luca Rufer (lrufer@student.ethz.ch)

# This script is used to load a .wlf file and compare it to a golden model

# ============ List of variables that may be passed to this script ============
# Any of these variables may not be changed while the vulnerable net analysis
# is running, unless noted otherwise. Changing any of the settings during
# runtime may result in undefined behaviour.
# ---------------------------------- General ----------------------------------
# 'comparison_file_list' : List of file names (including paths) of waves to be
#                       compared to the golden model. If this list is not empty,
#                       the first comparison is started when this script is
#                       sourced. After the comparison is created using the
#                       'create_comparison' proc, control is returned to the
#                       user. The user can continue to the next file in the
#                       list by calling the 'next_comparison' procedure.
#                       If this list is empty, no comparison is started when
#                       this file is sourced. A series of file comparisons
#                       may manually be started by calling
#                       'start_comparison_series' with the appropriate
#                       arguments. In that case, 'comparison_file_list' is
#                       ignored. By default, this list is empty.
# 'comparison_files_wildcard' : Path/File wildcard to find files to compare to
#                       the golden waves. 'comparisons_wildcard' is evaluated as
#                       argument for the 'ls' command.
#                       All files that are found are added to the
#                       'comparison_file_list' list.
#                       Set to an empty string ("") to prevent using the
#                       wildcard file detection (Default)

if {![info exists ::comparison_file_list]}      {set ::comparison_file_list  [list] }
if {![info exists ::comparison_files_wildcard]} {set ::comparison_files_wildcard "" }

# Description: Create the comparison
# --------------------------------- Arguments ---------------------------------
# 'comp_waves'        : Path and file name of the waves to be compared to the
#                       golden model. To use the current simulation data, set
#                       'comp_waves' to "sim" (Default)
# 'start_time'        : Start time of the comparison. Default is 0
# 'gold_waves'        : Golden waves file. Default is 'gold.wlf'.
# 'maxsignal_diff'    : Specifies an upper limit for the total differences
#                       encountered on any one signal. When the limit is
#                       reached, Questa SIM stops computing differences on that
#                       signal. Default is 1'000.
# 'maxtotal_diff'     : Specifies an upper limit for the total differences
#                       encountered. When the limit is reached, Questa SIM stops
#                       computing differences. Default is 10'000
proc create_comparison {{comp_waves "sim"} {start_time 0} {gold_waves gold.wlf} {maxsignal_diff 1000} {maxtotal_diff 10000}} {

  # Open golden dataset if not already open
  if {[lsearch [dataset list] gold] == -1} {
    dataset open $gold_waves gold
  }

  # If the compare file is open, close it
  if {[lsearch [dataset list] comp] != -1} {
    dataset close comp
  }

  # Open the dataset
  if {[string equal $comp_waves "sim"]} {
    dataset alias sim comp
  } else {
    dataset open $comp_waves comp
  }

  echo "\[Comparison\] Comparing $comp_waves to $gold_waves."

  # Compare
  compare start -maxsignal $maxsignal_diff -maxtotal $maxtotal_diff gold comp
  compare add -r -nowin /*
  compare run $start_time

  # Add all waves
  set all_signals [find signals -r compare:*]
  foreach sig $all_signals {
    set last_path_sep_index [string last "/" $sig]
    # Extract the signal path and signal name
    set sig_path [string range $sig 0 [expr $last_path_sep_index - 1]]
    set sig_name [string range $sig [expr $last_path_sep_index +2] end-1]
    # Fix the strings from the chars introduced by the comparison
    set sig_path [string map {"/\[/" "\\\[" "/\]/" "\\\]/"} $sig_path]
    set sig_name [lindex [split $sig_name "<>"] 0]
    set sig [string map {"\\" "\\\\" "\[" "\\\[" "\]" "\\\]"} $sig]
    # Split the signal path into multiple groups
    set groups [split $sig_path "/"]
    # Create the wave command
    set cmd "add wave "
    foreach g $groups { if {[string length $g] != 0} { append cmd "-group \"$g\" "}}
    append cmd "-label $sig_name compare:$sig"
    # Add the wave
    eval $cmd
  }

  # try to move the cursor to the injection time and focus the wave window there
  compare see -first
  #catch {
  #  set cursor_id [wave cursor add -time $::last_injection_time -name "Injection Time" -lock 1]
  #  wave cursor see $cursor_id -at 50
  #}
}

# Description: Start a series of comparisons, each loaded from a list of
#              files given as an argument. When this proc is called, the first
#              comparison is created and control is returned to the user. The
#              user can continue to the next comparison by calling
#              'next_comparison'.
# --------------------------------- Arguments ---------------------------------
# 'comp_waves'        : Path and file name of the waves to be compared to the
#                       golden model. The comparison using the first item in the
#                       list is immediately created.
#                       If this list is empty, the proc immediately returns
#                       without changing any state.
proc start_comparison_series {{comparison_file_list $::comparison_file_list}} {
  if {[llength $comparison_file_list] == 0} {return}

  # Set the active list
  set ::active_comparison_file_list $comparison_file_list
  set ::active_comparison_index -1

  # Start the first comparison
  next_comparison

  echo "\[Comparison\] Run 'next_comparison' to get the next comparison."
}

# Description: Continue with the next file in the current comparison file list.
#              Returns the number of comparisons left in the current list
proc next_comparison {} {
  # Advance the active comparison index
  incr ::active_comparison_index

  # Check if end of list is reached
  if {$::active_comparison_index >= [llength $::active_comparison_file_list]} {
    echo "\[Comparison\] No more comparisons left."
    return 0
  }

  # create the comparison
  set active_comparison_file [lindex $::active_comparison_file_list $::active_comparison_index]
  create_comparison $active_comparison_file

  return [expr [llength $::active_comparison_file_list] - $::active_comparison_index - 1]
}

# ================================ Main Thread ================================

# Set transcript to quiet
transcript quietly

# Set variable defaults
set ::active_comparison_file_list [list]
set ::active_comparison_index 0

if {[string length $::comparison_files_wildcard] != 0} {
  # Find all files using the wildcard
  set wildcard_list [eval {ls $::comparison_files_wildcard}]
  # Add the files to the list
  set ::comparison_file_list [concat $::comparison_file_list $wildcard_list]
}

# Start the first comparison series with the provided list
if {[llength $::comparison_file_list] != 0} {
  start_comparison_series $::comparison_file_list
}
