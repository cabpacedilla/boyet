#!/usr/bin/env bash
# Monitor editions (edits, saves, creates, deletes) of files in $HOME/Documents
# Keeps last 40, lets you open them on demand.
# Swap/backup/lock/autosave files are normalized to the real filename.
# Written by Claive Alvin P. Acedilla. Updated September 2025.

WATCH_DIR="$HOME/Documents"
LOG_DIR="$HOME/scriptlogs"
RECENT_FILES_LIST="$LOG_DIR/recentEdited.txt"
TAIL_LIST="$LOG_DIR/reverseEdited.txt"

mkdir -p "$LOG_DIR"

# Check if inotifywait is available
if ! command -v inotifywait >/dev/null 2>&1; then
    notify-send "Error" "inotify-tools not installed. Install with: sudo dnf install inotify-tools" &
    exit 1
fi

# --- Background watcher: updates file list ---
inotifywait -m -r \
  --exclude '(\.swp$|\.swo$|\.swx$|~$|\.tmp$|\.temp$|\.part$|\.crdownload$|\.bak$|\.autosave$)' \
  -e modify,close_write,create,delete "$WATCH_DIR" --format '%w%f' 2>/dev/null |
while read -r FILE; do
    BASENAME="$(basename "$FILE")"
    DIRNAME="$(dirname "$FILE")"

    # --- Map auto-generated backups/swaps back to the real file ---
    case "$BASENAME" in
        # Kate swap: .filename.kate-swp → filename
        .*.kate-swp)
            REAL="${BASENAME#.}"         # drop leading dot
            REAL="${REAL%.kate-swp}"     # drop suffix
            FILE="$DIRNAME/$REAL"
            ;;

        # Vim swap: .filename.swp → filename
        .*.sw[ponx])
            REAL="${BASENAME#.}"         # drop leading dot
            REAL="${REAL%.sw[ponx]}"     # drop suffix
            FILE="$DIRNAME/$REAL"
            ;;

        # Emacs autosave: #filename# → filename
        \#*\#)
            REAL="${BASENAME#\#}"        # drop leading #
            REAL="${REAL%\#}"            # drop trailing #
            FILE="$DIRNAME/$REAL"
            ;;

        # Emacs lock: .#filename → filename
        .\#*)
            REAL="${BASENAME#.}"         # drop leading dot
            REAL="${REAL#\#}"            # drop #
            FILE="$DIRNAME/$REAL"
            ;;

        # LibreOffice lock: .~lock.filename# → filename
        .~lock.*\#)
            REAL="${BASENAME#.~lock.}"   # drop prefix
            REAL="${REAL%\#}"            # drop trailing #
            FILE="$DIRNAME/$REAL"
            ;;
    esac
    # --- end mapping ---

    # Only log if it’s a valid file
    if [[ -n "$FILE" && "$FILE" != "$DIRNAME/" ]]; then
        grep -Fxv "$FILE" "$RECENT_FILES_LIST" 2>/dev/null > "$RECENT_FILES_LIST.tmp"
        echo "$FILE" >> "$RECENT_FILES_LIST.tmp"
        mv "$RECENT_FILES_LIST.tmp" "$RECENT_FILES_LIST"

        tail -n 40 "$RECENT_FILES_LIST" > "$RECENT_FILES_LIST.tmp" && mv "$RECENT_FILES_LIST.tmp" "$RECENT_FILES_LIST"
    fi
done &

# --- Foreground loop: user interaction ---
while true; do
    clear
    if [[ -s "$RECENT_FILES_LIST" ]]; then
        nl "$RECENT_FILES_LIST" > "$TAIL_LIST"
        echo "Recently edited files (last 40):"
        cat "$TAIL_LIST"
    else
        echo "No file edits detected yet..."
    fi

    echo
    echo "Enter number to open a file, or press Enter to refresh:"
    read -r SEQUENCE_NUM

    if [[ -n "$SEQUENCE_NUM" ]]; then
        mapfile -t RECENT_FILES_ARRAY < "$RECENT_FILES_LIST"
        if [[ "$SEQUENCE_NUM" =~ ^[0-9]+$ ]] && (( SEQUENCE_NUM >= 1 && SEQUENCE_NUM <= ${#RECENT_FILES_ARRAY[@]} )); then
            SELECTED_FILE="${RECENT_FILES_ARRAY[SEQUENCE_NUM-1]}"
            if [[ -e "$SELECTED_FILE" ]]; then
                xdg-open "$SELECTED_FILE" &
            else
                notify-send "File no longer exists" "$SELECTED_FILE" &
            fi
        else
            notify-send "Invalid input" "Please enter a valid number" &
        fi
    fi

    sleep 2
done
