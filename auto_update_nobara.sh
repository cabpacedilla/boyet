#!/usr/bin/bash
# This script will automatically upgrade upgradeable packages in Fedora.
# Modified from original script by Claive Alvin P. Acedilla.
# Runs as soon as any updates are available and includes security updates of pinned packages.

LOGFILE=~/scriptlogs/update_log.txt
LIST=~/scriptlogs/upgradeable.txt
PINNED_PACKAGES=("audacity" "falkon" "geany" "gimp" "inkscape" "libreoffice" "rsync" "thunderbird" "mpv" "vim" "vlc")

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
    local SEC_UPDATES_PINNED_PKGS=()
    for pkg in "${PINNED_PACKAGES[@]}"; do
        if sudo dnf check-update --security | grep -q "$pkg" ; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Security update available for $pkg" >> "$LOGFILE"
            SEC_UPDATES_PINNED_PKGS+=("$pkg")
        fi
    done

    if [ ${#SEC_UPDATES_PINNED_PKGS[@]} -gt 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Security updates available for pinned packages: ${SEC_UPDATES_PINNED_PKGS[*]}" >> "$LOGFILE"
        return 0  # Security update found
    else
        return 1  # No security updates found
    fi
}

while true; do
    notify-send "Auto-updates" "Checking system updates."

    # Check for updates and store in temp file, skipping first two lines
    sudo dnf check-update > "$LIST.tmp"
    CHECK_EXIT=$?

    if [ $CHECK_EXIT -eq 100 ]; then  # Updates available
        # Process the temporary list
        sed '1,2d' "$LIST.tmp" | grep -v '^$' > "$LIST"
        UPGRADES=$(wc -l < "$LIST")

        if [ "$UPGRADES" -gt 0 ]; then
            # Call the function to filter pinned packages
            # Call the function to filter pinned packages
            FILTERED_LIST=""

            # Unpin packages if there are security updates
            if check_security_updates; then
                notify-send "Security Updates" "Security updates available for pinned packages: ${SEC_UPDATES_PINNED_PKGS[*]}. Applying security updates for pinned packages..."
                unpin_packages
                sudo dnf upgrade --security -y 2>> "$LOGFILE"
                notify-send "Security Updates" "Security updates of pinned packages applied successfully."
                pin_packages
            else
                notify-send "Auto-updates" "No security updates of pinned packages found."
            fi

            while read -r line; do
                include=true
                for pinned in "${PINNED_PACKAGES[@]}"; do
                    # Check if the package name matches any pinned package
                    if echo "$line" | grep -q "$pinned"; then
                        include=false
                        break
                    fi
                done
                if [ "$include" = true ]; then
                    FILTERED_LIST+="$line"$'\n'
                fi
            done < "$LIST"  # Make sure we are reading the contents of $LIST (not the file path)

            # Notify-send the content of $LIST
            NOTIFY_PACKAGES=$(cat "$LIST")
            notify-send "Updates of pinned packages" "$NOTIFY_PACKAGES"

            # Log filtered packages for debugging
            echo "Filtered list of packages to upgrade: $FILTERED_LIST" >> "$LOGFILE"

            # If there are any packages to upgrade, proceed
            if [ -n "$FILTERED_LIST" ]; then
                NOTIFY_PACKAGES=$(echo "$FILTERED_LIST" | awk '{printf "%s %s\n", $1, $2}')
                notify-send "Auto-updates" "Updates available (excluding pinned packages):\n${NOTIFY_PACKAGES}"
                notify-send "Auto-updates" "Starting update process..."

                # Perform the upgrade for non-pinned packages
                if sudo dnf upgrade --refresh --no-best -y $(echo "$FILTERED_LIST" | awk '{print $1}') 2>> "$LOGFILE"; then
                    notify-send "Auto-updates" "Auto-removing unused packages"
                    sudo dnf -y autoremove 2>> "$LOGFILE"
                    sudo dnf clean all 2>> "$LOGFILE"
                    notify-send "Auto-updates" "Non-security upgrades applied successfully."

                    echo "$(date '+%Y-%m-%d %H:%M:%S') - Updated Packages:" >> "$LOGFILE"
                    echo "$FILTERED_LIST" >> "$LOGFILE"
                    echo "-----------------------------------" >> "$LOGFILE"
                else
                    notify-send "Auto-updates" "Upgrade failed! Check $LOGFILE."
                    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: Upgrade failed!" >> "$LOGFILE"
                fi
            else
                notify-send "Auto-updates" "No packages to upgrade."
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
