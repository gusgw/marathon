#!/bin/bash
#
# retry.sh - Retry mechanism with exponential backoff for Marathon
#
# PURPOSE:
#   Implements intelligent retry logic for transient failures with exponential
#   backoff. Distinguishes between retryable (network, timeout) and permanent
#   errors. Provides specialized handling for rclone operations and configurable
#   retry policies based on job criticality.
#
# USAGE:
#   This script is sourced by io.sh to provide retry capabilities
#   Can also be sourced independently for retry functionality
#
# KEY FUNCTIONS:
#   - retry_with_backoff: Execute any command with retry logic
#   - is_retryable_error: Determine if error should trigger retry
#   - retry_rclone_operation: Specialized retry for rclone commands
#   - configure_retry_policy: Adjust retry behavior by job type
#   - record_retry_metrics: Track retry statistics for analysis
#
# DEPENDENCIES:
#   - bump/return_codes.sh (for error code definitions)
#   - metadata.sh functions (optional, for error tracking)
#   - Standard Unix utilities: sleep
#
# ENVIRONMENT VARIABLES USED:
#   - MAX_RETRIES: Maximum retry attempts (default: 3)
#   - INITIAL_RETRY_DELAY: First retry delay in seconds (default: 60)
#   - MAX_RETRY_DELAY: Maximum delay between retries (default: 3600)
#   - RETRY_BACKOFF_FACTOR: Delay multiplier (default: 2)
#   - run_path: Marathon installation directory
#   - logs: Log directory path
#   - reports_base: Reports directory for metrics
#
# RETRY POLICIES:
#   - critical: 5 retries, 30s initial, 2hr max delay
#   - normal: 3 retries, 60s initial, 1hr max delay
#   - batch: 1 retry, 120s initial, 10min max delay
#
# RETRYABLE ERRORS:
#   - Network errors (20, 7, 52, 56)
#   - Timeouts (124, 28)
#   - SSH failures (255)
#   - NOT retryable: Spot interruptions, file errors

# Default retry configuration
export MAX_RETRIES=${MAX_RETRIES:-3}
export INITIAL_RETRY_DELAY=${INITIAL_RETRY_DELAY:-60}  # seconds
export MAX_RETRY_DELAY=${MAX_RETRY_DELAY:-3600}        # 1 hour max
export RETRY_BACKOFF_FACTOR=${RETRY_BACKOFF_FACTOR:-2}

# retry_with_backoff: Execute a command with retry logic
#
# Runs a command and retries on failure with exponential backoff.
# Records retry attempts and delays in logs.
#
# Usage: retry_with_backoff command [args...]
# Args:
#   $@ - Command and arguments to execute
# Returns: Exit code of the command (0 on success, last failure code on exhaustion)
function retry_with_backoff {
    local attempt=0
    local delay=${INITIAL_RETRY_DELAY}
    local exit_code=0
    local cmd="$@"
    
    while [[ ${attempt} -le ${MAX_RETRIES} ]]; do
        if [[ ${attempt} -gt 0 ]]; then
            log_message "Retry attempt ${attempt}/${MAX_RETRIES} for: ${cmd}"
            log_message "Waiting ${delay} seconds before retry..."
            sleep ${delay}
            
            # Calculate next delay with exponential backoff
            delay=$((delay * RETRY_BACKOFF_FACTOR))
            if [[ ${delay} -gt ${MAX_RETRY_DELAY} ]]; then
                delay=${MAX_RETRY_DELAY}
            fi
        fi
        
        # Execute the command
        "$@"
        exit_code=$?
        
        if [[ ${exit_code} -eq 0 ]]; then
            if [[ ${attempt} -gt 0 ]]; then
                log_message "Command succeeded after ${attempt} retries"
            fi
            return 0
        fi
        
        # Check if error is retryable
        if ! is_retryable_error ${exit_code}; then
            echo "Non-retryable error (exit code: ${exit_code}), aborting retries" >&2
            return ${exit_code}
        fi
        
        attempt=$((attempt + 1))
        
        if [[ ${attempt} -gt ${MAX_RETRIES} ]]; then
            log_error "Maximum retries (${MAX_RETRIES}) exhausted for: ${cmd}"
            log_error "Final exit code: ${exit_code}"
            
            # Update error index with retry exhaustion
            if command -v update_error_index >/dev/null 2>&1; then
                update_error_index ${exit_code} "Retry exhausted after ${MAX_RETRIES} attempts"
            fi
        fi
    done
    
    return ${exit_code}
}

