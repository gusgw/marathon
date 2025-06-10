#! /bin/bash
#
# io.sh - Data transfer operations for Marathon using rclone
#
# PURPOSE:
#   Manages all data input/output operations including downloading inputs,
#   uploading outputs, and handling GPG encryption/decryption. Provides
#   continuous output synchronization for long-running jobs.
#
# USAGE:
#   This script is sourced by run.sh to provide I/O functions
#   Should not be run directly
#
# KEY FUNCTIONS:
#   - get_inputs: Download input files from remote storage
#   - decrypt_inputs: Decrypt GPG-encrypted inputs in parallel
#   - encrypt_outputs: Encrypt and sign outputs with GPG
#   - send_outputs: Upload results to remote storage
#   - poll_outputs: Continuously sync outputs during execution
#
# DEPENDENCIES:
#   - rclone (with valid config at ${run_path}/rclone.conf)
#   - GnuPG (for encryption/decryption operations)
#   - GNU Parallel (for parallel crypto operations)
#   - retry.sh (optional, for automatic retry of failed transfers)
#
# ENVIRONMENT VARIABLES USED:
#   - NICE: Process nice value for resource management
#   - input/output: rclone source/destination paths
#   - work: Local working directory
#   - inglob/outglob: File patterns for input/output
#   - logs/logs_transfers: Log file locations
#   - INBOUND_TRANSFERS/OUTBOUND_TRANSFERS: Parallel transfer limits
#   - MAX_SUBPROCESSES: Parallel job limit for crypto operations
#   - encrypt_flag: "yes" to enable encryption
#   - sign/encrypt: GPG key IDs for signing and encryption
#   - WAIT: Seconds between status checks
#   - STAMP: Timestamp for log file naming
#   - job: Job identifier

# Load retry mechanism if available
if [[ -f "${run_path}/retry.sh" ]]; then
    . "${run_path}/retry.sh"
fi

# get_inputs: Download input files from remote storage using rclone
# 
# Synchronizes input files matching the global inglob pattern from the
# configured input location to the local work directory. Handles both
# regular files and GPG-encrypted files. Uses nice to reduce system impact.
# 
# Usage: get_inputs
# Globals:
#   NICE - Nice value for process priority
#   input - Source rclone path
#   work - Local work directory
#   inglob - Input file glob pattern
#   logs - Directory for log files
#   INBOUND_TRANSFERS - Number of parallel transfers
# Returns: 0 on success, reports error on failure
function get_inputs {

    if command -v retry_rclone_operation >/dev/null 2>&1; then
        retry_rclone_operation nice -n "${NICE}" rclone sync \
                    "${input}/" \
                    "${work}/" \
                    --config "${run_path}/rclone.conf" \
                    --log-level WARNING \
                    --log-file "${logs_transfers}/${STAMP}.${job}.rclone.input.log" \
                    --transfers "${INBOUND_TRANSFERS}" \
                    --include "${inglob}.gpg" ||\
            report $NETWORK_ERROR "download encrypted input data"
    else
        nice -n "${NICE}" rclone sync \
                    "${input}/" \
                    "${work}/" \
                    --config "${run_path}/rclone.conf" \
                    --log-level WARNING \
                    --log-file "${logs_transfers}/${STAMP}.${job}.rclone.input.log" \
                    --transfers "${INBOUND_TRANSFERS}" \
                    --include "${inglob}.gpg" ||\
            report $NETWORK_ERROR "download encrypted input data"
    fi
    if command -v retry_rclone_operation >/dev/null 2>&1; then
        retry_rclone_operation nice -n "${NICE}" rclone sync \
                    "${input}/" \
                    "${work}/" \
                    --config "${run_path}/rclone.conf" \
                    --log-level WARNING \
                    --log-file "${logs_transfers}/${STAMP}.${job}.rclone.input.log" \
                    --transfers "${INBOUND_TRANSFERS}" \
                    --include "${inglob}" ||\
            report $NETWORK_ERROR "download input data"
    else
        nice -n "${NICE}" rclone sync \
                    "${input}/" \
                    "${work}/" \
                    --config "${run_path}/rclone.conf" \
                    --log-level WARNING \
                    --log-file "${logs_transfers}/${STAMP}.${job}.rclone.input.log" \
                    --transfers "${INBOUND_TRANSFERS}" \
                    --include "${inglob}" ||\
            report $NETWORK_ERROR "download input data"
    fi

    return 0
}

