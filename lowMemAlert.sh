# This script will alert when free memory is 20% or less
# This script was assembled written by Claive Alvin P. Acedilla. It can be copied, modified and redistributed.
# October 2020

# Steps for the task:
# 1. Create a bin directory inside your home directory
# 2. Change directory to the bin directory
# 3. Create the bash script file below with nano or gedit and save it with a filename like lowMemAlert.sh
# 4. Make file executable with chmod +x lowMemAlert.sh command
# 5. Add the lowMemAlert.sh command in Startup applications
# 6. Reboot the laptop
# 7. Log in and simulate low memory scenario by running high memory consuming processes until free memory reaches 20% or less
# 8. Low memory alert message will be displayed

#!/usr/bin/bash
while true
do
   ## 1. get total free memory size in megabytes(MB) 
   free=$(free -mt | grep Total | awk '{print $4}')

   ## 2. check if free memory is less or equals to 30%
   if [ $free -le 1000 ] 
   then        
      ## 3. get top processes consuming system memory and send notification
      top_processes=`ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%mem | head` 
      notify-send "RAM has low free memory. Free high memory consuming processes: ${top_processes}" 
       
   fi
 
   ## 4. sleep script after 30 seconds
   sleep 30
done
