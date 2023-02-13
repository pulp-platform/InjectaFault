# Copyright 2023 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Author: Luca Rufer (lrufer@student.ethz.ch)

# Description: This file is used to extract specific groups of nets from
#              Snitch, so they can be used in the fault injection script

# Source generic netlist extraction procs
source ../scripts/fault_injection/extract_nets.tcl

# == Base Path of a Snitch Core ==
proc base_path {group tile core} {return "/mempool_tb/dut/i_mempool_cluster/gen_groups\[$group\]/i_group/gen_tiles\[$tile\]/i_tile/gen_cores\[$core\]/gen_mempool_cc/riscv_core/i_snitch"}

# == Determine the snitch core parameters ==
set is_dmr_enabled [examine -radix dec /snitch_dmr_pkg::DualModularRedundancy]
set is_ecc_enabled [examine -radix binary [base_path 0 0 0]/EnableECCReg]

# == Nets to ignore for transient bit flips ==
# nets used for debugging
lappend core_netlist_ignore *gen_stack_overflow_check*
# nets that would crash the simulation if flipped
lappend core_netlist_ignore *clk_i
lappend core_netlist_ignore *rst_ni
lappend core_netlist_ignore *rst_i
lappend core_netlist_ignore *rst
lappend core_netlist_ignore *dmr*
# registers/memories
lappend core_netlist_ignore *mem
lappend core_netlist_ignore *_q
# Others
# - none -

####################
#  State Netlists  #
####################

proc get_snitch_protected_master_state_netlist {group tile core} {
  if {$core % 2 != 0} {
    throw {CORE SEL} {Core $group $tile $core is not a Master.}
  }
  set base [base_path $group $tile $core]
  set netlist [list]
  # Snitch state
  if {$::is_dmr_enabled} {
    lappend netlist $base/DMR_state/mst/i_pc/data_q
    lappend netlist $base/DMR_state/mst/i_wfi/data_q
    lappend netlist $base/DMR_state/mst/i_wake_up/data_q
    lappend netlist $base/DMR_state/mst/i_sb/data_q
  } elseif {$::is_ecc_enabled} {
    lappend netlist $base/state/TMR/i_pc/data_q
    lappend netlist $base/state/TMR/i_wfi/data_q
    lappend netlist $base/state/TMR/i_wake_up/data_q
    lappend netlist $base/state/TMR/i_sb/data_q
  }
  return $netlist
}

proc get_snitch_protected_slave_state_netlist {group tile core} {
  if {$core % 2 != 1} {
    throw {CORE SEL} {Core $group $tile $core is not a slave.}
  }
  set base [base_path $group $tile $core]
  set netlist [list]
  # Snitch state
  if {$::is_ecc_enabled} {
    if {$::is_dmr_enabled} {
      lappend netlist $base/DMR_state/slv/TMR/i_pc/data_q
      lappend netlist $base/DMR_state/slv/TMR/i_wfi/data_q
      lappend netlist $base/DMR_state/slv/TMR/i_wake_up/data_q
      lappend netlist $base/DMR_state/slv/TMR/i_sb/data_q
    } else {
      lappend netlist $base/state/TMR/i_pc/data_q
      lappend netlist $base/state/TMR/i_wfi/data_q
      lappend netlist $base/state/TMR/i_wake_up/data_q
      lappend netlist $base/state/TMR/i_sb/data_q
    }
  }
  return $netlist
}

proc get_snitch_unprotected_master_state_netlist {group tile core} {
  if {$core % 2 != 0} {
    throw {CORE SEL} {Core $group $tile $core is not a Master.}
  }
  set base [base_path $group $tile $core]
  set netlist [list]
  # Snitch state
  if {!$::is_dmr_enabled && !$::is_ecc_enabled} {
    lappend netlist $base/pc_q
    lappend netlist $base/wfi_q
    lappend netlist $base/wake_up_q
    lappend netlist $base/sb_q
  }
  return $netlist
}

