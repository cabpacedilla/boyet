#!/usr/bin/bash

declare -a SERVICES=("blueman-applet" "nm-applet")

ctr=0   
while [ "${SERVICES[$ctr]}" != "${SERVICES[-1]}" ] ; do
   
   if pgrep -x "${SERVICES[$ctr]}" >/dev/null; then
      :
   
   else   
      sleep 2 &&
      ${SERVICES[$ctr]} &
      
   fi
   
   ctr=$[$ctr + 1] 
done
