#!/usr/bin/bash
# monitor_fedora_failures.sh
# Monitors Fedora KDE 6.3 logs for serious and critical system failures.

ALERT_LOG="$HOME/scriptlogs/monitor_alerts.log"
PIDFILE="$HOME/scriptlogs/monitor.pid"
mkdir -p "$(dirname "$ALERT_LOG")"

if [ -f "$PIDFILE" ]; then
    OLD_PID=$(cat "$PIDFILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        echo "Monitor script is already running with PID $OLD_PID"
        exit 1
    else
        echo "Removing stale PID file"
        rm -f "$PIDFILE"
    fi
fi
echo $$ > "$PIDFILE"

# Critical and serious error patterns
SHOW_STOPPER="panic|kernel BUG|oops|machine check|MCE|plasmashell.*crashed|kwin_wayland.*crashed|kwin_x11.*crashed|Xorg.*crashed|wayland.*crashed|emergency mode|rescue mode|thermal.*shutdown|out of memory|OOM killer|filesystem.*readonly|hardware error|fatal|segfault"
SERIOUS_FAILURES="GPU hang|GPU fault|GPU reset|plasma.*segfault|systemd.*failed|mount.*failed|disk.*error|memory.*error|temperature.*critical|network.*unreachable|authentication.*failed.*repeatedly|swap.*exhausted|compositor.*crashed|drkonqi|plasma.*core dumped"

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
    local hostname
    hostname=$(hostname)
    local severity
    severity=$(check_error_severity "$line")

    case "$severity" in
        "CRITICAL")
            if ! echo "$line" | grep -Eiq "screensaver"; then
                echo "$timestamp [CRITICAL] $source: $line" > "$ALERT_LOG"
            fi
            ;;
        "SERIOUS")
            echo "$timestamp [SERIOUS] $source: $line" > "$ALERT_LOG"
            ;;
    esac
}

monitor_log_file() {
    local logfile="$1"
    if [ ! -f "$logfile" ]; then
        echo "Log file '$logfile' not found. Skipping..."
        return
    fi
    echo "Monitoring $logfile..."
    sudo tail -n 0 -F "$logfile" 2>/dev/null | while IFS= read -r line; do
        severity=$(check_error_severity "$line")
        if [ "$severity" != "IGNORE" ]; then
            process_alert "$logfile" "$line"
        fi
    done &
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
wait
