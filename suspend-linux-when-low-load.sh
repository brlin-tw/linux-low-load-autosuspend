#!/bin/bash
# Suspend Linux system when load is low for a sustained period.
#
# Copyright 2025 林博仁(Buo-ren Lin) <buo.ren.lin@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Load threshold ratio (0.5 means half of physical cores are busy)
# This will be multiplied by the number of physical cores to get the actual threshold
LOAD_THRESHOLD_RATIO=0.5

# Time (in seconds) between each load check.
CHECK_INTERVAL=300 # 5 minutes

# How many consecutive times must the load be below the threshold and other conditions met
# before suspending. This prevents accidental suspend during momentary dips.
CONSECUTIVE_CHECKS_REQUIRED=3

# Path to the log file.
LOG_FILE="/var/log/auto_suspend.log"

# Function to get the number of physical CPU cores (not threads)
get_physical_cores() {
    # Get the number of unique physical processors and multiply by cores per processor
    local physical_cpus cores_per_processor

    if ! physical_cpus=$(grep -E "^physical id" /proc/cpuinfo | sort | uniq | wc -l); then
        log "Error: Failed to determine number of physical CPUs"
        return 1
    fi

    if ! cores_per_processor=$(grep -E "^cpu cores" /proc/cpuinfo | head -1 | awk '{print $4}'); then
        log "Error: Failed to determine cores per processor"
        return 1
    fi

    # Handle cases where the system might not report physical id (single CPU systems)
    if [ "${physical_cpus}" -eq 0 ]; then
        physical_cpus=1
    fi

    # Handle cases where cores per processor might be empty
    if [ -z "${cores_per_processor}" ]; then
        cores_per_processor=1
    fi

    echo $((physical_cpus * cores_per_processor))
}

# Function to log messages with a timestamp
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

# Function to get the current 5-minute load average
get_load_average() {
    # /proc/loadavg contains three numbers: 1-min, 5-min, 15-min load averages
    # We want the second number (5-minute average)
    if ! awk '{print $2}' /proc/loadavg; then
        log "Error reading load average from /proc/loadavg"
        return 1
    fi
}

# Function to perform the suspend action
perform_suspend() {
    log "Initiating system suspend..."
    # You need root privileges for this.
    # systemctl is the modern way. pm-suspend is older.
    # echo mem > /sys/power/state is low-level.
    if ! systemctl suspend; then
        log "Error: Failed to suspend the system using systemctl."
        return 1
    fi
    # This point is reached *after* the system resumes from suspend
    log "System resumed from suspend. Resuming monitoring."
}

log "Auto-suspend script started. PID: $$"

# Determine physical CPU cores and calculate actual load threshold
if ! PHYSICAL_CORES=$(get_physical_cores); then
    log "Error: Failed to determine physical CPU cores"
    exit 1
fi

LOAD_THRESHOLD=$(echo "${LOAD_THRESHOLD_RATIO} * ${PHYSICAL_CORES}" | bc -l)

log "System has ${PHYSICAL_CORES} physical CPU cores"
log "Configuration: Load Threshold Ratio=${LOAD_THRESHOLD_RATIO}, Actual Threshold=${LOAD_THRESHOLD}, Check Interval=${CHECK_INTERVAL}s, Consecutive Checks=${CONSECUTIVE_CHECKS_REQUIRED}"

# Initialize counter for consecutive low-load checks
low_load_count=0

while true; do
    if ! current_load=$(get_load_average); then
        log "Failed to determine load average."
        exit 1
    fi
    log "Current 5-min load average: ${current_load}"

    if (( $(echo "${current_load} < ${LOAD_THRESHOLD}" | bc -l) )); then
        # Load is low. Increment counter.
        low_load_count=$((low_load_count + 1))
        log "Load is low (${current_load} < ${LOAD_THRESHOLD}). Low load count: ${low_load_count}/${CONSECUTIVE_CHECKS_REQUIRED}"

        if [ "${low_load_count}" -ge "${CONSECUTIVE_CHECKS_REQUIRED}" ]; then
            # All conditions met: load is low consistently, no active users, no override.
            log "All conditions met: Load consistently low, system inactive."
            if ! perform_suspend; then
                log "Error: Failed to perform suspend."
                exit 1
            fi
            # After suspend and resume, reset the count to prevent immediate re-suspend
            low_load_count=0
        fi
    else
        # Load is NOT low. Reset the counter if it was accumulating.
        if [ "${low_load_count}" -gt 0 ]; then
            log "Load is no longer low (${current_load} >= ${LOAD_THRESHOLD}). Resetting low load count."
            low_load_count=0
        else
            log "Load is high (${current_load} >= ${LOAD_THRESHOLD}). Not accumulating."
        fi
    fi

    if ! sleep "${CHECK_INTERVAL}"; then
        log "Error: Failed to sleep periodically during check."
        exit 1
    fi
done
