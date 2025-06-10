#!/bin/bash
# test_all.sh - Run all Marathon framework tests
# This script executes all test suites to verify complete functionality
# Usage: ./test_all.sh
# Returns: 0 if all tests pass, non-zero if any test fails

# Don't use set -e as we want to run all tests even if some fail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counter
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Function to run a test and track results
run_test() {
    local test_name="$1"
    local test_script="$2"
    
    echo -e "\n${YELLOW}Running ${test_name}...${NC}"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if $test_script; then
        echo -e "${GREEN}✓ ${test_name} PASSED${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗ ${test_name} FAILED${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        # Don't exit on failure, continue with other tests
    fi
}

# Main test execution
echo "========================================="
echo "Marathon Framework - Complete Test Suite"
echo "========================================="
echo "Starting at: $(date)"

# Set quick test mode for faster execution
export QUICK_TEST=yes

# Basic functionality test
run_test "Basic Functionality Test" "./test_basic.sh"

# Process hierarchy tests
run_test "Process Hierarchy Tests" "./test/test.sh"

# Check if Marathon has been initialized
if [[ -d "/mnt/data/marathon" ]]; then
    echo -e "\n${GREEN}Marathon appears to be initialized. Running full test suite.${NC}"
    
    # Marathon framework tests
    run_test "Marathon Framework Tests" "./test_marathon.sh"
    
    # Cleanup mode tests (requires Marathon to be set up)
    run_test "Cleanup Mode Tests" "./test_cleanup_modes.sh"
    
    # Performance tests (run with shorter duration for test suite)
    export PERF_TEST_DURATION=10  # Short duration for test suite
    run_test "Performance Tests" "./test_performance.sh"
    
    # Quick report test
    run_test "Quick Report Test" "./test_report.sh"
else
    echo -e "\n${YELLOW}Marathon not initialized at /mnt/data/marathon. Skipping integration tests.${NC}"
    echo "To run full tests, first execute a Marathon job using ./run.sh"
fi

# These tests don't require Marathon to be initialized
# Retry mechanism tests
run_test "Retry Mechanism Tests" "./test_retry.sh"

# Summary generation test
run_test "Summary Generation Test" "./test_summary.sh"

# Test summary
echo -e "\n========================================="
echo "Test Suite Complete"
echo "========================================="
echo "Completed at: $(date)"
echo -e "Total Tests: ${TOTAL_TESTS}"
echo -e "Passed: ${GREEN}${PASSED_TESTS}${NC}"
echo -e "Failed: ${RED}${FAILED_TESTS}${NC}"

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "\n${GREEN}All tests passed successfully!${NC}"
    exit 0
else
    echo -e "\n${RED}Some tests failed. Please review the output above.${NC}"
    exit 1
fi