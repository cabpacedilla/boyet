run_session.sh
#!/usr/bin/bash

UNIQAPPS=~/bin/uniq_apps.txt

while read -r  line; do 
	#if grep "${line}" "$MENUAPPS"; then
	if [ "${line}" = "/usr/bin/lxqt-panel" ]; then
		:
	else
		"${line}" &
	fi                             
done  < "$UNIQAPPS"
 
save_session.sh &


save_session.sh
#!/usr/bin/bash
while true; do

LAST_PIDS=~/bin/last_pids.txt
LAST_APPS=~/bin/last_apps.txt
UNIQ_APPS=~/bin/uniq_apps.txt

> "$LAST_PIDS"

wmctrl -lp | awk '{print $3}' > "$LAST_PIDS"

> "$LAST_APPS"

while read -r  line; do 
	ps -ux | grep "${line}" | awk '{ print $11 }' >> "$LAST_APPS"             
	sort "$LAST_APPS" | uniq > "$UNIQ_APPS"             
done < "$LAST_PIDS"

sleep 2s
done

