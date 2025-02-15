#!/usr/bin/bash
# This script will automatically upgrade upgradeable packages in Fedora.
# Modified from original script by Claive Alvin P. Acedilla.
# Runs every two months (on the 15th of odd-numbered months)

while true; do
    LIST=~/bin/upgradeable.txt
    MONTH=$(date +%-m)
    DATE=$(date +%-d)

    # Check if it's the 15th of an odd-numbered month
    if [ "$DATE" = "15" ]; then
        notify-send "Auto-updates" "Checking system updates."

        # Check for updates and store in temp file, skipping first two lines
        sudo dnf check-update > "$LIST.tmp"
        if [ $? -eq 100 ]; then  # DNF returns 100 if updates are available
            # Skip the first two lines and empty lines, get package names
            sed '1,2d' "$LIST.tmp" | grep -v '^$' > "$LIST"
            UPGRADES=$(wc -l < "$LIST")

            if [ "$UPGRADES" -gt 0 ]; then
                # Get full list of packages for notification
                NOTIFY_PACKAGES=$(awk '{printf "%s\n", $1}' "$LIST")

                notify-send "Auto-updates" "Updates available for:\n${NOTIFY_PACKAGES}"
                notify-send "Auto-updates" "Starting update process..."

                # Clean cache and retry
                #sudo dnf clean all
                #sudo dnf makecache --refresh

                # First attempt to upgrade
                if sudo dnf upgrade --refresh --no-best -y; then
                    notify-send "Auto-updates:" "Auto-removing and auto-cleaning package updates"
                    sudo dnf -y autoremove
                    sudo dnf clean all
                    notify-send "Auto-updates" "$UPGRADES packages were updated.\nSystem is up to date."
                else
                    notify-send "Auto-updates" "Upgrade failed even after retry. Manual intervention required."
                fi
            fi
        fi
    else
        notify-send "Auto-updates" "System is already up to date."
    fi
    # Clean up temporary file
    rm -f "$LIST.tmp"

    # Sleep for 8 hours before checking again
    sleep 8h
done
