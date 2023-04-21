#!/usr/bin/bash

# This script will automatically switch to Skype or any message app when your office mate @mention you or @mention all to attend the message right away
# This code was assembled and written by Claive Alvin P. Acedilla. It can be copied, modified and redistributed.

while true; do
NOTIFLOGS=~/Documents/listenotif/notiflogs.txt
NOTIFBUF=~/Documents/listenotif/notifbuf.txt

NOTIF=("@mentioned you" "mentioned all")


dbus-monitor "interface='org.freedesktop.Notifications'" |\
grep --line-buffered "string" |\
grep --line-buffered -e method -e ":" -e '""' -e urgency -e notify -v |\
grep --line-buffered '.*(?=string)|(?<=string).*' -oPi |\
grep --line-buffered -v '^\s*$' |\
#xargs -d '\n' -I '{}' espeak '{}' \
xargs -d '\n' -I '{}' \
printf "---$(date)---\n"{}"\n" > $NOTIFLOGS &

# Switch to Skype every time someone @mention you or @mention all
while inotifywait -e modify $NOTIFLOGS
do     
   # Divert notification monitor update to log file
   dbus-monitor "interface='org.freedesktop.Notifications'" |\
      grep --line-buffered "string" |\
      grep --line-buffered -e method -e ":" -e '""' -e urgency -e notify -v |\
      grep --line-buffered '.*(?=string)|(?<=string).*' -oPi |\
      grep --line-buffered -v '^\s*$' |\
      #xargs -d '\n' -I '{}' espeak '{}'\
      xargs -d '\n' -I '{}'\
      printf "---$(date)---\n"{}"\n" > $NOTIFBUF &

   # Read buffer text file for keyword filter
while read -r line; do      
   	for KEYWORD in "${NOTIF[@]}"; do
   			if echo "${line}" | grep "$KEYWORD"; then
   				if [ "$KEYWORD" = "@mentioned you" ] || [ "$KEYWORD" = "@mentioned all" ] 
                  notify-send "Notification with $line"
         			break 2  
         		fi
         		   				
         	fi
      done
done < "$NOTIFBUF" 

sleep 0.01s
done
