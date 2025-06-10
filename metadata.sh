#! /bin/bash
#
# metadata.sh - Metadata generation and reporting utilities for Marathon
#
# PURPOSE:
#   Creates comprehensive metadata about job execution including manifests,
#   performance metrics, error tracking, and summary reports. Enables job
#   tracking, troubleshooting, and performance analysis across runs.
#
# USAGE:
#   This script is sourced by run.sh to provide metadata functions
#   Should not be run directly
#
# KEY FUNCTIONS:
#   - create_job_manifest: Generate JSON manifest with job details
#   - update_job_index: Maintain central index of all jobs
#   - update_error_index: Track failed jobs for troubleshooting
#   - generate_daily_summary: Create daily execution reports
#   - create_performance_report: Collect performance metrics
#
# DEPENDENCIES:
#   - sha256sum (for file checksums)
#   - Standard Unix utilities: stat, awk, grep, sort, du
#   - JSON-compatible output formatting
#
# ENVIRONMENT VARIABLES USED:
#   - job: Job identifier
#   - logs/logs_base: Log directories
#   - work: Working directory
#   - input/output: rclone paths
#   - inglob/outglob: File patterns
#   - STAMP: Timestamp for job
#   - HOSTNAME: System hostname
#   - encrypt_flag: Encryption status
#   - reports_base: Reports directory
#   - DATE_* variables: Date components
#
# OUTPUT FILES:
#   - manifest.json: Comprehensive job metadata
#   - job_index.txt: Master list of all jobs
#   - error_index.txt: Failed job tracking
#   - daily/*/summary.txt: Daily summaries
#   - performance/metrics_*.csv: Performance data

# create_job_manifest: Generate a JSON manifest file for the current job
#
# Creates a comprehensive manifest file containing job metadata including
# input/output file checksums, timestamps, resource usage, and exit status.
# The manifest is saved as manifest.json in the job's log directory.
#
# Usage: create_job_manifest exit_code
# Args:
#   $1 - Exit code of the job
# Globals:
#   job - Job name/identifier
#   logs - Job log directory
#   work - Job work directory
#   input/output - rclone paths
#   inglob/outglob - file patterns
#   STAMP - Job timestamp
#   HOSTNAME - System hostname
# Returns: 0 on success
function create_job_manifest {
    local exit_code=$1
    local manifest_file="${logs}/manifest.json"
    local start_time="${STAMP}"
    local end_time=$(date +%Y%m%dT%H%M%S)
    
    # Start JSON
    echo "{" > "${manifest_file}"
    echo "  \"job_id\": \"${STAMP}-${HOSTNAME}.${job}.$$\"," >> "${manifest_file}"
    echo "  \"job_name\": \"${job}\"," >> "${manifest_file}"
    echo "  \"hostname\": \"${HOSTNAME}\"," >> "${manifest_file}"
    echo "  \"pid\": $$," >> "${manifest_file}"
    echo "  \"start_time\": \"${start_time}\"," >> "${manifest_file}"
    echo "  \"end_time\": \"${end_time}\"," >> "${manifest_file}"
    echo "  \"exit_code\": ${exit_code}," >> "${manifest_file}"
    echo "  \"input_path\": \"${input}\"," >> "${manifest_file}"
    echo "  \"output_path\": \"${output}\"," >> "${manifest_file}"
    echo "  \"input_pattern\": \"${inglob}\"," >> "${manifest_file}"
    echo "  \"output_pattern\": \"${outglob}\"," >> "${manifest_file}"
    
    # Add input file checksums
    echo "  \"input_files\": [" >> "${manifest_file}"
    local first=true
    for file in "${work}"/${inglob}; do
        if [[ -f "$file" ]]; then
            if [[ "$first" != "true" ]]; then echo "," >> "${manifest_file}"; fi
            first=false
            local basename=$(basename "$file")
            local checksum=$(sha256sum "$file" | cut -d' ' -f1)
            local size=$(stat -c%s "$file")
            echo -n "    {\"name\": \"${basename}\", \"sha256\": \"${checksum}\", \"size\": ${size}}" >> "${manifest_file}"
        fi
    done
    echo "" >> "${manifest_file}"
    echo "  ]," >> "${manifest_file}"
    
    # Add output file checksums
    echo "  \"output_files\": [" >> "${manifest_file}"
    first=true
    for file in "${work}"/${outglob}; do
        if [[ -f "$file" ]]; then
            if [[ "$first" != "true" ]]; then echo "," >> "${manifest_file}"; fi
            first=false
            local basename=$(basename "$file")
            local checksum=$(sha256sum "$file" | cut -d' ' -f1)
            local size=$(stat -c%s "$file")
            echo -n "    {\"name\": \"${basename}\", \"sha256\": \"${checksum}\", \"size\": ${size}}" >> "${manifest_file}"
        fi
    done
    if [[ "${encrypt_flag}" == "yes" ]]; then
        for file in "${work}"/${outglob}.gpg; do
            if [[ -f "$file" ]]; then
                if [[ "$first" != "true" ]]; then echo "," >> "${manifest_file}"; fi
                first=false
                local basename=$(basename "$file")
                local checksum=$(sha256sum "$file" | cut -d' ' -f1)
                local size=$(stat -c%s "$file")
                echo -n "    {\"name\": \"${basename}\", \"sha256\": \"${checksum}\", \"size\": ${size}, \"encrypted\": true}" >> "${manifest_file}"
            fi
        done
    fi
    echo "" >> "${manifest_file}"
    echo "  ]," >> "${manifest_file}"
    
    # Add resource usage summary
    echo "  \"resource_usage\": {" >> "${manifest_file}"
    if [[ -f "${logs}/${STAMP}.${job}.$$.memory" ]]; then
        local max_memory=$(awk '{print $5}' "${logs}/${STAMP}.${job}.$$.memory" | sort -n | tail -1)
        echo "    \"max_memory_mb\": ${max_memory:-0}," >> "${manifest_file}"
    fi
    if [[ -f "${logs}/${STAMP}.${job}.$$.load" ]]; then
        local avg_load=$(awk '{sum+=$2; count++} END {if(count>0) print sum/count; else print 0}' "${logs}/${STAMP}.${job}.$$.load")
        echo "    \"avg_load_1min\": ${avg_load}" >> "${manifest_file}"
    fi
    echo "  }" >> "${manifest_file}"
    
    echo "}" >> "${manifest_file}"
    
    log_message "Created job manifest: ${manifest_file}"
    return 0
}

