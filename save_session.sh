run_session.sh
#!/usr/bin/bash

UNIQAPPS=~/Documents/bin/uniq_apps.txt

while read -r line; do 
    line=$(echo "$line" | sed 's/[[:space:]]*$//')  # Trim trailing spaces
    echo "$line"
    if [ "${line}" = "konsole -e /home/claiveapa/Documents/bin/recentFiles.sh" ] || 
       [ "${line}" = "/usr/bin/plasmashell --no-respawn" ]; then
        :
    elif [ "${line}" = "/usr/bin/vlc --started-from-file" ]; then
        vlc &>/dev/null &	
    elif [ "${line}" = "/usr/bin/python3 /usr/bin/catfish" ]; then
        catfish &>/dev/null &
    elif [ "${line}" = "/usr/bin/simplescreenrecorder --logfile" ]; then
        simplescreenrecorder &>/dev/null &
    elif [ "${line}" = "/usr/lib64/libreoffice/program/soffice.bin --writer --splash-pipe=5" ]; then
        /usr/lib64/libreoffice/program/soffice.bin --writer &>/dev/null &
    elif [ "${line}" = "/usr/lib64/libreoffice/program/soffice.bin --calc --splash-pipe=5" ]; then
        /usr/lib64/libreoffice/program/soffice.bin --calc &>/dev/null &
    else
        eval "${line}"  &>/dev/null &  # Use eval to run the command
    fi                             
done < "$UNIQAPPS"
save_session.sh &

save_session.sh
#!/usr/bin/bash
while true; do

LAST_PIDS=~/bin/last_pids.txt
LAST_APPS=~/bin/last_apps.txt
NEW_APPS=~/bin/new_apps.txt
UNIQ_APPS=~/bin/uniq_apps.txt

> "$LAST_PIDS"

wmctrl -lp | awk '{print $3}' > "$LAST_PIDS"

> "$NEW_APPS" 

while read -r line; do 
	if [ "${line}" = "0" ]; then
		echo "xfe" >> "$NEW_APPS" 
	elif [ "${line}" = "grep" ] || [ "${line}" = "CMD" ]; then
		:
	else    
		ps -o cmd fp "${line}" | grep / >> "$NEW_APPS"      
		#ps -ux | grep "${line}" | awk '{ print $11 }' >> "$NEW_APPS"
	fi            
done < "$LAST_PIDS"

diff "$NEW_APPS" "$LAST_APPS" 

if [ $(echo $?) = "0" ]; then
	:
else
	cat "$NEW_APPS" > "$LAST_APPS" 
	sort "$LAST_APPS" > "$UNIQ_APPS"      
fi

sleep 2s 
done
