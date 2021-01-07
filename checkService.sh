#!/usr/bin/bash

declare -a SERVICES=("blueman-applet" "nm-applet")

ctr=0   
while [ "$ctr" -le "${#SERVICES[@]}" ] ; do
   
   if pgrep -x "${SERVICES[$ctr]}" >/dev/null; then
      :
   
   else   
      ${SERVICES[$ctr]} &
      
   fi
   
   ctr=$[$ctr + 1] 
done