# decrypt_inputs: Decrypt GPG-encrypted input files in parallel
# 
# Finds all encrypted input files matching inglob.gpg pattern and decrypts
# them using GNU Parallel for efficiency. Monitors system resources during
# decryption. Uses --always-trust for automated processing.
# 
# Usage: decrypt_inputs
# Globals:
#   work - Directory containing encrypted files
#   inglob - Input file glob pattern
#   logs - Directory for log files
#   MAX_SUBPROCESSES - Maximum parallel decryption jobs
#   NICE - Nice value for process priority
#   WAIT - Seconds between resource checks
# Returns: 0 on success
function decrypt_inputs {

    shopt -s nullglob
    for file in "${work}"/${inglob}.gpg; do
        if [[ -e "${file}" ]]; then
            find "${work}" -name "${inglob}.gpg" |\
                parallel --results "${logs}/gpg/input/{/}/" \
                         --joblog "${logs}/${STAMP}.${job}.gpg.input.log" \
                         --jobs "$MAX_SUBPROCESSES" ${OPT_PARALLEL} \
                    nice -n "${NICE}" gpg --output {.} \
                                          --compress-algo 0 \
                                          --batch \
                                          --yes \
                                          --with-colons \
                                          --always-trust \
                                          --lock-multiple {} &
            local di_parallel_pid=$!
            while kill -0 "$di_parallel_pid" 2> /dev/null; do
                sleep ${WAIT}
                load_report "${job} decrypt"  "${logs_system:-${logs}}/${STAMP}.${job}.$$.load"
                free_memory_report "${job} gpg" \
                                   "${logs_system:-${logs}}/${STAMP}.${job}.$$.free"
            done
        fi
        break
    done
    shopt -u nullglob

    return 0
}

# encrypt_outputs: Encrypt and sign output files with GPG
# 
# Finds all output files matching outglob pattern and encrypts them with
# GPG signing. Uses GNU Parallel for parallel processing. Creates .gpg
# files alongside originals. Note: Resource monitoring is commented out.
# 
# Usage: encrypt_outputs
# Globals:
#   work - Directory containing files to encrypt
#   outglob - Output file glob pattern
#   logs - Directory for log files
#   MAX_SUBPROCESSES - Maximum parallel encryption jobs
#   NICE - Nice value for process priority
#   sign - GPG key ID for signing
#   encrypt - GPG key ID for encryption
# Returns: 0 on success
function encrypt_outputs {

    find "${work}" -name "${outglob}" |\
        parallel --results "${logs}/gpg/output/{/}/" \
                 --joblog "${logs}/${STAMP}.${job}.gpg.output.log" \
                 --jobs "$MAX_SUBPROCESSES" ${OPT_PARALLEL} \
            nice -n "${NICE}" gpg --output {}.gpg \
                                  --compress-algo 0 \
                                  --batch \
                                  --yes \
                                  --with-colons \
                                  --always-trust \
                                  --lock-multiple \
                                  --sign --local-user "$sign" \
                                  --encrypt --recipient "$encrypt" {} &
    # local eo_parallel_pid=$!
    # while kill -0 "$eo_parallel_pid" 2> /dev/null; do
    #     sleep ${WAIT}
    #     load_report "${job} encrypt"  "${logs}/${STAMP}.${job}.$$.load"
    #     free_memory_report "${job} gpg" \
    #                        "${logs}/${STAMP}.${job}.$$.free"
    # done

    return 0
}

