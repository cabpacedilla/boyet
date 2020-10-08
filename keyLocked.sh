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



