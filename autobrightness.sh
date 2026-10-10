#!/usr/bin/env bash
# Maintain the selected AMD backlight at TARGET_PERCENT.
#
# Design:
#   - Polling loop; no reliance on sysfs inotify.
#   - Persistent flock; never unlink the lock file.
#   - Refresh and validate max_brightness on every iteration.
#   - Rate-limited error logging; suppressed count flushed once on exit.
#   - Exit on missing sysfs files; systemd supervises recovery.
#   - Device discovery occurs once per process start.

set -uo pipefail

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"

readonly TARGET_PERCENT=90
readonly POLL_INTERVAL=2
readonly ERROR_LOG_INTERVAL=60

readonly STATE_DIR="${XDG_RUNTIME_DIR:-$HOME/.cache}"
readonly LOCK_FILE="$STATE_DIR/autobrightness.lock"
readonly LOG_FILE="$HOME/scriptlogs/autobrightness.log"

# ---------- directories ----------
if ! mkdir -p "$STATE_DIR" "$(dirname "$LOG_FILE")"; then
    printf 'FATAL: cannot create state or log directory\n' >&2
    exit 1
fi

# ---------- logging ----------
LAST_ERR_TS=0
ERR_SUPPRESS=0

flush_suppress() {
    if (( ERR_SUPPRESS > 0 )); then
        printf '%s Suppressed %d repeated error message(s).\n' \
            "$(date '+%F %T')" "$ERR_SUPPRESS" >> "$LOG_FILE"
        ERR_SUPPRESS=0
    fi
}

# EXIT runs on every exit path, including after the INT and TERM
# handlers below call exit. That gives exactly one flush, once.
# INT and TERM only translate the signal into the conventional exit
# status so the EXIT trap and systemd see the right code.
trap 'flush_suppress' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

log() {
    flush_suppress
    printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG_FILE"
}

log_err() {
    local now
    now=$(date +%s) || return 1

    if (( LAST_ERR_TS == 0 ||
          now - LAST_ERR_TS >= ERROR_LOG_INTERVAL )); then
        flush_suppress
        printf '%s ERROR: %s\n' \
            "$(date '+%F %T')" "$*" >> "$LOG_FILE"
        LAST_ERR_TS=$now
    else
        ERR_SUPPRESS=$((ERR_SUPPRESS + 1))
    fi
}

# ---------- configuration validation ----------
if [[ ! "$TARGET_PERCENT" =~ ^[0-9]+$ ]] ||
   (( TARGET_PERCENT < 0 || TARGET_PERCENT > 100 )); then
    log "FATAL: TARGET_PERCENT must be an integer from 0 to 100."
    exit 1
fi

if [[ ! "$POLL_INTERVAL" =~ ^[0-9]+$ ]] ||
   (( POLL_INTERVAL < 1 )); then
    log "FATAL: POLL_INTERVAL must be a positive integer."
    exit 1
fi

# ---------- dependencies ----------
for cmd in brightnessctl flock; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log "FATAL: required command not found: $cmd"
        exit 1
    fi
done

# ---------- single-instance lock ----------
# Keep the lock file permanently. Closing fd 9 releases the lock.
# Never unlink the path: that would allow a second instance to create
# a new inode and lock that instead.
if ! exec 9>"$LOCK_FILE"; then
    log "FATAL: cannot open lock file: $LOCK_FILE"
    exit 1
fi

if ! flock -n 9; then
    log "Another instance is already running; exiting."
    exit 1
fi

# ---------- device discovery ----------
DEVICE=""

for d in /sys/class/backlight/amdgpu_bl[0-9]*; do
    [[ -d "$d" ]] || continue

    name="${d##*/}"
    [[ "$name" =~ ^amdgpu_bl[0-9]+$ ]] || continue

    DEVICE="$name"
    break
done

if [[ -z "$DEVICE" ]]; then
    log "FATAL: no AMD backlight device found."
    exit 1
fi

readonly SYSFS_DIR="/sys/class/backlight/$DEVICE"
readonly BRIGHTNESS_FILE="$SYSFS_DIR/brightness"
readonly MAX_FILE="$SYSFS_DIR/max_brightness"

if [[ ! -r "$BRIGHTNESS_FILE" || ! -r "$MAX_FILE" ]]; then
    log "FATAL: backlight sysfs files are unavailable for $DEVICE."
    exit 1
fi

log "Started: device=$DEVICE target=${TARGET_PERCENT}% interval=${POLL_INTERVAL}s"

# ---------- brightness correction ----------
check_and_correct() {
    local max cur pct

    # Exit so systemd (or a wrapper supervisor) can restart and rediscover.
    if [[ ! -r "$BRIGHTNESS_FILE" || ! -r "$MAX_FILE" ]]; then
        log_err "Backlight sysfs files disappeared for $DEVICE."
        exit 1
    fi

    # Refresh maximum brightness on every pass.
    if ! max=$(<"$MAX_FILE"); then
        log_err "Cannot read max_brightness for $DEVICE."
        exit 1
    fi

    if [[ ! "$max" =~ ^[0-9]+$ ]] || (( max <= 0 )); then
        log_err "Invalid max_brightness='$max' for $DEVICE."
        exit 1
    fi

    if ! cur=$(brightnessctl -d "$DEVICE" get 2>/dev/null); then
        log_err "brightnessctl get failed for $DEVICE."
        return 1
    fi

    if [[ ! "$cur" =~ ^[0-9]+$ ]] || (( cur > max )); then
        log_err "Invalid brightness='$cur' or inconsistent maximum='$max'."
        return 1
    fi

    # Compare rounded percentage to avoid repeated corrections caused by
    # integer rounding when the hardware cannot represent 90% exactly.
    pct=$(( (cur * 100 + max / 2) / max ))

    if (( pct != TARGET_PERCENT )); then
        if ! brightnessctl -d "$DEVICE" set "${TARGET_PERCENT}%" \
                >/dev/null 2>&1; then
            log_err "brightnessctl set failed for $DEVICE."
            return 1
        fi

        log "Corrected ${pct}% -> ${TARGET_PERCENT}% (raw=$cur max=$max)"
    fi

    return 0
}

# Initial correction, followed by periodic checks.
check_and_correct || true

while true; do
    sleep "$POLL_INTERVAL"
    check_and_correct || true
done