proc get_snitch_unprotected_slave_state_netlist {group tile core} {
  if {$core % 2 != 1} {
    throw {CORE SEL} {Core $group $tile $core is not a slave.}
  }
  set base [base_path $group $tile $core]
  set netlist [list]
  # Snitch state
  if {!$::is_ecc_enabled} {
    if {$::is_dmr_enabled} {
      lappend netlist $base/DMR_state/slv/pc_qq
      lappend netlist $base/DMR_state/slv/wfi_qq
      lappend netlist $base/DMR_state/slv/wake_up_qq
      lappend netlist $base/DMR_state/slv/sb_qq
    } else {
      lappend netlist $base/pc_q
      lappend netlist $base/wfi_q
      lappend netlist $base/wake_up_q
      lappend netlist $base/sb_q
    }
  }
  return $netlist
}

proc get_snitch_slave_state_netlist {group tile core} {
  if {$core % 2 != 1} {
    throw {CORE SEL} {Core $group $tile $core is not a slave.}
  }
  set protected_netlist [get_snitch_protected_slave_state_netlist $group $tile $core]
  set unprotected_netlist [get_snitch_unprotected_slave_state_netlist $group $tile $core]
  return [concat $protected_netlist $unprotected_netlist]
}

proc get_snitch_master_state_netlist {group tile core} {
  if {$core % 2 != 0} {
    throw {CORE SEL} {Core $group $tile $core is not a master.}
  }
  set protected_netlist [get_snitch_protected_master_state_netlist $group $tile $core]
  set unprotected_netlist [get_snitch_unprotected_master_state_netlist $group $tile $core]
  return [concat $protected_netlist $unprotected_netlist]
}

proc get_snitch_unprotected_state_netlist {group tile core} {
  if {$core % 2 == 0} {
    return [get_snitch_unprotected_master_state_netlist $group $tile $core]
  } else {
    return [get_snitch_unprotected_slave_state_netlist $group $tile $core]
  }
}

proc get_snitch_protected_state_netlist {group tile core} {
  if {$core % 2 == 0} {
    return [get_snitch_protected_master_state_netlist $group $tile $core]
  } else {
    return [get_snitch_protected_slave_state_netlist $group $tile $core]
  }
}

proc get_snitch_state_netlist {group tile core} {
  if {$core % 2 == 0} {
    return [get_snitch_master_state_netlist $group $tile $core]
  } else {
    return [get_snitch_slave_state_netlist $group $tile $core]
  }
}

proc get_snitch_protected_regfile_mem_netlist {group tile core} {
  set base [base_path $group $tile $core]
  set netlist [list]
  if {$core % 2 == 0} {
    # Protected Master
    if {$::is_dmr_enabled} {
      for {set i 0} {$i < 32} {incr i} {
        lappend netlist $base/gen_dmr_regfile/i_snitch_regfile/mem\[$i\]
      }
    } elseif {$::is_ecc_enabled} {
      for {set i 0} {$i < 32} {incr i} {
        lappend netlist $base/gen_regfile/ECC/i_snitch_regfile/mem\[$i\]
      }
    }
  } else {
    # Protected Slave
    if {$::is_ecc_enabled} {
      if {$::is_dmr_enabled} {
        for {set i 0} {$i < 32} {incr i} {
          lappend netlist $base/gen_dmr_regfile/i_snitch_regfile/mem\[$i\]
        }
      } else {
        for {set i 0} {$i < 32} {incr i} {
          lappend netlist $base/gen_regfile/ECC/i_snitch_regfile/mem\[$i\]
        }
      }
    }
  }
  return $netlist
}

