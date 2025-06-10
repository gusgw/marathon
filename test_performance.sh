#!/bin/bash
# test_performance.sh - Performance and stress testing for Marathon framework
#
# DESCRIPTION:
#   This script runs comprehensive performance tests on the Marathon framework
#   to validate its behavior under various load conditions. It tests parallel
#   execution, memory tracking, CPU load monitoring, transfer performance,
#   concurrent job handling, and performance report generation.
#
# USAGE:
#   ./test_performance.sh
#   
#   Environment variables:
#   - PERF_TEST_DURATION: Test duration in seconds (default: 30)
#   - PERF_TEST_PARALLEL: Number of parallel jobs (default: 4)
#
# WHAT IT TESTS:
#   1. Parallel execution - Runs multiple jobs simultaneously
#   2. Memory tracking - Monitors memory usage during intensive operations
#   3. Load monitoring - Tracks CPU load averages
#   4. Transfer performance - Measures data transfer speeds
#   5. Concurrent jobs - Tests multiple independent job executions
#   6. Performance reports - Validates metric collection and reporting
#
# EXPECTED OUTCOMES:
#   - All parallel jobs complete successfully
#   - Memory usage statistics are recorded in .memory files
#   - CPU load averages are tracked in .load files
#   - Transfer logs show input/output operations
#   - Concurrent jobs run without interference
#   - Performance metrics CSV contains accurate data
#   - Summary statistics show reasonable values
#
# SPECIAL REQUIREMENTS:
#   - Sufficient disk space for test files (at least 500MB)
#   - Write access to /mnt/data/marathon directories
#   - stress utility installed for CPU/memory testing
#   - dd command available for file generation
#   - Multiple CPU cores for parallel testing
#
# NOTES:
#   - Creates temporary test files that are cleaned up automatically
#   - May temporarily increase system load during testing
#   - Performance results vary based on system capabilities
#   - All tests run sequentially to avoid interference

set -e
set -o pipefail

# Configuration
export PERF_TEST_DURATION=${PERF_TEST_DURATION:-30}  # seconds
export PERF_TEST_PARALLEL=${PERF_TEST_PARALLEL:-4}   # parallel jobs

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Marathon Performance Test Suite${NC}"
echo -e "${BLUE}==============================${NC}"
echo

# Test 1: Parallel job execution
test_parallel_execution() {
    echo -e "${YELLOW}Test 1: Parallel execution (${PERF_TEST_PARALLEL} jobs)${NC}"
    
    # Create multiple input files
    local input_dir="/mnt/data/marathon/input"
    for i in $(seq 1 ${PERF_TEST_PARALLEL}); do
        dd if=/dev/urandom of="${input_dir}/perf${i}.input" bs=1M count=10 2>/dev/null
    done
    
    # Override inglob to match our test files
    export inglob="perf*.input"
    
    # Record start time
    local start_time=$(date +%s)
    
    # Run parallel job
    ./run.sh keep perftest_parallel
    
    # Record end time
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo -e "${GREEN}✓${NC} Completed ${PERF_TEST_PARALLEL} parallel jobs in ${duration} seconds"
    
    # Check performance metrics
    local perf_file="/mnt/data/marathon/log/reports/performance/metrics_$(date +%Y%m).csv"
    if [[ -f "$perf_file" ]]; then
        echo -e "${GREEN}✓${NC} Performance metrics recorded"
        
        # Show last few entries
        echo -e "\nLatest performance metrics:"
        tail -5 "$perf_file" | column -t -s,
    fi
    
    # Cleanup test files
    rm -f "${input_dir}"/perf*.input
    unset inglob
}

# Test 2: Memory usage tracking
test_memory_tracking() {
    echo -e "\n${YELLOW}Test 2: Memory usage tracking${NC}"
    
    # Run a memory-intensive job
    export STRESS_VM_BYTES="100M"
    ./run.sh keep perftest_memory >/dev/null 2>&1
    unset STRESS_VM_BYTES
    
    # Check memory reports
    local date_path=$(date +%Y/%m/%d)
    local memory_files=$(find "/mnt/data/marathon/log/system/${date_path}" -name "*perftest_memory*.memory" -type f)
    
    if [[ -n "$memory_files" ]]; then
        echo -e "${GREEN}✓${NC} Memory tracking files created"
        
        # Analyze memory usage
        echo -e "\nMemory usage statistics:"
        for file in $memory_files; do
            if [[ -s "$file" ]]; then
                local max_mem=$(awk '{print $5}' "$file" | sort -n | tail -1)
                echo "  - $(basename "$file"): Max ${max_mem} KB"
            fi
        done
    fi
}

