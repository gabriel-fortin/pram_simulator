#!/bin/bash

WORK_DIR=`echo $PWD/$0 | sed "s@\(.*\)\/.*@\1@"`
cd $WORK_DIR

# directories for the erlang compiler
SRC_DIR=src
BIN_DIR=ebin

# prepare binary files
mkdir -p $BIN_DIR
erlc    -o $BIN_DIR  $SRC_DIR/*/*/*.erl  && \
   erlc -o $BIN_DIR  $SRC_DIR/*/*.erl
COMPILE_RESULT=$?
cp  $SRC_DIR/app_structure/pram_sim.app  $BIN_DIR/pram_sim.app

# visual indication of success
[ $COMPILE_RESULT -eq 0 ] && echo ===================== || echo ===ERRORS===

# return compilation's result to allow command chaining
#    for example:  ./compile.sh && ./rerun.sh
exit $COMPILE_RESULT

