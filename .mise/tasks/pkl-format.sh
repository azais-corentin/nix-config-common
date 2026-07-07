#!/usr/bin/env sh
#MISE description="Format pkl via stdin, normalizing exit codes for dprint"
#MISE raw=true
#MISE quiet=true
pkl format -
e=$?
test $e -eq 0 -o $e -eq 11