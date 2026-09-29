#!/usr/bin/env bash
# ============================================================
# lid-wake-wallpaper.sh  (v3)
#
# Supervisor for random_wallpaper.sh:
#   - Single-instance guarded (flock)
#   - Serialized restarts (flock)
#   - Waits for the old wallpaper script to die before relaunch
#   - Watchdog based on log growth (size + mtime) AND liveness
#   - Debounce/grace state shared via a state file so it survives
#     subshell boundaries
#   - Correct pgrep/pkill patterns for "bash <script>" process
#   - Logs which signal killed it and from which parent
#   - Log rotation
#
# Effective stuck detection:
#   STUCK_THRESHOLD * CHECK_INTERVAL ≈ 5 minutes of silence
#   before the watchdog forces a restart.
# ============================================================
set -uo pipefail

# ------------------------------------------------------------
# CONFIG
# ------------------------------------------------------------
WALLPAPER_SCRIPT="$HOME/Documents/bin/random_wallpaper.sh"
WALLPAPER_LOG="$HOME/scriptlogs/wallpaper.log"
WALLPAPER_STDOUT="$HOME/scriptlogs/wallpaper-stdout.log"

CACHE_DIR="$HOME/.cache"
SUPERVISOR_LOCK="$CACHE_DIR/lid-wake-wallpaper.lock"
RESTART_LOCK="$CACHE_DIR/lid-wake-wallpaper-restart.lock"
STATE_FILE="$CACHE_DIR/lid-wake-wallpaper.state"
WALLPAPER_LOCK="$CACHE_DIR/random_wallpaper.lock"

LOG="$HOME/scriptlogs/lid-wake.log"
LOG_MAX_SIZE=5242880          # 5 MB

CHECK_INTERVAL=60             # seconds between watchdog checks
STUCK_THRESHOLD=5             # consecutive stalled checks => restart
GRACE_AFTER_RESTART=90        # grace period after any restart
RESUME_DEBOUNCE=60            # ignore duplicate resumes within N s
KILL_WAIT_MAX=90              # max seconds to wait for wallpaper to die
RESTART_LOCK_WAIT=180         # max seconds to wait for restart lock

SETTLE_SLEEP=2                # pause after acquiring restart lock
RELAUNCH_VERIFY_SLEEP=3       # pause before verifying relaunch
WATCHDOG_STARTUP_SLEEP=10     # initial delay before watchdog begins

mkdir -p "$(dirname "$LOG")" "$(dirname "$WALLPAPER_LOG")" "$CACHE_DIR"

# ------------------------------------------------------------
# LOGGING
# ------------------------------------------------------------
log() {
    printf '%s - [supervisor %d] %s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$$" "$*" >> "$LOG"
}

rotate_log() {
    [ -f "$LOG" ] || return 0
    local sz
    sz=$(stat -c%s "$LOG" 2>/dev/null \
         || stat -f%z "$LOG" 2>/dev/null \
         || echo 0)
    if [ "${sz:-0}" -gt "$LOG_MAX_SIZE" ]; then
        mv "$LOG" "$LOG.$(date +%Y%m%d_%H%M%S)"
        log "Log rotated (was ${sz} bytes)"
    fi
}

# ------------------------------------------------------------
# SINGLE-INSTANCE GUARD
# ------------------------------------------------------------
exec 9>"$SUPERVISOR_LOCK"
if ! flock -n 9; then
    echo "$(date) - lid-wake-wallpaper.sh already running; exiting." >> "$LOG"
    exit 1
fi
log "Supervisor lock acquired"

# Restart lock (used to serialize restart_wallpaper calls)
exec 8>"$RESTART_LOCK"

# ------------------------------------------------------------
# HOUSEKEEPING
# ------------------------------------------------------------
# Remove orphan temp files from a previous run that was killed
# between `printf > tmp` and `mv`.
find "$CACHE_DIR" -maxdepth 1 -name "$(basename "$STATE_FILE").tmp.*" \
    -mtime +1 -delete 2>/dev/null || true

# ------------------------------------------------------------
# SHARED STATE (survives subshells)
# ------------------------------------------------------------
read_state() {
    LAST_RESUME=0
    LAST_RESTART=0
    if [ -f "$STATE_FILE" ]; then
        local key val
        while IFS='=' read -r key val; do
            case "$key" in
                LAST_RESUME)  LAST_RESUME=${val:-0} ;;
                LAST_RESTART) LAST_RESTART=${val:-0} ;;
            esac
        done < "$STATE_FILE"
    fi
    LAST_RESUME=${LAST_RESUME:-0}
    LAST_RESTART=${LAST_RESTART:-0}
}

