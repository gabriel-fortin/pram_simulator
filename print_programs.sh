#!/bin/bash

source script_data.sh

for PROG in `ls $PROG_DIR`
do
    echo "=============="
    echo " $PROG"
    echo "=============="
    cat $PROG_DIR/$PROG
done

