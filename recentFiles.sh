#!/usr/bin/env bash
# This script is used to monitor and access recently used files
# This script was assembled written by Claive Alvin P. Acedilla. It can be copied, modified and redistributed.
# June 2024
# call script to launch in a terminal konsole -e /home/claiveapa/Documents/bin/recentFiles.sh

# Relaunch in terminal if not running interactively
if [[ ! -t 0 ]]; then
    TERMINALS=("gnome-terminal" "konsole" "xfce4-terminal" "xterm" "lxterminal" "tilix" "mate-terminal" "deepin-terminal" "alacritty" "urxvt")
    for term in "${TERMINALS[@]}"; do
        if command -v "$term" >/dev/null 2>&1; then
            "$term" -e "$0" &
            exit 0
        fi
    done
    notify-send "Error" "No supported terminal emulator found to launch script." &
    exit 1
fi

# Define file paths
RECENT_FILES_LIST="$HOME/scriptlogs/recentFiles.txt"
TAIL_LIST="$HOME/scriptlogs/reverseRecent.txt"
RECENTLY_XBEL_FILE=~/.local/share/recently-used.xbel

# Create scriptlogs directory if it doesn't exist
mkdir -p "$HOME/scriptlogs"

# Infinite loop to continuously check recent files
while true; do

	# Ensure the recently-used.xbel file exists
	if [[ ! -f "$RECENTLY_XBEL_FILE" ]]; then
		notify-send "Error" "File $RECENTLY_XBEL_FILE does not exist. Script exiting." &
		exit 1
	fi

	# Extract recent file paths from the recently-used.xbel file and cleanup path percent encoding
	# NOTE: This Bash-only approach is less robust for highly complex/multibyte
	#       UTF-8 characters or HTML/XML entities (like &amp;) compared to external tools (e.g., Python).
	#       Specifically, &amp; will NOT be converted to & by this sed chain.
	RECENT_FILES=$(grep -o 'file:///[^"]*' "$RECENTLY_XBEL_FILE" |
	sed 's|file://||' |
	# Start the sed command with its first -e, and then continue with more -e flags on subsequent lines.
	# Comments are now on their own logical lines, preventing parsing issues.
	sed -e 's/%25/%/g' \
	    -e 's/%0A/\n/g' \
	    -e 's/%20/ /g' \
	    -e 's/%21/!/g' \
	    -e 's/%22/"/g' \
	    -e 's/%23/#/g' \
	    -e 's/%24/\$/g' \
	    -e 's/%26/\&/g' \
	    -e 's/%27/'\''/g' \
	    -e 's/%28/(/g' \
	    -e 's/%29/)/g' \
	    -e 's/%2A/*/g' \
	    -e 's/%2B/+/g' \
	    -e 's/%2C/,/g' \
	    -e 's/%2D/-/g' \
	    -e 's/%2E/\./g' \
	    -e 's/%2F/\//g' \
	    -e 's/%3A/:/g' \
	    -e 's/%3B/;/g' \
	    -e 's/%3C/</g' \
	    -e 's/%3D/=/g' \
	    -e 's/%3E/>/g' \
	    -e 's/%3F/?/g' \
	    -e 's/%40/@/g' \
	    -e 's/%5B/[/g' \
	    -e 's/%5C/\\/g' \
	    -e 's/%5D/]/g' \
	    -e 's/%5E/^/g' \
	    -e 's/%5F/_/g' \
	    -e 's/%60//g' \
	    -e 's/%7B/{/g' \
	    -e 's/%7C/|/g' \
	    -e 's/%7D/}/g' \
	    -e 's/%7E/~/g' \
	    -e 's/&amp;/\&/g' \
	    -e 's/%E2%81%84/⁄/g' \
	) # End of sed chain and command substitution

	# Save recent files to RECENT_FILES_LIST
	echo "$RECENT_FILES" > "$RECENT_FILES_LIST"

	# Get the last few recent files (the most recent 40 files)
	RECENT_FILES_LAST_40=$(tail -n 40 "$RECENT_FILES_LIST")

	# Save the recent 40 files to RECENT_FILES_LIST
	echo "$RECENT_FILES_LAST_40" > "$RECENT_FILES_LIST"

	# Place recent files list to an array
	mapfile -t RECENT_FILES_ARRAY < "$RECENT_FILES_LIST"

	# Check if the array is empty
	if [ ${#RECENT_FILES_ARRAY[@]} -eq 0 ]; then
		notify-send "No recent files found." &
		sleep 5  # Pause for a moment before the next loop iteration
		continue
	fi

	# Add line numbers to the recent files and display
	nl "$RECENT_FILES_LIST" > "$TAIL_LIST"
	cat "$TAIL_LIST"

	# Prompt the user to select a file
	echo "Please provide the sequence number of the accessed file: "
	read -r SEQUENCE_NUM

	# Validate user input
	if [[ ! "$SEQUENCE_NUM" =~ ^[0-9]+$ ]] || [[ "$SEQUENCE_NUM" -lt 1 ]] || [[ "$SEQUENCE_NUM" -gt "${#RECENT_FILES_ARRAY[@]}" ]]; then
		notify-send "Invalid input. Please enter a valid sequence number." &
		continue
	fi

	# Get the selected file
	SELECTED_FILE="${RECENT_FILES_ARRAY[SEQUENCE_NUM - 1]}"
	# Open the folder with a file manager, being flexible for different DEs

	# List of common file managers in a general preferred order.
	# This order prioritizes commonly used managers in case multiple are installed.
	declare -a FILE_MANAGER_CANDIDATES=(
		"dolphin"    # KDE Plasma (e.g., Kubuntu, openSUSE KDE)
		"nautilus"   # GNOME (e.g., Ubuntu, Fedora Workstation)
		"nemo"       # Cinnamon (e.g., Linux Mint Cinnamon)
		"caja"       # MATE (e.g., Linux Mint MATE, Ubuntu MATE)
		"thunar"     # XFCE (e.g., Xubuntu, Linux Mint XFCE)
		"pcmanfm-qt" # LXQt (e.g., Lubuntu, Fedora LXQt)
		"pcmanfm"    # LXDE (older Lubuntu, various lightweight setups)
	)

	FOUND_FILE_MANAGER=""

	# Iterate through candidates and use the first one found that exists
	for fm_cmd in "${FILE_MANAGER_CANDIDATES[@]}"; do
		if command -v "$fm_cmd" >/dev/null 2>&1; then
			FOUND_FILE_MANAGER="$fm_cmd"
			break # Found an executable file manager, stop searchingss
		fi
	done

	if [[ -f "$SELECTED_FILE" ]]; then
		# Open the file with the preferred application using xdg-open
		xdg-open "$SELECTED_FILE" &
	else
		notify-send "Path does not exist: $SELECTED_FILE" &
	fi
done

