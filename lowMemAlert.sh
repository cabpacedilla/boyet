#!/usr/bin/bash
while true
do
   free_mem=$(free_mem -mt | grep Total | awk '{print $4}')

   if [ $free_mem -le 800 ] 
   then
      top_processes=`ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%mem | head` 
      
      notify-send "RAM has low free memory. Free high memory consuming applications from the top memory consuming processes: ${top_processes}" 
  
   elif [ $free -gt 800 ]
   then
      :
      
   fi

   sleep 30
done
