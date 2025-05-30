#!/bin/bash
# Suspend Linux system when load is low for a sustained period.
#
# Copyright 2025 林博仁(Buo-ren Lin) <buo.ren.lin@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# --- Configuration ---
# Threshold for 5-minute load average. If load goes below this, we start counting.
# Adjust based on your CPU cores. For example, if you have 8 cores, 1.0 or 2.0 might be 'low'.
LOAD_THRESHOLD=0.5

# Time (in seconds) between each load check.
CHECK_INTERVAL=30

# How many consecutive times must the load be below the threshold and other conditions met
# before suspending. This prevents accidental suspend during momentary dips.
CONSECUTIVE_CHECKS_REQUIRED=5

# Path to the log file.
LOG_FILE="/var/log/auto_suspend.log"

# Path to a file that, if it exists, will prevent the system from suspending.
# This is useful for manual override (e.g., during large downloads/compilations).
NO_SLEEP_FILE="/tmp/no_auto_suspend"

# --- Functions ---

# Function to log messages with a timestamp
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function to get the current 5-minute load average
get_load_average() {
    # /proc/loadavg contains three numbers: 1-min, 5-min, 15-min load averages
    # We want the second number (5-minute average)
    awk '{print $2}' /proc/loadavg
}

# Function to check if the system is currently active (users logged in, X session active)
is_system_active() {
    # Check for any active user sessions (local or SSH)
    # Exclude system users like 'reboot' or 'runlevel'
    if who | grep -v 'reboot' | grep -v 'runlevel' | grep -v 'LOGIN' | grep -q -v ' pts/0 ' ; then # 'pts/0' might be this script's own terminal
        log "Active users detected."
        return 0 # System is active
    fi

    # Check for active graphical sessions (Xorg processes or Wayland)
    if pgrep -x Xorg >/dev/null || pgrep -x gnome-shell >/dev/null || pgrep -x kwin_wayland >/dev/null; then
        log "Active graphical session detected."
        return 0 # System is active
    fi

    # Check for active logind sessions (more robust)
    if loginctl list-sessions --no-legend | awk '{print $1}' | while read -r session_id; do
        if loginctl show-session "$session_id" | grep -q "State=active"; then
            log "Active logind session detected (ID: $session_id)."
            return 0 # System is active
        fi
    done; then
        return 0 # System is active due to a logind session
    fi

    # Check for specific processes you might want to prevent sleep for (e.g., apt, rsync, backups)
    # Add more `pgrep` commands as needed
    if pgrep -x apt >/dev/null || pgrep -x rsync >/dev/null || pgrep -x borg >/dev/null; then
        log "Specific critical process (apt, rsync, borg) detected."
        return 0 # System is active
    fi

    # If no activity detected
    return 1 # System is NOT active
}

# Function to perform the suspend action
perform_suspend() {
    log "Initiating system suspend..."
    # You need root privileges for this.
    # systemctl is the modern way. pm-suspend is older.
    # echo mem > /sys/power/state is low-level.
    systemctl suspend
    # This point is reached *after* the system resumes from suspend
    log "System resumed from suspend. Resuming monitoring."
}

# --- Main Logic ---

log "Auto-suspend script started. PID: $$"
log "Configuration: Load Threshold=${LOAD_THRESHOLD}, Check Interval=${CHECK_INTERVAL}s, Consecutive Checks=${CONSECUTIVE_CHECKS_REQUIRED}"

# Initialize counter for consecutive low-load checks
low_load_count=0

while true; do
    # 1. Get current load average
    current_load=$(get_load_average)
    log "Current 5-min load average: $current_load"

    # 2. Check for manual override file
    if [ -f "$NO_SLEEP_FILE" ]; then
        log "Override file '$NO_SLEEP_FILE' found. Suspend prevented."
        low_load_count=0 # Reset count as we're intentionally not suspending
        sleep "$CHECK_INTERVAL"
        continue # Skip to next loop iteration
    fi

    # 3. Check if load is below threshold
    # Using 'bc -l' for floating point comparison
    if (( $(echo "$current_load < $LOAD_THRESHOLD" | bc -l) )); then
        # Load is low. Increment counter.
        low_load_count=$((low_load_count + 1))
        log "Load is low ($current_load < $LOAD_THRESHOLD). Low load count: $low_load_count/$CONSECUTIVE_CHECKS_REQUIRED"

        # 4. Check if consecutive low-load conditions are met
        if [ "$low_load_count" -ge "$CONSECUTIVE_CHECKS_REQUIRED" ]; then
            # 5. Perform final activity check before suspending
            if is_system_active; then
                log "System became active during low-load period. Resetting low load count."
                low_load_count=0 # Reset because activity was detected
            else
                # All conditions met: load is low consistently, no active users, no override.
                log "All conditions met: Load consistently low, system inactive."
                perform_suspend
                # After suspend and resume, reset the count to prevent immediate re-suspend
                low_load_count=0
            fi
        fi
    else
        # Load is NOT low. Reset the counter if it was accumulating.
        if [ "$low_load_count" -gt 0 ]; then
            log "Load is no longer low ($current_load >= $LOAD_THRESHOLD). Resetting low load count."
            low_load_count=0
        else
            log "Load is high ($current_load >= $LOAD_THRESHOLD). Not accumulating."
        fi
    fi

    # Wait for the next check interval
    sleep "$CHECK_INTERVAL"
done