# send_outputs: Upload output files to remote storage using rclone
# 
# Copies output files from local work directory to configured output
# location. Handles both encrypted (.gpg) and unencrypted files based
# on encrypt_flag setting. Uses nice to reduce system impact.
# 
# Usage: send_outputs
# Globals:
#   encrypt_flag - "yes" if outputs should be encrypted
#   NICE - Nice value for process priority
#   work - Local work directory
#   output - Destination rclone path
#   outglob - Output file glob pattern
#   logs - Directory for log files
#   OUTBOUND_TRANSFERS - Number of parallel transfers
# Returns: 0 on success, reports error on failure
function send_outputs {

    # for file in ${work}/${outglob}.gpg; do
    if [ "${encrypt_flag}" == "yes" ]; then
        if command -v retry_rclone_operation >/dev/null 2>&1; then
            retry_rclone_operation nice -n "${NICE}" rclone copy \
                    "${work}/" \
                    "${output}/" \
                    --config "${run_path}/rclone.conf" \
                    --log-level WARNING \
                    --log-file "${logs_transfers}/${STAMP}.${job}.rclone.output.log" \
                    --include "${outglob}.gpg" \
                    --transfers "${OUTBOUND_TRANSFERS}" ||\
                report $NETWORK_ERROR "save encrypted results"
        else
            nice -n "${NICE}" rclone copy \
                    "${work}/" \
                    "${output}/" \
                    --config "${run_path}/rclone.conf" \
                    --log-level WARNING \
                    --log-file "${logs_transfers}/${STAMP}.${job}.rclone.output.log" \
                    --include "${outglob}.gpg" \
                    --transfers "${OUTBOUND_TRANSFERS}" ||\
                report $NETWORK_ERROR "save encrypted results"
        fi
    else
        if command -v retry_rclone_operation >/dev/null 2>&1; then
            retry_rclone_operation nice -n "${NICE}" rclone copy \
                    "${work}/" \
                    "${output}/" \
                    --config "${run_path}/rclone.conf" \
                    --log-level WARNING \
                    --log-file "${logs_transfers}/${STAMP}.${job}.rclone.output.log" \
                    --include "${outglob}" \
                    --transfers "${OUTBOUND_TRANSFERS}" ||\
                report $NETWORK_ERROR "save results"
        else
            nice -n "${NICE}" rclone copy \
                    "${work}/" \
                    "${output}/" \
                    --config "${run_path}/rclone.conf" \
                    --log-level WARNING \
                    --log-file "${logs_transfers}/${STAMP}.${job}.rclone.output.log" \
                    --include "${outglob}" \
                    --transfers "${OUTBOUND_TRANSFERS}" ||\
                report $NETWORK_ERROR "save results"
        fi
    fi
    return 0
}

# poll_outputs: Continuously encrypt and upload outputs while job runs
# 
# Monitors a running process and periodically encrypts and uploads any
# new output files. Useful for long-running jobs to save intermediate
# results. Continues until monitored process terminates.
# 
# Usage: poll_outputs monitor_pid wait_seconds
# Args:
#   $1 - Process ID to monitor (loop continues while this runs)
#   $2 - Seconds to wait between upload cycles
# Globals:
#   encrypt_flag - "yes" if outputs should be encrypted
# Returns: 0 when monitored process terminates
function poll_outputs {

    local po_pid_monitor=$1
    local po_wait=$2
    not_empty "$po_pid_monitor" "PID to monitor in loop condition"
    not_empty "$po_wait" "time between checks for outputs"

    while kill -0 "$po_pid_monitor" 2> /dev/null; do

        sleep "${po_wait}"

        # Encrypt the results
        if [ "${encrypt_flag}" == "yes" ]; then
            log_message "calling encrypt_outputs"
            encrypt_outputs
        fi

        # Save the results to the output destination
        send_outputs

    done
}