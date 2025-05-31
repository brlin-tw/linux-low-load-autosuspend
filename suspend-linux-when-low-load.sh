#!/bin/bash
# Suspend Linux system when load is low for a sustained period.
#
# Copyright 2025 林博仁(Buo-ren Lin) <buo.ren.lin@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

LOAD_THRESHOLD_RATIO="${LOAD_THRESHOLD_RATIO:-0.5}"
CHECK_INTERVAL="${CHECK_INTERVAL:-300}" # 5 minutes
CONSECUTIVE_CHECKS_REQUIRED="${CONSECUTIVE_CHECKS_REQUIRED:-3}"

# Path to the log file.
LOG_FILE="/var/log/auto_suspend.log"

set_opts=(
    # Exit on unhandled errors
    -o errexit
    -o errtrace

    # Treat unset variables as an error
    -o nounset
)
if ! set "${set_opts[@]}"; then
    printf 'Error: Failed to set shell options.\n' >&2
    exit 1
fi

if ! trap 'printf "Error: Unhandled error occurred.\\n"; exit 99' ERR; then
    printf 'Error: Failed to set ERR trap.\n' >&2
    exit 1
fi

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
    if test "${physical_cpus}" -eq 0; then
        physical_cpus=1
    fi

    # Handle cases where cores per processor might be empty
    if test -z "${cores_per_processor}"; then
        cores_per_processor=1
    fi

    echo $((physical_cpus * cores_per_processor))
}

# Function to log messages with a timestamp
log() {
    message="${1}"; shift

    local potential_message_tag="${message%:*}"
    local flag_msg_to_stderr=false
    case "${potential_message_tag^^}" in
        "ERROR"|"WARNING")
            flag_msg_to_stderr=true
            ;;
        *)
            :
            ;;
    esac

    local timestamp
    if ! timestamp="$(printf '%(%Y-%m-%d %H:%M:%S)T' -1)"; then
        printf 'Error: Failed to generate timestamp.\n' 1>&2
        return 1
    fi

    local log_entry
    log_entry="${timestamp} - ${message}"

    if test "${flag_msg_to_stderr}" == true; then
        printf '%s\n' "${log_entry}" | tee -a "${LOG_FILE}" 1>&2
    else
        printf '%s\n' "${log_entry}" | tee -a "${LOG_FILE}"
    fi
    return 0
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

required_commands=(
    awk
    bc
    grep
    head
    sort
    systemctl
    tee
    uniq
    wc
)
for command in "${required_commands[@]}"; do
    if ! command -v "${command}" &>/dev/null; then
        log "Error: Required command \"${command}\" is not available."
        exit 1
    fi
done

readonly regex_positive_floating_point_number='^[0-9]+(\.[0-9]+)?$'
if [[ ! "${LOAD_THRESHOLD_RATIO}" =~ ${regex_positive_floating_point_number} ]]; then
    log "Error: LOAD_THRESHOLD_RATIO must be a positive floating-point number."
    exit 1
fi

readonly regex_natural_number='^[1-9]+[0-9]*$'
if [[ ! "${CHECK_INTERVAL}" =~ ${regex_natural_number} ]]; then
    log "Error: CHECK_INTERVAL must be a natural number (positive integer)."
    exit 1
fi

if test "${CHECK_INTERVAL}" -lt 10; then
    log "Error: CHECK_INTERVAL must be at least 10 seconds."
    exit 1
fi

if [[ ! "${CONSECUTIVE_CHECKS_REQUIRED}" =~ ${regex_natural_number} ]]; then
    log "Error: CONSECUTIVE_CHECKS_REQUIRED must be a natural number (positive integer)."
    exit 1
fi

if test "${CONSECUTIVE_CHECKS_REQUIRED}" -lt 1; then
    log "Error: CONSECUTIVE_CHECKS_REQUIRED must be at least 1."
    exit 1
fi

if test "${EUID}" -ne 0; then
    printf 'Error: This script must be run as root.\n' 1>&2
    exit 1
fi

log "Info: Auto-suspend script started. PID: $$"

# Determine physical CPU cores and calculate actual load threshold
if ! physical_cores=$(get_physical_cores); then
    log "Error: Failed to determine physical CPU cores"
    exit 1
fi

load_threshold=$(echo "${LOAD_THRESHOLD_RATIO} * ${physical_cores}" | bc -l)

# Ensure leading zero for numbers less than 1
readonly regex_floating_point_numbers_less_than_one='^\.[0-9]+$'
if [[ "${load_threshold}" =~ ${regex_floating_point_numbers_less_than_one} ]]; then
    load_threshold="0${load_threshold}"
fi

log "Info: System has ${physical_cores} physical CPU cores"
log "Info: Configuration: Load Threshold Ratio=${LOAD_THRESHOLD_RATIO}, Actual Threshold=${load_threshold}, Check Interval=${CHECK_INTERVAL}s, Consecutive Checks=${CONSECUTIVE_CHECKS_REQUIRED}"

# Initialize counter for consecutive low-load checks
low_load_count=0

while true; do
    if ! current_load=$(get_load_average); then
        log "Error: Failed to determine load average."
        exit 1
    fi
    log "Info: Current 5-min load average: ${current_load}"

    if (( $(echo "${current_load} < ${load_threshold}" | bc -l) )); then
        low_load_count=$((low_load_count + 1))
        log "Info: Load is low (${current_load} < ${load_threshold}). Low load count: ${low_load_count}/${CONSECUTIVE_CHECKS_REQUIRED}"

        if test "${low_load_count}" -ge "${CONSECUTIVE_CHECKS_REQUIRED}"; then
            log "Info: All conditions met: Load consistently low, system inactive."
            if ! perform_suspend; then
                log "Error: Failed to perform suspend."
                exit 1
            fi
            break
        fi
    else
        # Load is NOT low. Reset the counter if it was accumulating.
        if test "${low_load_count}" -gt 0; then
            log "Info: Load is no longer low (${current_load} >= ${load_threshold}). Resetting low load count."
            low_load_count=0
        else
            log "Info: Load is high (${current_load} >= ${load_threshold}). Not accumulating."
        fi
    fi

    if ! sleep "${CHECK_INTERVAL}"; then
        log "Error: Failed to sleep periodically during check."
        exit 1
    fi
done

log "Info: Operation completed without errors."
exit 0
