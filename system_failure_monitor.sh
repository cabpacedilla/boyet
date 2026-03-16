#!/usr/bin/env bash
# monitor_system_failures.sh
# Monitors critical and serious system failures across popular Linux distros.

ALERT_LOG="$HOME/scriptlogs/monitor_alerts.log"
PIDFILE="$HOME/scriptlogs/monitor.pid"
mkdir -p "$(dirname "$ALERT_LOG")"

# === Patterns for detection ===
SHOW_STOPPER="panic|kernel BUG|oops|machine check|MCE|thermal.*(shutdown|trip)|ACPI.*error|hardware error|fatal|segfault|out of memory|OOM killer|swap.*exhausted|filesystem.*readonly|journal aborted|journal.*disk.*full|no space left on device|ENOSPC|dracut.*failed|emergency mode|rescue mode|mount.*failed.*at boot|soft lockup|hard lockup|watchdog: BUG|task hung|blocked for more than|rcu_sched detected stalls|rcu: INFO|SMART.*failure|smartd.*error"

SERIOUS_FAILURES="GPU hang|GPU fault|GPU reset|DRM error|i915.*error|amdgpu.*error|nouveau.*error|plasma.*segfault|plasma.*core dumped|compositor.*crashed|plasmashell.*crashed|kwin_wayland.*crashed|kwin_x11.*crashed|Xorg.*crashed|wayland.*crashed|GDM.*crashed|SDDM.*crashed|systemd.*failed|service.*failed|unit.*failed|mount.*failed|disk.*error|I/O error|memory.*error|temperature.*critical|network.*unreachable|network.*down|link.*down|dns.*failed|name.*resolution.*failed|connection refused|timeout|authentication.*failed.*repeatedly|sudo:.*authentication failure|ssh.*connection.*failed|drkonqi|pulseaudio.*crashed|pipewire.*crashed|wireplumber.*crashed|dbus.*crash|DMA error|bus error|rpm.*error|dnf.*error|apt.*error|dpkg.*error|zypper.*error"

LOGFILES=(
    "/var/log/syslog"           # Debian-based
    "/var/log/messages"         # RHEL/Fedora/openSUSE
    "/var/log/secure"
    "/var/log/Xorg.0.log"
    "/var/log/audit/audit.log"
)

pids=()

# === Notification handling ===
send_notification() {
    local message="$1"
    local urgency="$2"

    # truncate to 500 chars to prevent KDE notify crashes
    message=$(echo "$message" | cut -c1-500)

    if [ -z "$message" ]; then
        return
    fi

    local active_user
    active_user=$(who | grep '(:0)' | awk '{print $1}' | head -n 1)

    if [ -n "$active_user" ]; then
        local user_display
        user_display=$(who | grep "$active_user" | grep '(:0)' | awk '{print $5}' | tr -d '()')
        if [ -n "$user_display" ]; then
            sudo -u "$active_user" DISPLAY="$user_display" notify-send \
                --urgency="$urgency" --icon=dialog-error \
                --app-name="System Monitor" "System Alert" "$message" 2>/dev/null
        fi
    fi

    # fallback if running as user
    if [ "$USER" != "root" ]; then
        notify-send --urgency="$urgency" --icon=dialog-error \
            --app-name="System Monitor" "System Alert" "$message" 2>/dev/null
    fi
}

# === Severity classification ===
check_error_severity() {
    local line="$1"
    if echo "$line" | grep -Eqi "$SHOW_STOPPER"; then
        echo "CRITICAL"
    elif echo "$line" | grep -Eqi "$SERIOUS_FAILURES"; then
        echo "SERIOUS"
    else
        echo "IGNORE"
    fi
}

# === Processing alerts ===
process_alert() {
    local source="$1"
    local line="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local severity
    severity=$(check_error_severity "$line")

    case "$severity" in
        "CRITICAL")
            if ! echo "$line" | grep -Eiq "screensaver"; then
                echo "$timestamp [CRITICAL] $source: $line" >> "$ALERT_LOG"
                send_notification "$line" "critical"
                open_terminal_with_logs   # auto-open logs on CRITICAL
            fi
            ;;
        "SERIOUS")
            echo "$timestamp [SERIOUS] $source: $line" >> "$ALERT_LOG"
            ;;
    esac
}

# === Monitoring functions ===
monitor_log_file() {
    local logfile="$1"
    if [ ! -f "$logfile" ]; then
        echo "Log file '$logfile' not found. Skipping..."
        return
    fi

    echo "Monitoring $logfile..."
    (
        tail -n 0 -F "$logfile" 2>/dev/null | while IFS= read -r line; do
            local severity
            severity=$(check_error_severity "$line")
            if [ "$severity" != "IGNORE" ]; then
                process_alert "$logfile" "$line"
            fi
        done
    ) &
    pids+=($!)
}

monitor_journal() {
    journalctl -f -p 3 --no-pager | while IFS= read -r line; do
        local severity
        severity=$(check_error_severity "$line")
        if [ "$severity" != "IGNORE" ]; then
            process_alert "systemd-journal" "$line"
        fi
    done
}

monitor_dmesg() {
    dmesg -w 2>/dev/null | while IFS= read -r line; do
        local severity
        severity=$(check_error_severity "$line")
        if [ "$severity" != "IGNORE" ]; then
            process_alert "kernel-dmesg" "$line"
        fi
    done
}

# === Terminal popup for CRITICAL logs ===
open_terminal_with_logs() {
    [ -f "$ALERT_LOG" ] || return
    local CRITICAL_LOGS
    CRITICAL_LOGS=$(grep "\[CRITICAL\]" "$ALERT_LOG" | tail -n 20)  # last 20 only
    [ -z "$CRITICAL_LOGS" ] && return

    TERM_CMDS=(
        "konsole"
        "gnome-terminal"
        "xfce4-terminal"
        "tilix"
        "xterm"
        "lxterminal"
        "mate-terminal"
        "alacritty"
        "terminator"
        "urxvt"
        "kitty"
        "deepin-terminal"
        "qterminal"
    )

    for term in "${TERM_CMDS[@]}"; do
        if command -v "$term" > /dev/null; then
            "$term" -e bash -c "echo '=== CRITICAL LOGS ==='; echo \"$CRITICAL_LOGS\"; echo; read -p 'Press Enter to close...'" &
            return
        fi
    done

    echo "No compatible terminal found to display critical logs."
}

# === Script starts here ===
for logfile in "${LOGFILES[@]}"; do
    monitor_log_file "$logfile"
done

if command -v journalctl > /dev/null; then
    echo "Monitoring systemd journal..."
    monitor_journal &
    pids+=($!)
fi

if command -v dmesg > /dev/null; then
    echo "Monitoring dmesg..."
    monitor_dmesg &
    pids+=($!)
fi

cleanup() {
    echo "Stopping monitoring..."
    for pid in "${pids[@]}"; do
        kill "$pid" 2>/dev/null
    done
    rm -f "$PIDFILE"
    echo "Clean exit."
    exit 0
}

trap cleanup SIGINT SIGTERM SIGHUP EXIT

send_notification "System monitor started (CRITICAL notifications only)" "low"
open_terminal_with_logs   # show logs if old CRITICAL events exist

echo "=== Linux System Monitor Running ==="
echo "Logging CRITICAL and SERIOUS issues, notifying only CRITICAL."

wait
