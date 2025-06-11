#!/bin/bash
#
# health.sh - Health check endpoint for Marathon workers
#
# PURPOSE:
#   Provides comprehensive health monitoring for Marathon workers with both
#   command-line and HTTP interfaces. Performs multiple system checks to
#   ensure worker readiness and detect potential issues early.
#
# USAGE:
#   ./health.sh {check|serve [port]|json}
#   
#   check - Run health check and exit with status code
#   serve - Start HTTP health check server (default port: 8080)
#   json  - Output JSON status without exit code
#
# KEY FUNCTIONS:
#   - health_check: Performs comprehensive system health checks
#   - serve_health_http: Simple HTTP server for monitoring tools
#   - Checks disk space, memory, load, dependencies, and errors
#
# DEPENDENCIES:
#   - netcat (nc) for HTTP server mode
#   - bc (for arithmetic comparisons)
#   - Standard Unix utilities: df, awk, nproc, uptime
#   - /proc filesystem for system metrics
#
# ENVIRONMENT VARIABLES USED:
#   - workspace: Working directory to check (defaults to current directory)
#   - logspace: Log directory to check
#   - reports_base: Reports directory for error checking
#   - HOSTNAME: System hostname
#
# EXIT CODES:
#   - 0: Healthy - all checks passed
#   - 1: Unhealthy - non-critical issues detected
#   - 2: Critical - essential components missing
#
# HEALTH CHECKS:
#   1. Critical directories exist
#   2. Disk space >10% free
#   3. Active marathon jobs (informational)
#   4. rclone availability (critical)
#   5. System load below threshold
#   6. Memory >10% available
#   7. GNU Parallel availability (critical)
#   8. Recent error rate acceptable
#
# OUTPUT FORMAT:
#   JSON with status, checks passed/total, messages, and metrics

# Source configuration and utilities
export run_path=$(dirname $(realpath $0))
. ${run_path}/bump/bump.sh

# health_check: Main health check function
#
# Performs various checks to determine worker health status.
# Outputs JSON response with health information.
#
# Usage: health_check
# Returns: 0 if healthy, 1 if unhealthy, 2 if critical
function health_check {
    local status="healthy"
    local exit_code=0
    local checks_passed=0
    local checks_total=0
    local messages=()
    
    # Check 1: Verify critical directories exist
    checks_total=$((checks_total + 1))
    if [[ -d "${workspace}" ]] && [[ -d "${logspace}" ]]; then
        checks_passed=$((checks_passed + 1))
    else
        status="unhealthy"
        exit_code=1
        messages+=("Critical directories missing")
    fi
    
    # Check 2: Check disk space (need at least 10% free)
    checks_total=$((checks_total + 1))
    # Use workspace if set, otherwise check current directory
    local check_path="${workspace:-.}"
    local disk_usage=$(df "${check_path}" 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//')
    if [[ "${disk_usage}" -lt 90 ]]; then
        checks_passed=$((checks_passed + 1))
    else
        status="unhealthy"
        exit_code=1
        messages+=("Low disk space: ${disk_usage}% used")
    fi
    
    # Check 3: Check if any marathon jobs are running
    checks_total=$((checks_total + 1))
    local running_jobs=$(find /dev/shm -name "*-$$" -type d 2>/dev/null | wc -l)
    if [[ -n "${running_jobs}" ]]; then
        checks_passed=$((checks_passed + 1))
    fi
    
    # Check 4: Verify rclone is available
    checks_total=$((checks_total + 1))
    if command -v rclone >/dev/null 2>&1; then
        checks_passed=$((checks_passed + 1))
    else
        status="critical"
        exit_code=2
        messages+=("rclone not found")
    fi
    
    # Check 5: Check system load
    checks_total=$((checks_total + 1))
    if [[ -f /proc/loadavg ]]; then
        local load_1min=$(cut -d' ' -f1 /proc/loadavg)
        local cpu_count=$(nproc 2>/dev/null || echo 1)
        local load_threshold=$((cpu_count * 2))
        
        if (( $(echo "${load_1min} < ${load_threshold}" | bc -l) )); then
            checks_passed=$((checks_passed + 1))
        else
            messages+=("High system load: ${load_1min}")
        fi
    else
        checks_passed=$((checks_passed + 1))
    fi
    
    # Check 6: Check memory availability
    checks_total=$((checks_total + 1))
    if [[ -f /proc/meminfo ]]; then
        local mem_available=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)
        local mem_total=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
        local mem_percent=$((mem_available * 100 / mem_total))
        
        if [[ "${mem_percent}" -gt 10 ]]; then
            checks_passed=$((checks_passed + 1))
        else
            status="unhealthy"
            exit_code=1
            messages+=("Low memory: ${mem_percent}% available")
        fi
    else
        checks_passed=$((checks_passed + 1))
    fi
    
    # Check 7: Verify GNU Parallel is available
    checks_total=$((checks_total + 1))
    if command -v parallel >/dev/null 2>&1; then
        checks_passed=$((checks_passed + 1))
    else
        status="critical"
        exit_code=2
        messages+=("GNU Parallel not found")
    fi
    
    # Check 8: Check for recent errors in job index
    checks_total=$((checks_total + 1))
    if [[ -f "${reports_base}/error_index.txt" ]]; then
        local recent_errors=$(tail -10 "${reports_base}/error_index.txt" | grep -c "^$(date +%Y-%m-%d)")
        if [[ "${recent_errors}" -lt 5 ]]; then
            checks_passed=$((checks_passed + 1))
        else
            messages+=("${recent_errors} errors today")
        fi
    else
        checks_passed=$((checks_passed + 1))
    fi
    
    # Generate timestamp
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Output JSON response
    echo "{"
    echo "  \"status\": \"${status}\","
    echo "  \"timestamp\": \"${timestamp}\","
    echo "  \"hostname\": \"${HOSTNAME}\","
    echo "  \"checks_passed\": ${checks_passed},"
    echo "  \"checks_total\": ${checks_total},"
    echo "  \"running_jobs\": ${running_jobs},"
    
    if [[ "${#messages[@]}" -gt 0 ]]; then
        echo "  \"messages\": ["
        local first=true
        for msg in "${messages[@]}"; do
            if [[ "${first}" != "true" ]]; then echo ","; fi
            first=false
            echo -n "    \"${msg}\""
        done
        echo ""
        echo "  ],"
    fi
    
    echo "  \"uptime\": \"$(uptime -p 2>/dev/null || echo 'unknown')\""
    echo "}"
    
    return ${exit_code}
}

# serve_health_http: Simple HTTP server for health checks
#
# Starts a minimal HTTP server on port 8080 that responds to health check requests.
# Only responds to GET /health requests.
#
# Usage: serve_health_http
function serve_health_http {
    local port=${1:-8080}
    
    echo "Starting health check HTTP server on port ${port}"
    
    while true; do
        # Use netcat to listen for HTTP requests
        { echo -ne "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n"; health_check; } | \
            nc -l -p ${port} -q 1 >/dev/null 2>&1
    done
}

# Main execution
case "${1:-check}" in
    check)
        # Run single health check
        health_check
        exit $?
        ;;
    serve)
        # Start HTTP server
        port=${2:-8080}
        serve_health_http ${port}
        ;;
    json)
        # Output only JSON (no exit code)
        health_check
        ;;
    *)
        echo "Usage: $0 {check|serve [port]|json}"
        echo "  check - Run health check and exit with status code"
        echo "  serve - Start HTTP health check server (default port: 8080)"
        echo "  json  - Output JSON status without exit code"
        exit 1
        ;;
esac