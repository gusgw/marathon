export RULE="***"

export NICE=19

# Get date components for directory organization
export DATE_YEAR=$(date +%Y)
export DATE_MONTH=$(date +%m)
export DATE_DAY=$(date +%d)
export DATE_PATH="${DATE_YEAR}/${DATE_MONTH}/${DATE_DAY}"

export work="${workspace}/${job}"
log_setting "workspace subfolder for this job" "${work}"
mkdir -p "${work}" || report $FILING_ERROR "create work folder for $job" "cannot continue without workspace"

# Create organized log structure
export logs_base="${logspace}"
export logs="${logs_base}/jobs/${job}"
export logs_system="${logs_base}/system/${DATE_PATH}"
export logs_transfers="${logs_base}/transfers/${DATE_PATH}"

log_setting "job log folder" "${logs}"
log_setting "system metrics folder" "${logs_system}"
log_setting "transfer logs folder" "${logs_transfers}"

# Create all log directories
mkdir -p "${logs}" || report $FILING_ERROR "create log folder for $job" "cannot continue without log directory"
mkdir -p "${logs}/status" || report $FILING_ERROR "create status folder for $job" "cannot continue without status directory"
mkdir -p "${logs_system}" || report $FILING_ERROR "create system metrics folder" "cannot continue without system metrics directory"
mkdir -p "${logs_transfers}" || report $FILING_ERROR "create transfer logs folder" "cannot continue without transfer logs directory"

# Create reports directories
export reports_base="${logspace}/reports"
mkdir -p "${reports_base}/daily/${DATE_PATH}" || report $FILING_ERROR "create daily reports folder"
mkdir -p "${reports_base}/failures" || report $FILING_ERROR "create failures folder"
mkdir -p "${reports_base}/performance" || report $FILING_ERROR "create performance folder"

export ramdisk="/dev/shm/${job}-$$"
log_setting "ramdisk space for this job" "${ramdisk}"
mkdir -p "${ramdisk}" || report $FILING_ERROR "setup ramdisk for $job" "cannot continue without ramdisk"

insize=$(nice -n "${NICE}" rclone --config "${run_path}/rclone.conf" lsl "${input}/" \
                                  --include "${inglob}*" |\
                                gawk '{sum+=$1} END {print sum;}')
log_setting "size of inputs" "${insize}"
worksize=$(echo ${insize}*${workfactor}+1 | bc -l | sed 's/\([0-9]*\)\..*$/\1/')
log_setting "size needed for workspace" "${worksize}"
