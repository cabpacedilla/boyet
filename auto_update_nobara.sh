#!/usr/bin/bash
# This script will automatically upgrade upgradeable packages in Fedora.
# Modified from the original script by Claive Alvin P. Acedilla.
# Runs as soon as any updates are available and includes security updates of pinned packages.

LOGFILE_GENERAL=~/scriptlogs/general_update_log.txt
LOGFILE_PINNED=~/scriptlogs/pinned_update_log.txt
SEC_LOGFILE_PINNED=~/scriptlogs/sec_pinned_update_log.txt
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
        if sudo dnf check-update --security | grep -q "$pkg"; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Security update available for $pkg" >> "$SEC_LOGFILE_PINNED"
            SEC_UPDATES_PINNED_PKGS+=("$pkg")
        fi
    done

    if [ ${#SEC_UPDATES_PINNED_PKGS[@]} -gt 0 ]; then
       # echo "$(date '+%Y-%m-%d %H:%M:%S') - Security updates available for pinned packages: ${SEC_UPDATES_PINNED_PKGS[*]}" >> "$LOGFILE_PINNED"
        echo "${SEC_UPDATES_PINNED_PKGS[@]}"  # Security update found
    else
        return 1  # No security updates found
    fi
}

while true; do
    notify-send "Auto-updates" "Checking system updates."

    NON_SECURITY_COUNT=0

    # Check for updates and store in temp file, skipping first two lines
    sudo dnf update nobara-updater --refresh
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
                sudo dnf upgrade --security -y
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
                        echo "$(date '+%Y-%m-%d %H:%M:%S') - Pinned package update: $line" >> "$LOGFILE_PINNED"
                        break
                    fi
                done
                if [ "$include" = true ]; then
                    FILTERED_LIST+="$line"$'\n'
                    NON_SECURITY_COUNT=$((NON_SECURITY_COUNT + 1))
                fi
            done < "$LIST"

            # Notify-send the content of general updates for pinned packages
            NOTIFY_PACKAGES=$(cat "$LOGFILE_PINNED")
            notify-send "Updates for pinned packages" "$NOTIFY_PACKAGES"

            # Log filtered packages for debugging
            echo "Filtered list of packages to upgrade: $FILTERED_LIST" >> "$LOGFILE_GENERAL"
            echo "Number of non-security packages to be updated: $NON_SECURITY_COUNT" >> "$LOGFILE_GENERAL"

            # If there are any packages to upgrade, proceed
            if [ -n "$FILTERED_LIST" ]; then
                NOTIFY_PACKAGES=$(echo "$FILTERED_LIST" | awk '{printf "%s %s\n", $1, $2}')
                notify-send "Auto-updates" "Updates available (excluding pinned packages):\n${NOTIFY_PACKAGES}"
                notify-send "Auto-updates" "Starting update process..."

                # Process each package one at a time
                while read -r package; do
                    CTR=0
                    # Extract the package name from each line (first word)
                    package_name=$(echo "$package" | awk -F '.' '{print $1}')
                    if [ "$CTR" -ge "$NON_SECURITY_COUNT" ]; then
                        break
                    elif [ "$package_name" = "Obsoleting packages" ] || [ "$package_name" = "" ]; then
                        continue
                    fi

                    # Perform the upgrade for each package
                    if sudo dnf upgrade --skip-unavailable --no-best --allowerasing -y "$package_name" 2>> "$LOGFILE_GENERAL"; then
                        # Verify successful installation
                        if rpm -q "$package_name" &>/dev/null; then
                            notify-send "Auto-updates" "$package_name upgraded successfully."
                            CTR=$((CTR + 1))
                            if [ "$CTR" -ge "$NON_SECURITY_COUNT" ] && [ "$package_name" = "Obsoleting packages" ]; then
                                break
                            else
                                continue
                            fi
                        else
                            notify-send "Auto-updates" "Error: $package_name failed to upgrade. Check logs."
                        fi
                    else
                        notify-send "Auto-updates" "Error during upgrade of $package_name. Check logs."
                    fi
                done <<< "$FILTERED_LIST"

                # Remove unused packages
                if sudo dnf -y autoremove 2>> "$LOGFILE_GENERAL"; then
                    # Notify user about autoremove
                    notify-send "Auto-updates" "Auto-removed unused packages"
                else
                    # Error handling for autoremove
                    notify-send "Auto-updates" "Error during autoremove. Check logs."
                fi

                # Clean up package manager cache
                if sudo dnf clean all 2>> "$LOGFILE_GENERAL"; then
                    # Notify user about cleanup
                    notify-send "Auto-updates" "Package manager cache cleaned."
                else
                    # Error handling for cache cleanup
                    notify-send "Auto-updates" "Error during cache cleanup. Check logs."
                fi
            fi
        fi
    elif [ $CHECK_EXIT -eq 0 ]; then
        notify-send "Auto-updates" "System is already up to date."
    else
        notify-send "Auto-updates" "Error checking for updates! See $LOGFILE_GENERAL."
        echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: dnf check-update failed with exit code $CHECK_EXIT" >> "$LOGFILE_GENERAL"
    fi

    rm -f "$LIST.tmp"  # Ensure temp file cleanup

    sleep 1h  # Wait before next check
done
