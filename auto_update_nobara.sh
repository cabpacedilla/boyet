#!/usr/bin/bash
# This script will automatically upgrade upgradeable packages in Fedora.
# Modified from original script by Claive Alvin P. Acedilla.
# Runs as soon as any updates are available.

LOGFILE=~/bin/update_log.txt

while true; do
    LIST=~/bin/upgradeable.txt

    notify-send "Auto-updates" "Checking system updates."

    # Check for updates and store in temp file, skipping first two lines
    sudo dnf check-update > "$LIST.tmp"
    if [ $? -eq 100 ]; then  # DNF returns 100 if updates are available
        # Skip the first two lines and empty lines, get package names and versions
        sed '1,2d' "$LIST.tmp" | grep -v '^$' > "$LIST"
        UPGRADES=$(wc -l < "$LIST")

        if [ "$UPGRADES" -gt 0 ]; then
            # Get full list of packages for notification
            NOTIFY_PACKAGES=$(awk '{printf "%s %s\n", $1, $2}' "$LIST")

            notify-send "Auto-updates" "Updates available for:\n${NOTIFY_PACKAGES}"
            notify-send "Auto-updates" "Starting update process..."

            # First attempt to upgrade
            if sudo dnf upgrade --refresh --no-best -y; then
                notify-send "Auto-updates" "Auto-removing unused packages"
                sudo dnf -y autoremove
                sudo dnf clean all
                notify-send "Auto-updates" "$UPGRADES packages were updated.\nSystem is up to date."

                # Log updates with timestamp
                echo "$(date '+%Y-%m-%d %H:%M:%S') - Updated Packages:" >> "$LOGFILE"
                awk '{printf "%s %s\n", $1, $2}' "$LIST" >> "$LOGFILE"
                echo "-----------------------------------" >> "$LOGFILE"
            else
                notify-send "Auto-updates" "Upgrade failed even after retry. Manual intervention required."
            fi
        fi
    else
        notify-send "Auto-updates" "System is already up to date."
    fi
    # Clean up temporary file
    rm -f "$LIST.tmp"

    # Sleep for 8 hours before checking again
    sleep 4h
done
