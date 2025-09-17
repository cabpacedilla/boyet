#!/usr/bin/bash
# Low Memory Alert Script (percentage-based)
# Alerts when free memory (available) is less than or equal to a percentage limit of total RAM
# Assembled and written by Claive Alvin P. Acedilla. Can be copied, modified, and redistributed.
# October 2020

# Steps for the task:
# 1. Create a bin directory inside your home directory
# 2. Change directory to the bin directory
# 3. Create the bash script file below with nano or gedit and save it with a filename like lowMemAlert.sh
# 4. Make file executable with chmod +x lowMemAlert.sh command
# 5. Add the lowMemAlert.sh command in Startup applications
# 6. Reboot the laptop
# 7. Log in and simulate low memory scenario by running many high memory consuming processes
# 8. Low memory alert message will be displayed

TERMINALS=("gnome-terminal" "xfce4-terminal" "tilix" "lxterminal" "mate-terminal" "alacritty" "urxvt" "konsole")

while true; do
    # 1. Set your free memory percentage limit (e.g., 15 means 15% of total RAM)
    MEMFREE_LIMIT_PERCENT=15

    # 2. Get total and available memory in MB
    TOTAL_MEM=$(free -m | awk 'NR==2 {print $2}')
    MEMFREE=$(free -m | awk 'NR==2 {print $7}')

    # 3. Compute threshold in MB
    THRESHOLD=$(( TOTAL_MEM * MEMFREE_LIMIT_PERCENT / 100 ))

    # 4. Check if free memory is below or equal to threshold
    if [[ "$MEMFREE" =~ ^[0-9]+$ ]] && [ "$MEMFREE" -le "$THRESHOLD" ]; then
        # Get top 10 memory-consuming processes
        TOP_PROCESSES=$(ps -eo pid,ppid,%mem,%cpu,cmd --sort=-%mem | head -n 11 | \
            awk '{cmd = ""; for (i=5; i<=NF; i++) cmd = cmd $i " ";
                  if(length(cmd) > 115) cmd = substr(cmd, 1, 113) "...";
                  if ($5 !~ /konsole/)
                      printf "%-10s %-10s %-5s %-5s %s\n", $1, $2, $3, $4, cmd}')

        launched=false
        for term in "${TERMINALS[@]}"; do
            if command -v "$term" >/dev/null 2>&1; then
                "$term" -e bash -c "echo -e \"⚠️ Low memory alert: RAM below ${MEMFREE_LIMIT_PERCENT}%.\nFree high memory consuming processes:\n${TOP_PROCESSES}\n\"; read -p 'Press enter to close...'" &
                launched=true
                break
            fi
        done

        if [ "$launched" = false ]; then
            notify-send "⚠️ Low Memory Alert" "RAM below ${MEMFREE_LIMIT_PERCENT}%. No supported terminal emulator found."
        fi
    fi

    # 5. Sleep for 30 seconds before checking again
    sleep 30
done
