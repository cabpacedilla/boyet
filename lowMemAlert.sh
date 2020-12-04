# This script will alert when free memory is less than or equals to desired low free memory space in megabytes
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

#!/usr/bin/bash
while true
do
   ## 1. Get total free memory size in megabytes(MB) 
   free=$(free -mt | grep Total | awk '{print $4}')

   ## 2. Check if free memory is less or equals to desired low free memory space in megabytes
   if [ $free -le 1000 ] 
   then        
      ## 3. get top processes consuming system memory and show notification with the top 10 memory consuming processes
      top_processes=`ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%mem | head` 
      notify-send -t 10000 "RAM has low free memory. Free high memory consuming processes: ${top_processes}" 
       
   fi
   ## 4. sleep script for 30 seconds
   sleep 30
done
