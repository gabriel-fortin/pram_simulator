#!/bin/bash

WORK_DIR=`echo $PWD/$0 | sed "s@\(.*\)\/.*@\1@"`
cd $WORK_DIR

source script_data.sh


# remove the result of a previous run
rm -f $OUTPUT_FILE
rm -f $STATS_FILE


# the only script's argument can be the memory model
POTENTIAL_MEMORY_MODEL=$1
case $POTENTIAL_MEMORY_MODEL in
    ("EREW" | "CREW")  memory_model=$POTENTIAL_MEMORY_MODEL;;
                  (*)  memory_model="-";;
esac


# if memory_model is set then use it as the memory model
if [ "$memory_model" == "-" ]
then
    echo "memory_model from app config will be used"
    EXTRA_PARAM=""
else
    echo "recognized memory_model: $memory_model"
    EXTRA_PARAM="-pram_sim memory_model '$memory_model'"
fi


# execute
nice -n 19 \
 erl -pa $BIN_DIR  -eval "$APP_START"  \
                   -eval "$PRAM_RUN"  \
                   -eval "$EXIT"  \
                   $EXTRA_PARAM  \
                   $ERROR_REPORT_MAX_LENGTH  &&\
   echo "OUTPUT: `cat $OUTPUT_FILE`"

