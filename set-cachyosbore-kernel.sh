#!/usr/bin/env bash
# ============================================================================
# set-cachyosbore-kernel.sh
#
# Purpose: choose a stable CachyOS kernel that passes structural bootability
# checks and set it as the GRUB default. Does NOT install/remove kernels.
#
# Selection policy:
#   - Filter grubby entries down to CachyOS kernels that pass structural
#     checks (kernel file, initrd, modules tree, RPM record, subvolume
#     existence, non-snapshot).
#   - Sort the survivors by version (ascending).
#   - Target slot = count - 1 - STABLE_OFFSET.
#   - Within slots <= target, prefer a kernel that has previously been
#     observed booting (journald kernel messages from an earlier boot).
#     If none qualifies, use the target slot itself.
#
# Fallback: if fewer than STABLE_OFFSET+1 valid candidates exist, use the
# newest valid candidate. This avoids leaving an old default in place just
# because the requested offset is unavailable.
#
# Environment:
#   DEBUG=true    -> print per-candidate rejection reasons on stderr
#   DRY_RUN=true  -> report decision, do not invoke grubby --set-default
# ============================================================================

# Root-safe PATH: do NOT inherit the caller's $PATH.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

set -euo pipefail

# ================= CONFIG =================
STABLE_OFFSET=2
INCLUDE_LEGACY=true
MIN_KERNEL_SIZE=$((2 * 1024 * 1024))
MIN_INITRD_SIZE=$((4 * 1024 * 1024))
MAX_BOOTS_TO_SCAN=20

# Reject any kernel whose rootflags reference this path component anywhere.
# Component-aware matching is used, so '@/.nobara-updater/foo' and nested
# forms are caught as well as the top-level '.nobara-updater/foo'.
POISON_SUBVOL_COMPONENT=".nobara-updater"

DEBUG="${DEBUG:-false}"
DRY_RUN="${DRY_RUN:-false}"

LOCK_FILE="/run/lock/set-cachyosbore-kernel.lock"

# ================= HELPERS =================
reject() {
    [[ "$DEBUG" == "true" ]] && echo "reject: $*" >&2
    return 0
}

die() {
    echo "Error: $*" >&2
    exit 1
}

# ================= DEPENDENCIES =================
required_commands=(
    flock grubby findmnt btrfs journalctl
    grep awk sort rpm stat basename dirname
)
for cmd in "${required_commands[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 \
        || die "required command not found: $cmd"
done

# ================= SINGLE-INSTANCE LOCK =================
mkdir -p "$(dirname "$LOCK_FILE")"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "Another kernel-selection run is already active; exiting." >&2
    exit 1
fi

# ================= GRUBBY READ =================
if ! grubby_info=$(grubby --info=ALL); then
    die "unable to read GRUB kernel entries with grubby"
fi
[[ -n "$grubby_info" ]] || die "grubby returned no entries"

# ================= BTRFS STATE =================
# Explicitly distinguish three states:
#   on_btrfs=0              -> / is not btrfs, subvol checks skipped
#   on_btrfs=1, list_ok=1   -> subvol list retrieved, use for existence checks
#   on_btrfs=1, list_ok=0   -> list query FAILED; treat as verification failure
on_btrfs=0
btrfs_list_ok=0
snap_list=""

if [[ "$(findmnt -n -o FSTYPE / 2>/dev/null)" == "btrfs" ]]; then
    on_btrfs=1
    if snap_list=$(btrfs subvolume list / 2>/dev/null | awk '{print $NF}'); then
        btrfs_list_ok=1
    fi
fi

# ================= BOOT HISTORY =================
# Set of kernel versions that journald has observed booting on this machine.
# Evidence: a Linux version string present in kernel-journal messages from a
# prior boot. This means the kernel reached userspace; it does not by itself
# prove the graphical session, all modules, or long-term stability.
declare -A BOOTED_OK=()
if [[ -d /var/log/journal ]]; then
    while read -r bid; do
        [[ -z "$bid" ]] && continue
        kver=$(journalctl -b "$bid" -k --no-pager 2>/dev/null \
               | grep -m1 -oP 'Linux version \K\S+' || true)
        [[ -n "$kver" ]] && BOOTED_OK["$kver"]=1
    done < <(journalctl --list-boots --no-pager 2>/dev/null \
             | awk 'NR>1 {print $2}' | tail -n "$MAX_BOOTS_TO_SCAN")
fi

