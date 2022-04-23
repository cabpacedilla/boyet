#!/usr/bin/bash

# This script will automatically switch to Skype or any message app when your office mate @mention you or @mention all to attend the message right away

while true
do
   NOTIFLOGS=~/bin/notiflogs.txt
   NOTIFBUF=~/bin/notifbuf.txt
   
   declare -a NOTIF
   NOTIF=("@mentioned you" "mentioned all"
   
  # Divert notification monitor update to log file
  dbus-monitor "interface='org.freedesktop.Notifications'" |\
   grep --line-buffered "string" |\
   grep --line-buffered -e method -e ":" -e '""' -e urgency -e notify -v |\
   grep --line-buffered '.*(?=string)|(?<=string).*' -oPi |\
   grep --line-buffered -v '^\s*$' |\
   #xargs -d '\n' -I '{}' espeak '{}'\
   xargs -d '\n' -I '{}'\
   printf "---$(date)---\n"{}"\n" > $NOTIFLOGS &
  
   # Switch to  every time someone @mention you or @mention all
   while inotifywait -e modify $NOTIFLOGS
   do     
      # Get first 10 lines from log file and save to buffer text file
      head $NOTIFLOGS > $NOTIFBUF 
     
      # Read buffer text file for keyword filter
      while read -r line
      do     
         for KEYWORD in "${NOTIF[@]}"; do
            #echo $KEYWORD
            case "$line" in
                  *"$KEYWORD"*)
                  if [ "$KEYWORD" = "@mentioned you" ] [ "$KEYWORD" = "mentioned all" ]; then 
                     SKYPE_WIN=$(wmctrl -lp | grep Skype | awk '{print $1}')
                     wmctrl -ia "$SKYPE_WIN"   
                  fi
                  ;;                 
            esac              
        done
     done < $NOTIFBUF
         
     # Empty text files
     > $NOTIFLOGS
     > $NOTIFBUF
    
   done  
   sleep 0.01s
done
