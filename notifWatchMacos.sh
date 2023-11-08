#!/usr/bin/env bash
# Set user in /etc/sudoers file without providing password with rsync command
# add line <username> ALL=(ALL) NOPASSWD: /usr/bin/rsync

# Needs filesystem change monitoring tool like inotify in Linux
#SRC_DIR="/private/var/root"
SRC_DIR="/private/var/folders/ql/6lc79_dd3t58x2zm3v9qzv040000gn/T/.LINKS"
SRC_FILE="/private/var/folders/ql/6lc79_dd3t58x2zm3v9qzv040000gn/0/com.apple.notificationcenter/db2/db-wal"

while sudo /opt/local/bin/fswatch "$SRC_DIR" | osascript -e "display notification \"Watching for messages.\" with title \"Message notification:    $TIME\""; do
	TIME=$(date +"%I:%M %p")
    if [ $? = 0 ]; then
        RECEIVED_MESSAGE=$(grep -a "received" "$SRC_FILE"  | tail -1)
        RECEIVED_MESSAGE=${RECEIVED_MESSAGE#*received}
        RECEIVED_MESSAGE=${RECEIVED_MESSAGE%#A*}
	    osascript -e "display notification \"$RECEIVED_MESSAGE.\" with title \"Message notification:    $TIME\""
	fi
done

