#!/usr/bin/env bash
export PATH="$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"
set -euo pipefail

# Get all grubby info once
grubby_info=$(sudo grubby --info=ALL)

# Extract all CachyOS kernel paths
cachyos_kernels=$(echo "$grubby_info" | grep -oP '(?<=kernel=")[^"]*cachyos[^"]*' || true)

# Count how many CachyOS kernels we have
kernel_count=$(echo "$cachyos_kernels" | grep -c . || true)

if [[ "$kernel_count" -lt 3 ]]; then
    echo "Error: Less than 3 CachyOS kernels found. Cannot select the 3rd newest."
    exit 1
fi

# Sort by version and grab the 3rd newest (two versions before the latest)
# tail -3 gets the last 3 items, head -1 gets the oldest of those three (the 3rd newest overall)
bls_kernel=$(echo "$cachyos_kernels" | sort -V | tail -3 | head -1)

# Find the index associated with this kernel path
target_index=$(echo "$grubby_info" | awk -v k="$bls_kernel" '
    /^index=/ { sub(/^index=/, ""); current_idx=$0 }
    $0 ~ "kernel=\""k"\"" { print current_idx; exit }
')

if [[ -z "$target_index" ]]; then
    echo "Error: Could not find grubby index for $bls_kernel"
    exit 1
fi

echo "Setting default to the stable (N-2) CachyOS kernel:"
echo "Index: $target_index"
echo "Kernel: $bls_kernel"
sudo grubby --set-default-index="$target_index"

echo "New default kernel index: $(sudo grubby --default-index)"