# update_job_index: Add current job to the job index file
#
# Appends a summary line for the current job to the central job index.
# Creates the index file if it doesn't exist with a header line.
#
# Usage: update_job_index status
# Args:
#   $1 - Job status (completed/failed/cancelled)
# Globals:
#   reports_base - Base directory for reports
#   job - Job name
#   STAMP - Job timestamp
# Returns: 0 on success
function update_job_index {
    local status=$1
    local index_file="${reports_base}/job_index.txt"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    
    # Create header if file doesn't exist
    if [[ ! -f "${index_file}" ]]; then
        echo "TIMESTAMP|JOB_ID|JOB_NAME|STATUS|HOSTNAME|PID" > "${index_file}"
    fi
    
    # Append job entry
    echo "${timestamp}|${STAMP}-${HOSTNAME}.${job}.$$|${job}|${status}|${HOSTNAME}|$$" >> "${index_file}"
    
    return 0
}

# update_error_index: Add failed job to error index
#
# Records failed jobs in a dedicated error index for quick troubleshooting.
# Includes error details and log file locations.
#
# Usage: update_error_index exit_code error_message
# Args:
#   $1 - Exit code
#   $2 - Error message/description
# Globals:
#   reports_base - Base directory for reports
#   job - Job name
#   logs - Job log directory
# Returns: 0 on success
function update_error_index {
    local exit_code=$1
    local error_msg=$2
    local error_file="${reports_base}/error_index.txt"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    
    # Create header if file doesn't exist
    if [[ ! -f "${error_file}" ]]; then
        echo "TIMESTAMP|JOB_ID|EXIT_CODE|ERROR_MESSAGE|LOG_PATH" > "${error_file}"
    fi
    
    # Append error entry
    echo "${timestamp}|${STAMP}-${HOSTNAME}.${job}.$$|${exit_code}|${error_msg}|${logs}" >> "${error_file}"
    
    # Also copy logs to failures directory for easy access
    local failure_dir="${reports_base}/failures/${DATE_PATH}/${job}-${STAMP}"
    mkdir -p "${failure_dir}"
    cp -r "${logs}"/* "${failure_dir}/" 2>/dev/null || true
    
    return 0
}

# generate_daily_summary: Create daily job execution summary
#
# Generates a summary report of all jobs executed on the current day,
# including success/failure counts, resource usage statistics, and
# performance metrics.
#
# Usage: generate_daily_summary
# Globals:
#   reports_base - Base directory for reports
#   DATE_PATH - Current date path (YYYY/MM/DD)
# Returns: 0 on success
function generate_daily_summary {
    local summary_file="${reports_base}/daily/${DATE_PATH}/summary.txt"
    local date_str=$(date +"%Y-%m-%d")
    
    echo "Marathon Daily Summary - ${date_str}" > "${summary_file}"
    echo "======================================" >> "${summary_file}"
    echo "" >> "${summary_file}"
    
    # Count jobs by status from index
    if [[ -f "${reports_base}/job_index.txt" ]]; then
        local total_jobs=$(grep "^${date_str}" "${reports_base}/job_index.txt" | wc -l)
        local completed_jobs=$(grep "^${date_str}" "${reports_base}/job_index.txt" | grep "|completed|" | wc -l)
        local failed_jobs=$(grep "^${date_str}" "${reports_base}/job_index.txt" | grep "|failed|" | wc -l)
        
        echo "Job Statistics:" >> "${summary_file}"
        echo "  Total jobs: ${total_jobs}" >> "${summary_file}"
        echo "  Completed: ${completed_jobs}" >> "${summary_file}"
        echo "  Failed: ${failed_jobs}" >> "${summary_file}"
        echo "" >> "${summary_file}"
    fi
    
    # Add performance metrics if available
    echo "Performance Metrics:" >> "${summary_file}"
    echo "  (Detailed metrics to be implemented)" >> "${summary_file}"
    
    return 0
}

# create_performance_report: Generate performance metrics report
#
# Creates a CSV file with aggregated performance metrics for trend analysis.
# Includes CPU usage, memory consumption, and job duration statistics.
#
# Usage: create_performance_report
# Globals:
#   job - Job name
#   logs - Job log directory
#   reports_base - Base directory for reports
# Returns: 0 on success
function create_performance_report {
    local perf_file="${reports_base}/performance/metrics_${DATE_YEAR}${DATE_MONTH}.csv"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    
    # Create header if file doesn't exist
    if [[ ! -f "${perf_file}" ]]; then
        echo "timestamp,job_id,job_name,duration_sec,max_memory_mb,avg_load,input_size_bytes,output_size_bytes" > "${perf_file}"
    fi
    
    # Calculate metrics
    local duration=0
    if [[ -f "${logs}/${STAMP}.${job}.run.log" ]]; then
        duration=$(grep "^Seq.*Exitval" "${logs}/${STAMP}.${job}.run.log" | awk '{sum+=$10} END {print sum}')
    fi
    
    local max_memory=0
    if [[ -f "${logs}/${STAMP}.${job}.$$.memory" ]]; then
        max_memory=$(awk '{print $5}' "${logs}/${STAMP}.${job}.$$.memory" | sort -n | tail -1)
    fi
    
    local avg_load=0
    if [[ -f "${logs}/${STAMP}.${job}.$$.load" ]]; then
        avg_load=$(awk '{sum+=$2; count++} END {if(count>0) print sum/count; else print 0}' "${logs}/${STAMP}.${job}.$$.load")
    fi
    
    local input_size=$(du -sb "${work}"/${inglob} 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
    local output_size=$(du -sb "${work}"/${outglob} 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
    
    # Append metrics
    echo "${timestamp},${STAMP}-${HOSTNAME}.${job}.$$,${job},${duration},${max_memory},${avg_load},${input_size},${output_size}" >> "${perf_file}"
    
    return 0
}