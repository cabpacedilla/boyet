#!/usr/bin/bash
# This script will automatically upgrade upgradeable packages in Fedora.
# Modified from original script by Claive Alvin P. Acedilla.
# Runs as soon as any updates are available and include security updates of pinned packages.

LOGFILE=~/scriptlogs/update_log.txt
LIST=~/scriptlogs/upgradeable.txt
PINNED_PACKAGES=("vim" "gimp" "falkon" "geany" "libreoffice" "audacity" "inkscape")

# Function to clean up temporary files
cleanup() {
    rm -f "$LIST.tmp"
    notify-send "Auto-updates" "Update terminated. Cleaned up temporary files."
}
trap cleanup EXIT  # Ensures cleanup on exit

# Function to unpin packages
unpin_packages() {
    sudo sed -i '/exclude=/d' /etc/dnf/dnf.conf
}

# Function to pin packages back
pin_packages() {
    echo "exclude=${PINNED_PACKAGES[*]}" | sudo tee -a /etc/dnf/dnf.conf
}

# Function to check for security updates
check_security_updates() {
    for pkg in "${PINNED_PACKAGES[@]}"; do
        if sudo dnf --security check-update "$pkg" | grep -q 'Security'; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Security update available for $pkg" >> "$LOGFILE"
            return 0  # Security update found
        fi
    done
    return 1  # No security updates found
}

while true; do
    notify-send "Auto-updates" "Checking system updates."

    # Check for updates and store in temp file, skipping first two lines
    sudo dnf check-update > "$LIST.tmp"
    CHECK_EXIT=$?

    if [ $CHECK_EXIT -eq 100 ]; then  # Updates available
        sed '1,2d' "$LIST.tmp" | grep -v '^$' > "$LIST"
        UPGRADES=$(wc -l < "$LIST")

        if [ "$UPGRADES" -gt 0 ]; then
            NOTIFY_PACKAGES=$(awk '{printf "%s %s\n", $1, $2}' "$LIST")

            notify-send "Auto-updates" "Updates available:\n${NOTIFY_PACKAGES}"
            notify-send "Auto-updates" "Starting update process..."

            # Unpin packages if there are security updates
            if check_security_updates; then
                unpin_packages
                notify-send "Security Updates" "Security updates available. Applying updates..."
                sudo dnf upgrade --security -y 2>> "$LOGFILE"
                notify-send "Security Updates" "Security updates applied successfully."
                pin_packages
            fi

            # First attempt to upgrade
            if sudo dnf upgrade --refresh --no-best -y 2>> "$LOGFILE"; then
                notify-send "Auto-updates" "Auto-removing unused packages"
                sudo dnf -y autoremove 2>> "$LOGFILE"
                sudo dnf clean all 2>> "$LOGFILE"
                notify-send "Auto-updates" "$UPGRADES packages were updated.\nSystem is up to date."

                echo "$(date '+%Y-%m-%d %H:%M:%S') - Updated Packages:" >> "$LOGFILE"
                awk '{printf "%s %s\n", $1, $2}' "$LIST" >> "$LOGFILE"
                echo "-----------------------------------" >> "$LOGFILE"
            else
                notify-send "Auto-updates" "Upgrade failed! Check $LOGFILE."
                echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: Upgrade failed!" >> "$LOGFILE"
            fi
        fi
    elif [ $CHECK_EXIT -eq 0 ]; then
        notify-send "Auto-updates" "System is already up to date."
    else
        notify-send "Auto-updates" "Error checking for updates! See $LOGFILE."
        echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: dnf check-update failed with exit code $CHECK_EXIT" >> "$LOGFILE"
    fi

    rm -f "$LIST.tmp"  # Ensure temp file cleanup

    sleep 1h  # Wait before next check
done