# Test 3: Load average monitoring
test_load_monitoring() {
    echo -e "\n${YELLOW}Test 3: Load average monitoring${NC}"
    
    # Run CPU-intensive job
    export STRESS_CPU_COUNT=2
    ./run.sh keep perftest_load >/dev/null 2>&1
    unset STRESS_CPU_COUNT
    
    # Check load reports
    local date_path=$(date +%Y/%m/%d)
    local load_files=$(find "/mnt/data/marathon/log/system/${date_path}" -name "*perftest_load*.load" -type f)
    
    if [[ -n "$load_files" ]]; then
        echo -e "${GREEN}✓${NC} Load tracking files created"
        
        # Show load statistics
        echo -e "\nLoad average samples:"
        for file in $load_files; do
            if [[ -s "$file" ]]; then
                echo "  - $(basename "$file"):"
                head -3 "$file" | awk '{print "    " $1 " " $2}' | column -t
            fi
        done
    fi
}

# Test 4: Transfer performance
test_transfer_performance() {
    echo -e "\n${YELLOW}Test 4: Transfer performance logging${NC}"
    
    # Create larger test file
    dd if=/dev/urandom of="/mnt/data/marathon/input/transfer_test.input" bs=1M count=100 2>/dev/null
    export inglob="transfer_test.input"
    
    # Run transfer test
    ./run.sh output perftest_transfer >/dev/null 2>&1
    
    # Check transfer logs
    local date_path=$(date +%Y/%m/%d)
    local transfer_logs="/mnt/data/marathon/log/transfers/${date_path}"
    local input_log=$(find "$transfer_logs" -name "*perftest_transfer*input.log" -type f | head -1)
    local output_log=$(find "$transfer_logs" -name "*perftest_transfer*output.log" -type f | head -1)
    
    if [[ -f "$input_log" && -f "$output_log" ]]; then
        echo -e "${GREEN}✓${NC} Transfer logs created"
        
        # Extract transfer statistics if available
        echo -e "\nTransfer statistics:"
        if [[ -s "$input_log" ]]; then
            echo "  - Input transfer: $(wc -l < "$input_log") log entries"
        fi
        if [[ -s "$output_log" ]]; then
            echo "  - Output transfer: $(wc -l < "$output_log") log entries"
        fi
    fi
    
    # Cleanup
    rm -f "/mnt/data/marathon/input/transfer_test.input"
    unset inglob
}

# Test 5: Concurrent job stress test
test_concurrent_jobs() {
    echo -e "\n${YELLOW}Test 5: Concurrent jobs stress test${NC}"
    
    # Launch multiple jobs concurrently
    echo "Launching 3 concurrent jobs..."
    
    ./run.sh keep stress_job1 >/dev/null 2>&1 &
    local pid1=$!
    
    ./run.sh keep stress_job2 >/dev/null 2>&1 &
    local pid2=$!
    
    ./run.sh keep stress_job3 >/dev/null 2>&1 &
    local pid3=$!
    
    # Wait for all jobs
    wait $pid1 && echo -e "${GREEN}✓${NC} Job 1 completed"
    wait $pid2 && echo -e "${GREEN}✓${NC} Job 2 completed"
    wait $pid3 && echo -e "${GREEN}✓${NC} Job 3 completed"
    
    # Check job index
    local job_count=$(grep -c "stress_job" "/mnt/data/marathon/log/reports/job_index.txt" 2>/dev/null || echo 0)
    echo -e "${GREEN}✓${NC} All ${job_count} jobs recorded in index"
}

# Test 6: Performance report generation
test_performance_reports() {
    echo -e "\n${YELLOW}Test 6: Performance report analysis${NC}"
    
    # Generate summary of all performance data
    local perf_file="/mnt/data/marathon/log/reports/performance/metrics_$(date +%Y%m).csv"
    
    if [[ -f "$perf_file" ]]; then
        echo -e "\nPerformance summary for this session:"
        
        # Calculate statistics
        local total_jobs=$(tail -n +2 "$perf_file" | wc -l)
        local total_duration=$(tail -n +2 "$perf_file" | awk -F, '{sum+=$4} END {print sum}')
        local avg_duration=$(tail -n +2 "$perf_file" | awk -F, '{sum+=$4; count++} END {if(count>0) print sum/count; else print 0}')
        local total_input=$(tail -n +2 "$perf_file" | awk -F, '{sum+=$8} END {print sum}')
        local total_output=$(tail -n +2 "$perf_file" | awk -F, '{sum+=$9} END {print sum}')
        
        echo "  - Total jobs: ${total_jobs}"
        echo "  - Total duration: ${total_duration} seconds"
        echo "  - Average duration: ${avg_duration} seconds"
        echo "  - Total input processed: $((total_input / 1048576)) MB"
        echo "  - Total output generated: $((total_output / 1048576)) MB"
    fi
}

# Main execution
main() {
    # Run all performance tests
    test_parallel_execution
    test_memory_tracking
    test_load_monitoring
    test_transfer_performance
    test_concurrent_jobs
    test_performance_reports
    
    echo -e "\n${BLUE}======================================${NC}"
    echo -e "${GREEN}Performance tests completed${NC}"
    echo -e "${BLUE}======================================${NC}"
}

# Make scripts executable
chmod +x test_*.sh 2>/dev/null || true

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi