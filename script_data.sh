#!/bin/bash

# directory with compiled files
BIN_DIR=ebin/

# dirs for test programs, their inputs, and expected outputs
PROG_DIR=manual_testing/Programs
INPUT_DIR=manual_testing/Inputs
OUTPUT_DIR=manual_testing/Outputs

PROG_FILE=manual_testing/program
INPUT_FILE=manual_testing/input
OUTPUT_FILE=manual_testing/output
EXP_OUTPUT_FILE=manual_testing/expected_output

STATS_FILE=manual_testing/stats

INFO_FILE=manual_testing/current


# start actions
APP_START="application:start(pram_sim)"
PRAM_RUN="pram_sim:start_from_env()"
DISABLE_LOGS="pram_sim:disable_logs()"
EXIT="init:stop()"
ERROR_REPORT_MAX_LENGTH="+#3000"


