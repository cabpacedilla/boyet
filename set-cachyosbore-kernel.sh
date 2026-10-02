#!/usr/bin/env bash
export PATH="$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"
set -euo pipefail

# ================= CONFIG =================
# Only consider kernels whose path matches this pattern.
# Currently: legacy vmlinuz layout  -> /boot/vmlinuz-<version>
VMLINUZ_GLOB='*/vmlinuz-*'

# ================= FETCH GRUBBY INFO =================
grubby_info=$(sudo grubby --info=ALL)

# ================= EXTRACT VMLINUZ CACHYOS KERNELS =================
# Collect every kernel path that:
#   - ends with a vmlinuz-* basename
#   - contains "cachyos" in its version
# Emit "version<TAB>path" lines so we can sort by version, not by path.
mapfile -t entries < <(
    echo "$grubby_info" \
        | grep -oP '(?<=kernel=")[^"]*' \
        | while read -r path; do
              case "$path" in
                  $VMLINUZ_GLOB) ;;
                  *) continue ;;
              esac
              ver="${path##*/vmlinuz-}"
              [[ "$ver" == *cachyos* ]] || continue
              printf '%s\t%s\n' "$ver" "$path"
          done \
        | sort -V -k1,1 -u
)

count=${#entries[@]}
if (( count == 0 )); then
    echo "Error: No CachyOS vmlinuz kernels found."
    exit 1
fi

# Newest = last entry after ascending sort
latest_entry="${entries[$(( count - 1 ))]}"
latest_version="${latest_entry%%$'\t'*}"
latest_path="${latest_entry#*$'\t'}"

# ================= FIND GRUBBY INDEX =================
target_index=$(echo "$grubby_info" | awk -v k="$latest_path" '
    /^index=/ { sub(/^index=/, ""); current_idx=$0 }
    index($0, "kernel=\"" k "\"") { print current_idx; exit }
')

if [[ -z "$target_index" ]]; then
    echo "Error: Could not find grubby index for $latest_path"
    exit 1
fi

# ================= APPLY =================
echo "Setting default to the latest CachyOS vmlinuz kernel:"
echo "Version: $latest_version"
echo "Index:   $target_index"
echo "Kernel:  $latest_path"
echo

sudo grubby --set-default-index="$target_index"

echo "New default kernel index: $(sudo grubby --default-index)"
echo "New default kernel:       $(sudo grubby --default-kernel)"
