#!/usr/bin/env bash
set -euo pipefail

OLD_DIR="$HOME/Documents/screensavers"
NEW_DIR="/usr/libexec/xscreensaver"

mkdir -p "$OLD_DIR"

if [[ ! -d "$NEW_DIR" ]]; then
    echo "ERROR: System screensaver directory not found: $NEW_DIR"
    echo "Install with: sudo dnf install xscreensaver xscreensaver-extras xscreensaver-gl-extras"
    exit 1
fi

echo "Copying ELF executable files from $NEW_DIR to $OLD_DIR..."
count=0

for src in "$NEW_DIR"/*; do
    # Check if it's a regular file and has execute permission
    if [[ -f "$src" && -x "$src" ]]; then
        # Use 'file' to check the actual type (ELF binary vs script)
        if file "$src" | grep -q "ELF.*executable"; then
            base=$(basename "$src")
            dst="$OLD_DIR/screensaver-$base"
            cp "$src" "$dst"
            chmod +x "$dst"
            echo "  $base -> screensaver-$base"
            count=$((count + 1))
        fi
    fi
done

echo "Done! $count true ELF binaries copied."