write_state() {
    local tmp="$STATE_FILE.tmp.$$"
    umask 077
    if printf 'LAST_RESUME=%d\nLAST_RESTART=%d\n' \
            "$LAST_RESUME" "$LAST_RESTART" > "$tmp"; then
        mv -f "$tmp" "$STATE_FILE"
    else
        rm -f "$tmp"
    fi
    umask 022
}

# ------------------------------------------------------------
# PROCESS HELPERS
# ------------------------------------------------------------
# Match "bash /path/random_wallpaper.sh" or "/path/random_wallpaper.sh",
# but not other processes that merely mention the path in their cmdline
# (e.g. an editor, grep, this supervisor itself).
WALLPAPER_PGREP_PATTERN="^(bash|sh|/bin/bash|/usr/bin/bash)?[[:space:]]*${WALLPAPER_SCRIPT}(\$|[[:space:]])"

wallpaper_pids() {
    pgrep -f -- "$WALLPAPER_PGREP_PATTERN" 2>/dev/null || true
}

wallpaper_running() {
    [ -n "$(wallpaper_pids)" ]
}

wait_for_wallpaper_death() {
    local max="$1" i=0
    while [ "$i" -lt "$max" ]; do
        wallpaper_running || return 0
        sleep 1
        i=$((i + 1))
    done
    return 1
}

# ------------------------------------------------------------
# RESTART
# ------------------------------------------------------------
# NOTE: every return path after `flock -w … 8` must call
# `flock -u 8` before returning. The lock is also released if
# this process exits, so the worst case of a missed unlock is a
# delayed next restart, never a deadlock.
restart_wallpaper() {
    local reason="${1:-manual}"
    local now
    now=$(date +%s)

    if ! flock -w "$RESTART_LOCK_WAIT" 8; then
        log "restart_wallpaper: could not acquire restart lock ($reason); skipping"
        return 1
    fi

    read_state

    if [ "$reason" = "resume" ] \
       && [ $((now - LAST_RESUME)) -lt "$RESUME_DEBOUNCE" ]; then
        log "Ignoring duplicate resume (debounce ${RESUME_DEBOUNCE}s)"
        flock -u 8
        return 0
    fi

    [ "$reason" = "resume" ] && LAST_RESUME=$now
    LAST_RESTART=$now
    write_state

    log "Restart requested (reason: $reason)"
    sleep "$SETTLE_SLEEP"

    # ---- Kill existing instance(s) -------------------------
    local pids
    pids=$(wallpaper_pids)
    if [ -n "$pids" ]; then
        log "Sending SIGTERM to wallpaper PIDs: $(echo "$pids" | tr '\n' ' ')"
        # shellcheck disable=SC2086
        kill -TERM $pids 2>/dev/null || true

        if ! wait_for_wallpaper_death "$KILL_WAIT_MAX"; then
            log "Wallpaper did not exit within ${KILL_WAIT_MAX}s; SIGKILL"
            pids=$(wallpaper_pids)
            if [ -n "$pids" ]; then
                # shellcheck disable=SC2086
                kill -KILL $pids 2>/dev/null || true
            fi
            sleep 2
        fi
        log "Wallpaper script is down"
    else
        log "No running random_wallpaper.sh instance found"
    fi

    # ---- Kill orphan helpers -------------------------------
    pkill -f "deviousq"         2>/dev/null && log "Killed orphan deviousq"
    pkill -f "wget.*wallpaper_" 2>/dev/null && log "Killed orphan wget"
    pkill -x "variety"          2>/dev/null && log "Killed stuck Variety"

    # ---- Stale wallpaper lock ------------------------------
    # Never delete a lock that is still held: rm on the path
    # would let a second instance create a fresh inode and lock.
    if [ -e "$WALLPAPER_LOCK" ]; then
        exec 7>>"$WALLPAPER_LOCK"
        if flock -n 7; then
            flock -u 7
            exec 7>&-
            log "Stale wallpaper lock (no holder) — removing"
            rm -f "$WALLPAPER_LOCK"
        else
            exec 7>&-
            log "WARNING: wallpaper lock still held; leaving it alone"
        fi
    fi

    # ---- Sanity check --------------------------------------
    if [ ! -x "$WALLPAPER_SCRIPT" ]; then
        log "ERROR: $WALLPAPER_SCRIPT is not executable"
        flock -u 8
        return 1
    fi

    # ---- Relaunch, with failure detection ------------------
    if ! nohup "$WALLPAPER_SCRIPT" \
            >> "$WALLPAPER_STDOUT" 2>&1 \
            < /dev/null &
    then
        log "ERROR: failed to launch $WALLPAPER_SCRIPT"
        flock -u 8
        return 1
    fi
    local new_pid=$!
    disown 2>/dev/null || true
    log "Relaunched random_wallpaper.sh (PID $new_pid)"

    sleep "$RELAUNCH_VERIFY_SLEEP"
    if wallpaper_running; then
        log "Verified: random_wallpaper.sh is running"
    else
        log "WARNING: random_wallpaper.sh not detected after relaunch"
    fi

    flock -u 8
    return 0
}

