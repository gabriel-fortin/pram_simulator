#!/bin/bash

WORK_DIR=`echo $PWD/$0 | sed "s@\(.*\)\/.*@\1@"`
cd $WORK_DIR

source script_data.sh


NUM_ARGS=$#
PREFIX=$1

# validate arguments
if [[ $NUM_ARGS -lt 1 ]]; then
    echo "Usage $0 prog_number"
    echo "for example:"
    echo "             $0 0010"
    exit 1
fi


# choose the input/output pair (either user-selected or automatic)
if [[ $NUM_ARGS -eq 2 ]]; then
    DATA_ID=$2
    DATA_FILE_NAME=`ls -1 $INPUT_DIR/$PREFIX/ | grep "\($DATA_ID\)_"`
else
    DATA_FILE_NAME=`ls -1 $INPUT_DIR/$PREFIX | head -n 1`
fi
echo "$PREFIX, $DATA_FILE_NAME" > $INFO_FILE
echo "" >> $INFO_FILE


# prepare the setup (program file, input file, expected output file)
PROG_NAME=`ls $PROG_DIR | grep "^\($PREFIX\)_" | head -n 1`
echo "prog name: $PROG_NAME"
cp  $PROG_DIR/$PROG_NAME  $PROG_FILE  &&\

INPUT_FILE_SOURCE=$INPUT_DIR/$PREFIX/$DATA_FILE_NAME
cp  $INPUT_FILE_SOURCE  $INPUT_FILE  &&\

OUTPUT_FILE_SOURCE=$OUTPUT_DIR/$PREFIX/$DATA_FILE_NAME
cp  $OUTPUT_FILE_SOURCE  $EXP_OUTPUT_FILE  ||\
    exit 2

# remove the result of a previous run
rm -f $OUTPUT_FILE
rm -f $STATS_FILE


# execute
nice -n 19 \
 erl -pa $BIN_DIR  -eval "$APP_START"  \
                   -eval "$DISABLE_LOGS"  \
                   -eval "$PRAM_RUN"  \
                   -eval "$EXIT"  \
                   $ERROR_REPORT_MAX_LENGTH


# verify result
echo "DIFF:"
diff -swbB  $OUTPUT_FILE  $EXP_OUTPUT_FILE

