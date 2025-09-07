#!/bin/bash
# login_monitor.sh
# Real-time login alerts for SSH, sudo, su attempts (success & failure)
# Logs to ~/scriptlogs/login-monitor.log and sends desktop notifications
# Requires: libnotify (notify-send command)

LOGFILE="$HOME/scriptlogs/login-monitor.log"
mkdir -p "$(dirname "$LOGFILE")"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Export so notify-send works in GUI
# export DISPLAY=:0
# export XDG_RUNTIME_DIR="/run/user/$(id -u)"

# Cooldown seconds for identical repeated messages
COOLDOWN=5
declare -A last_event

# Function to send notifications and log them
send_alert() {
    TITLE="$1"
    MSG="$2"
    URGENCY="$3"
    notify-send "$TITLE" "$MSG" -u "$URGENCY" &
    echo "[$(date '+%F %T')] [$TITLE] $MSG" >> "$LOGFILE"
}

echo "[$(date '+%F %T')] Starting login monitor..." | tee -a "$LOGFILE"
notify-send "Login Monitor" "Starting login monitor..." &

journalctl -f -n0 -o short-iso --since now \
  _COMM=sshd _COMM=sshd-session _COMM=sudo _COMM=su | \
while read -r LINE; do
    NOW=$(date +%s)
    TS=$(date '+%F %T')

    # --- SSH ---
    if [[ "$LINE" =~ "sshd" || "$LINE" =~ "sshd-session" ]]; then
        if [[ "$LINE" =~ "Accepted " ]]; then
            USER=$(echo "$LINE" | grep -oP "for \K[^ ]+")
            IP=$(echo "$LINE" | grep -oP "from \K[^ ]+")
            EVENT_ID="ssh_success_${USER}_${IP}_$(echo "$LINE" | awk '{print $1}')"

            if [[ -n "${last_event[$EVENT_ID]}" ]] && (( NOW - last_event[$EVENT_ID] < COOLDOWN )); then
                continue
            fi
            last_event[$EVENT_ID]=$NOW

            MSG="User: $USER | From: $IP | Time: $TS"
            echo -e "${GREEN}[SSH SUCCESS]${NC} $LINE" | tee -a "$LOGFILE"
            send_alert "SSH Login Success" "$MSG" critical

        elif [[ "$LINE" =~ "Failed password" ]]; then
            USER=$(echo "$LINE" | grep -oP "for \K[^ ]+")
            IP=$(echo "$LINE" | grep -oP "from \K[^ ]+")
            EVENT_ID="ssh_fail_${USER}_${IP}_${NOW}_$(echo "$LINE" | awk '{print $1"_"$2}')"

            if [[ -n "${last_event[$EVENT_ID]}" ]] && (( NOW - last_event[$EVENT_ID] < COOLDOWN )); then
                continue
            fi
            last_event[$EVENT_ID]=$NOW

            MSG="User: $USER | From: $IP | Time: $TS"
            echo -e "${RED}[SSH FAILURE]${NC} $LINE" | tee -a "$LOGFILE"
            send_alert "SSH Login Failed" "$MSG" critical
        fi
    fi

    # --- SUDO ---
    if [[ "$LINE" =~ "sudo" ]]; then
        if [[ "$LINE" =~ "session opened" ]]; then
            USER=$(echo "$LINE" | grep -oP "by \K[^ ]+")
            EVENT_ID="sudo_success_${USER}_$(echo "$LINE" | awk '{print $1"_"$2}')"

            if [[ -n "${last_event[$EVENT_ID]}" ]] && (( NOW - last_event[$EVENT_ID] < COOLDOWN )); then
                continue
            fi
            last_event[$EVENT_ID]=$NOW

            RAW=$(journalctl _COMM=sudo -n5 -o cat | grep "COMMAND=" | tail -1)
            CONTEXT=$(echo "$RAW" | sed -E 's/; COMMAND=.*//')
            CMD=$(echo "$RAW" | sed -E 's/.*COMMAND=(.*)/\1/')
            MSG="User: $USER | Time: $TS\n$CONTEXT\nCommand: $CMD"
            echo -e "${GREEN}[SUDO SUCCESS]${NC} $LINE | $CONTEXT | Command: $CMD" | tee -a "$LOGFILE"
            send_alert "Sudo Success" "$MSG" critical

        # Handle PAM authentication failures (first failure attempt - uses PAM log)
        elif [[ "$LINE" =~ "pam_unix(sudo:auth): authentication failure" ]]; then
            if [[ "$LINE" =~ "user="([^\ ]+) ]]; then
                USER="${BASH_REMATCH[1]}"
            else
                USER="unknown"
            fi

            EVENT_ID="sudo_pam_fail_${USER}_${NOW}"

            if [[ -n "${last_event[$EVENT_ID]}" ]] && (( NOW - last_event[$EVENT_ID] < 2 )); then
                continue
            fi
            last_event[$EVENT_ID]=$NOW

            # Extract PAM failure details from the log line
            PAM_DETAILS=$(echo "$LINE" | sed -n 's/.*authentication failure; \(.*\)/\1/p')

            # Don't try to get command for PAM failures - it's from previous session
            MSG="User: $USER | Time: $TS\n$PAM_DETAILS\nCommand: (will be logged on final attempt)"
            echo -e "${RED}[SUDO FAILURE]${NC} $LINE | $PAM_DETAILS | Command: (will be logged on final attempt)" | tee -a "$LOGFILE"
            send_alert "Sudo Failure" "$MSG" critical

        # Handle sudo's own failure messages (successive attempts - uses sudo log)
        elif [[ "$LINE" =~ "incorrect password attempts" ]] || [[ "$LINE" =~ "sorry, try again" ]] || [[ "$LINE" =~ "password attempts" ]]; then
            # Simple approach: extract username using awk after sudo[pid]:
            USER=$(echo "$LINE" | awk -F'sudo\\[[0-9]*\\]: *' '{print $2}' | awk '{print $1}')

            # If that fails, try alternative extraction
            if [[ -z "$USER" ]] || [[ "$USER" == ":" ]]; then
                # Use sed to extract first word after sudo[number]:
                USER=$(echo "$LINE" | sed -n 's/.*sudo\[[0-9]*\]: *\([^ ]*\).*/\1/p')
            fi

            # Final fallback
            if [[ -z "$USER" ]]; then
                USER="unknown"
            fi

            EVENT_ID="sudo_fail_${USER}_${NOW}_$(echo "$LINE" | awk '{print $1"_"$2}')"

            if [[ -n "${last_event[$EVENT_ID]}" ]] && (( NOW - last_event[$EVENT_ID] < 2 )); then
                continue
            fi
            last_event[$EVENT_ID]=$NOW

            # For sudo's own logs, extract command directly from the line
            if [[ "$LINE" =~ COMMAND=(.+)$ ]]; then
                CMD="${BASH_REMATCH[1]}"
                CONTEXT=$(echo "$LINE" | sed -E 's/; COMMAND=.*//')
            else
                # Fallback to journal query
                RAW=$(journalctl _COMM=sudo -n5 -o cat | grep "COMMAND=" | tail -1)
                CONTEXT=$(echo "$RAW" | sed -E 's/; COMMAND=.*//')
                CMD=$(echo "$RAW" | sed -E 's/.*COMMAND=(.*)/\1/')
            fi

            MSG="User: $USER | Time: $TS\n$CONTEXT\nCommand: $CMD"
            echo -e "${RED}[SUDO FAILURE]${NC} $LINE | $CONTEXT | Command: $CMD" | tee -a "$LOGFILE"
            send_alert "Sudo Failure" "$MSG" critical
        fi
    fi

    # --- SU ---
    if [[ "$LINE" =~ " su[" && "$LINE" =~ "session opened" ]]; then
        USER=$(echo "$LINE" | grep -oP "by \K[^ ]+")
        EVENT_ID="su_success_${USER}_$(echo "$LINE" | awk '{print $1"_"$2}')"

        if [[ -n "${last_event[$EVENT_ID]}" ]] && (( NOW - last_event[$EVENT_ID] < COOLDOWN )); then
            continue
        fi
        last_event[$EVENT_ID]=$NOW

        MSG="User: $USER | Time: $TS"
        echo -e "${GREEN}[SU SUCCESS]${NC} $LINE" | tee -a "$LOGFILE"
        send_alert "su Login Success" "$MSG" critical

    elif [[ "$LINE" =~ " su[" && "$LINE" =~ "authentication failure" ]]; then
        # Extract both the source user (ruser) and target user (user) from su failure
        if [[ "$LINE" =~ ruser=([^[:space:]]+) ]]; then
            SOURCE_USER="${BASH_REMATCH[1]}"
        elif [[ "$LINE" =~ logname=([^[:space:]]+) ]]; then
            SOURCE_USER="${BASH_REMATCH[1]}"
        else
            SOURCE_USER="unknown"
        fi

        if [[ "$LINE" =~ user=([^[:space:]]+)$ ]] || [[ "$LINE" =~ user=([^[:space:]]+)[[:space:]] ]]; then
            TARGET_USER="${BASH_REMATCH[1]}"
        else
            TARGET_USER="unknown"
        fi

        # Make each su failure unique
        EVENT_ID="su_fail_${SOURCE_USER}_${TARGET_USER}_${NOW}_$(echo "$LINE" | awk '{print $1"_"$2}')"

        if [[ -n "${last_event[$EVENT_ID]}" ]] && (( NOW - last_event[$EVENT_ID] < 2 )); then
            continue
        fi
        last_event[$EVENT_ID]=$NOW

        MSG="Source User: $SOURCE_USER | Target User: $TARGET_USER | Time: $TS"
        echo -e "${RED}[SU FAILURE]${NC} $LINE" | tee -a "$LOGFILE"
        send_alert "su Failure" "$MSG" critical
    fi
done
