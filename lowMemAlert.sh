# This script will alert when free memory is 20% or less
# This script was written by Claive Alvin P. Acedilla. It can be copied, modified and redistributed.
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
   free_mem=$(free_mem -mt | grep Total | awk '{print $4}')

   if [ $free_mem -le 800 ] 
   then
      top_processes=`ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%mem | head` 
      
      notify-send "RAM has low free memory. Free high memory consuming applications from the top memory consuming processes: ${top_processes}" 
  
   elif [ $free_mem -gt 800 ]
   then
      :
      
   fi

   sleep 30
don
