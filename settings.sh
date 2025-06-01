export RULE="***"

export NICE=19

export work="${workspace}/${job}"
log_setting "workspace subfolder for this job" "${work}"
mkdir -p "${work}" || report $FILING_ERROR "create work folder for $job" "cannot continue without workspace"

export logs="${logspace}/${job}"
log_setting "log subfolder for this job" "${logs}"
mkdir -p "${logs}" || report $FILING_ERROR "create log folder for $job" "cannot continue without log directory"
mkdir -p "${logs}/status" || report $FILING_ERROR "create status folder for $job" "cannot continue without status directory"

export ramdisk="/dev/shm/${job}-$$"
log_setting "ramdisk space for this job" "${ramdisk}"
mkdir -p "${ramdisk}" || report $FILING_ERROR "setup ramdisk for $job" "cannot continue without ramdisk"

insize=$(nice -n "${NICE}" rclone --config "${run_path}/rclone.conf" lsl "${input}/" \
                                  --include "${inglob}*" |\
                                gawk '{sum+=$1} END {print sum;}')
log_setting "size of inputs" "${insize}"
worksize=$(echo ${insize}*${workfactor}+1 | bc -l | sed 's/\([0-9]*\)\..*$/\1/')
log_setting "size needed for workspace" "${worksize}"