# is_retryable_error: Determine if an error code is retryable
#
# Checks if the given exit code represents a transient error that
# should be retried. Network errors, timeouts, and certain AWS
# errors are considered retryable.
#
# Usage: is_retryable_error exit_code
# Args:
#   $1 - Exit code to check
# Returns: 0 if retryable, 1 if not retryable
function is_retryable_error {
    local exit_code=$1
    
    # Load return codes if available
    if [[ -f "${run_path}/bump/return_codes.sh" ]]; then
        . "${run_path}/bump/return_codes.sh"
    fi
    
    # Define retryable error codes
    case ${exit_code} in
        ${NETWORK_ERROR:-20})
            # Network errors are typically transient
            return 0
            ;;
        ${TIMEOUT_ERROR:-124})
            # Timeout errors might succeed on retry
            return 0
            ;;
        28)
            # curl timeout
            return 0
            ;;
        7)
            # curl connection failed
            return 0
            ;;
        52|56)
            # curl empty reply or network data error
            return 0
            ;;
        255)
            # SSH connection error
            return 0
            ;;
        *)
            # Check if it's an AWS spot interruption
            if [[ -f "${logs}/spot_interruption_detected" ]]; then
                return 1  # Don't retry spot interruptions
            fi
            
            # All other errors are not retryable by default
            return 1
            ;;
    esac
}

# retry_rclone_operation: Wrapper for rclone operations with retry
#
# Specifically handles rclone operations which are prone to network issues.
# Uses more aggressive retry settings for better reliability.
#
# Usage: retry_rclone_operation rclone_command [args...]
# Returns: Exit code from rclone operation
function retry_rclone_operation {
    local old_max_retries=${MAX_RETRIES}
    local old_initial_delay=${INITIAL_RETRY_DELAY}
    
    # Use more aggressive retry settings for rclone
    export MAX_RETRIES=5
    export INITIAL_RETRY_DELAY=30
    
    retry_with_backoff "$@"
    local exit_code=$?
    
    # Restore original settings
    export MAX_RETRIES=${old_max_retries}
    export INITIAL_RETRY_DELAY=${old_initial_delay}
    
    return ${exit_code}
}

# record_retry_metrics: Log retry statistics for analysis
#
# Records retry attempt information for later analysis and optimization
# of retry parameters.
#
# Usage: record_retry_metrics job_id attempts success delay_total
# Args:
#   $1 - Job identifier
#   $2 - Number of retry attempts
#   $3 - Success (1) or failure (0)
#   $4 - Total delay time in seconds
function record_retry_metrics {
    local job_id=$1
    local attempts=$2
    local success=$3
    local delay_total=$4
    local retry_log="${reports_base}/retry_metrics.csv"
    
    # Create header if file doesn't exist
    if [[ ! -f "${retry_log}" ]]; then
        echo "timestamp,job_id,attempts,success,total_delay_seconds" > "${retry_log}"
    fi
    
    # Append retry metrics
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ"),${job_id},${attempts},${success},${delay_total}" >> "${retry_log}"
}

# configure_retry_policy: Set retry policy based on job type
#
# Adjusts retry parameters based on the type of job being executed.
# Critical jobs get more retries, batch jobs get fewer.
#
# Usage: configure_retry_policy job_type
# Args:
#   $1 - Job type (critical|normal|batch)
function configure_retry_policy {
    local job_type=${1:-normal}
    
    case ${job_type} in
        critical)
            export MAX_RETRIES=5
            export INITIAL_RETRY_DELAY=30
            export MAX_RETRY_DELAY=7200  # 2 hours
            log_message "Using critical job retry policy (max ${MAX_RETRIES} retries)"
            ;;
        batch)
            export MAX_RETRIES=1
            export INITIAL_RETRY_DELAY=120
            export MAX_RETRY_DELAY=600   # 10 minutes
            log_message "Using batch job retry policy (max ${MAX_RETRIES} retries)"
            ;;
        normal|*)
            export MAX_RETRIES=3
            export INITIAL_RETRY_DELAY=60
            export MAX_RETRY_DELAY=3600  # 1 hour
            log_message "Using normal job retry policy (max ${MAX_RETRIES} retries)"
            ;;
    esac
}