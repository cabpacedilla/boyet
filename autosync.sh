#!/usr/bin/bash
# Set user in /etc/sudoers file without providing password with rsync command
# add line <username> ALL=(ALL) NOPASSWD: /usr/bin/rsync

while inotifywait -r -e modify,create /home/claiveapa/Documents/; do
	BACKUP_TIME=$(date +"%I:%M %p")
	rsync -avz --protect-args "/home/claiveapa/Documents/" "/run/media/claiveapa/Data/claive/Documents/nobara/kde42/"
    STATUS=$?

    if [[ $STATUS -eq 0 || $STATUS -eq 24 ]]; then
        notify-send --app-name "✅ Auto-backup: $BACKUP_TIME" "Backup sync was successful." &
    else
        notify-send --app-name "⚠️ Auto-backup: $BACKUP_TIME" "Backup sync encountered an error (code $STATUS)." &
    fi
done
