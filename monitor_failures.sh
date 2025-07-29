#!/usr/bin/bash
# monitor_fedora_failures.sh
# Monitors Fedora KDE 6.3 logs for critical and serious system failures in real-time.

ALERT_LOG="$HOME/scriptlogs/monitor_alerts.log"
PIDFILE="$HOME/scriptlogs/monitor.pid"

# Optional: Prevent duplicate instances
# mkdir -p "$(dirname "$ALERT_LOG")"
# if [ -f "$PIDFILE" ]; then
#     OLD_PID=$(cat "$PIDFILE")
#     if kill -0 "$OLD_PID" 2>/dev/null; then
#         echo "Monitor script is already running with PID $OLD_PID"
#         exit 1
#     else
#         echo "Removing stale PID file"
#         rm -f "$PIDFILE"
#     fi
# fi
# echo $$ > "$PIDFILE"

SHOW_STOPPER="panic|kernel BUG|oops|machine check|MCE|thermal.*shutdown|plasmashell.*crashed|kwin_wayland.*crashed|kwin_x11.*crashed|Xorg.*crashed|wayland.*crashed|GDM.*crashed|SDDM.*crashed|emergency mode|rescue mode|out of memory|OOM killer|filesystem.*readonly|hardware error|fatal|segfault|login.*failed.*repeatedly|dracut.*failed|mount.*failed.*at boot|soft lockup|hard lockup|watchdog: BUG|page allocation failure|journal aborted"
SERIOUS_FAILURES="GPU hang|GPU fault|GPU reset|DRM error|i915.*error|amdgpu.*error|nouveau.*error|plasma.*segfault|plasma.*core dumped|compositor.*crashed|systemd.*failed|mount.*failed|disk.*error|I/O error|memory.*error|temperature.*critical|network.*unreachable|network.*down|link.*down|authentication.*failed.*repeatedly|swap.*exhausted|drkonqi|pulseaudio.*crashed|pipewire.*crashed|wireplumber.*crashed|dbus.*crash|journal.*disk.*full"

LOGFILES=(
    "/var/log/messages"
    "/var/log/secure"
    "/var/log/Xorg.0.log"
    "/var/log/audit/audit.log"
)

pids=()

send_notification() {
    local message="$1"
    local urgency="$2"
    local active_user=$(who | grep '(:0)' | awk '{print $1}' | head -1)
    if [ -n "$active_user" ]; then
        local user_display=$(who | grep "$active_user" | grep '(:0)' | awk '{print $5}' | tr -d '()')
        if [ -n "$user_display" ]; then
            sudo -u "$active_user" DISPLAY="$user_display" notify-send \
                --urgency="$urgency" \
                --icon=dialog-error \
                --app-name="System Monitor" "System Alert" "$message" 2>/dev/null
        fi
    fi

    if [ "$USER" != "root" ]; then
        notify-send --urgency="$urgency" --icon=dialog-error \
            --app-name="System Monitor" "System Alert" "$message" 2>/dev/null
    fi
}

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
            fi
            ;;
        "SERIOUS")
            echo "$timestamp [SERIOUS] $source: $line" >> "$ALERT_LOG"
            ;;
    esac
}

monitor_log_file() {
    local logfile="$1"
    if [ ! -f "$logfile" ]; then
        echo "Log file '$logfile' not found. Skipping..."
        return
    fi

    echo "Monitoring $logfile with inotify..."

    (
        tail -n 0 -F "$logfile" 2>/dev/null | while IFS= read -r line; do
            severity=$(check_error_severity "$line")
            if [ "$severity" != "IGNORE" ]; then
                process_alert "$logfile" "$line"
            fi
        done
    ) &
    pids+=($!)

    (
        while inotifywait -e modify "$logfile" >/dev/null 2>&1; do
            :
            # Keeps watching for modifications
        done
    ) &
    pids+=($!)
}

for logfile in "${LOGFILES[@]}"; do
    monitor_log_file "$logfile"
done

if command -v journalctl > /dev/null; then
    echo "Monitoring systemd journal..."
    journalctl -f -p 3 --no-pager | while IFS= read -r line; do
        severity=$(check_error_severity "$line")
        if [ "$severity" != "IGNORE" ]; then
            process_alert "systemd-journal" "$line"
        fi
    done &
    pids+=($!)
fi

if command -v dmesg > /dev/null; then
    echo "Monitoring dmesg..."
    dmesg -w 2>/dev/null | while IFS= read -r line; do
        severity=$(check_error_severity "$line")
        if [ "$severity" != "IGNORE" ]; then
            process_alert "kernel-dmesg" "$line"
        fi
    done &
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

echo "=== Fedora KDE System Monitor Running ==="
echo "Logging CRITICAL and SERIOUS issues, notifying only CRITICAL."

# Optional: Show existing critical alerts once at startup
open_terminal_with_logs() {
    CRITICAL_LOGS=$(grep "\[CRITICAL\]" "$ALERT_LOG")
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
    )

    for term in "${TERM_CMDS[@]}"; do
        if command -v "$term" > /dev/null; then
            "$term" -e bash -c "cat <<EOF
$CRITICAL_LOGS
EOF
read -p 'Press Enter to close...'" &
            return
        fi
    done

    echo "No compatible terminal found to display critical logs."
}

if [ -f "$ALERT_LOG" ]; then
    open_terminal_with_logs
fi

wait
