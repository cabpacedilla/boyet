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
# 6. Add the autoupdate_debian.sh command in Startup applications

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
    for pkg in "${PINNED_PACKAGES[@]}"; do
        sudo apt-mark unhold "$pkg"
    done
}

# Function to pin packages back
pin_packages() {
    for pkg in "${PINNED_PACKAGES[@]}"; do
        sudo apt-mark hold "$pkg"
    done
}

# Function to check for security updates
check_security_updates() {
    sudo apt update > /dev/null
    for pkg in "${PINNED_PACKAGES[@]}"; do
        if apt list --upgradable 2>/dev/null | grep -q "$pkg"; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Security update available for $pkg" >> "$LOGFILE"
            return 0  # Security update found
        fi
    done
    return 1  # No security updates found
}

while true; do
    notify-send "Auto-updates" "Checking system updates."

    # Check for updates and store in temp file
    sudo apt update > "$LIST.tmp"
    sudo apt upgrade -s | grep "^Inst" > "$LIST"

    UPGRADES=$(wc -l < "$LIST")

    if [ "$UPGRADES" -gt 0 ]; then
        NOTIFY_PACKAGES=$(awk '{print $2}' "$LIST")

        notify-send "Auto-updates" "Updates available:\n${NOTIFY_PACKAGES}"
        notify-send "Auto-updates" "Starting update process..."

        # Unpin packages if there are security updates
        if check_security_updates; then
            unpin_packages
            notify-send "Security Updates" "Security updates available. Applying updates..."
            sudo apt upgrade -y >> "$LOGFILE"
            notify-send "Security Updates" "Security updates applied successfully."
            pin_packages
        fi

        # Apply general updates
        if sudo apt upgrade -y >> "$LOGFILE"; then
            notify-send "Auto-updates" "Auto-removing unused packages"
            sudo apt autoremove -y >> "$LOGFILE"
            sudo apt clean >> "$LOGFILE"
            notify-send "Auto-updates" "$UPGRADES packages were updated.\nSystem is up to date."

            echo "$(date '+%Y-%m-%d %H:%M:%S') - Updated Packages:" >> "$LOGFILE"
            awk '{print $2}' "$LIST" >> "$LOGFILE"
            echo "-----------------------------------" >> "$LOGFILE"
        else
            notify-send "Auto-updates" "Upgrade failed! Check $LOGFILE."
            echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: Upgrade failed!" >> "$LOGFILE"
        fi
    else
        notify-send "Auto-updates" "System is already up to date."
    fi

    rm -f "$LIST.tmp"  # Ensure temp file cleanup

    sleep 1h  # Wait before next check
done
