#!/usr/bin/bash
while true
do
   EMAIL=cabapacedilla@gmail.com
   NOTIFLOGS=~/bin/notiflogs.txt
   NOTIFBUF=~/bin/notifbuf.txt
    
   NOTIF=("Thunderbird" "@mentioned you" "mentioned all")
  
   # Listen log file change
   # gnome-terminal -- inotifywait -e modify $NOTIFLOGS &
  
   # Divert notification monitor update to log file
   #dbus-monitor "interface='g.freedesktop.Notifications'" |\
   # grep --line-buffered  "member=Notify\|string" |\
   #grep --line-buffered "string" |\
  dbus-monitor "interface='org.freedesktop.Notifications'" |\
   grep --line-buffered "string" |\
   grep --line-buffered -e method -e ":" -e '""' -e urgency -e notify -v |\
   grep --line-buffered '.*(?=string)|(?<=string).*' -oPi |\
   grep --line-buffered -v '^\s*$' |\
   #xargs -d '\n' -I '{}' espeak '{}'\
   xargs -d '\n' -I '{}'\
   printf "---$( date )---\n"{}"\n" > $NOTIFLOGS &
  
   # Send mail every time log file is changed
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
                  if [ "$KEYWORD" = "Thunderbird" ]
                  then
                     break
                    
                    #${KEYMESSAGE[${KEYWORD}]}
                  elif [ "$KEYWORD" = "@mentioned you" ] [ "$KEYWORD" = "mentioned all" ]
                  then 
                     echo "Sending email..."
                     mail -s "Notification from $KEYWORD" $EMAIL < $NOTIFBUF     
                    
                     MAIL_WIN=$(wmctrl -lp | grep Thunderbird | awk '{print $1}')
                     wmctrl -ia "$MAIL_WIN"   

                     break
                  fi
                  ;;                 
            esac              
        done
     done <$NOTIFBUF
        
   # Empty text files
   >$NOTIFLOGS
   >$NOTIFBUF
    
   done
  
   sleep 0.001
done
