#!/usr/bin/env bash
# ============================================================================
# /usr/local/sbin/prune-old-kernels.sh
#
# Policy (always keep):
#   1. The currently running kernel.
#   2. The newest N additional kernels of each family (CachyOS, mainline)
#      that are NOT the running kernel (default N=2).
#
# --keep=0 keeps only the running kernel.
#
# Safety:
#   - Exact RPM package discovery. No broad package-name guessing.
#   - Family-aware: CachyOS and mainline are tracked independently.
#   - Only versions represented by a recognized family anchor package are
#     eligible for pruning. Unknown kernel families and orphaned/unanchored
#     packages are ignored and left untouched.
#   - --dry-run prints the plan, touches nothing, requires no sudo.
#   - The running kernel is verified to belong to exactly one recognized
#     family (ambiguous matches are fatal) and to be present in the keep
#     set before any removal.
#   - Each version is a separate DNF transaction, verified by exact NEVRA
#     after removal.
#   - --no-autoremove prevents DNF from automatically removing packages
#     that merely become unneeded as a side effect of the requested removal.
#   - Post-flight verifies the anchor package for every protected
#     family|version remains installed.
#
# Version-ordering note:
#   Kernel versions are sorted newest-first with GNU `sort -V`. This is
#   not RPM's full version-comparison algorithm and the inventory does not
#   carry %{EPOCH}. For the Fedora/Nobara kernel NVR forms this script
#   targets, `sort -V` matches the expected ordering; treat it as an
#   approximation, not an RPM-equivalent comparison.
#
# Concurrency note:
#   Real runs take an exclusive flock on /run/lock/prune-old-kernels.lock
#   so a manual invocation cannot race an automated one (systemd, DNF
#   post-transaction action, or the auto-update daemon) over the same
#   RPM inventory. Dry-runs are read-only and skip the lock.
# ============================================================================

set -euo pipefail

# ================= CONFIG =================
KEEP_ADDITIONAL_PER_FAMILY=2
DRY_RUN=false

# Package names that constitute a kernel "version" for each family.
# Enumerate explicitly — do NOT use broad prefixes like kernel-*,
# which would match headers, srpm-macros, tools, etc.
#
# The lists are deliberately conservative: an unknown package with the
# same version-release is left untouched rather than guessed at.
readonly CACHYOS_PKGS=(
    kernel-cachyos
    kernel-cachyos-core
    kernel-cachyos-modules
    kernel-cachyos-modules-core
    kernel-cachyos-devel
    kernel-cachyos-devel-matched
)
readonly MAINLINE_PKGS=(
    kernel
    kernel-core
    kernel-modules
    kernel-modules-core
    kernel-devel
    kernel-devel-matched
)

# The "anchor" package per family: its presence defines whether that
# family/version is recognized and eligible for pruning.
readonly CACHYOS_ANCHOR="kernel-cachyos-core"
readonly MAINLINE_ANCHOR="kernel-core"

# ================= ARGUMENTS =================
usage() {
    cat <<'EOF'
Usage: prune-old-kernels.sh [OPTIONS]

Prune installed kernels while preserving:
  1. The currently running kernel (always).
  2. The newest N additional kernels per family that are not the
     running kernel (default N=2).

OPTIONS:
  --dry-run       Print the plan, remove nothing, require no sudo.
  --keep=N        Keep the newest N additional kernels per family.
                  N=0 keeps only the running kernel. (default: 2)
  -h, --help      Show this help.

FAMILIES:
  cachyos   kernel-cachyos-core and siblings
  mainline  kernel-core and siblings

Only versions represented by a recognized family anchor package are
eligible for pruning. Unknown kernel families and orphaned/unanchored
packages are ignored and left untouched.
EOF
}

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --keep=*)
            KEEP_ADDITIONAL_PER_FAMILY="${arg#--keep=}"
            [[ "$KEEP_ADDITIONAL_PER_FAMILY" =~ ^[0-9]+$ ]] || {
                echo "ERROR: --keep requires a non-negative integer" >&2
                exit 2
            }
            ;;
        -h|--help) usage; exit 0 ;;
        *) echo "ERROR: unknown argument: $arg" >&2; usage >&2; exit 2 ;;
    esac
done

# ================= DEPENDENCIES =================
# flock is part of util-linux, always installed on Fedora/Nobara. We
# check it explicitly because the concurrency lock below depends on it.
for cmd in uname rpm flock; do
    command -v "$cmd" >/dev/null 2>&1 \
        || { echo "ERROR: required command not found: $cmd" >&2; exit 1; }