proc get_snitch_unprotected_regfile_mem_netlist {group tile core} {
  set base [base_path $group $tile $core]
  set netlist [list]
  if {$::is_ecc_enabled || ($core % 2 == 0 && $::is_dmr_enabled)} {return $netlist}

  if {$::is_dmr_enabled && ($core % 2 == 1) && !$::is_ecc_enabled} {
    for {set i 0} {$i < 32} {incr i} {
      lappend netlist $base/gen_dmr_regfile/i_snitch_regfile/mem\[$i\]
    }
  } else {
    for {set i 0} {$i < 32} {incr i} {
      lappend netlist $base/gen_regfile/noECC/i_snitch_regfile/mem\[$i\]
    }
  }
  return $netlist
}

proc get_snitch_regfile_mem_netlist {group tile core} {
  set protected_netlist [get_snitch_protected_regfile_mem_netlist $group $tile $core]
  set unprotected_netlist [get_snitch_unprotected_regfile_mem_netlist $group $tile $core]
  return [concat $protected_netlist $unprotected_netlist]
}

proc lsu_is_dmr_master {group tile core} {
  set is_master 0
  if {$::is_dmr_enabled} {
    set base [base_path $group $tile $core]/gen_DMR_lsu/i_snitch_lsu
    set is_master [examine -radix decimal $base/IsDMRMaster]
  }
  return $is_master
}

proc get_snitch_protected_lsu_state_netlist {group tile core} {
  set base [base_path $group $tile $core]
  set netlist [list]
  if {$::is_dmr_enabled} {
    set NumOutstandingLoads [examine -radix decimal $base/gen_DMR_lsu/i_snitch_lsu/NumOutstandingLoads]
    if {[lsu_is_dmr_master $group $tile $core]} {
      lappend netlist $base/gen_DMR_lsu/i_snitch_lsu/mst_state/i_id/data_q
      for {set i 0} {$i < $NumOutstandingLoads} {incr i} {
      lappend netlist $base/gen_DMR_lsu/i_snitch_lsu/metadata_q\[$i\]
      }
    } else {
      if {$::is_ecc_enabled} {
        lappend netlist $base/gen_DMR_lsu/i_snitch_lsu/slv_state/ECC/i_id/data_q
        for {set i 0} {$i < $NumOutstandingLoads} {incr i} {
          lappend netlist $base/gen_DMR_lsu/i_snitch_lsu/metadata_q\[$i\]
        }
      }
    }
  } else {
    set NumOutstandingLoads [examine -radix decimal $base/gen_lsu/i_snitch_lsu/NumOutstandingLoads]
    if {$::is_ecc_enabled} {
      lappend netlist $base/gen_lsu/i_snitch_lsu/ECC/i_id/data_q
      for {set i 0} {$i < $NumOutstandingLoads} {incr i} {
        lappend netlist $base/gen_lsu/i_snitch_lsu/metadata_q\[$i\]
      }
    }
  }

  return $netlist
}

