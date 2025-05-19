#!/usr/bin/bash
# This script will automatically update updateable packages in Nobara Linux.
# Modified from the original script by Claive Alvin P. Acedilla.
# Runs as soon as any updates are available and includes security updates of pinned packages.

LOGFILE_GENERAL=~/scriptlogs/general_update_log.txt
LOGFILE_PINNED=~/scriptlogs/pinned_pkgs_update_log.txt
SEC_LOGFILE_PINNED=~/scriptlogs/sec_pinned_pkgs_update_log.txt
FILTERED_LOGFILE=~/scriptlogs/filtered_pkgs_update_log.txt
LIST=~/scriptlogs/updateable.txt
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
    SEC_UPDATES_PINNED_PKGS=()
    for pkg in "${PINNED_PACKAGES[@]}"; do
        if sudo dnf check-update --security | grep -q "$pkg"; then
            notify-send "Security update available for $pkg"
            SEC_UPDATES_PINNED_PKGS+=("$pkg")
        fi
    done

    if [ ${#SEC_UPDATES_PINNED_PKGS[@]} -gt 0 ]; then
        echo "${SEC_UPDATES_PINNED_PKGS[@]}"  # Security update found
    else
        return 1  # No security updates found
    fi
}

NON_SECURITY_COUNT=0

while true; do
    notify-send -t 0 "Auto-updates" "Checking system updates."

    # Check for updates and store in temp file, skipping first two lines
    sudo dnf update nobara-updater --refresh -y
    sudo dnf check-update > "$LIST.tmp"
    CHECK_EXIT=$?

    if [ $CHECK_EXIT -eq 100 ]; then  # Updates available
        # Process the temporary list
        cat "$LIST.tmp" > "$LIST"
        UPDATES=$(wc -l < "$LIST")

        if [ "$UPDATES" -gt 0 ]; then
            FILTERED_LIST=""

            # Unpin packages if there are security updates
            if check_security_updates; then
            timestamp=$(date '+%Y-%m-%d %H:%M:%S')
            notify-send -t 0 "Security Updates" "Security updates available for pinned packages: ${SEC_UPDATES_PINNED_PKGS[*]}. Applying updates..."

            unpin_packages
            for pkg in "${SEC_UPDATES_PINNED_PKGS[@]}"; do
                if sudo dnf upgrade --security -y "$pkg" 2>> "$SEC_LOGFILE_PINNED"; then
                    if rpm -q "$pkg" &>/dev/null; then
                        echo "$timestamp - Security update applied successfully: $pkg" >> "$SEC_LOGFILE_PINNED"
                        notify-send "Security Updates" "$pkg updated successfully."
                    else
                        echo "$timestamp - ERROR: $pkg failed to install after upgrade." >> "$SEC_LOGFILE_PINNED"
                        notify-send -t 0 "Security Updates" "ERROR: $pkg failed to install after upgrade."
                    fi
                else
                    echo "$timestamp - ERROR: Failed to apply security update to $pkg" >> "$SEC_LOGFILE_PINNED"
                    notify-send -t 0 "Security Updates" "ERROR: Failed to apply security update to $pkg" >> "$SEC_LOGFILE_PINNED"
                fi
            done

            echo "$(date '+%Y-%m-%d %H:%M:%S') - Security updates of pinned packages: ${SEC_UPDATES_PINNED_PKGS[@]} applied successfully." >> "$SEC_LOGFILE_PINNED"
            notify-send -t 0 "Security Updates" "Security updates of pinned packages: ${SEC_UPDATES_PINNED_PKGS[@]} applied successfully."
            pin_packages
            else
                notify-send -t 0 "Auto-updates" "No security updates of pinned packages found."
            fi

            > $LOGFILE_PINNED
            while read -r line; do
                include=true
                for pinned in "${PINNED_PACKAGES[@]}"; do
                    # Check if the package name matches any pinned package
                    if echo "$line" | grep "$pinned"; then
                        include=false
                        echo "$(date '+%Y-%m-%d %H:%M:%S') - Pinned package update: $line" >> "$LOGFILE_PINNED"
                        continue
                    fi
                done

                if [ "$include" = true ]; then
                    FILTERED_LIST+="$line"$'\n'
                    NON_SECURITY_COUNT=$((NON_SECURITY_COUNT + 1))
                fi
            done < "$LIST"

            # Log filtered packages for debugging
            echo "Number of non-security packages to be updated: $NON_SECURITY_COUNT" >> "$LOGFILE_GENERAL"
            echo "Filtered list of packages to update: $FILTERED_LIST" >> "$LOGFILE_GENERAL"

            # If there are any packages to update, proceed
            if [ -n "$FILTERED_LIST" ]; then
                NOTIFY_PACKAGES=$(echo "$FILTERED_LIST" | awk '{printf "%s %s\n", $1, $2}')
                notify-send "Auto-updates" "Number of non-security packages to be updated: $NON_SECURITY_COUNT\nUpdates available (excluding pinned packages):\n${NOTIFY_PACKAGES}"
                notify-send -t 0 "Auto-updates" "Update in progress..."

                CTR=0
                # Process each package one at a time
                while read -r package; do
                    # Extract the package name from each line (first word)
                    #package_name=$(echo "$package" | awk -F '-' '{print $1}')
                    package_name=$(echo "$package" | awk '{print $1}')
                    if [ "$CTR" -gt "$NON_SECURITY_COUNT" ]; then
                        break
                    elif [ "$package_name" = "Obsoleting" ] || [ "$package_name" = "" ]; then
                        break
                    fi

                    # Perform the update for each package
#                   if sudo dnf upgrade --skip-unavailable --no-best --allowerasing -y "$package_name" 2>> "$LOGFILE_GENERAL"; then
                    if notify-send "Auto-updates" "Updating package $package_name" && \
                        sudo dnf update --allowerasing -y "$package_name" 2>> "$LOGFILE_GENERAL"; then
                        # Verify successful installation
                        if rpm -q "$package_name" &>/dev/null; then
                            UPDATED_PILTERED_PKGS+=("$package_name")
                            echo "$(date '+%Y-%m-%d %H:%M:%S') -" "Auto-updates" "$package_name updated successfully." >> "$LOGFILE_GENERAL"
                            echo "$(date '+%Y-%m-%d %H:%M:%S') -" "Auto-updates" "$package_name updated successfully." >> "$FILTERED_LOGFILE"
                            notify-send "Auto-updates" "$package_name updated successfully."
                            CTR=$((CTR + 1))
                            if [ "$CTR" -gt "$NON_SECURITY_COUNT" ] && [ "$package_name" = "Obsoleting" ]; then
                                break
                            else
                                continue
                            fi
                        else
                            notify-send "Auto-updates" "Error: $package_name failed to update. Check logs."
                        fi
                    else
                        notify-send "Auto-updates" "Error during update of $package_name. Check logs."
                    fi
                done <<< "$FILTERED_LIST"

                if [ ${#UPDATED_PILTERED_PKGS[@]} -gt 0 ]; then
                    declare -A unique_items # Create an associative array
                    for pkg in "${UPDATED_PILTERED_PKGS[@]}"; do
                        unique_items["$pkg"]=1 # Add each item as a key
                    done

                    local keys=("${!unique_items[@]}")

                    # Join the unique items into a newline-separated string
                    IFS=$'\n'
                    UPDATED_LIST=$(printf "%s\n" "${keys[@]}" | sort)
                    unset IFS # Reset IFS to default
                    notify-send -t 0 "Auto-updates" "System is updated. The following packages were successfully updated:\n$UPDATED_LIST"
                    UPDATED_LIST=()
                else
                    notify-send "Auto-updates" "No packages were updated."
                fi

                # Remove unused packages
                if sudo dnf -y autoremove 2>> "$LOGFILE_GENERAL"; then
                    # Notify user about autoremove
                    echo "Auto-updates" "Auto-removed unused packages" >> "$LOGFILE_GENERAL"
                    notify-send "Auto-updates" "Auto-removed unused packages"
                else
                    # Error handling for autoremove
                    notify-send "Auto-updates" "Error during autoremove. Check logs."
                fi

                # Clean up package manager cache
                if sudo dnf clean all 2>> "$LOGFILE_GENERAL"; then
                    # Notify user about cleanup
                    echo "Auto-updates" "Package manager cache cleaned" >> "$LOGFILE_GENERAL"
                else
                    # Error handling for cache cleanup
                    notify-send "Auto-updates" "Error during cache cleanup. Check logs."
                fi
            else
                notify-send "Auto-updates" "No packages to updated."
            fi
        fi
    elif [ $CHECK_EXIT -eq 0 ]; then
        notify-send -t 0 "Auto-updates" "System is already up to date."
    else
        notify-send "Auto-updates" "Error checking for updates! See $LOGFILE_GENERAL."
        echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: dnf check-update failed with exit code $CHECK_EXIT" >> "$LOGFILE_GENERAL"
    fi

    rm -f "$LIST.tmp"  # Ensure temp file cleanup
    sleep 1h  # Wait before next check
done

