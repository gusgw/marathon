#!/bin/bash
# test_marathon.sh - Comprehensive test suite for the Marathon framework
#
# DESCRIPTION:
#   This is the main integration test suite that validates all core features
#   of the Marathon parallel computation framework. It tests cleanup modes,
#   directory structure, metadata generation, resource monitoring, error
#   tracking, and archival functionality.
#
# USAGE:
#   ./test_marathon.sh
#
# WHAT IT TESTS:
#   1. Directory structure creation (logs, jobs, system metrics, reports)
#   2. Metadata generation (manifest.json, job index, performance metrics)
#   3. All cleanup modes (keep, output, gpg, all)
#   4. Resource monitoring (CPU load, memory usage, disk space)
#   5. Health check endpoint functionality
#   6. Archive system for old logs
#   7. Retry mechanism with exponential backoff
#   8. Transfer logging for rclone operations
#   9. Error tracking and failure reporting
#
# EXPECTED OUTCOMES:
#   - All tests should pass (green checkmarks)
#   - Test environment is created in /mnt/data/marathon_test
#   - Each cleanup mode behaves correctly:
#     * keep: retains all files
#     * output: removes work/logs, keeps output
#     * gpg: keeps only encrypted files
#     * all: removes everything except archived output
#   - System metrics are collected and stored
#   - Failed jobs appear in error index
#   - All temporary test files are cleaned up
#
# SPECIAL REQUIREMENTS:
#   - Requires write access to /mnt/data/marathon_test
#   - Needs GNU Parallel, rclone, and other Marathon dependencies
#   - Must be run from the Marathon root directory
#   - May need sudo for some cleanup operations
#
# NOTES:
#   - Creates and destroys test environment automatically
#   - Uses color output (can be disabled by unsetting color vars)
#   - Exit code 0 if all tests pass, 1 if any fail
#   - Detailed test results shown with pass/fail counts

set -e
set -o pipefail

# Test configuration
export TEST_BASE="/mnt/data/marathon_test"
export ORIGINAL_WORKSPACE="${workspace:-/mnt/data/marathon/work}"
export ORIGINAL_LOGSPACE="${logspace:-/mnt/data/marathon/log}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Helper functions
log_test() {
    echo -e "\n${YELLOW}TEST:${NC} $1"
    ((TESTS_RUN++))
}

pass() {
    echo -e "${GREEN}✓ PASS:${NC} $1"
    ((TESTS_PASSED++))
}

fail() {
    echo -e "${RED}✗ FAIL:${NC} $1"
    ((TESTS_FAILED++))
}

assert_exists() {
    if [[ -e "$1" ]]; then
        pass "$2 exists"
    else
        fail "$2 missing: $1"
        return 1
    fi
}

assert_not_exists() {
    if [[ ! -e "$1" ]]; then
        pass "$2 removed"
    else
        fail "$2 still exists: $1"
        return 1
    fi
}

assert_file_contains() {
    if grep -q "$2" "$1" 2>/dev/null; then
        pass "$3"
    else
        fail "$3 - pattern not found in $1"
        return 1
    fi
}

count_files() {
    find "$1" -type f 2>/dev/null | wc -l
}

# Setup test environment
setup_test_env() {
    echo "Setting up test environment..."
    
    # Create test directories
    mkdir -p "${TEST_BASE}/work"
    mkdir -p "${TEST_BASE}/log"
    mkdir -p "${TEST_BASE}/input"
    mkdir -p "${TEST_BASE}/output"
    
    # Create dummy input files
    echo "Test input 1" > "${TEST_BASE}/input/test1.input"
    echo "Test input 2" > "${TEST_BASE}/input/test2.input"
    
    # Export test paths
    export workspace="${TEST_BASE}/work"
    export logspace="${TEST_BASE}/log"
    export input="dummy:${TEST_BASE}/input"
    export output="dummy:${TEST_BASE}/output"
}