proc get_snitch_unprotected_lsu_state_netlist {group tile core} {
  set base [base_path $group $tile $core]
  set netlist [list]
  # LSU state
  if {$::is_dmr_enabled} {
    set NumOutstandingLoads [examine -radix decimal $base/gen_DMR_lsu/i_snitch_lsu/NumOutstandingLoads]
    if {![lsu_is_dmr_master $group $tile $core] && !$::is_ecc_enabled} {
      lappend netlist $base/gen_DMR_lsu/i_snitch_lsu/id_available_q
      for {set i 0} {$i < $NumOutstandingLoads} {incr i} {
        lappend netlist $base/gen_DMR_lsu/i_snitch_lsu/metadata_q\[$i\]
      }
    }
  } else {
    set NumOutstandingLoads [examine -radix decimal $base/gen_lsu/i_snitch_lsu/NumOutstandingLoads]
    if {!$::is_ecc_enabled} {
      set lsu_netlist [find signal $base/gen_lsu/i_snitch_lsu/*_q]
      set netlist [concat $netlist $lsu_netlist]
    }
  }
  return $netlist
}

proc get_snitch_lsu_state_netlist {group tile core} {
  set protected_netlist [get_snitch_protected_lsu_state_netlist $group $tile $core]
  set unprotected_netlist [get_snitch_unprotected_lsu_state_netlist $group $tile $core]
  return [concat $protected_netlist $unprotected_netlist]
}

proc get_snitch_protected_csr_netlist {group tile core} {
  set base [base_path $group $tile $core]
  set netlist [list]
  if {$::is_ecc_enabled} {
    lappend netlist $base/csr_mhpm_parity_q
    lappend netlist $base/csr_mhpmh_parity_q
    lappend netlist $base/csr_mhpm_valid_q
    lappend netlist $base/csr_mhpmh_valid_q
    lappend netlist $base/cycle_q
    lappend netlist $base/instret_q
    lappend netlist $base/stall_ins_q
    lappend netlist $base/stall_raw_q
    lappend netlist $base/stall_lsu_q
    lappend netlist $base/seu_detected_q
  }
  if {$::is_dmr_enabled} {
    lappend netlist $base/dmr_sts_q
  }
  return $netlist
}

proc get_snitch_unprotected_csr_netlist {group tile core} {
  set base [base_path $group $tile $core]
  set netlist [list]
  if {!$::is_ecc_enabled} {
    lappend netlist $base/csr_mhpm_valid_q
    lappend netlist $base/csr_mhpmh_valid_q
    lappend netlist $base/cycle_q
    lappend netlist $base/instret_q
    lappend netlist $base/stall_ins_q
    lappend netlist $base/stall_raw_q
    lappend netlist $base/stall_lsu_q
    lappend netlist $base/seu_detected_q
  }
  return $netlist
}

proc get_snitch_csr_netlist {group tile core} {
  set protected_netlist [get_snitch_protected_csr_netlist $group $tile $core]
  set unprotected_netlist [get_snitch_unprotected_csr_netlist $group $tile $core]
  return [concat $protected_netlist $unprotected_netlist]
}

proc get_snitch_all_protected_reg_netlist {group tile core} {
  set state_netlist [get_snitch_protected_state_netlist $group $tile $core]
  set regfile_mem_netlist [get_snitch_protected_regfile_mem_netlist $group $tile $core]
  set lsu_state_netlist [get_snitch_protected_lsu_state_netlist $group $tile $core]
  set csr_netlist [get_snitch_protected_csr_netlist $group $tile $core]
  return [concat $state_netlist $regfile_mem_netlist $lsu_state_netlist $csr_netlist]
}

proc get_snitch_all_reg_netlist {group tile core} {
  set state_netlist [get_snitch_state_netlist $group $tile $core]
  set regfile_mem_netlist [get_snitch_regfile_mem_netlist $group $tile $core]
  set lsu_state_netlist [get_snitch_lsu_state_netlist $group $tile $core]
  set csr_netlist [get_snitch_csr_netlist $group $tile $core]
  return [concat $state_netlist $regfile_mem_netlist $lsu_state_netlist $csr_netlist]
}

######################
#  Core Output Nets  #
######################

proc get_snitch_output_netlist {group tile core} {
  return [get_output_netlist [base_path $group $tile $core]]
}

#####################
#  Next State Nets  #
#####################

proc get_snitch_next_state_netlist {group tile core} {
  return [get_next_state_netlist [base_path $group $tile $core]]
}

################
#  Assertions  #
################

proc get_snitch_assertions {group tile core} {
  set assertion_list [list]
  lappend assertion_list [base_path $group $tile $core]/InstructionInterfaceStable
  lappend assertion_list [base_path $group $tile $core]/**/i_snitch_lsu/invalid_resp_id
  lappend assertion_list [base_path $group $tile $core]/**/i_snitch_lsu/invalid_req_id
  return $assertion_list
}

##############################
#  Get all nets from a core  #
##############################

proc get_all_core_nets {group tile core} {
  set core_path [base_path $group $tile $core]
  return [extract_all_nets_recursive_filtered $core_path $::core_netlist_ignore]
}
