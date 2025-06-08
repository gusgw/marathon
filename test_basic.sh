#!/bin/bash
# test_basic.sh: Simple tests for core marathon functionality

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

pass() {
    echo -e "${GREEN}✓ PASS:${NC} $1"
    ((TESTS_PASSED++))
}

fail() {
    echo -e "${RED}✗ FAIL:${NC} $1"
    ((TESTS_FAILED++))
}

echo "Marathon Basic Tests"
echo "==================="
echo

# Test 1: Check all new scripts exist
echo -e "${YELLOW}Test 1: Script existence${NC}"
for script in metadata.sh archive.sh retry.sh health.sh; do
    if [[ -f "$script" && -x "$script" ]]; then
        pass "$script exists and is executable"
    else
        fail "$script missing or not executable"
    fi
done

# Test 2: Check script syntax
echo -e "\n${YELLOW}Test 2: Script syntax${NC}"
for script in *.sh; do
    if bash -n "$script" 2>/dev/null; then
        pass "$script syntax valid"
    else
        fail "$script has syntax errors"
    fi
done

# Test 3: Check health functionality
echo -e "\n${YELLOW}Test 3: Health check basics${NC}"
if ./health.sh json | grep -q '"status":'; then
    pass "Health check produces JSON output"
else
    fail "Health check JSON output invalid"
fi

# Test 4: Check demo functionality
echo -e "\n${YELLOW}Test 4: Demo script${NC}"
if ./demo_cleanup.sh | grep -q "KEEP mode"; then
    pass "Demo script runs successfully"
else
    fail "Demo script failed"
fi

# Test 5: Check archive functionality
echo -e "\n${YELLOW}Test 5: Archive help${NC}"
if ./archive.sh 2>&1 | grep -q "Usage:"; then
    pass "Archive script shows help"
else
    fail "Archive script help failed"
fi

# Test 6: Check directory structure exists
echo -e "\n${YELLOW}Test 6: Log directory structure${NC}"
for dir in /mnt/data/marathon/log/jobs /mnt/data/marathon/log/system /mnt/data/marathon/log/transfers /mnt/data/marathon/log/reports; do
    if [[ -d "$dir" ]]; then
        pass "$(basename $dir) directory exists"
    else
        fail "$(basename $dir) directory missing"
    fi
done

# Test 7: Check reports files
echo -e "\n${YELLOW}Test 7: Reports files${NC}"
if [[ -f "/mnt/data/marathon/log/reports/job_index.txt" ]]; then
    local job_count=$(grep -c "|completed|" /mnt/data/marathon/log/reports/job_index.txt 2>/dev/null || echo 0)
    pass "Job index exists with $job_count completed jobs"
else
    fail "Job index missing"
fi

if [[ -f "/mnt/data/marathon/log/reports/performance/metrics_$(date +%Y%m).csv" ]]; then
    pass "Performance metrics file exists"
else
    fail "Performance metrics file missing"
fi

# Test 8: Check output archives
echo -e "\n${YELLOW}Test 8: Output archives${NC}"
local archive_count=$(ls /mnt/data/marathon/output/*.tar.xz 2>/dev/null | wc -l)
if [[ $archive_count -gt 0 ]]; then
    pass "$archive_count output archives exist"
else
    fail "No output archives found"
fi

# Test 9: Check manifest exists
echo -e "\n${YELLOW}Test 9: Job manifests${NC}"
local manifest_count=$(find /mnt/data/marathon/log/jobs -name "manifest.json" 2>/dev/null | wc -l)
if [[ $manifest_count -gt 0 ]]; then
    pass "$manifest_count job manifests found"
    
    # Check manifest content
    local manifest=$(find /mnt/data/marathon/log/jobs -name "manifest.json" | head -1)
    if grep -q '"input_files":' "$manifest" 2>/dev/null; then
        pass "Manifest contains input files"
    else
        fail "Manifest missing input files"
    fi
    
    if grep -q '"sha256":' "$manifest" 2>/dev/null; then
        pass "Manifest contains checksums"
    else
        fail "Manifest missing checksums"
    fi
else
    fail "No job manifests found"
fi

# Test 10: Check system metrics
echo -e "\n${YELLOW}Test 10: System metrics${NC}"
local date_path=$(date +%Y/%m/%d)
local metrics_dir="/mnt/data/marathon/log/system/$date_path"
if [[ -d "$metrics_dir" ]]; then
    local metric_files=$(find "$metrics_dir" -name "*.load" -o -name "*.memory" -o -name "*.free" | wc -l)
    if [[ $metric_files -gt 0 ]]; then
        pass "$metric_files system metric files found"
    else
        fail "No system metric files found"
    fi
else
    fail "System metrics directory missing for today"
fi

# Summary
echo -e "\n${YELLOW}========================================${NC}"
echo "Test Summary:"
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "\n${GREEN}All basic tests passed!${NC}"
    exit 0
else
    echo -e "\n${RED}Some tests failed!${NC}"
    exit 1
fi