# Cleanup test environment
cleanup_test_env() {
    echo "Cleaning up test environment..."
    rm -rf "${TEST_BASE}"
    
    # Restore original paths
    export workspace="${ORIGINAL_WORKSPACE}"
    export logspace="${ORIGINAL_LOGSPACE}"
}

# Test directory structure creation
test_directory_structure() {
    log_test "Directory structure creation"
    
    # Run a dummy job
    ./run.sh keep test_structure >/dev/null 2>&1 || fail "Job execution failed"
    
    # Check base directories
    assert_exists "${TEST_BASE}/log/jobs" "Jobs log directory"
    assert_exists "${TEST_BASE}/log/system" "System metrics directory"
    assert_exists "${TEST_BASE}/log/transfers" "Transfer logs directory"
    assert_exists "${TEST_BASE}/log/reports" "Reports directory"
    assert_exists "${TEST_BASE}/log/reports/daily" "Daily reports directory"
    assert_exists "${TEST_BASE}/log/reports/failures" "Failures directory"
    assert_exists "${TEST_BASE}/log/reports/performance" "Performance directory"
    
    # Check date-based subdirectories
    local date_path=$(date +%Y/%m/%d)
    assert_exists "${TEST_BASE}/log/system/${date_path}" "System metrics date directory"
    assert_exists "${TEST_BASE}/log/transfers/${date_path}" "Transfer logs date directory"
    assert_exists "${TEST_BASE}/log/reports/daily/${date_path}" "Daily reports date directory"
}

# Test metadata generation
test_metadata_generation() {
    log_test "Metadata generation"
    
    # Run a job
    ./run.sh keep test_metadata >/dev/null 2>&1 || fail "Job execution failed"
    
    # Check manifest file
    local manifest=$(find "${TEST_BASE}/log/jobs/test_metadata" -name "manifest.json" -type f | head -1)
    assert_exists "${manifest}" "Job manifest"
    
    if [[ -f "${manifest}" ]]; then
        assert_file_contains "${manifest}" '"job_name": "test_metadata"' "Manifest contains job name"
        assert_file_contains "${manifest}" '"hostname":' "Manifest contains hostname"
        assert_file_contains "${manifest}" '"input_files":' "Manifest contains input files"
        assert_file_contains "${manifest}" '"output_files":' "Manifest contains output files"
    fi
    
    # Check job index
    assert_exists "${TEST_BASE}/log/reports/job_index.txt" "Job index file"
    assert_file_contains "${TEST_BASE}/log/reports/job_index.txt" "test_metadata" "Job index contains test job"
    
    # Check performance metrics
    local perf_file="${TEST_BASE}/log/reports/performance/metrics_$(date +%Y%m).csv"
    assert_exists "${perf_file}" "Performance metrics file"
    
    # Check daily summary
    local summary="${TEST_BASE}/log/reports/daily/$(date +%Y/%m/%d)/summary.txt"
    assert_exists "${summary}" "Daily summary file"
}

# Test cleanup mode: keep
test_cleanup_keep() {
    log_test "Cleanup mode: keep"
    
    # Run with keep mode
    ./run.sh keep test_keep >/dev/null 2>&1 || fail "Job execution failed"
    
    # Everything should be retained
    assert_exists "${TEST_BASE}/work/test_keep" "Work directory"
    assert_exists "${TEST_BASE}/log/jobs/test_keep" "Log directory"
    
    # Check for output files
    local output_count=$(count_files "${TEST_BASE}/output")
    if [[ ${output_count} -gt 0 ]]; then
        pass "Output files created"
    else
        fail "No output files created"
    fi
}

# Test cleanup mode: output
test_cleanup_output() {
    log_test "Cleanup mode: output"
    
    # Run with output mode
    ./run.sh output test_output >/dev/null 2>&1 || fail "Job execution failed"
    
    # Work and logs should be cleaned
    assert_not_exists "${TEST_BASE}/work/test_output" "Work directory"
    assert_not_exists "${TEST_BASE}/log/jobs/test_output" "Log directory"
    
    # Output should exist
    local output_count=$(count_files "${TEST_BASE}/output")
    if [[ ${output_count} -gt 0 ]]; then
        pass "Output files retained"
    else
        fail "Output files missing"
    fi
}

# Test cleanup mode: gpg
test_cleanup_gpg() {
    log_test "Cleanup mode: gpg"
    
    # Enable encryption for this test
    export encrypt_flag="yes"
    
    # Run with gpg mode
    ./run.sh gpg test_gpg >/dev/null 2>&1 || fail "Job execution failed"
    
    # Check that only GPG files remain in work
    if [[ -d "${TEST_BASE}/work/test_gpg" ]]; then
        local gpg_count=$(find "${TEST_BASE}/work/test_gpg" -name "*.gpg" -type f | wc -l)
        local non_gpg_count=$(find "${TEST_BASE}/work/test_gpg" -type f ! -name "*.gpg" | wc -l)
        
        if [[ ${gpg_count} -gt 0 && ${non_gpg_count} -eq 0 ]]; then
            pass "Only GPG files retained"
        else
            fail "Non-GPG files found or no GPG files present"
        fi
    fi
    
    unset encrypt_flag
}

# Test cleanup mode: all
test_cleanup_all() {
    log_test "Cleanup mode: all"
    
    # Run with all mode
    ./run.sh all test_all >/dev/null 2>&1 || fail "Job execution failed"
    
    # Everything should be cleaned
    assert_not_exists "${TEST_BASE}/work/test_all" "Work directory"
    assert_not_exists "${TEST_BASE}/log/jobs/test_all" "Log directory"
    
    # Output should still exist (archived)
    local output_count=$(count_files "${TEST_BASE}/output")
    if [[ ${output_count} -gt 0 ]]; then
        pass "Output archive created"
    else
        fail "No output archive found"
    fi
}

# Test resource monitoring
test_resource_monitoring() {
    log_test "Resource monitoring"
    
    # Run a job
    ./run.sh keep test_monitor >/dev/null 2>&1 || fail "Job execution failed"
    
    # Check system metrics
    local date_path=$(date +%Y/%m/%d)
    local metrics_dir="${TEST_BASE}/log/system/${date_path}"
    
    # Look for metric files
    local load_files=$(find "${metrics_dir}" -name "*.load" -type f 2>/dev/null | wc -l)
    local memory_files=$(find "${metrics_dir}" -name "*.memory" -type f 2>/dev/null | wc -l)
    local free_files=$(find "${metrics_dir}" -name "*.free" -type f 2>/dev/null | wc -l)
    
    if [[ ${load_files} -gt 0 ]]; then
        pass "Load metrics collected"
    else
        fail "No load metrics found"
    fi
    
    if [[ ${memory_files} -gt 0 ]]; then
        pass "Memory metrics collected"
    else
        fail "No memory metrics found"
    fi
    
    if [[ ${free_files} -gt 0 ]]; then
        pass "Free memory metrics collected"
    else
        fail "No free memory metrics found"
    fi
}

# Test health check
test_health_check() {
    log_test "Health check endpoint"
    
    # Run health check
    if ./health.sh check >/dev/null 2>&1; then
        pass "Health check passed"
    else
        fail "Health check failed"
    fi
    
    # Test JSON output
    local health_json=$(./health.sh json 2>/dev/null)
    if echo "${health_json}" | grep -q '"status":'; then
        pass "Health check JSON valid"
    else
        fail "Health check JSON invalid"
    fi
}

# Test archive functionality
test_archive_system() {
    log_test "Archive system"
    
    # Create some old log files
    local old_job_dir="${TEST_BASE}/log/jobs/test_old"
    mkdir -p "${old_job_dir}"
    touch -t $(date -d '10 days ago' +%Y%m%d%H%M) "${old_job_dir}/old.log"
    
    # Run archive command
    ./archive.sh rotate 5 >/dev/null 2>&1
    
    # Check if old logs were archived
    if [[ -d "${TEST_BASE}/log/archive" ]]; then
        pass "Archive directory created"
        
        local archive_count=$(find "${TEST_BASE}/log/archive" -name "*.tar.gz" -type f | wc -l)
        if [[ ${archive_count} -gt 0 ]]; then
            pass "Logs archived successfully"
        else
            fail "No archived logs found"
        fi
    else
        fail "Archive directory not created"
    fi
}

