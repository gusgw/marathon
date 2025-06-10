#! /bin/bash
#
# cleanup.sh - Graceful shutdown and cleanup routines for Marathon
#
# PURPOSE:
#   Provides comprehensive cleanup functionality for both normal exits and
#   signal-triggered shutdowns. Ensures all data is saved, processes are
#   terminated cleanly, and resources are released properly.
#
# USAGE:
#   This script is sourced by run.sh to register cleanup handlers
#   Should not be run directly
#
# KEY FUNCTIONS:
#   - cleanup_run: Main cleanup handler for orchestrator process
#   - parallel_cleanup_run: Cleanup for individual parallel workers
#   - Handles signal trapping and graceful termination
#   - Manages data persistence before shutdown
#   - Controls workspace cleanup based on mode
#
# DEPENDENCIES:
#   - GNU Parallel (for job control)
#   - rclone (for uploading logs)
#   - tar/xz (for log archiving)
#   - metadata.sh functions (if available)
#   - Standard Unix utilities: kill, rm, sleep
#
# ENVIRONMENT VARIABLES USED:
#   - parallel_pid: PID of GNU Parallel process
#   - logs/logspace: Log directories
#   - work/workspace: Working directories
#   - clean: Cleanup mode (keep/output/gpg/all)
#   - encrypt_flag: Whether encryption is enabled
#   - inglob/outglob: File patterns
#   - ramdisk: Temporary file location
#   - output: rclone destination for results
#   - STAMP: Timestamp for file naming
#   - job: Job identifier
#   - OUTBOUND_TRANSFERS: Parallel upload limit
#
# CLEANUP MODES:
#   - keep: Preserve all files
#   - output: Remove output files only
#   - gpg: Remove output and encrypted files
#   - all: Complete cleanup and optional shutdown

cleanup_functions+=('cleanup_run')