# ================= CANDIDATE FILTERING =================
# Output: version <TAB> kernel_path <TAB> proof_flag(0|1)
# When the same version appears in multiple layouts, the first entry in
# grubby output order is kept.
mapfile -t candidates < <(
    echo "$grubby_info" | awk '
        /^kernel="/ { sub(/^kernel="/,""); sub(/"$/,""); kpath=$0 }
        /^args="/   { sub(/^args="/,"");   sub(/"$/,""); args=$0 }
        /^initrd="/ { sub(/^initrd="/,""); sub(/"$/,""); ipath=$0 }
        /^id="/     { sub(/^id="/,"");     sub(/"$/,""); id=$0;
                      if (kpath != "") {
                          printf "%s\t%s\t%s\t%s\n", kpath, ipath, id, args;
                          kpath=""; ipath=""; id=""; args=""
                      }
                    }
    ' | while IFS=$'\t' read -r kpath ipath id args; do

        # --- Layout / version extraction ---
        case "$(basename "$kpath")" in
            linux)
                ver=$(basename "$(dirname "$kpath")")
                ;;
            vmlinuz-*)
                [[ "$INCLUDE_LEGACY" == "true" ]] || continue
                ver="${kpath##*/vmlinuz-}"
                ;;
            *)
                continue
                ;;
        esac

        # --- Scope: CachyOS only; skip rescue/memtest ---
        [[ "$ver" == *cachyos* ]] || continue
        [[ "$ver" == *rescue*  ]] && { continue; }
        [[ "$ver" == *memtest* ]] && { continue; }

        # --- Kernel file ---
        [[ -f "$kpath" ]] || { reject "$ver: kernel file missing ($kpath)"; continue; }
        ksz=$(stat -c%s "$kpath" 2>/dev/null || echo 0)
        (( ksz >= MIN_KERNEL_SIZE )) \
            || { reject "$ver: kernel too small (${ksz}B)"; continue; }

        # --- Initrd ---
        [[ -f "$ipath" ]] || { reject "$ver: initrd missing ($ipath)"; continue; }
        isz=$(stat -c%s "$ipath" 2>/dev/null || echo 0)
        (( isz >= MIN_INITRD_SIZE )) \
            || { reject "$ver: initrd too small (${isz}B)"; continue; }

        # --- Modules tree ---
        [[ -f "/usr/lib/modules/$ver/modules.dep" ]] \
            || { reject "$ver: modules.dep missing"; continue; }

        # --- RPM record ---
        if ! rpm -q "kernel-cachyos-core-$ver" >/dev/null 2>&1 \
           && ! rpm -q "kernel-cachyos-$ver"      >/dev/null 2>&1; then
            reject "$ver: no matching kernel RPM"
            continue
        fi

        # --- Extract subvolume from args, if any ---
        subvol=$(grep -oP 'rootflags=subvol=\K\S+' <<<"$args" || true)

        if [[ -n "$subvol" ]]; then
            # Component-aware snapshot check: catches '@/.nobara-updater/x',
            # '.nobara-updater/x', 'foo/.nobara-updater/bar', etc., without
            # matching a similarly-named path like 'my.nobara-updater-backup'.
            if [[ "/$subvol/" == *"/$POISON_SUBVOL_COMPONENT/"* ]]; then
                reject "$ver: snapshot subvol '$subvol'"
                continue
            fi

            # Existence check: only run when btrfs enumeration succeeded.
            # If enumeration FAILED (list_ok=0), verification is inconclusive
            # and we reject the candidate (fail-closed).
            if (( on_btrfs )); then
                if (( ! btrfs_list_ok )); then
                    reject "$ver: btrfs enumeration failed, cannot verify subvol '$subvol'"
                    continue
                fi
                if ! grep -Fxq "$subvol" <<<"$snap_list"; then
                    reject "$ver: subvol '$subvol' not present"
                    continue
                fi
            fi
        fi

        proof=0
        [[ -n "${BOOTED_OK[$ver]:-}" ]] && proof=1
        printf '%s\t%s\t%s\n' "$ver" "$kpath" "$proof"
    done \
    | sort -V -k1,1 -s \
    | awk -F'\t' '!seen[$1]++'
)

if (( ${#candidates[@]} == 0 )); then
    die "no bootable CachyOS kernel found"
fi

# ================= SLOT SELECTION =================
count=${#candidates[@]}

if (( count <= STABLE_OFFSET )); then
    echo "Note: only $count valid candidate(s); falling back to newest (STABLE_OFFSET=$STABLE_OFFSET)." >&2
    target=$(( count - 1 ))
else
    target=$(( count - 1 - STABLE_OFFSET ))
fi

# Prefer a previously-observed kernel at or below the target slot.
sel=""
for (( i = target; i >= 0; i-- )); do
    if [[ "${candidates[$i]##*$'\t'}" == "1" ]]; then
        sel=$i
        break
    fi
done
[[ -z "$sel" ]] && sel=$target

chosen="${candidates[$sel]}"
stable_version="${chosen%%$'\t'*}"
rest="${chosen#*$'\t'}"
stable_path="${rest%%$'\t'*}"
stable_proof="${chosen##*$'\t'}"

# ================= REPORT =================
echo "CachyOS candidates (ascending; newest last):"
for i in "${!candidates[@]}"; do
    c="${candidates[$i]}"
    v="${c%%$'\t'*}"
    p="${c##*$'\t'}"
    marker=" "
    (( i == sel )) && marker="->"
    tag=""
    [[ "$p" == "1" ]] && tag="[observed-boot]"
    printf '  %s [%d] %-40s %s\n' "$marker" "$i" "$v" "$tag"
done
echo
echo "Selection:"
echo "  Slot:    $sel of $(( count - 1 ))  (target N-$STABLE_OFFSET = $target)"
echo "  Version: $stable_version"
echo "  Path:    $stable_path"
if [[ "$stable_proof" == "1" ]]; then
    echo "  Evidence: kernel version observed in a prior journald boot"
else
    echo "  Evidence: none (structural checks passed; no prior boot observed)"
fi
echo

# ================= APPLY =================
if [[ "$DRY_RUN" == "true" ]]; then
    echo "DRY_RUN=true: not invoking grubby --set-default."
    exit 0
fi

if ! grubby --set-default="$stable_path"; then
    die "grubby --set-default failed for $stable_path"
fi

new_default=$(grubby --default-kernel)
echo "New default kernel: $new_default"

if [[ "$new_default" != "$stable_path" ]]; then
    die "grubby did not set the expected default (wanted $stable_path)"
fi

exit 0
