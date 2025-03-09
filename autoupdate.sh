#!/usr/bin/bash
# This script will automatically upgrade upgradeable packages in Debian-based systems.
# Modified from original script by Claive Alvin P. Acedilla.
# Runs as soon as any updates are available and includes security updates of pinned packages.
# Steps
# 1. Create a bin directory inside your home directory
# 2. Add the bin PATH in ~/.profile on the export PATH line: export PATH="$PATH:~/bin"
# 3. Change directory to the bin directory
# 4. Create the bash script file below with nano or gedit and save it with a filename like autoupdate_debian.sh
# 5. Make file executable with chmod +x autoupdate_debian.sh command
# 6. Create the update log and upgradeable list files in a scrtiptlogs folder in home directory
# 7. Add the autoupdate_debian.sh command in Startup applications

LOGFILE=~/scriptlogs/update_log.txt
LIST=~/scriptlogs/upgradeable.txt
PINNED_PACKAGES=("audacity" "falkon" "geany" "gimp" "inkscape" "libreoffice" "rsync" "thunderbird" "mpv" "vim" "vlc")
NON_SECURITY_COUNT=0

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
        if sudo dnf check-update --security | grep -q "$pkg"; then
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
            FILTERED_LIST=""

            # Unpin packages if there are security updates
            if check_security_updates; then
                notify-send "Security Updates" "Security updates available for pinned packages: ${SEC_UPDATES_PINNED_PKGS[*]}. Applying security updates of pinned packages..."
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
                    NON_SECURITY_COUNT=$((NON_SECURITY_COUNT + 1))
                fi
            done < "$LIST"

            # Notify-send the content of $LIST
            NOTIFY_PACKAGES=$(cat "$LIST")
            notify-send "Updates for pinned packages" "$NOTIFY_PACKAGES"

            # Log filtered packages for debugging
            echo "Filtered list of packages to upgrade: $FILTERED_LIST" >> "$LOGFILE"
            echo "Number of non-security packages to be updated: $NON_SECURITY_COUNT" >> "$LOGFILE"

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
                    notify-send "Auto-updates" "$NON_SECURITY_COUNT mon-security upgrades applied successfully."

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

