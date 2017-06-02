#!/bin/bash

DEFINITIONS_FILE="\"src/parsing/scanner.xrl\""
OPTIONS="[{scannerfile, \"src/parsing/generated/scanner.erl\"}]"
CMD="leex:file($DEFINITIONS_FILE, $OPTIONS)"
EXIT="init:stop()"

mkdir -p src/parsing/generated
erl -eval "$CMD, $EXIT"
echo

