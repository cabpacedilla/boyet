#!/usr/bin/env bash

#!/usr/bin/env bash

# ==============================================================================
# XSCREENSAVER AUTO-SYNC SCRIPT (Systemd Watcher Edition)
# ==============================================================================
# DESCRIPTION:
#   Automatically detects and copies new xscreensaver binaries from the system
#   directory (/usr/libexec/xscreensaver) to a local user folder, 
#   renaming them with a "screensaver-" prefix.
#
# SETUP INSTRUCTIONS:
#   1. Ensure the script is executable:
#      chmod +x /home/claiveapa/Documents/bin/update_screensavers.sh
#
#   2. Link or copy to a global system path (Optional but recommended):
#      sudo ln -sf /home/claiveapa/Documents/bin/update_screensavers.sh /usr/local/bin/sync-screensavers
#
#   3. Create a Systemd Service (/etc/systemd/system/sync-screensavers.service):
#      [Service]
#      Type=oneshot
#      ExecStart=/home/claiveapa/Documents/bin/update_screensavers.sh
#      User=root
#
#   4. Create a Systemd Path Watcher (/etc/systemd/system/sync-screensavers.path):
#      [Path]
#      PathChanged=/usr/libexec/xscreensaver
#      Unit=sync-screensavers.service
#
#   5. Enable the watcher:
#      sudo systemctl daemon-reload
#      sudo systemctl enable --now sync-screensavers.path
# ==============================================================================

# --- Configuration ---
#!/bin/bash

# --- Configuration ---
SOURCE_DIR="/usr/libexec/xscreensaver"
TARGET_DIR="/home/claiveapa/Documents/screensavers"
LOG_FILE="/home/claiveapa/scriptlogs/screensaver_sync_log.txt"
USER_NAME="claiveapa"

# 1. Ensure directories exist
mkdir -p "$TARGET_DIR"
mkdir -p "$(dirname "$LOG_FILE")"

# 2. Log Start & Fix Ownership of Log
echo "--- Forced Binary Sync: $(date) ---" >> "$LOG_FILE"
chown "$USER_NAME:$USER_NAME" "$LOG_FILE"

# 3. Use RSYNC with strict filters
# --delete: Removes files in TARGET that don't exist in SOURCE (kills the junk)
# --exclude: Explicitly drops Perl, Shell, and DNF temp files
# --include: Only grabs the actual files
rsync -rv --delete \
    --exclude="*;*" \
    --exclude="*.pl" \
    --exclude="*.sh" \
    --exclude="*.original" \
    --exclude="vidwhacker" \
    --exclude="webcollage" \
    --include="*" \
    "$SOURCE_DIR/" "$TARGET_DIR/"

# 4. Rename files to add the "screensaver-" prefix locally
# We do this after rsync so rsync doesn't get confused
cd "$TARGET_DIR" || exit
for f in *; do
    if [[ ! "$f" == screensaver-* ]]; then
        mv "$f" "screensaver-$f" 2>/dev/null
    fi
done

# 5. Final Permission Wipe
chown -R "$USER_NAME:$USER_NAME" "$TARGET_DIR"

echo "Sync Finished. Files in folder: $(ls "$TARGET_DIR" | wc -l)" >> "$LOG_FILE"
