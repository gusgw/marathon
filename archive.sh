#!/bin/bash
# archive.sh: Log rotation and archiving utilities for marathon
#
# Provides functions to manage log retention, compress old logs,
# and move completed jobs to archive directories.

# archive_old_logs: Move and compress logs older than specified days
#
# Finds log files older than the retention period and moves them
# to the archive directory with compression. Maintains directory
# structure in the archive.
#
# Usage: archive_old_logs days_to_keep
# Args:
#   $1 - Number of days to keep logs in active directories
# Globals:
#   logspace - Base log directory
#   workspace - Base work directory
# Returns: 0 on success
function archive_old_logs {
    local days_to_keep=${1:-7}
    local archive_base="${logspace}/archive"
    
    # Create archive directory structure
    mkdir -p "${archive_base}"
    
    # Archive old job logs
    if [[ -d "${logspace}/jobs" ]]; then
        find "${logspace}/jobs" -type d -name "test*" -mtime +${days_to_keep} | while read -r job_dir; do
            local job_name=$(basename "${job_dir}")
            local year=$(date -r "${job_dir}" +%Y)
            local month=$(date -r "${job_dir}" +%m)
            local archive_path="${archive_base}/${year}/${month}/jobs"
            
            mkdir -p "${archive_path}"
            echo "Archiving ${job_dir} to ${archive_path}/"
            
            # Create compressed archive
            tar -czf "${archive_path}/${job_name}.tar.gz" -C "${logspace}/jobs" "${job_name}/" && \
                rm -rf "${job_dir}"
        done
    fi
    
    # Archive old system metrics (compress by day)
    if [[ -d "${logspace}/system" ]]; then
        find "${logspace}/system" -type d -name "[0-9][0-9]" -mtime +${days_to_keep} | while read -r day_dir; do
            local rel_path=$(realpath --relative-to="${logspace}/system" "${day_dir}")
            local archive_path="${archive_base}/system/$(dirname "${rel_path}")"
            local day_name=$(basename "${day_dir}")
            
            mkdir -p "${archive_path}"
            echo "Compressing system metrics ${day_dir}"
            
            # Compress the day's metrics
            tar -czf "${archive_path}/${day_name}.tar.gz" -C "${day_dir}" . && \
                rm -rf "${day_dir}"
        done
    fi
    
    # Archive old transfer logs
    if [[ -d "${logspace}/transfers" ]]; then
        find "${logspace}/transfers" -type d -name "[0-9][0-9]" -mtime +${days_to_keep} | while read -r day_dir; do
            local rel_path=$(realpath --relative-to="${logspace}/transfers" "${day_dir}")
            local archive_path="${archive_base}/transfers/$(dirname "${rel_path}")"
            local day_name=$(basename "${day_dir}")
            
            mkdir -p "${archive_path}"
            echo "Compressing transfer logs ${day_dir}"
            
            # Compress the day's logs
            tar -czf "${archive_path}/${day_name}.tar.gz" -C "${day_dir}" . && \
                rm -rf "${day_dir}"
        done
    fi
    
    return 0
}

# clean_old_archives: Remove archives older than specified days
#
# Removes archived logs that exceed the maximum retention period.
# Use with caution as this permanently deletes data.
#
# Usage: clean_old_archives max_days
# Args:
#   $1 - Maximum days to keep archived logs
# Globals:
#   logspace - Base log directory
# Returns: 0 on success
function clean_old_archives {
    local max_days=${1:-90}
    local archive_base="${logspace}/archive"
    
    if [[ -d "${archive_base}" ]]; then
        echo "Removing archives older than ${max_days} days"
        find "${archive_base}" -name "*.tar.gz" -mtime +${max_days} -delete
        find "${archive_base}" -name "*.tar.xz" -mtime +${max_days} -delete
        
        # Remove empty directories
        find "${archive_base}" -type d -empty -delete
    fi
    
    return 0
}

