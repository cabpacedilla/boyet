# This script will notify when Caps lock or Num lock are on using the xset q command.
# This script was assembled and written by Claive Alvin P. Acedilla. It can be copied, modified and redistributed.
# October 2020

# Steps for the task:
# 1. 

#!/usr/bin/bash

while true
do
   value="$(xset q | grep 'LED mask' | awk '{ print $NF }')"

   if [ "$value" = 00000001 ]
   then
      notify-send -t 10000 "Caps lock is on."
   
   elif [ "$value" = 00000002 ]
   then 
      notify-send -t 10000 "Num lock is on."
       
   elif  [ "$value" = 00000003 ]   
   then
      notify-send -t 10000 "Caps lock and Num lock are on."
   
   elif [ "$value" = 00000000 ] 
   then
      : 
   
   fi

sleep 15
done    



