#!/bin/bash

DECLARATIONS_FILE="\"src/parsing/parser.yrl\""
OPTIONS="[{parserfile, \"src/parsing/generated/parser.erl\"}, {verbose, false}]"
CMD="yecc:file($DECLARATIONS_FILE, $OPTIONS)"
EXIT="init:stop()"

mkdir -p src/parsing/generated
erl -eval "$CMD, $EXIT"
echo

