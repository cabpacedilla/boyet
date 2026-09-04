#!/usr/bin/env bash
# Set default GRUB entry to the second-newest kernel (index 1)

set -euo pipefail

# Check if index 1 exists and is a valid kernel entry
if sudo grubby --info=1 >/dev/null 2>&1; then
    title=$(sudo grubby --info=1 | grep '^title=' | cut -d'=' -f2-)
    if [[ -n "$title" ]]; then
        echo "Setting default to index 1: $title"
        sudo grubby --set-default-index=1
        echo "New default kernel: $(sudo grubby --default-kernel)"
    else
        echo "ERROR: Index 1 does not appear to be a kernel entry."
        exit 1
    fi
else
    echo "ERROR: Index 1 does not exist. Only one kernel found?"
    exit 1
fi
