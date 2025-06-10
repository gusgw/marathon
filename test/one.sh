#!/bin/bash
# one.sh - First level process in hierarchy test
#
# DESCRIPTION:
#   This script is the first subprocess launched by test.sh to create
#   a multi-level process hierarchy. It spawns two.sh and runs for
#   10 minutes, printing its process ID every 10 seconds.
#
# USAGE:
#   ./one.sh  (typically called by test.sh)
#
# WHAT IT DOES:
#   - Launches two.sh as a background process
#   - Loops 60 times with 10-second sleeps (10 minutes total)
#   - Prints "one: [PID] [iteration]" each loop
#   - Creates second level of process hierarchy
#
# EXPECTED BEHAVIOR:
#   - Runs as child of test.sh
#   - Creates two.sh as its child
#   - Outputs progress every 10 seconds
#   - Demonstrates process tree: test.sh -> one.sh -> two.sh
#
# NOTES:
#   - Part of process hierarchy testing suite
#   - Used to validate Marathon's subprocess tracking

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"${SCRIPT_DIR}/two.sh" &
# Check if we're in quick test mode
if [[ "${QUICK_TEST:-no}" == "yes" ]]; then
    MAX_ITERATIONS=3
else
    MAX_ITERATIONS=60
fi

for k in $(seq 1 $MAX_ITERATIONS); do
    echo "one: $$ $k"
    sleep 10
done
exit 0
