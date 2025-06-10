#!/bin/bash
# two.sh - Second level process in hierarchy test
#
# DESCRIPTION:
#   This script is the second subprocess in the test hierarchy, launched
#   by one.sh. It spawns three.sh and runs for 10 minutes, demonstrating
#   the middle level of a three-tier process tree.
#
# USAGE:
#   ./two.sh  (typically called by one.sh)
#
# WHAT IT DOES:
#   - Launches three.sh as a background process
#   - Loops 60 times with 10-second sleeps (10 minutes total)
#   - Prints "two: [PID] [iteration]" each loop
#   - Creates third level of process hierarchy
#
# EXPECTED BEHAVIOR:
#   - Runs as child of one.sh
#   - Creates three.sh as its child
#   - Outputs progress every 10 seconds
#   - Demonstrates process tree: test.sh -> one.sh -> two.sh -> three.sh
#
# NOTES:
#   - Part of process hierarchy testing suite
#   - Shows how Marathon tracks nested subprocesses

./three.sh &
for k in {1..60}; do
    echo "two: $$ $k"
    sleep 10
done
exit 0
