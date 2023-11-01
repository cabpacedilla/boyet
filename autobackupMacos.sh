#!/usr/bin/env bash
#while true; do
# Set user in /etc/sudoers file without providing password with rsync command
# add line <username> ALL=(ALL) NOPASSWD: /usr/bin/rsync

# Needs filesystem change monitoring tool like inotify in Linux
SRC_DIR="/Users/mini001/Documents/Claive/"
DST_DIR="/Users/mini001/Documents/backup_claive"
TIME=$(date +"%I:%M %p")

while /opt/local/bin/fswatch -o -r "$SRC_DIR" | osascript -e "display notification \"Watching folder for changes.\" with title \"Backup sync:    $TIME\""; do 
#xargs -n1 -I{} rsync -avl "$SRC_DIR"  "$DST_DIR"; 
	echo $?
	if [ $? = 0 ]; then
		osascript -e "display notification \"Folder was updated. Syncing folder.\" with title \"Backup sync:    $TIME\""
        rsync -avl "$SRC_DIR"  "$DST_DIR" 
        if [ $? = 0 ]; then
            osascript -e "display notification \"Backup sync was successful.\" with title \"Backup sync:    $TIME\""
        else 
		    osascript -e "display notification \"Backup sync encountered an error.\" with title \"Backup sync:    $TIME\""
        fi
	fi
done
