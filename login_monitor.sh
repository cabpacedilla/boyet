#!/usr/bin/env bash
# login_monitor.sh
# Real-time login alerts for SSH, sudo, su attempts (success & failure)
# Logs to ~/scriptlogs/login-monitor.log and sends desktop notifications
# Requires: libnotify (notify-send command)

LOCK_FILE="/tmp/login_monitor_$(whoami).lock"

exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
    exit 1
fi

# Store our PID
echo $$ > "$LOCK_FILE"

cleanup() {
    # Only remove if it's our PID
    if [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$$" ]]; then
        rm -f "$LOCK_FILE"
    fi

    flock -u 9
    exec 9>&-
}

trap cleanup EXIT

LOGFILE="$HOME/scriptlogs/login-monitor.log"
mkdir -p "$(dirname "$LOGFILE")"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Cooldown seconds for identical repeated messages
COOLDOWN=5

# Store last event timestamps
declare -A last_event

# Track processed events for periodic cleanup
EVENT_COUNTER=0

# Cleanup old cooldown entries (prevents unbounded memory growth)
cleanup_old_events() {
    local current
    current=$(date +%s)

    for key in "${!last_event[@]}"; do
        if (( current - last_event[$key] > 600 )); then
            unset 'last_event[$key]'
        fi
    done
}

# Function to send notifications and log them
send_alert() {
    local TITLE="$1"
    local MSG="$2"
    local URGENCY="$3"

    timeout 2 notify-send "$TITLE" "$MSG" -u "$URGENCY" 2>/dev/null &

    echo "[$(date '+%F %T')] [$TITLE] $MSG" >> "$LOGFILE"
}

echo "[$(date '+%F %T')] Starting login monitor..." | tee -a "$LOGFILE"

timeout 2 notify-send "Login Monitor" "Starting login monitor..." 2>/dev/null &

# Restart automatically if journalctl exits
while true; do
    journalctl -f -n0 -o short-iso --no-tail \
        _COMM=sshd \
        _COMM=sshd-session \
        _COMM=sudo \
        _COMM=su 2>/dev/null | \
    while IFS= read -r LINE; do

        NOW=$(date +%s)
        TS=$(date '+%F %T')

        # Periodic cleanup
        EVENT_COUNTER=$((EVENT_COUNTER + 1))

        if (( EVENT_COUNTER % 50 == 0 )); then
            cleanup_old_events
        fi

        # =========================================================
        # SSH EVENTS
        # =========================================================
        if [[ "$LINE" =~ "sshd" || "$LINE" =~ "sshd-session" ]]; then

            # SSH SUCCESS
            if [[ "$LINE" =~ "Accepted " ]]; then

                USER=$(echo "$LINE" | grep -oP "for \K[^ ]+")
                IP=$(echo "$LINE" | grep -oP "from \K[^ ]+")

                EVENT_ID="ssh_success_${USER}_${IP}"

                if [[ -n "${last_event[$EVENT_ID]}" ]] &&
                   (( NOW - last_event[$EVENT_ID] < COOLDOWN )); then
                    continue
                fi

                last_event[$EVENT_ID]=$NOW

                MSG="User: $USER | From: $IP | Time: $TS"

                echo -e "✅ ${GREEN}[SSH SUCCESS]${NC} $LINE" | tee -a "$LOGFILE"

                send_alert "✅ SSH Login Success" "$MSG" critical

            # SSH FAILURE
            elif [[ "$LINE" =~ "Failed password" ]]; then

                USER=$(echo "$LINE" | grep -oP "for \K[^ ]+")
                IP=$(echo "$LINE" | grep -oP "from \K[^ ]+")

                EVENT_ID="ssh_fail_${USER}_${IP}"

                if [[ -n "${last_event[$EVENT_ID]}" ]] &&
                   (( NOW - last_event[$EVENT_ID] < COOLDOWN )); then
                    continue
                fi

                last_event[$EVENT_ID]=$NOW

                MSG="User: $USER | From: $IP | Time: $TS"

                echo -e "⚠️ ${RED}[SSH FAILURE]${NC} $LINE" | tee -a "$LOGFILE"

                send_alert "⚠️ SSH Login Failed" "$MSG" critical
            fi
        fi

        # =========================================================
        # SUDO EVENTS
        # =========================================================
        if [[ "$LINE" =~ "sudo" ]]; then

            # SUDO SUCCESS
            if [[ "$LINE" =~ "session opened" ]]; then

                USER=$(echo "$LINE" | grep -oP "by \K[^ ]+")

                EVENT_ID="sudo_success_${USER}"

                if [[ -n "${last_event[$EVENT_ID]}" ]] &&
                   (( NOW - last_event[$EVENT_ID] < COOLDOWN )); then
                    continue
                fi

                last_event[$EVENT_ID]=$NOW

                RAW=$(journalctl _COMM=sudo -n5 -o cat | grep "COMMAND=" | tail -1)

                CONTEXT=$(echo "$RAW" | sed -E 's/; COMMAND=.*//')
                CMD=$(echo "$RAW" | sed -E 's/.*COMMAND=(.*)/\1/')

                MSG="User: $USER | Time: $TS\n$CONTEXT\nCommand: $CMD"

                echo -e "✅ ${GREEN}[SUDO SUCCESS]${NC} $LINE | $CONTEXT | Command: $CMD" | tee -a "$LOGFILE"

                send_alert "✅ Sudo Success" "$MSG" critical

            # PAM AUTH FAILURE
            elif [[ "$LINE" =~ "pam_unix(sudo:auth): authentication failure" ]]; then

                if [[ "$LINE" =~ user=([^[:space:]]+) ]]; then
                    USER="${BASH_REMATCH[1]}"
                else
                    USER="unknown"
                fi

                EVENT_ID="sudo_fail_${USER}"

                if [[ -n "${last_event[$EVENT_ID]}" ]] &&
                   (( NOW - last_event[$EVENT_ID] < 2 )); then
                    continue
                fi

                last_event[$EVENT_ID]=$NOW

                PAM_DETAILS=$(echo "$LINE" | sed -n 's/.*authentication failure; \(.*\)/\1/p')

                MSG="User: $USER | Time: $TS\n$PAM_DETAILS\nCommand: (will be logged on final attempt)"

                echo -e "⚠️ ${RED}[SUDO FAILURE]${NC} $LINE | $PAM_DETAILS | Command: (will be logged on final attempt)" | tee -a "$LOGFILE"

                send_alert "⚠️ Sudo Failure" "$MSG" critical

            # SUDO FAILURE
            elif [[ "$LINE" =~ "incorrect password attempts" ]] ||
                 [[ "$LINE" =~ "sorry, try again" ]] ||
                 [[ "$LINE" =~ "password attempts" ]]; then

                USER=$(echo "$LINE" |
                    awk -F'sudo\\[[0-9]*\\]: *' '{print $2}' |
                    awk '{print $1}')

                if [[ -z "$USER" ]] || [[ "$USER" == ":" ]]; then
                    USER=$(echo "$LINE" |
                        sed -n 's/.*sudo\[[0-9]*\]: *\([^ ]*\).*/\1/p')
                fi

                if [[ -z "$USER" ]]; then
                    USER="unknown"
                fi

                EVENT_ID="sudo_fail_${USER}"

                if [[ -n "${last_event[$EVENT_ID]}" ]] &&
                   (( NOW - last_event[$EVENT_ID] < 2 )); then
                    continue
                fi

                last_event[$EVENT_ID]=$NOW

                if [[ "$LINE" =~ COMMAND=(.+)$ ]]; then
                    CMD="${BASH_REMATCH[1]}"
                    CONTEXT=$(echo "$LINE" | sed -E 's/; COMMAND=.*//')
                else
                    RAW=$(journalctl _COMM=sudo -n5 -o cat | grep "COMMAND=" | tail -1)

                    CONTEXT=$(echo "$RAW" | sed -E 's/; COMMAND=.*//')
                    CMD=$(echo "$RAW" | sed -E 's/.*COMMAND=(.*)/\1/')
                fi

                MSG="User: $USER | Time: $TS\n$CONTEXT\nCommand: $CMD"

                echo -e "⚠️ ${RED}[SUDO FAILURE]${NC} $LINE | $CONTEXT | Command: $CMD" | tee -a "$LOGFILE"

                send_alert "⚠️ Sudo Failure" "$MSG" critical
            fi
        fi

        # =========================================================
        # SU EVENTS
        # =========================================================
        if [[ "$LINE" =~ " su[" && "$LINE" =~ "session opened" ]]; then

            USER=$(echo "$LINE" | grep -oP "by \K[^ ]+")

            EVENT_ID="su_success_${USER}"

            if [[ -n "${last_event[$EVENT_ID]}" ]] &&
               (( NOW - last_event[$EVENT_ID] < COOLDOWN )); then
                continue
            fi

            last_event[$EVENT_ID]=$NOW

            MSG="User: $USER | Time: $TS"

            echo -e "✅ ${GREEN}[SU SUCCESS]${NC} $LINE" | tee -a "$LOGFILE"

            send_alert "✅ su Login Success" "$MSG" critical

        elif [[ "$LINE" =~ " su[" && "$LINE" =~ "authentication failure" ]]; then

            # Source user
            if [[ "$LINE" =~ ruser=([^[:space:]]+) ]]; then
                SOURCE_USER="${BASH_REMATCH[1]}"
            elif [[ "$LINE" =~ logname=([^[:space:]]+) ]]; then
                SOURCE_USER="${BASH_REMATCH[1]}"
            else
                SOURCE_USER="unknown"
            fi

            # Target user
            if [[ "$LINE" =~ user=([^[:space:]]+)$ ]] ||
               [[ "$LINE" =~ user=([^[:space:]]+)[[:space:]] ]]; then
                TARGET_USER="${BASH_REMATCH[1]}"
            else
                TARGET_USER="unknown"
            fi

            EVENT_ID="su_fail_${SOURCE_USER}_${TARGET_USER}"

            if [[ -n "${last_event[$EVENT_ID]}" ]] &&
               (( NOW - last_event[$EVENT_ID] < 2 )); then
                continue
            fi

            last_event[$EVENT_ID]=$NOW

            MSG="Source User: $SOURCE_USER | Target User: $TARGET_USER | Time: $TS"

            echo -e "⚠️ ${RED}[SU FAILURE]${NC} $LINE" | tee -a "$LOGFILE"

            send_alert "⚠️ su Failure" "$MSG" critical
        fi
    done

    echo "[$(date '+%F %T')] journalctl disconnected, restarting..." | tee -a "$LOGFILE"

    sleep 2
done