# cleanup_run: Main cleanup handler for graceful shutdown
# 
# Performs comprehensive cleanup when the job exits (normally or via signal):
# - Terminates GNU Parallel and all worker processes
# - Saves process status information
# - Encrypts outputs if configured
# - Uploads results and logs to remote storage
# - Removes temporary files based on cleanup mode
# - Optionally shuts down the instance (for cloud deployments)
# 
# WARNING: When using report() here, never use a third argument
#          or it will cause an infinite loop!
# 
# Usage: cleanup_run exit_code
# Args:
#   $1 - Exit code to log (passed from cleanup function)
# Globals:
#   parallel_pid - PID of GNU Parallel process
#   logs - Directory for log files
#   work - Working directory
#   clean - Cleanup mode (keep/output/gpg/all)
#   encrypt_flag - Whether to encrypt outputs
#   inglob/outglob - File patterns
#   ramdisk - Temporary storage location
# Returns: Exits with appropriate code or triggers shutdown
function cleanup_run {

    ######################################
    # If using the report function here, #
    # make sure it has NO THIRD ARGUMENT #
    # or there will be an infinite loop! #
    # This function may be used to       #
    # handle trapped signals             #
    ######################################

    local rc=$1

    >&2 echo "---"
    >&2 echo "${STAMP}: exiting cleanly with code ${rc}. . ."

    ######################################################################
    # Signal GNU Parallel if necessary
    # One TERM signal stops new jobs from starting,
    # two term signals kills existing jobs.
    if [ -n "$parallel_pid" ]; then
        log_setting "PID of GNU Parallel for cleanup" "$parallel_pid"
        if kill -0 "$parallel_pid" 2> /dev/null; then
            >&2 echo "${STAMP}: signalling parallel"
            kill -TERM "$parallel_pid"
            kill -TERM "$parallel_pid"
        fi
    fi

    ######################################################################
    # Save the status of this process and kill remaining workers
    # before the rest of the cleanup work

    >&2 echo "${STAMP}: checking for child processes"

    local status="${logs}/status/$$.${STAMP}.cleanup.status"
    cp "/proc/$$/status" "$status"
    chmod u+w "$status"

    if [[ -f "$ramdisk/workers" ]]; then
        while read -r pid; do
            # Extract just the PID if line contains more data
            local actual_pid="${pid%% *}"
            if [[ -n "$actual_pid" ]] && kill -0 "$actual_pid" 2>/dev/null; then
                >&2 echo "${STAMP}: ${pid} is still running - trying to stop it"
                # Try graceful termination first
                kill -TERM "$actual_pid" 2>/dev/null || true
                # Give process time to exit gracefully
                local count=0
                while [[ $count -lt 3 ]] && kill -0 "$actual_pid" 2>/dev/null; do
                    sleep 1
                    ((count++))
                done
                # Force kill if still running
                if kill -0 "$actual_pid" 2>/dev/null; then
                    >&2 echo "${STAMP}: Force killing ${actual_pid}"
                    kill -KILL "$actual_pid" 2>/dev/null || true
                fi
            fi
        done < "$ramdisk/workers"
    fi

    ######################################################################
    # Encrypt the results
    if [ "${encrypt_flag}" == "yes" ]; then
        >&2 echo "${STAMP}: calling encrypt_outputs"
        encrypt_outputs
    fi

    ######################################################################
    # Save the results to the output destination
    >&2 echo "${STAMP}: saving outputs"
    send_outputs

    if ! [ "$clean" == "keep" ]; then
        >&2 echo "${STAMP}: removing downloaded input files"
        shopt -s nullglob
        for f in "${work}"/${inglob}.gpg; do
            rm -f "${f}" || report $FILING_ERROR "remove input file ${f}"
        done
        for f in "${work}"/${inglob}; do
            rm -f "${f}" || report $FILING_ERROR "remove input file ${f}"
        done
        shopt -u nullglob
    fi

    if [ "$clean" == "output" ] || [ "$clean" == "gpg" ] || [ "$clean" == "all" ]; then
        >&2 echo "${STAMP}: removing output files"
        shopt -s nullglob
        for f in "${work}"/${outglob}; do
            rm -f "${f}" || report $FILING_ERROR "remove raw output ${f}"
        done
        shopt -u nullglob
    else
        >&2 echo "${STAMP}: keeping output files"
    fi

    if [ "$clean" == "gpg" ] || [ "$clean" == "all" ]; then
        >&2 echo "${STAMP}: removing GPG files"
        shopt -s nullglob
        for gpg in "${work}"/${outglob}.gpg; do
            rm -f "${gpg}" || report $FILING_ERROR "remove signed and encrypted ${gpg}"
        done
        shopt -u nullglob
    else
        >&2 echo "${STAMP}: keeping GPG files"
    fi

    # Generate metadata before archiving logs
    >&2 echo "${STAMP}: generating job metadata"
    if command -v create_job_manifest >/dev/null 2>&1; then
        create_job_manifest "${rc}"
    fi
    
    # Update job index
    if command -v update_job_index >/dev/null 2>&1; then
        local job_status="completed"
        if [[ "${rc}" -ne 0 ]]; then
            job_status="failed"
        fi
        update_job_index "${job_status}"
    fi
    
    # Update error index if job failed
    if [[ "${rc}" -ne 0 ]] && command -v update_error_index >/dev/null 2>&1; then
        update_error_index "${rc}" "Job failed with exit code ${rc}"
    fi
    
    # Generate performance report
    if command -v create_performance_report >/dev/null 2>&1; then
        create_performance_report
    fi
    
    # Generate daily summary
    if command -v generate_daily_summary >/dev/null 2>&1; then
        generate_daily_summary
    fi
    
    local log_archive="${work}/${STAMP}.${job}.$$.logs.tar.xz"
    savewd="$(pwd)"
    cd "${logspace}" && tar Jcvf "${log_archive}" "${job}/"
    cd "${savewd}"
    rclone copy "${log_archive}" \
                "${output}/" \
                --config "${run_path}/rclone.conf" \
                --log-level WARNING \
                --transfers "${OUTBOUND_TRANSFERS}" ||\
        report $NETWORK_ERROR "sending logs to output folder"

    if [ "$clean" == "all" ]; then
        rm -rf ${work} || report $FILING_ERROR "removing work folder"
    else
        >&2 echo "${STAMP}: keeping work folder"
    fi

    if [ "$clean" == "all" ]; then
        rm -rf ${logs} || report $FILING_ERROR "removing log folder"
    else
        >&2 echo "${STAMP}: keeping log folder"
    fi

    rm $ramdisk/workers
    rm -rf $ramdisk

    >&2 echo "${STAMP}: . . . all done with code ${rc}"
    >&2 echo "---"
    if [ "$clean" == "all" ] && [ "$rc" -eq 0 ]; then
        sudo shutdown now
    else
        exit $rc
    fi
}

export parallel_cleanup_function="parallel_cleanup_run"

# parallel_cleanup_run: Cleanup handler for GNU Parallel worker processes
# 
# Called when individual parallel jobs exit. Saves process status information
# for debugging and monitoring. Uses GNU Parallel environment variables to
# identify the specific job instance.
# 
# Usage: parallel_cleanup_run exit_code
# Args:
#   $1 - Exit code of the parallel job
# Environment:
#   PARALLEL_PID - PID of the GNU Parallel parent
#   PARALLEL_JOBSLOT - Job slot number
#   PARALLEL_SEQ - Job sequence number
# Globals:
#   logs - Directory for log files
#   STAMP - Timestamp for file naming
# Returns: The provided exit code
function parallel_cleanup_run {
    local rc=$1
    >&2 echo "---"
    >&2 echo "${STAMP}" "${PARALLEL_PID}" \
                        "${PARALLEL_JOBSLOT}" \
                        "${PARALLEL_SEQ}: exiting run cleanly with code ${rc}. . ."
    whoami="$$.${PARALLEL_PID}.${PARALLEL_JOBSLOT}.${PARALLEL_SEQ}"
    local status="${logs}/status/${whoami}.${STAMP}.parallel_cleanup.status"
    cp "/proc/$$/status" "$status" || parallel_report $FILING_ERROR "copy status files"
    chmod u+w "$status"
    >&2 echo "${STAMP}" "${PARALLEL_PID}" \
                        "${PARALLEL_JOBSLOT}" \
                        "${PARALLEL_SEQ}: . . . all done with code ${rc}"
    >&2 echo "---"
    return $rc
}
export -f parallel_cleanup_run
