#!/usr/bin/env bash
set -euo pipefail

# Find the newest CachyOS kernel
kernel=$(ls -1 /boot/vmlinuz-*cachyos* 2>/dev/null | sort -V | tail -1)

if [[ -z "$kernel" ]]; then
    echo "No CachyOS kernel found."
    exit 1
fi

echo "Setting default to: $kernel"
sudo grubby --set-default "$kernel"
echo "New default kernel: $(sudo grubby --default-kernel)"
