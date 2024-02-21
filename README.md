# Fault Injection in Simulation

This repository hosts a set of files to inject faults in RTL simulations, assisting with net
extraction and vulnerability analysis. This project is developed as part of the PULP platform, a
joint effort between ETH Zurich and the University of Bologna.

## User Guide

The scripts were developed for use with QuestaSim newer than 2019.3. Other tools and older versions
are currently not supported.

This repository contains several files in the `scripts` directory with the main tooling for:
- fault injection
- signal name extraction
- vulnerability analysis
- signal/simulation comparison

These scripts provide functionality to assist with the above functionality, however for your own
design you will need to provide your own set of scripts calling the provided functions. Several
examples for this can be found in the `examples` directory. The scripts and their functionality is
documented within the respective files.

## License

Unless specified otherwise in the respective file headers, all code checked into this repository is
made available under a permissive license. All hardware sources and tool scripts are licensed under
the Solderpad Hardware License 0.51 (see `LICENSE`).
