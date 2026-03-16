#!/usr/bin/env bash
# Set user in /etc/sudoers file without providing password with rsync command
# add line <username> ALL=(ALL) NOPASSWD: /usr/bin/rsync

LOCK_FILE="/tmp/autosync_$(whoami).lock"
exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
    exit 1
fi

# Store our PID
echo $$ > "$LOCK_FILE"

# Enhanced cleanup that only removes our PID file
cleanup() {
    # Only remove if it's our PID (prevents removing another process's lock)
    if [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$$" ]]; then
        rm -f "$LOCK_FILE"
    fi
    flock -u 9
    exec 9>&-
}

trap cleanup EXIT

while inotifywait -r -e modify,create /home/claiveapa/Documents/; do
	BACKUP_TIME=$(date +"%I:%M %p")
	rsync -a --protect-args --delete \
      --backup --backup-dir="/run/media/claiveapa/Data/claive/Documents/nobara/kde42/backups/$(date +%F)" \
      --exclude='*.swp' --exclude='*.swo' --exclude='*.swx' --exclude='*~' \
      --exclude='*.tmp' --exclude='*.bak' --exclude='*.autosave' --exclude='*.part' --exclude='*.crdownload' \
      "/home/claiveapa/Documents/" "/run/media/claiveapa/Data/claive/Documents/nobara/kde42/main/"
    STATUS=$?

    if [[ $STATUS -eq 0 || $STATUS -eq 24 || $STATUS -eq 23 ]]; then
        notify-send --app-name "✅ Auto-backup: $BACKUP_TIME" "Backup sync was successful (code $STATUS)."
    else
        notify-send --app-name "⚠️ Auto-backup: $BACKUP_TIME" "Backup sync encountered errors (code $STATUS)."
    fi
done
