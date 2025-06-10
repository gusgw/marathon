#!/bin/bash
# three.sh - Third level process in hierarchy test
#
# DESCRIPTION:
#   This script is the deepest subprocess in the test hierarchy, launched
#   by two.sh. It runs for 10 minutes without spawning any children,
#   representing the leaf node in the process tree.
#
# USAGE:
#   ./three.sh  (typically called by two.sh)
#
# WHAT IT DOES:
#   - Loops 60 times with 10-second sleeps (10 minutes total)
#   - Prints "three: [PID] [iteration]" each loop
#   - Does not spawn any child processes
#   - Represents the deepest level of the hierarchy
#
# EXPECTED BEHAVIOR:
#   - Runs as child of two.sh
#   - No child processes created
#   - Outputs progress every 10 seconds
#   - Completes process tree: test.sh -> one.sh -> two.sh -> three.sh
#
# NOTES:
#   - Part of process hierarchy testing suite
#   - Validates Marathon can track deeply nested processes

for k in {1..60}; do
    echo "three: $$ $k"
    sleep 10
done
exit 0
