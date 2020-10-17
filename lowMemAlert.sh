#!/usr/bin/bash
while true
do
   ## get total free memory size in megabytes(MB) 
   free=$(free -mt | grep Total | awk '{print $4}')

   ## check if free memory is less or equals to 20%
   if [ $free -le 800 ] 
   then
        
      ## get top processes consuming system memory and
      top_processes=`ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%mem | head` 
      notify-send "RAM has low free memory. Free high memory consuming applications from the top memory consuming processes: ${top_processes}" 
  
   elif [ $free -gt 800 ]
   then
      :
      
   fi

   sleep 30
done