done

# ================= CONCURRENCY LOCK (real runs only) =================
# Dry-runs are read-only and need no lock. Real runs must run as root
# and take an exclusive flock on /run/lock so a manual invocation cannot
# race an automated one over the same RPM inventory.
#
# Placement matters: this block runs AFTER the argument parser has set
# DRY_RUN and AFTER the dependency check has confirmed flock exists.
# It runs BEFORE any RPM query so the inventory below cannot become
# stale due to a concurrent invocation.
if [[ "$DRY_RUN" != "true" ]]; then
    if [[ $EUID -ne 0 ]]; then
        echo "ERROR: real runs must be invoked via sudo (or as root)." >&2
        echo "       Use: sudo $0 $*" >&2
        exit 1
    fi
    exec 9>/run/lock/prune-old-kernels.lock
    if ! flock -n 9; then
        echo "ERROR: another instance of prune-old-kernels is already running." >&2
        exit 1
    fi
fi

# ================= RUNNING KERNEL =================
# Two representations:
#   RUNNING_KERNEL  = uname -r  (includes .arch, e.g. 7.2.5-cachyos1.fc44.x86_64)
#   RUNNING_VERREL  = rpm %{VERSION}-%{RELEASE}  (no arch, e.g. 7.2.5-cachyos1.fc44)
# All rpm comparisons use RUNNING_VERREL. Display uses RUNNING_KERNEL.
RUNNING_KERNEL=$(uname -r)
RUNNING_VERREL="${RUNNING_KERNEL%.*}"

echo "Running kernel: $RUNNING_KERNEL"
echo "  (normalized for rpm: $RUNNING_VERREL)"
echo

# ================= RPM INVENTORY (fail closed) =================
# Enumerate all installed RPMs once, up front. Capture the rpm command's
# exit status directly (via command substitution) so an inventory failure
# is fatal. A process substitution (mapfile < <(rpm ...)) would NOT expose
# rpm's exit status to mapfile — mapfile would observe only its own read
# status and could "succeed" on an empty/partial stream. Command
# substitution gives us a real failure boundary:
#   rpm succeeds -> inventory captured -> mapfile parses it
#   rpm fails    -> script exits immediately
declare -a INSTALLED_RPMS=()
RPM_INVENTORY=""

if ! RPM_INVENTORY=$(
    rpm -qa --qf '%{NAME}\t%{VERSION}-%{RELEASE}\t%{ARCH}\n'
); then
    echo "FATAL: failed to enumerate installed RPM packages." >&2
    exit 1
fi

if [[ -z "$RPM_INVENTORY" ]]; then
    echo "FATAL: rpm -qa returned no packages; refusing to proceed." >&2
    exit 1
fi

mapfile -t INSTALLED_RPMS <<< "$RPM_INVENTORY"

# ================= DISCOVER INSTALLED KERNELS =================
# family -> newline-separated version-release strings
#
# Only versions represented by the family anchor package are discovered.
# Orphaned/unanchored packages (e.g. kernel-cachyos-7.0 with no matching
# kernel-cachyos-core-7.0) are intentionally invisible to this script and
# will not be pruned.
declare -A FAMILY_VERSIONS

is_known_pkg() {
    local pkg="$1" fam="$2" p
    case "$fam" in
        cachyos)  for p in "${CACHYOS_PKGS[@]}";  do [[ "$p" == "$pkg" ]] && return 0; done ;;
        mainline) for p in "${MAINLINE_PKGS[@]}"; do [[ "$p" == "$pkg" ]] && return 0; done ;;
    esac
    return 1
}

# Anchor packages: their presence defines the set of installed versions.
for record in "${INSTALLED_RPMS[@]}"; do
    IFS=$'\t' read -r name verrel _arch <<< "$record"
    case "$name" in
        "$CACHYOS_ANCHOR") FAMILY_VERSIONS[cachyos]+="$verrel"$'\n' ;;
        "$MAINLINE_ANCHOR") FAMILY_VERSIONS[mainline]+="$verrel"$'\n' ;;
    esac
done

