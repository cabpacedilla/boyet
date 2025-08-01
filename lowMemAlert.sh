#!/usr/bin/bash
# This script will alert when free memory is less than or equals to the free available RAM percentage limit
# This script was assembled written by Claive Alvin P. Acedilla. It can be copied, modified and redistributed.
# October 2020

# Steps for the task:
# 1. Create a bin directory inside your home directory
# 2. Change directory to the bin directory
# 3. Create the bash script file below with nano or gedit and save it with a filename like lowMemAlert.sh
# 4. Make file executable with chmod +x lowMemAlert.sh command
# 5. Add the lowMemAlert.sh command in Startup applications
# 6. Reboot the laptop
# 7. Log in and simulate low memory scenario by running many high memory consuming processes until free memory space reaches desired low free memory space in megabytes
# 8. Low memory alert message will be displayed

TERMINALS=("gnome-terminal" "xfce4-terminal" "tilix" "lxterminal" "mate-terminal" "alacritty" "urxvt" "konsole")

#!/usr/bin/bash
while true; do
# 1. Set memory free limit
MEMFREE_LIMIT=1440
	
# 2. Get total free memory size in megabytes(MB) 
MEMFREE=$(free -m | awk 'NR==2 {print $7}')

# 3. Check if free memory is less or equals to desired low free memory space in megabytes
if [[ "$MEMFREE" =~ ^[0-9]+$ ]] && [ "$MEMFREE" -le "$MEMFREE_LIMIT" ]; then    
   # 4. get top processes consuming system memory and show notification with the top 10 memory consuming processes
#    TOP_PROCESSES=$(ps -eo pid,ppid,%mem,%cpu,cmd --sort=-%mem | head -n 11 | awk '{cmd = ""; for (i=5; i<=NF; i++) cmd = cmd $i " "; if(length(cmd) > 115) cmd = substr(cmd, 1, 113) "..."; printf "%-10s %-10s %-5s %-5s %s\n", $1, $2, $3, $4, cmd}')
   TOP_PROCESSES=$(ps -eo pid,ppid,%mem,%cpu,cmd --sort=-%mem | head -n 11 | awk '{cmd = ""; for (i=5; i<=NF; i++) cmd = cmd $i " "; if(length(cmd) > 115) cmd = substr(cmd, 1, 113) "..."; if ($5 !~ /konsole/) printf "%-10s %-10s %-5s %-5s %s\n", $1, $2, $3, $4, cmd}')
  

   launched=false
   for term in "${TERMINALS[@]}"; do
      if command -v "$term" >/dev/null 2>&1; then
         "$term" -e bash -c "echo -e \"Low memory alert: RAM has low free memory. Free high memory consuming processes:\n${TOP_PROCESSES}\n\"; read -p 'Press enter to close...'" &
         launched=true
         break
      fi
   done

   if [ "$launched" = false ]; then
      notify-send "Low Memory Alert" "No supported terminal emulator found to display memory usage."
   fi
fi

# 4. sleep for 30 seconds
sleep 30
done


