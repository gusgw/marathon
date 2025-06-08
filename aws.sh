# spot_interruption_found: Check for AWS EC2 spot instance termination notice
# 
# Queries EC2 instance metadata to detect if a spot interruption notice has been
# posted. AWS provides a 2-minute warning before terminating spot instances.
# Uses IMDSv2 (Instance Metadata Service Version 2) for secure metadata access.
# 
# Usage: spot_interruption_found "/path/to/metadata.log"
# Args:
#   $1 - Path to file where EC2 metadata should be saved
# Returns: 
#   0 if no interruption notice found (including if not on EC2)
#   Non-zero if interruption notice is detected
# Reference: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-instance-termination-notices.html
function spot_interruption_found {
    local ec2_metadata_save=$1
    log_setting "file to save metadata" "$ec2_metadata_save"
    ec2-metadata 2> /dev/null 1> "$ec2_metadata_save" ||\
            report $? "checking for ec2 metadata"
    rc=$?
    if [ "$rc" -eq 0 ]; then
        TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" \
                    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" \
                    --connect-timeout 2 --max-time 5` &&\
            curl -H "X-aws-ec2-metadata-token: $TOKEN" \
                --connect-timeout 2 --max-time 5 \
                http://169.254.169.254/latest/meta-data/spot/instance-action |\
            grep -qs "404 - Not Found"
        return $?
    else
        # If the ec2-metadata command failed,
        # we should not report a spot interruption with
        # a non-zero code.
        return 0
    fi
}

# poll_spot_interruption: Continuously monitor for EC2 spot instance termination
# 
# Runs in a loop checking for spot interruption notices while a monitored process
# is active. If an interruption is detected, reports the event and triggers
# cleanup with SHUTDOWN_SIGNAL exit code. This allows graceful shutdown before
# AWS forcibly terminates the instance.
# 
# Usage: poll_spot_interruption pid wait_seconds
# Args:
#   $1 - Process ID to monitor (loop continues while this process runs)
#   $2 - Seconds to wait between interruption checks
# Returns: Does not return on interruption - calls report which triggers cleanup
function poll_spot_interruption {
    local psi_pid=$1
    local psi_wait=$2
    not_empty "$psi_pid" "PID running while interruption checks needed"
    not_empty "$psi_wait" "time between checks for an interruption notice"
    while kill -0 "$psi_pid" 2> /dev/null; do
        sleep "$psi_wait"
        spot_interruption_found "${logs}/${STAMP}.${job}.$$.metadata" ||\
                                report "${SHUTDOWN_SIGNAL}" \
                                "checking for interruption" \
                                "spot interruption detected"
    done
}