if (( ${#FAMILY_VERSIONS[@]} == 0 )); then
    echo "No kernel anchor packages found (looked for: $CACHYOS_ANCHOR, $MAINLINE_ANCHOR)."
    exit 0
fi

# ================= SORT EACH FAMILY NEWEST-FIRST =================
# Sort version-release strings newest-first.
# GNU sort -V handles the Fedora/Nobara kernel version formats used here.
# It is NOT RPM's full version-comparison algorithm, and the inventory
# above does not carry %{EPOCH}. Treat this as an ordering approximation
# appropriate for the NVR forms this script targets.
declare -A FAMILY_SORTED
for fam in "${!FAMILY_VERSIONS[@]}"; do
    FAMILY_SORTED[$fam]=$(
        printf '%s' "${FAMILY_VERSIONS[$fam]}" | sort -u | sort -Vr
    )
done

# ================= DETECT RUNNING FAMILY (fail closed on ambiguity) =================
# The running kernel must belong to exactly one recognized family. We do
# not assume this — we verify it. Both families are probed:
#   0 matches -> fatal (running kernel not managed by this script)
#   1 match   -> use that family
#   2 matches -> fatal (ambiguous; refuse to guess)
running_family=""
matched_families=()

if rpm -q "$CACHYOS_ANCHOR-$RUNNING_VERREL" >/dev/null 2>&1; then
    matched_families+=("cachyos")
fi
if rpm -q "$MAINLINE_ANCHOR-$RUNNING_VERREL" >/dev/null 2>&1; then
    matched_families+=("mainline")
fi

case "${#matched_families[@]}" in
    0)
        echo "FATAL: running kernel $RUNNING_VERREL does not match any recognized family anchor." >&2
        exit 1
        ;;
    1)
        running_family="${matched_families[0]}"
        ;;
    *)
        echo "FATAL: running kernel $RUNNING_VERREL matches multiple families: ${matched_families[*]}" >&2
        echo "       Refusing to proceed with an ambiguous running-family assignment." >&2
        exit 1
        ;;
esac

# ================= BUILD KEEP SET =================
# KEEP_PAIRS: array of "family|verrel"
# KEEP_MARK:  associative set keyed by "family|verrel"
declare -a KEEP_PAIRS=("$running_family|$RUNNING_VERREL")
declare -A KEEP_MARK
KEEP_MARK["$running_family|$RUNNING_VERREL"]=1

for fam in "${!FAMILY_SORTED[@]}"; do
    count=0
    while IFS= read -r v; do
        [[ -z "$v" ]] && continue
        [[ "$v" == "$RUNNING_VERREL" ]] && continue
        (( count >= KEEP_ADDITIONAL_PER_FAMILY )) && break
        KEEP_MARK["$fam|$v"]=1
        KEEP_PAIRS+=("$fam|$v")
        count=$((count + 1))
    done <<< "${FAMILY_SORTED[$fam]}"
done

# ================= SAFETY: RUNNING KERNEL IS KEPT =================
if [[ -z "${KEEP_MARK[$running_family|$RUNNING_VERREL]:-}" ]]; then
    echo "FATAL: running kernel not in keep set for family $running_family." >&2
    exit 1
fi

# ================= BUILD REMOVAL SET =================
declare -a REMOVE_PAIRS=()
for fam in "${!FAMILY_SORTED[@]}"; do
    while IFS= read -r v; do
        [[ -z "$v" ]] && continue
        [[ -n "${KEEP_MARK[$fam|$v]:-}" ]] && continue
        REMOVE_PAIRS+=("$fam|$v")
    done <<< "${FAMILY_SORTED[$fam]}"
done

# ================= PLAN OUTPUT =================
echo "Policy: keep running kernel + newest $KEEP_ADDITIONAL_PER_FAMILY additional per family"
echo

for fam in $(printf '%s\n' "${!FAMILY_SORTED[@]}" | sort); do
    echo "  family: $fam"
    while IFS= read -r v; do
        [[ -z "$v" ]] && continue
        if [[ "$v" == "$RUNNING_VERREL" ]]; then
            printf '    → %s   (running)\n' "$v"
        elif [[ -n "${KEEP_MARK[$fam|$v]:-}" ]]; then
            printf '      %s\n' "$v"
        fi
    done <<< "${FAMILY_SORTED[$fam]}"
done
echo

