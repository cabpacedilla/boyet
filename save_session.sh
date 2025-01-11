run_session.sh script
#!/usr/bin/bash
UNIQAPPS=~/bin/uniq_apps.txt

# Check if the file exists and is not empty
if [ ! -s "$UNIQAPPS" ]; then
    :
fi

launch_app() {
    nohup "$@" > /dev/null 2>&1 &
    # Add small delay between launches
    sleep 0.5  
}

while read -r line; do 
    line=$(echo "$line" | sed 's/[[:space:]]*$//')  # Trim trailing spaces
    echo "$line"
    if [ "${line}" = "/usr/bin/lxqt-panel" ] || [ "${line}" = "/usr/bin/lxqt-leave --logout" ] || [ "${line}" = "/usr/bin/lxqt-leave --reboot" ] || [ "${line}" = "/usr/bin/lxqt-leave --shutdown" ] || [ "${line}" = "/usr/bin/lxqt-leave --suspend" ]; then
        :
    else
        eval "${line}"  &>/dev/null &
    fi                             
done < "$UNIQAPPS"

# Run save_session.sh from the current directory
save_session.sh &

save_session.sh script
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