# archive_completed_work: Move completed work directories to archive
#
# Moves work directories for completed jobs to an archive location
# to free up space in the active work area.
#
# Usage: archive_completed_work
# Globals:
#   workspace - Base work directory
#   reports_base - Reports directory containing job index
# Returns: 0 on success
function archive_completed_work {
    local work_archive="${workspace}/archive/${DATE_PATH}"
    local job_index="${reports_base}/job_index.txt"
    
    if [[ ! -f "${job_index}" ]]; then
        echo "No job index found, skipping work archival"
        return 0
    fi
    
    mkdir -p "${work_archive}"
    
    # Read completed jobs from index
    grep "|completed|" "${job_index}" | while IFS='|' read -r timestamp job_id job_name status hostname pid; do
        local work_dir="${workspace}/${job_name}"
        
        if [[ -d "${work_dir}" ]]; then
            # Check if work directory is old enough to archive (1 day)
            if [[ $(find "${work_dir}" -maxdepth 0 -mtime +1 | wc -l) -gt 0 ]]; then
                echo "Archiving completed work: ${work_dir}"
                mv "${work_dir}" "${work_archive}/" || echo "Failed to move ${work_dir}"
            fi
        fi
    done
    
    return 0
}

# generate_archive_report: Create a summary of archived data
#
# Generates a report showing the size and count of archived logs
# by category and date range.
#
# Usage: generate_archive_report
# Globals:
#   logspace - Base log directory
#   reports_base - Reports directory
# Returns: 0 on success
function generate_archive_report {
    local archive_base="${logspace}/archive"
    local report_file="${reports_base}/archive_summary_$(date +%Y%m%d).txt"
    
    echo "Archive Summary Report - $(date)" > "${report_file}"
    echo "======================================" >> "${report_file}"
    echo "" >> "${report_file}"
    
    if [[ -d "${archive_base}" ]]; then
        echo "Archive Contents:" >> "${report_file}"
        echo "" >> "${report_file}"
        
        # Summary by year/month
        for year_dir in "${archive_base}"/*; do
            if [[ -d "${year_dir}" ]] && [[ $(basename "${year_dir}") =~ ^[0-9]{4}$ ]]; then
                local year=$(basename "${year_dir}")
                echo "Year ${year}:" >> "${report_file}"
                
                for month_dir in "${year_dir}"/*; do
                    if [[ -d "${month_dir}" ]] && [[ $(basename "${month_dir}") =~ ^[0-9]{2}$ ]]; then
                        local month=$(basename "${month_dir}")
                        local size=$(du -sh "${month_dir}" 2>/dev/null | cut -f1)
                        local count=$(find "${month_dir}" -name "*.tar.*" | wc -l)
                        echo "  ${year}-${month}: ${count} archives, ${size}" >> "${report_file}"
                    fi
                done
            fi
        done
        
        echo "" >> "${report_file}"
        echo "Total Archive Size: $(du -sh "${archive_base}" | cut -f1)" >> "${report_file}"
    else
        echo "No archives found" >> "${report_file}"
    fi
    
    echo "Report saved to: ${report_file}"
    return 0
}

# Main execution if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Load configuration
    export run_path=$(dirname $(realpath $0))
    . ${run_path}/bump/bump.sh
    
    # Parse command line arguments
    case "${1:-help}" in
        rotate)
            days=${2:-7}
            echo "Rotating logs older than ${days} days"
            archive_old_logs ${days}
            ;;
        clean)
            days=${2:-90}
            echo "Cleaning archives older than ${days} days"
            clean_old_archives ${days}
            ;;
        work)
            echo "Archiving completed work directories"
            archive_completed_work
            ;;
        report)
            echo "Generating archive report"
            generate_archive_report
            ;;
        all)
            echo "Running full archive maintenance"
            archive_old_logs 7
            archive_completed_work
            clean_old_archives 90
            generate_archive_report
            ;;
        *)
            echo "Usage: $0 {rotate|clean|work|report|all} [days]"
            echo "  rotate [days] - Archive logs older than days (default: 7)"
            echo "  clean [days]  - Remove archives older than days (default: 90)"
            echo "  work          - Archive completed work directories"
            echo "  report        - Generate archive summary report"
            echo "  all           - Run all maintenance tasks"
            exit 1
            ;;
    esac
fi