if (( ${#REMOVE_PAIRS[@]} == 0 )); then
    echo "Nothing to remove."
    exit 0
fi

echo "REMOVE:"
for entry in "${REMOVE_PAIRS[@]}"; do
    echo "  [${entry%%|*}] ${entry#*|}"
done
echo

# ================= DRY-RUN EXIT =================
if [[ "$DRY_RUN" == "true" ]]; then
    echo "DRY-RUN: no changes made."
    exit 0
fi

# ================= SUDO (only reached in real run) =================
command -v dnf >/dev/null 2>&1 \
    || { echo "ERROR: required command not found: dnf" >&2; exit 1; }
command -v sudo >/dev/null 2>&1 \
    || { echo "ERROR: required command not found: sudo" >&2; exit 1; }

# Note: if we got this far we are already root (the CONCURRENCY LOCK
# block enforces EUID==0 for real runs). The sudo check above is a
# defensive check in case someone invokes the script in an unusual
# environment; the actual dnf remove calls below still use sudo so the
# script works both when invoked via `sudo` and when invoked directly
# by a root process (systemd, DNF post-transaction action).
sudo -v 2>/dev/null \
    || { echo "ERROR: could not obtain sudo privileges." >&2; exit 1; }

# ================= REMOVE ONE VERSION AT A TIME =================
removed_count=0

for entry in "${REMOVE_PAIRS[@]}"; do
    fam="${entry%%|*}"
    ver="${entry#*|}"

    # Invariant: never remove the running kernel's own family|version.
    # This is the authoritative check; the package-level defense below
    # is a secondary net.
    if [[ "$fam" == "$running_family" && "$ver" == "$RUNNING_VERREL" ]]; then
        echo "FATAL: attempted removal of running kernel: $fam|$ver" >&2
        exit 1
    fi

    # Discover every installed package for this family that has this
    # exact version-release. Filter the already-enumerated inventory —
    # no additional rpm invocation is needed.
    pkgs=()
    for record in "${INSTALLED_RPMS[@]}"; do
        IFS=$'\t' read -r pkg_name pkg_verrel pkg_arch <<< "$record"
        [[ "$pkg_verrel" == "$ver" ]] || continue
        is_known_pkg "$pkg_name" "$fam" || continue

        # Last-line defense: exact structured comparison against the
        # running kernel's version-release. Family-aware, so a mainline
        # package that merely shares the running version string is not
        # mistaken for the running kernel. This is a precise identity
        # check — not a substring match against a reconstructed NEVRA.
        if [[ "$fam" == "$running_family" && "$pkg_verrel" == "$RUNNING_VERREL" ]]; then
            echo "FATAL: removal set contains running kernel package: ${pkg_name}-${pkg_verrel}.${pkg_arch}" >&2
            exit 1
        fi

        pkgs+=("${pkg_name}-${pkg_verrel}.${pkg_arch}")
    done

    if (( ${#pkgs[@]} == 0 )); then
        echo "[$fam] $ver: no installed packages matched — skipping"
        continue
    fi

    echo "============================================================"
    echo "[$fam] Removing $ver"
    echo "============================================================"
    printf '  - %s\n' "${pkgs[@]}"
    echo

    if ! sudo dnf remove -y --no-autoremove "${pkgs[@]}"; then
        echo "ERROR: dnf remove failed for [$fam] $ver" >&2
        exit 1
    fi

    # Verify each targeted NEVRA is actually gone. This matches the exact
    # package identifier we handed to dnf, including architecture.
    for p in "${pkgs[@]}"; do
        if rpm -q "$p" >/dev/null 2>&1; then
            echo "ERROR: package still installed after removal: $p" >&2
            exit 1
        fi
    done

    removed_count=$((removed_count + 1))
    echo
done

# ================= POST-FLIGHT VERIFICATION (anchor per protected pair) =================
# Verifies the anchor package for every protected family|version remains
# installed. This is not a full re-verification of every sibling package
# in the family allowlist; the anchor defines the version, and the
# per-version removal loop already verifies actual removal.
echo "Verifying anchor package for each protected kernel..."
for entry in "${KEEP_PAIRS[@]}"; do
    fam="${entry%%|*}"
    ver="${entry#*|}"
    case "$fam" in
        cachyos) anchor="$CACHYOS_ANCHOR" ;;
        mainline) anchor="$MAINLINE_ANCHOR" ;;
        *) echo "FATAL: unknown family in keep set: $fam" >&2; exit 1 ;;
    esac
    if ! rpm -q "${anchor}-${ver}" >/dev/null 2>&1; then
        echo "FATAL: protected kernel anchor missing after prune: $fam|$ver ($anchor-$ver)" >&2
        exit 1
    fi
done
echo "OK: all protected kernel anchors still installed."
echo
echo "Removed $removed_count kernel version(s)."
echo
df -h /boot
