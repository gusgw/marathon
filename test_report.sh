#!/bin/bash
# test_report.sh - Quick validation report for Marathon framework installation
#
# DESCRIPTION:
#   This script provides a rapid health check of the Marathon framework by
#   validating that all required scripts exist, are executable, and that
#   the system has been properly initialized with the expected directory
#   structure and output files. It's designed as a quick smoke test.
#
# USAGE:
#   ./test_report.sh
#
# WHAT IT TESTS:
#   1. Core scripts existence and permissions (metadata.sh, archive.sh, etc)
#   2. Test scripts availability and executable status
#   3. Health check endpoint functionality
#   4. Log directory structure (jobs/, system/, transfers/, reports/)
#   5. Generated files (job index, performance metrics, manifests)
#   6. System metrics collection and storage
#
# EXPECTED OUTCOMES:
#   - All core scripts present and executable
#   - Test scripts available for execution
#   - Health check returns valid JSON
#   - Log directories properly created
#   - Job index file exists with completed jobs
#   - Performance metrics CSV for current month
#   - At least one job manifest found
#   - Output archives present
#   - System metrics being collected
#   - 100% success rate for full functionality
#
# SPECIAL REQUIREMENTS:
#   - Marathon must have run at least one job previously
#   - Read access to /mnt/data/marathon directories
#   - Scripts must be marked executable
#
# NOTES:
#   - This is a quick validation, not a comprehensive test
#   - Use test_marathon.sh for full integration testing
#   - Exit code 0 if all checks pass, 1 if any fail
#   - Results shown with checkmarks (✓) and X marks (✗)

echo "Marathon Test Report"
echo "==================="
echo

passed=0
failed=0

# Check scripts exist
echo "1. Core Scripts:"
for script in metadata.sh archive.sh retry.sh health.sh; do
    if [[ -f "$script" && -x "$script" ]]; then
        echo "   ✓ $script"
        ((passed++))
    else
        echo "   ✗ $script"
        ((failed++))
    fi
done

echo
echo "2. Test Scripts:"
for script in test_*.sh demo_cleanup.sh; do
    if [[ -f "$script" && -x "$script" ]]; then
        echo "   ✓ $script"
        ((passed++))
    else
        echo "   ✗ $script"
        ((failed++))
    fi
done

echo
echo "3. Health Check:"
if ./health.sh json | grep -q '"status":' 2>/dev/null; then
    echo "   ✓ Health check JSON output"
    ((passed++))
else
    echo "   ✗ Health check failed"
    ((failed++))
fi

echo
echo "4. Log Structure:"
for dir in jobs system transfers reports; do
    if [[ -d "/mnt/data/marathon/log/$dir" ]]; then
        echo "   ✓ logs/$dir/ directory"
        ((passed++))
    else
        echo "   ✗ logs/$dir/ missing"
        ((failed++))
    fi
done

echo
echo "5. Generated Files:"
if [[ -f "/mnt/data/marathon/log/reports/job_index.txt" ]]; then
    jobs=$(grep -c "|completed|" /mnt/data/marathon/log/reports/job_index.txt 2>/dev/null || echo 0)
    echo "   ✓ Job index ($jobs completed jobs)"
    ((passed++))
else
    echo "   ✗ Job index missing"
    ((failed++))
fi

if [[ -f "/mnt/data/marathon/log/reports/performance/metrics_$(date +%Y%m).csv" ]]; then
    echo "   ✓ Performance metrics"
    ((passed++))
else
    echo "   ✗ Performance metrics missing"
    ((failed++))
fi

manifests=$(find /mnt/data/marathon/log/jobs -name "manifest.json" 2>/dev/null | wc -l)
if [[ $manifests -gt 0 ]]; then
    echo "   ✓ Job manifests ($manifests found)"
    ((passed++))
else
    echo "   ✗ No job manifests"
    ((failed++))
fi

archives=$(ls /mnt/data/marathon/output/*.tar.xz 2>/dev/null | wc -l)
if [[ $archives -gt 0 ]]; then
    echo "   ✓ Output archives ($archives found)"
    ((passed++))
else
    echo "   ✗ No output archives"
    ((failed++))
fi

echo
echo "6. System Metrics:"
date_path=$(date +%Y/%m/%d)
metrics_dir="/mnt/data/marathon/log/system/$date_path"
if [[ -d "$metrics_dir" ]]; then
    metric_files=$(find "$metrics_dir" -name "*.load" -o -name "*.memory" -o -name "*.free" 2>/dev/null | wc -l)
    echo "   ✓ System metrics directory ($metric_files files)"
    ((passed++))
else
    echo "   ✗ System metrics directory missing"
    ((failed++))
fi

echo
echo "=========================================="
echo "TOTAL RESULTS:"
echo "  Passed: $passed"
echo "  Failed: $failed"
echo "  Success Rate: $(( passed * 100 / (passed + failed) ))%"
echo

if [[ $failed -eq 0 ]]; then
    echo "🎉 ALL TESTS PASSED!"
    exit 0
else
    echo "⚠️  Some features need attention"
    exit 1
fi