# Test retry mechanism
test_retry_mechanism() {
    log_test "Retry mechanism"
    
    # Source retry.sh
    . ./retry.sh
    
    # Test with a command that succeeds on second try
    local attempt=0
    retry_test_command() {
        ((attempt++))
        if [[ ${attempt} -eq 2 ]]; then
            return 0
        else
            return 1
        fi
    }
    
    # Override retry settings for faster testing
    export MAX_RETRIES=3
    export INITIAL_RETRY_DELAY=1
    
    if retry_with_backoff retry_test_command; then
        pass "Retry mechanism works"
    else
        fail "Retry mechanism failed"
    fi
}

# Test transfer logging
test_transfer_logging() {
    log_test "Transfer logging"
    
    # Run a job
    ./run.sh keep test_transfer >/dev/null 2>&1 || fail "Job execution failed"
    
    # Check transfer logs
    local date_path=$(date +%Y/%m/%d)
    local transfer_dir="${TEST_BASE}/log/transfers/${date_path}"
    
    local input_logs=$(find "${transfer_dir}" -name "*rclone.input.log" -type f 2>/dev/null | wc -l)
    local output_logs=$(find "${transfer_dir}" -name "*rclone.output.log" -type f 2>/dev/null | wc -l)
    
    if [[ ${input_logs} -gt 0 ]]; then
        pass "Input transfer logs created"
    else
        fail "No input transfer logs found"
    fi
    
    if [[ ${output_logs} -gt 0 ]]; then
        pass "Output transfer logs created"
    else
        fail "No output transfer logs found"
    fi
}

# Test error tracking
test_error_tracking() {
    log_test "Error tracking"
    
    # Create a job that will fail
    export FORCE_FAIL="yes"
    
    # Run failing job (allow it to fail)
    ./run.sh keep test_error 2>/dev/null || true
    
    unset FORCE_FAIL
    
    # Check error index
    if [[ -f "${TEST_BASE}/log/reports/error_index.txt" ]]; then
        pass "Error index created"
        
        if grep -q "test_error" "${TEST_BASE}/log/reports/error_index.txt" 2>/dev/null; then
            pass "Failed job recorded in error index"
        else
            fail "Failed job not in error index"
        fi
    else
        fail "Error index not created"
    fi
    
    # Check failure directory
    local failure_logs=$(find "${TEST_BASE}/log/reports/failures" -type f 2>/dev/null | wc -l)
    if [[ ${failure_logs} -gt 0 ]]; then
        pass "Failure logs copied"
    else
        fail "No failure logs found"
    fi
}

# Main test execution
main() {
    echo "Marathon Framework Test Suite"
    echo "============================"
    
    # Setup
    setup_test_env
    
    # Run all tests
    test_directory_structure
    test_metadata_generation
    test_cleanup_keep
    test_cleanup_output
    test_cleanup_gpg
    test_cleanup_all
    test_resource_monitoring
    test_health_check
    test_archive_system
    test_retry_mechanism
    test_transfer_logging
    test_error_tracking
    
    # Cleanup
    cleanup_test_env
    
    # Summary
    echo -e "\n============================"
    echo "Test Summary"
    echo "============================"
    echo -e "Tests run:    ${TESTS_RUN}"
    echo -e "Tests passed: ${GREEN}${TESTS_PASSED}${NC}"
    echo -e "Tests failed: ${RED}${TESTS_FAILED}${NC}"
    
    if [[ ${TESTS_FAILED} -eq 0 ]]; then
        echo -e "\n${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "\n${RED}Some tests failed!${NC}"
        exit 1
    fi
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi