#!/usr/bin/bash

declare -a SERVICES=("blueman-applet" "nm-applet")

ctr=0   
while [ "$ctr" -le "${#SERVICES[@]}" ] ; do
   
   # check if process is running comparing array item with pgrep -x 
   if pgrep -x "${SERVICES[$ctr]}" >/dev/null; then
      :
   
   else   
      ${SERVICES[$ctr]} &
      
   fi
   
   ctr=$[$ctr + 1] 
done