# ------------------------------------------------------------
# WATCHDOG
# ------------------------------------------------------------
# Two independent triggers:
#   1. Log has not grown in STUCK_THRESHOLD * CHECK_INTERVAL s
#   2. The wallpaper process is simply gone
watchdog_loop() {
    sleep "$WATCHDOG_STARTUP_SLEEP"

    local last_size=""
    local last_mtime=""
    local stalled=0

    while true; do
        sleep "$CHECK_INTERVAL"
        rotate_log

        read_state
        local since_restart=$(( $(date +%s) - LAST_RESTART ))
        if [ "$since_restart" -lt "$GRACE_AFTER_RESTART" ]; then
            last_size=""
            last_mtime=""
            stalled=0
            continue
        fi

        # ---- Trigger 2: process missing --------------------
        if ! wallpaper_running; then
            log "WATCHDOG: random_wallpaper.sh is not running"
            restart_wallpaper "watchdog-not-running"
            last_size=""
            last_mtime=""
            stalled=0
            continue
        fi

        # ---- Trigger 1: log growth -------------------------
        [ -f "$WALLPAPER_LOG" ] || continue

        local cur_size cur_mtime
        cur_size=$(stat -c%s "$WALLPAPER_LOG" 2>/dev/null \
                   || stat -f%z "$WALLPAPER_LOG" 2>/dev/null || echo 0)
        cur_mtime=$(stat -c%Y "$WALLPAPER_LOG" 2>/dev/null \
                   || stat -f%m "$WALLPAPER_LOG" 2>/dev/null || echo 0)

        if [ "$cur_size" = "$last_size" ] && [ "$cur_mtime" = "$last_mtime" ]; then
            stalled=$((stalled + 1))
            log "Watchdog: wallpaper.log unchanged for ${stalled}/${STUCK_THRESHOLD} checks"
        else
            last_size="$cur_size"
            last_mtime="$cur_mtime"
            stalled=0
        fi

        if [ "$stalled" -ge "$STUCK_THRESHOLD" ]; then
            log "WATCHDOG: wallpaper.log has not grown for ~$((stalled * CHECK_INTERVAL))s"
            restart_wallpaper "watchdog-stuck-log"
            last_size=""
            last_mtime=""
            stalled=0
        fi
    done
}

# ------------------------------------------------------------
# CLEANUP
# ------------------------------------------------------------
on_exit() {
    local ec=$?
    trap - INT TERM HUP EXIT
    log "Shutting down (exit=$ec)"

    if [ -n "${WATCHDOG_PID:-}" ]; then
        kill "$WATCHDOG_PID" 2>/dev/null || true
        wait "$WATCHDOG_PID" 2>/dev/null || true
    fi

    # Locks release automatically on FD close, but be explicit.
    flock -u 8 2>/dev/null || true
    flock -u 9 2>/dev/null || true

    exit "$ec"
}

trap on_exit EXIT

# Log the source of termination for diagnostics.
trap 'log "Received SIGTERM (ppid=$PPID)"; exit 143' TERM
trap 'log "Received SIGHUP  (ppid=$PPID)"; exit 129' HUP
trap 'log "Received SIGINT  (ppid=$PPID)"; exit 130' INT

# ------------------------------------------------------------
# MAIN
# ------------------------------------------------------------
log "lid-wake-wallpaper.sh started (PID $$, PPID $PPID)"

if ! wallpaper_running; then
    log "Wallpaper script not running at supervisor start — starting it"
    restart_wallpaper "initial-start"
fi

watchdog_loop 
WATCHDOG_PID=$!
log "Watchdog started (PID $WATCHDOG_PID, interval=${CHECK_INTERVAL}s, threshold=${STUCK_THRESHOLD})"

# ------------------------------------------------------------
# Monitor PrepareForSleep via dbus-monitor.
#
# Process substitution keeps this while-loop in the current
# shell (unlike `cmd | while …`, which runs it in a subshell
# unless `shopt -s lastpipe` is set and job control is off).
# That means the state written inside the loop is visible to
# the rest of the script via the shared state file and the
# restart lock, regardless of the shell's job-control setting.
# ------------------------------------------------------------
while IFS= read -r line; do
    if [[ "$line" == *"boolean false"* ]]; then
        restart_wallpaper "resume"
    fi
done < <(stdbuf -oL dbus-monitor --system \
            "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'" \
            2>/dev/null)

log "dbus-monitor exited — supervisor stopping"
