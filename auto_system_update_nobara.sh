#!/usr/bin/env bash
# ============================================================================
# Nobara Linux Auto-Update Daemon
# ============================================================================
# DEPLOYMENT NOTE (FIX 133):
#   Run under systemd with KillMode=control-group so SIGTERM reaches every
#   descendant. The script's pkill -P $$ is best-effort only. Example:
#     [Service]
#     KillMode=control-group
#     TimeoutStopSec=30
#
# DRY-RUN CONTRACT (FIX 130, FIX 137, FIX 139, FIX 143):
#   --dry-run writes discovery lists to $STATE_DIR/dry-run/, uses $LISTS_DIR
#   for temp files, skips history migration and rows. Only $STATE_DIR, $LOG_DIR,
#   the dry-run subdirectory, lock file, and logs are created. Verification
#   and archive directories are NOT created in dry-run (FIX 139).
#
#   LIMITATION [FIX 143]: `flatpak remote-ls --updates` may refresh local
#   Flatpak metadata caches even without `--appstream`. The dry-run contract
#   covers "no package transactions and no persistent operational state
#   changes under $STATE_DIR/$LOG_DIR"; it does NOT guarantee that Flatpak's
#   own cache directories (~/.cache/flatpak, /var/cache/flatpak) remain
#   byte-for-byte unchanged. This is inherent to how Flatpak resolves remote
#   metadata and cannot be avoided without skipping Flatpak discovery
#   entirely in dry-run.
#
# HEALTH vs TRANSACTION (FIX 135, FIX 142):
#   Three independent timestamps, each with a specific meaning:
#
#   last_success
#     Advances only when transaction=OK AND health=HEALTHY.
#     Means: full clean cycle (nobara-sync succeeded, verification healthy).
#
#   last_transaction_success
#     Advances whenever run_updates() returns 0 — i.e., transaction=OK OR
#     FALLBACK-OK. Means: the configured update pipeline completed
#     successfully, whether via nobara-sync or the authorized fallback.
#     Does NOT advance on FAIL or SKIP.
#
#   last_nobara_sync_success
#     Advances only when transaction=OK (not FALLBACK-OK).
#     Means: nobara-sync itself, not the fallback, completed successfully.
#
#   History CSV TRANSACTION column encodes the same distinction:
#     OK          = nobara-sync + flatpak succeeded, health-healthy optional
#     FALLBACK-OK = nobara-sync failed, authorized fallback succeeded
#     FAIL/SKIP   = see log for details
#
# REPORT HEALTH vs REPORT PERSISTENCE (FIX 134, FIX 141, FIX 146):
#   The verification report describes health checks only (HEALTH STATUS:).
#   Persistence outcome is logged separately (PERSISTENCE: report_saved=...
#   log_appended=...). The function's return code includes persistence failures
#   and may be DEGRADED even when HEALTH STATUS: HEALTHY.
#
# REVISION NOTES (search "[FIX n]"):
#   [FIX 1]-[FIX 143] prior rounds (see inline).
#   [FIX 144] detect_offline_update_pending probes child directories via
#             sudo when parent is unreadable (e.g. /var/lib/nobara-updater
#             at 0700 root). Without this, reboot notification was sticky.
#   [FIX 145] check_disk includes a /boot/efi check (32 MiB threshold,
#             matching nobara-sync's own requirement) so the daemon blocks
#             cleanly instead of retrying hourly into a guaranteed failure.
#   [FIX 146] Verification report block uses explicit if/fi + trailing true
#             so the group's exit status is 0 when no issues are present.
#             Previously the [[ ]] && { } form caused the || handler to
#             delete the report on every healthy cycle.
#   [FIX 147] Flatpak discovery parser relaxed: single-field rows (runtimes
#             with no version) are accepted as "name (no version)"; only
#             NF>2 and malformed IDs are rejected. Previously the strict
#             NF==2 check aborted the entire fetch on any runtime update.
#   [FIX 148] nobara-sync stages updates for the next boot (JSON result has
#             "reboot_required": true) instead of installing them, so neither
#             the kernel comparison nor the offline-directory probes saw a
#             pending reboot. run_updates() now records a boot-ID-keyed marker
#             ($STATE_DIR/reboot_staged); detect_offline_update_pending()
#             honours it (=> RESTART REQUIRED notification); main() skips
#             fetch/update while the marker is valid for the current boot, so
#             the same transaction is no longer re-staged every hour.
# ============================================================================

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${HOME}/.local/bin"

if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]] && [[ -S "/run/user/$(id -u)/bus" ]]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
fi

set -uo pipefail
NL=$'\n'

# ================= CONFIG =================
STATE_DIR="$HOME/.auto_update_state"
LOG_DIR="$HOME/scriptlogs"
LOGFILE="$LOG_DIR/nobara_update_log.txt"
HISTORY_LOG="$LOG_DIR/update_history.csv"
PACKAGE_LOG="$LOG_DIR/package_history.log"
VERIFICATION_LOG_DIR="$STATE_DIR/verifications"
LOCK_FILE="$STATE_DIR/auto_update.lock"

DRY_RUN=false
ENABLE_AUTOREMOVE=false
ENABLE_FALLBACK=false
ALLOW_UNKNOWN_REPAIR=false
TIMEOUT_SECONDS=3600
TIMEOUT_KILL_AFTER=30
MIN_DISK_SPACE_GB=5
MIN_BOOT_SPACE_GB=1
MIN_BATTERY_PCT=30
MAX_LOG_AGE_DAYS=30
MAX_LOG_SIZE_MB=5
MAX_HISTORY_SIZE_MB=10
MAX_HISTORY_AGE_DAYS=365
MAX_VERIFICATION_AGE_DAYS=90
MAX_NOTIFICATION_ITEMS=30

HISTORY_HEADER="DATE,TRANSACTION,HEALTH,CLEANUP,FALLBACK,DNF_COUNT,FLATPAK_COUNT"
FALLBACK_CMD=(/usr/bin/dnf distro-sync --refresh -y)
CURRENT_FLATPAK_FRESHNESS="unknown"

HOST_ARCH=$(uname -m 2>/dev/null || echo "x86_64")
BASE_ARCHS="x86_64|i686|i386|aarch64|armv7hl|armv7|ppc64le|s390x|noarch"
if [[ ! "$HOST_ARCH" =~ ^($BASE_ARCHS)$ ]]; then
    ALLOWED_ARCHS="${BASE_ARCHS}|${HOST_ARCH}"
else
    ALLOWED_ARCHS="$BASE_ARCHS"
fi

# ================= CLI PARSING =================
usage() {
    cat >&2 <<EOF
Usage: $0 [flags]

  --dry-run              No package transactions. Discovery lists go to
                         \$STATE_DIR/dry-run/. Only \$STATE_DIR, \$LOG_DIR,
                         the dry-run subdirectory, lock, and logs are created.
                         Verification/archive directories are NOT created.
                         Note: flatpak remote-ls may refresh Flatpak's own
                         metadata caches; dry-run is not filesystem-read-only.
  --enable-autoremove    Enable post-update dnf autoremove (risky)
  --enable-fallback      Enable dnf upgrade fallback on package conflict
  --no-fallback          Disable fallback (default)
  --allow-unknown-repair Permit flatpak repair on unclassified failures
  --help, -h             This message

Exit: 0 success, 1 runtime failure, 2 CLI error
EOF
}

for arg in "$@"; do
    case "$arg" in
        --dry-run)               DRY_RUN=true ;;
        --enable-autoremove)     ENABLE_AUTOREMOVE=true ;;
        --enable-fallback)       ENABLE_FALLBACK=true ;;
        --no-fallback)           ENABLE_FALLBACK=false ;;
        --allow-unknown-repair)  ALLOW_UNKNOWN_REPAIR=true ;;
        --help|-h)               usage; exit 0 ;;
        *)                       echo "ERROR: unknown argument: $arg" >&2
                                 usage; exit 2 ;;
    esac
done

readonly CRITICAL_SERVICES=(
    "NetworkManager.service" "sshd.service" "dbus.service" "systemd-logind.service"
)
is_critical_service() {
    local svc="$1" c
    for c in "${CRITICAL_SERVICES[@]}"; do [[ "$svc" == "$c" ]] && return 0; done
    return 1
}

# [FIX 139] Dry-run only creates directories it actually uses.
mkdir -p "$STATE_DIR" "$LOG_DIR" || {
    echo "FATAL: Cannot create directories" >&2; exit 1
}
if [[ "$DRY_RUN" != "true" ]]; then
    mkdir -p "$VERIFICATION_LOG_DIR" "$LOG_DIR/archive" || {
        echo "FATAL: Cannot create operational directories" >&2; exit 1
    }
fi

# [FIX 130] [FIX 137] Dry-run isolation: lists and temp files go elsewhere.
if [[ "$DRY_RUN" == "true" ]]; then
    LISTS_DIR="$STATE_DIR/dry-run"
    mkdir -p "$LISTS_DIR" || { echo "FATAL: Cannot create dry-run dir" >&2; exit 1; }
else
    LISTS_DIR="$STATE_DIR"
fi

SYSTEM_UPTODATE_LOG_FILE="$STATE_DIR/last_system_uptodate_log"
PRE_UPDATE_KERNEL_FILE="$STATE_DIR/pre_update_kernel"
PRE_UPDATE_TRANSACTION_FILE="$STATE_DIR/pre_update_transaction"
POST_UPDATE_KERNEL_FILE="$STATE_DIR/post_update_kernel"
FLATPAK_FRESHNESS_FILE="$STATE_DIR/flatpak_freshness"
NOBARA_SYNC_SUCCESS_FILE="$STATE_DIR/last_nobara_sync_success"
TRANSACTION_SUCCESS_FILE="$STATE_DIR/last_transaction_success"
# [FIX 148] Marker for "nobara-sync staged an update for the next boot".
# Content is the boot ID of the boot in which staging happened, so the marker
# goes stale by itself after a reboot. BOOT_ID_FILE is overridable for testing.
REBOOT_STAGED_FILE="$STATE_DIR/reboot_staged"
BOOT_ID_FILE="${BOOT_ID_FILE:-/proc/sys/kernel/random/boot_id}"

UPDATE_START_TS=""
MUTATING_IN_PROGRESS=false
PRE_UPDATE_STATE_VALID=false

LAST_DNF_EXIT=""
LAST_ORIGINAL_DNF_EXIT=""
LAST_FLATPAK_EXIT=""
LAST_VERIFY_RC=""
LAST_FALLBACK_USED=false
LAST_CLEANUP_FAILED=false
LAST_CLEANUP_ACTIONS=""

# ================= ATOMIC FILE WRITES =================
safe_write_timestamp() {
    local target="$1" tmp
    tmp=$(mktemp "$STATE_DIR/tmp.ts.XXXXXX" 2>/dev/null) || return 1
    date +%s > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
    mv -f "$tmp" "$target" 2>/dev/null || { rm -f "$tmp"; return 1; }
}

safe_write_content() {
    local target="$1" content="$2" tmp
    tmp=$(mktemp "$STATE_DIR/tmp.content.XXXXXX" 2>/dev/null) || return 1
    printf '%s\n' "$content" > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
    mv -f "$tmp" "$target" 2>/dev/null || { rm -f "$tmp"; return 1; }
}

mktemp_safe() {
    local dir="${1:-$STATE_DIR}"
    mktemp "$dir/tmp.XXXXXX" 2>/dev/null || {
        echo "FATAL: mktemp failed in $dir" >> "$LOGFILE"
        return 1
    }
}

safe_archive_move() {
    local src="$1" base="$2" ext="$3" dest suffix
    dest="$LOG_DIR/archive/${base}.$(date +%F-%H%M%S).${ext}"
    if ln "$src" "$dest" 2>/dev/null; then
        if rm -f "$src" 2>/dev/null && [[ ! -e "$src" ]]; then
            printf '%s\n' "$dest"; return 0
        fi
        rm -f "$dest" 2>/dev/null; return 1
    fi
    suffix="${RANDOM}${RANDOM}"
    dest="$LOG_DIR/archive/${base}.$(date +%F-%H%M%S).${suffix}.${ext}"
    if ln "$src" "$dest" 2>/dev/null; then
        if rm -f "$src" 2>/dev/null && [[ ! -e "$src" ]]; then
            printf '%s\n' "$dest"; return 0
        fi
        rm -f "$dest" 2>/dev/null; return 1
    fi
    dest="$LOG_DIR/archive/${base}.$(date +%F-%H%M%S).${suffix}.mv.${ext}"
    if mv -n "$src" "$dest" 2>/dev/null && [[ ! -e "$src" ]] && [[ -e "$dest" ]]; then
        printf '%s\n' "$dest"; return 0
    fi
    return 1
}

run_with_timeout() {
    local t="$1"; shift
    timeout --signal=TERM --kill-after="${TIMEOUT_KILL_AFTER}s" "$t" "$@"
}

# ================= LOGGING =================
log()      { printf '%s %s\n' "$(date '+%F %T')" "- $*" | tee -a "$LOGFILE"; }
log_raw()  { printf '%s\n' "$*" | tee -a "$LOGFILE"; }
log_blank(){ printf '\n' >> "$LOGFILE"; }

# ================= NOTIFICATION =================
notify() {
    [[ "$DRY_RUN" == "true" ]] && return 0
    command -v notify-send >/dev/null || return 0
    notify-send -u "${2:-normal}" -t "${3:-5000}" "Auto Update" "$1" 2>/dev/null && return 0
    return 0
}
notify_with_list() {
    [[ "$DRY_RUN" == "true" ]] && return 0
    command -v notify-send >/dev/null || return 0
    local plain="${2//<b>/}"; plain="${plain//<\/b>/}"
    [[ ${#plain} -gt 3000 ]] && plain="${plain:0:3000}..."
    notify-send -u "${3:-normal}" -t "${4:-0}" "Auto Update: $1" "$plain" 2>/dev/null && return 0
    return 0
}
alert_failure() { log "ALERT: $1"; notify "$1" critical; }

system_up_to_date() {
    local now=$(date +%s) last_log=0
    [[ -f "$SYSTEM_UPTODATE_LOG_FILE" ]] && {
        last_log=$(<"$SYSTEM_UPTODATE_LOG_FILE")
        [[ ! "$last_log" =~ ^[0-9]+$ ]] && last_log=0
    }
    if [[ $((now - last_log)) -ge 86400 ]]; then
        log "System is up to date."
        notify "System is up to date." normal
        if [[ "$DRY_RUN" != "true" ]]; then
            safe_write_timestamp "$SYSTEM_UPTODATE_LOG_FILE" || \
                log "WARNING: could not persist up-to-date timestamp"
        fi
    fi
}

# ================= INTERNET =================
check_internet() {
    local e
    for e in "https://www.google.com" "https://www.cloudflare.com" \
             "https://www.microsoft.com" "https://mirrors.fedoraproject.org"; do
        curl -fsI --connect-timeout 5 --max-time 10 "$e" >/dev/null 2>&1 && return 0
    done
    return 1
}

# ================= LOCK HANDLING =================
KEEP_ALIVE_PID=""
LOCK_ACQUIRED=false
cleanup_keepalive() {
    if [[ -n "${KEEP_ALIVE_PID:-}" ]] && kill -0 "$KEEP_ALIVE_PID" 2>/dev/null; then
        kill "$KEEP_ALIVE_PID" 2>/dev/null || true
        wait "$KEEP_ALIVE_PID" 2>/dev/null || true
    fi
    KEEP_ALIVE_PID=""
}
cleanup_lock() {
    if [[ "${LOCK_ACQUIRED:-false}" == "true" ]]; then
        flock -u 9 2>/dev/null || true
        exec 9>&- 2>/dev/null || true
        LOCK_ACQUIRED=false
    fi
}

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    printf '%s - Already running\n' "$(date '+%F %T')" | tee -a "$LOGFILE"; exit 1
fi
LOCK_ACQUIRED=true

handle_signal() {
    local sig="$1" code="$2"
    trap '' SIGTERM SIGINT
    log "Received $sig, exiting..."
    pkill -TERM -P $$ 2>/dev/null || true
    local w=0
    while pgrep -P $$ >/dev/null 2>&1 && [[ $w -lt 10 ]]; do sleep 1; ((w++)); done
    pgrep -P $$ >/dev/null 2>&1 && { log "Escalating to SIGKILL"; pkill -KILL -P $$ 2>/dev/null || true; sleep 1; }
    [[ "${MUTATING_IN_PROGRESS:-false}" == "true" ]] && \
        log "WARNING: terminated during mutating phase; use systemd KillMode=control-group for full safety"
    cleanup_keepalive
    cleanup_lock
    exit $(( 128 + code ))
}
trap 'handle_signal SIGTERM 15' SIGTERM
trap 'handle_signal SIGINT 2' SIGINT

# History schema migration (skipped in dry-run)
if [[ "$DRY_RUN" != "true" ]]; then
    if [[ -s "$HISTORY_LOG" ]]; then
        if ! head -1 "$HISTORY_LOG" | grep -q "^${HISTORY_HEADER}$"; then
            _old="${LOG_DIR}/archive/update_history.v1.$(date +%F-%H%M%S).csv"
            [[ -e "$_old" ]] && _old="${_old%.csv}.${RANDOM}.csv"
            mv -f "$HISTORY_LOG" "$_old" 2>/dev/null || {
                echo "FATAL: could not archive old history" >&2; exit 1; }
            printf '%s\n' "$HISTORY_HEADER" > "$HISTORY_LOG" || {
                echo "FATAL: could not write new history header" >&2; exit 1; }
            echo "Migrated old history to $_old" >&2
        fi
    else
        printf '%s\n' "$HISTORY_HEADER" > "$HISTORY_LOG" || {
            echo "FATAL: could not initialize history" >&2; exit 1; }
    fi
fi

# ================= SAFETY CHECKS =================
check_package_lock() {
    local p
    for p in dnf dnf5 rpm packagekitd; do
        ps -C "$p" --no-headers >/dev/null 2>&1 && { log "$p already running"; return 1; }
    done
    return 0
}

check_disk() {
    local avail min_bytes=$(( MIN_DISK_SPACE_GB * 1024 * 1024 * 1024 ))
    avail=$(df -B1 --output=avail / 2>/dev/null | tail -1 | tr -dc '0-9')
    [[ -z "$avail" || ! "$avail" =~ ^[0-9]+$ ]] && { log "Could not determine / disk space"; return 1; }
    [[ "$avail" -lt "$min_bytes" ]] && { log "Low disk on /: $((avail/1024/1024))MB"; return 1; }
    if [[ -d /boot ]]; then
        local bt brc=0
        bt=$(findmnt -n -o TARGET /boot 2>/dev/null) || brc=$?
        [[ $brc -ne 0 || -z "$bt" ]] && { log "Could not determine /boot mount"; return 1; }
        if [[ "$bt" != "/" ]]; then
            avail=$(df -B1 --output=avail /boot 2>/dev/null | tail -1 | tr -dc '0-9')
            [[ -z "$avail" || ! "$avail" =~ ^[0-9]+$ ]] && { log "Could not determine /boot space"; return 1; }
            local bmin=$(( MIN_BOOT_SPACE_GB * 1024 * 1024 * 1024 ))
            [[ "$avail" -lt "$bmin" ]] && { log "Low disk on /boot: $((avail/1024/1024))MB"; return 1; }
        fi
    fi
    # [FIX 145] /boot/efi check — nobara-sync refuses to update if <32 MiB free
    if [[ -d /boot/efi ]]; then
        local efi_target efi_rc=0
        efi_target=$(findmnt -n -o TARGET /boot/efi 2>/dev/null) || efi_rc=$?
        if [[ $efi_rc -eq 0 && -n "$efi_target" ]]; then
            avail=$(df -B1 --output=avail /boot/efi 2>/dev/null | tail -1 | tr -dc '0-9')
            if [[ -z "$avail" || ! "$avail" =~ ^[0-9]+$ ]]; then
                log "Could not determine /boot/efi space - blocking"; return 1
            fi
            local efi_min=$(( 32 * 1024 * 1024 ))
            if [[ "$avail" -lt "$efi_min" ]]; then
                log "Low disk on /boot/efi: $((avail/1024/1024))MB (nobara-sync needs 32MB)"
                return 1
            fi
        fi
    fi
    return 0
}

BATTERY_WARNING_LOGGED=false
check_battery() {
    shopt -s nullglob
    local bat_files=(/sys/class/power_supply/BAT* /sys/class/power_supply/BATT*)
    shopt -u nullglob
    local sysfs_found=false cap status
    for bat in "${bat_files[@]}"; do
        [[ -f "$bat/capacity" ]] || continue
        sysfs_found=true
        cap=$(<"$bat/capacity"); status=$(<"$bat/status")
        [[ ! "$cap" =~ ^[0-9]+$ || -z "$status" ]] && { log "Battery $bat unreadable"; return 1; }
        [[ "$status" == "Discharging" && "$cap" -lt "$MIN_BATTERY_PCT" ]] && {
            log "Low battery: ${cap}% ($status)"; return 1; }
    done
    $sysfs_found && return 0
    if command -v upower >/dev/null 2>&1; then
        local urc=0 devs bat_devs
        devs=$(upower -e 2>/dev/null) || urc=$?
        [[ $urc -ne 0 ]] && { log "upower failed (rc=$urc)"; return 1; }
        bat_devs=$(printf '%s\n' "$devs" | grep -i BAT || true)
        if [[ -z "$bat_devs" ]]; then
            ! $BATTERY_WARNING_LOGGED && { log "No battery (desktop)"; BATTERY_WARNING_LOGGED=true; }
            return 0
        fi
        local any=false info cap_int
        while IFS= read -r dev; do
            [[ -z "$dev" ]] && continue
            any=true
            info=$(upower -i "$dev" 2>/dev/null) || { log "upower -i $dev failed"; return 1; }
            cap=$(printf '%s\n' "$info" | awk '/percentage/ {gsub(/%/,"",$2); print $2}')
            status=$(printf '%s\n' "$info" | awk '/state/ {print $2}')
            [[ ! "$cap" =~ ^[0-9]+(\.[0-9]+)?$ || -z "$status" ]] && {
                log "Battery $dev unparseable"; return 1; }
            awk -v v="$cap" 'BEGIN { exit !(v >= 0 && v <= 100) }' || {
                log "Battery $dev out of range ($cap)"; return 1; }
            cap_int="${cap%.*}"; [[ -z "$cap_int" ]] && cap_int=0
            [[ "$status" == "discharging" && "$cap_int" -lt "$MIN_BATTERY_PCT" ]] && {
                log "Low battery: $dev ${cap}%"; return 1; }
        done <<< "$bat_devs"
        $any && return 0
    fi
    ! $BATTERY_WARNING_LOGGED && { log "No battery (desktop)"; BATTERY_WARNING_LOGGED=true; }
    return 0
}

# ================= COOLDOWNS =================
can_notify_warning() {
    local f="$STATE_DIR/last_warning_notify"
    [[ ! -f "$f" ]] && return 0
    local t=$(<"$f"); [[ ! "$t" =~ ^[0-9]+$ ]] && t=0
    [[ $(( $(date +%s) - t )) -gt 86400 ]]
}
can_notify_restored() {
    local f="$STATE_DIR/last_restored_notify"
    [[ ! -f "$f" ]] && return 0
    local t=$(<"$f"); [[ ! "$t" =~ ^[0-9]+$ ]] && t=0
    [[ $(( $(date +%s) - t )) -gt 3600 ]]
}
update_warning_timestamp() {
    [[ "$DRY_RUN" == "true" ]] && return 0
    safe_write_timestamp "$STATE_DIR/last_warning_notify" || log "WARNING: cooldown timestamp failed"
}
update_restored_timestamp() {
    [[ "$DRY_RUN" == "true" ]] && return 0
    safe_write_timestamp "$STATE_DIR/last_restored_notify" || log "WARNING: cooldown timestamp failed"
}
update_success_timestamp() {
    [[ "$DRY_RUN" == "true" ]] && return 0
    safe_write_timestamp "$STATE_DIR/last_success"
}
update_transaction_success_timestamp() {
    [[ "$DRY_RUN" == "true" ]] && return 0
    safe_write_timestamp "$TRANSACTION_SUCCESS_FILE" || log "WARNING: transaction timestamp failed"
}
update_nobara_sync_success_timestamp() {
    [[ "$DRY_RUN" == "true" ]] && return 0
    safe_write_timestamp "$NOBARA_SYNC_SUCCESS_FILE" || log "WARNING: nobara-sync timestamp failed"
}

# ================= PRE-UPDATE STATE =================
track_pre_update_state() {
    PRE_UPDATE_STATE_VALID=false
    local ck=$(uname -r) kok=false tok=false
    safe_write_content "$PRE_UPDATE_KERNEL_FILE" "$ck" && kok=true || log "WARNING: pre-update kernel not persisted"
    log "📝 Pre-update kernel: $ck"
    local tid
    tid=$(dnf5 history list 2>/dev/null | awk 'NR>1 && $1 ~ /^[0-9]+$/ {print $1; exit}')
    [[ -z "$tid" ]] && tid=$(dnf history list 2>/dev/null | awk 'NR>1 && $1 ~ /^[0-9]+$/ {print $1; exit}')
    if [[ -n "$tid" && "$tid" =~ ^[0-9]+$ ]]; then
        safe_write_content "$PRE_UPDATE_TRANSACTION_FILE" "$tid" && tok=true || log "WARNING: pre-update trans not persisted"
        log "📝 Pre-update transaction: $tid"
    else
        log "⚠️ Could not determine DNF transaction ID"
    fi
    $kok && $tok && PRE_UPDATE_STATE_VALID=true
}

# ================= VERIFICATION (FIX 146) =================
verify_system_health() {
    local vlog="$VERIFICATION_LOG_DIR/verification_$(date +%F-%H%M%S).${RANDOM}${RANDOM}.log"
    local failed=0 has_critical=false new_failures="" diag_failed=0
    local start_time="${UPDATE_START_TS:-$(date -d '-30 minutes' '+%Y-%m-%d %H:%M:%S')}"

    log "Running post-update verification (journal since $start_time)..."

    local fs systemctl_rc=0
    fs=$(systemctl --failed --no-legend --plain --no-pager 2>/dev/null) || systemctl_rc=$?
    [[ $systemctl_rc -ne 0 ]] && { log "WARNING: systemctl failed (rc=$systemctl_rc)"; diag_failed=1; }
    fs=$(printf '%s\n' "$fs" | awk '{print $1}' | grep -v '^$' | grep -v 'drkonqi-coredump-processor' || true)

    if [[ -n "$fs" ]]; then
        failed=1
        log "WARNING: Failed services:"
        while IFS= read -r svc; do log "  - $svc"; done <<< "$fs"
        while IFS= read -r svc; do
            if [[ -n "$svc" ]] && is_critical_service "$svc"; then
                log "CRITICAL: $svc"
                has_critical=true
                new_failures+="  • $svc (CRITICAL)${NL}"
            fi
        done <<< "$fs"
    elif [[ $systemctl_rc -eq 0 ]]; then
        log "All services OK."
    fi

    local findmnt_rc=0 findmnt_out
    findmnt_out=$(findmnt -n -o OPTIONS / 2>/dev/null) || findmnt_rc=$?
    if [[ $findmnt_rc -ne 0 ]]; then
        log "WARNING: findmnt failed (rc=$findmnt_rc)"; diag_failed=1
    elif echo "$findmnt_out" | grep -qE '(^|,)ro(,|$)'; then
        log "ERROR: Root filesystem read-only!"; failed=1
    else
        log "Root filesystem writable."
    fi

    local journalctl_rc=0 critical_errors
    critical_errors=$(journalctl --since "$start_time" -p 2 --no-pager 2>/dev/null) || journalctl_rc=$?
    if [[ $journalctl_rc -ne 0 ]]; then
        log "WARNING: journalctl failed (rc=$journalctl_rc)"; diag_failed=1; critical_errors=""
    else
        critical_errors=$(printf '%s\n' "$critical_errors" \
            | grep -v -E "drkonqi|coredump|wireplumber.*crashed" \
            | grep -v "^-- No entries" | head -10 || true)
    fi
    if [[ -n "$critical_errors" ]]; then
        log "WARNING: Critical journal entries since update start"; failed=1
    elif [[ $journalctl_rc -eq 0 ]]; then
        log "No critical journal entries."
    fi

    local health_status
    if [[ $failed -eq 1 ]]; then
        health_status="ISSUES DETECTED"
    elif [[ $diag_failed -eq 1 ]]; then
        health_status="DEGRADED (health diagnostics incomplete)"
    else
        health_status="HEALTHY"
    fi

    local tmp_report=""
    tmp_report=$(mktemp "$VERIFICATION_LOG_DIR/report.tmp.XXXXXX" 2>/dev/null) || {
        log "ERROR: could not create verification tempfile"
        diag_failed=1
        tmp_report=""
    }

    if [[ -n "$tmp_report" ]]; then
        {
            echo "=========================================="
            echo "Nobara Post-Update Verification Report"
            echo "=========================================="
            echo "Time: $(date '+%F %T')"
            echo "Host: $(hostname)"
            echo "Kernel: $(uname -r)"
            echo ""
            echo "1. FAILED SERVICES:"
            [[ -n "$fs" ]] && echo "$fs" || echo "None"
            echo ""
            echo "2. CRITICAL SERVICE FAILURES:"
            [[ "$has_critical" == "true" ]] && echo "YES - Manual intervention recommended" || echo "None"
            echo ""
            echo "3. FILESYSTEM STATUS:"
            if [[ $findmnt_rc -ne 0 ]]; then echo "UNKNOWN (findmnt failed)"
            elif echo "$findmnt_out" | grep -qE '(^|,)ro(,|$)'; then echo "READ-ONLY - CRITICAL"
            else echo "Writable - OK"; fi
            echo ""
            echo "4. CRITICAL JOURNAL ENTRIES (priority<=2, since $start_time):"
            if [[ $journalctl_rc -ne 0 ]]; then echo "UNKNOWN (journalctl failed)"
            else echo "$critical_errors"; fi
            echo ""
            echo "5. DIAGNOSTIC STATE:"
            [[ $diag_failed -eq 1 ]] && echo "Some checks incomplete" || echo "All checks completed"
            echo "=========================================="
            echo "HEALTH STATUS: $health_status"
            echo "  (Report persistence is logged separately as PERSISTENCE:; the"
            echo "   function's return code may be DEGRADED even when this line says HEALTHY.)"
            echo "=========================================="
            # [FIX 146] Explicit if + trailing `true` so the group's exit status
            # is 0 when $failed=0, preventing the || handler from deleting the
            # report on healthy cycles.
            if [[ $failed -eq 1 ]]; then
                echo ""
                if [[ "$PRE_UPDATE_STATE_VALID" == "true" ]]; then
                    echo "MANUAL ROLLBACK INFO:"
                    echo "  sudo dnf history rollback $(cat "$PRE_UPDATE_TRANSACTION_FILE" 2>/dev/null || echo 'N/A')"
                else
                    echo "MANUAL ROLLBACK INFO: UNAVAILABLE (pre-update state not persisted)"
                fi
            fi
            true
        } > "$tmp_report" 2>&1 || {
            diag_failed=1
            rm -f "$tmp_report" 2>/dev/null
            tmp_report=""
        }
    fi

    local report_saved="no" log_appended="no"
    if [[ -n "$tmp_report" ]]; then
        if mv -f "$tmp_report" "$vlog" 2>/dev/null; then
            report_saved="yes"
            if cat "$vlog" >> "$LOGFILE" 2>/dev/null; then
                log_appended="yes"
            else
                log "ERROR: could not append report to main log"
                diag_failed=1
            fi
        else
            log "ERROR: could not persist report to $vlog"
            diag_failed=1
            rm -f "$tmp_report"
        fi
    fi
    log "PERSISTENCE: report_saved=$report_saved log_appended=$log_appended (vlog=$vlog)"

    if [[ $failed -eq 1 ]]; then
        log "Post-update verification: ISSUES DETECTED"
        if [[ "$has_critical" == "true" ]]; then
            notify_with_list "⚠️ CRITICAL ISSUES" \
                "Critical services failed:${NL}${NL}${new_failures}${NL}Log: $vlog" "critical" 0
        else
            notify "Post-update issues detected - check log" normal
        fi
    elif [[ $diag_failed -eq 1 ]]; then
        log "Post-update verification: DEGRADED"
    else
        log "Post-update verification: HEALTHY"
    fi

    find "$VERIFICATION_LOG_DIR" -type f -name "verification_*.log" -mtime +"$MAX_VERIFICATION_AGE_DAYS" -delete 2>/dev/null || true

    if [[ $failed -eq 1 ]]; then return 1; fi
    if [[ $diag_failed -eq 1 ]]; then return 2; fi
    return 0
}

# ================= SECURITY CHECKS (advisory) =================
post_update_security_check() {
    log "Running post-update security checks (advisory)..."
    command -v aa-status >/dev/null 2>&1 && { aa-status >> "$LOGFILE" 2>&1 || log "AppArmor check failed"; }
    for svc in NetworkManager sshd dbus systemd-logind firewalld auditd; do
        systemctl is-active --quiet "$svc" 2>/dev/null && log "✅ $svc active" || log "⚠️ $svc not active"
    done
    log "Listening ports (ss):"
    local ss_out ss_rc=0
    ss_out=$(sudo -n /usr/bin/ss -tulpn 2>/dev/null) || ss_rc=$?
    [[ $ss_rc -ne 0 ]] && { log "  (privileged ss rc=$ss_rc; trying unpriv)"; ss_out=$(ss -tulpn 2>/dev/null) || true; }
    [[ -n "$ss_out" ]] && printf '%s\n' "$ss_out" | head -50 | while read -r line; do log_raw "  $line"; done
    log "Recent kernel errors:"
    journalctl -b -p 3 --no-pager 2>/dev/null | tail -50 | while read -r line; do log_raw "  $line"; done
    local fu
    fu=$(systemctl --failed --no-legend --plain --no-pager 2>/dev/null \
        | awk '{print $1}' | grep -v '^$' | grep -v 'drkonqi-coredump-processor' || true)
    [[ -n "$fu" ]] && { log "⚠️ Failed units:"; while IFS= read -r u; do log "  - $u"; done <<< "$fu"; } \
                   || log "✅ No failed units"
    log "Advisory checks complete."
}

# ================= REBOOT TRACKING =================
detect_installed_kernel() {
    local running=$(uname -r) family newest
    family=$(rpm -qf "/lib/modules/${running}/vmlinuz" 2>/dev/null | head -n1 | sed 's/-[0-9].*$//')
    [[ "$family" != kernel* ]] || ! rpm -q "$family" >/dev/null 2>&1 && { printf '\n'; return 0; }
    newest=$(rpm -q "$family" 2>/dev/null | sed "s/^${family}-//" | sort -V | tail -n1)
    printf '%s\n' "$newest"
}

# [FIX 148] Staged-update marker helpers.
current_boot_id() { tr -d '[:space:]' < "$BOOT_ID_FILE" 2>/dev/null; }

# True (0) when nobara-sync staged an update during the CURRENT boot.
update_already_staged() {
    local bid marker
    bid=$(current_boot_id)
    [[ -n "$bid" && -s "$REBOOT_STAGED_FILE" ]] || return 1
    marker=$(tr -d '[:space:]' < "$REBOOT_STAGED_FILE" 2>/dev/null)
    [[ "$marker" == "$bid" ]]
}

detect_offline_update_pending() {
    [[ -e /system-update || -L /system-update ]] && return 0
    # [FIX 148] nobara-sync stages updates under /var/lib/nobara-updater/jobs/,
    # which the directory probes below do not cover; use the marker instead.
    update_already_staged && return 0
    if [[ -e "$REBOOT_STAGED_FILE" && "$DRY_RUN" != "true" ]]; then
        rm -f "$REBOOT_STAGED_FILE"   # marker belongs to a previous boot
    fi
    local unknown=0 d contents rc parent
    for d in /usr/lib/sysimage/dnf/offline /var/lib/dnf/offline \
             /var/lib/nobara-updater/offline /var/lib/nobara-updater/staged; do
        if [[ -d "$d" ]]; then
            rc=0; contents=$(ls -A "$d" 2>/dev/null) || rc=$?
            if [[ $rc -ne 0 ]]; then
                rc=0; contents=$(sudo -n /usr/bin/ls -A "$d" 2>/dev/null) || rc=$?
                [[ $rc -ne 0 ]] && { unknown=1; continue; }
            fi
            [[ -n "$contents" ]] && return 0
        else
            parent=$(dirname "$d")
            [[ ! -d "$parent" ]] && continue
            if [[ ! -r "$parent" ]] || { [[ ! -x "$parent" ]] && [[ "$(id -u)" != "0" ]]; }; then
                # [FIX 144] Parent is unreadable/untraversable (e.g.
                # /var/lib/nobara-updater is 0700 root). Use sudo to probe
                # the child directly:
                #   rc=0, empty output  -> exists but empty  -> not pending
                #   rc=0, non-empty     -> exists with files -> pending
                #   rc=2                -> ENOENT            -> not pending
                #   anything else       -> genuinely unknown
                rc=0
                contents=$(sudo -n /usr/bin/ls -A "$d" 2>/dev/null) || rc=$?
                if [[ $rc -eq 0 ]]; then
                    [[ -n "$contents" ]] && return 0
                elif [[ $rc -ne 2 ]]; then
                    unknown=1
                fi
                continue
            fi
        fi
    done
    [[ $unknown -eq 1 ]] && return 2
    return 1
}

REBOOT_NOTIFIED_FILE="$STATE_DIR/reboot_notified"
is_reboot_needed() {
    local offline_rc=0
    detect_offline_update_pending; offline_rc=$?
    [[ $offline_rc -eq 0 ]] && return 0
    local installed=$(detect_installed_kernel) running=$(uname -r)
    [[ -z "$installed" ]] && return 2
    [[ "$installed" != "$running" ]] && return 0
    [[ $offline_rc -eq 2 ]] && return 2
    return 1
}

set_reboot_notified() {
    local value="$1"
    if [[ "$DRY_RUN" == "true" ]]; then
        REBOOT_NOTIFIED="$value"; log "DEBUG: dry-run reboot_notified=$value"; return 0
    fi
    if safe_write_content "$REBOOT_NOTIFIED_FILE" "$value"; then
        REBOOT_NOTIFIED="$value"; return 0
    fi
    log "WARNING: could not persist reboot_notified=$value"; return 1
}

clear_reboot_notification_if_not_needed() {
    [[ "$DRY_RUN" == "true" ]] && return 1
    local rc=0
    is_reboot_needed; rc=$?
    case $rc in 0|2) return 1 ;; esac
    if [[ -f "$REBOOT_NOTIFIED_FILE" ]]; then
        local content=$(<"$REBOOT_NOTIFIED_FILE")
        if [[ "$(tr -d '[:space:]' <<< "$content")" == "true" ]]; then
            set_reboot_notified "false" && log "Cleared reboot notification" \
                || log "WARNING: failed to clear notification"
        fi
    fi
    return 0
}

REBOOT_NOTIFIED=false
if [[ -f "$REBOOT_NOTIFIED_FILE" ]]; then
    _rc=$(<"$REBOOT_NOTIFIED_FILE")
    [[ "$(tr -d '[:space:]' <<< "$_rc")" == "true" ]] && REBOOT_NOTIFIED=true
fi

quick_verify() {
    local issues=0
    clear_reboot_notification_if_not_needed

    local sctl_rc=0 fo
    fo=$(systemctl --failed --no-legend --plain --no-pager 2>/dev/null) || sctl_rc=$?
    if [[ $sctl_rc -ne 0 ]]; then
        log "Quick check: systemctl failed (rc=$sctl_rc)"
        can_notify_warning && { notify "System UNKNOWN - systemctl failed" normal; update_warning_timestamp; } \
                            || log "Quick check: alert suppressed (cooldown)"
        issues=1
    else
        if printf '%s\n' "$fo" | awk '{print $1}' | grep -v '^$' \
            | grep -v 'drkonqi-coredump-processor' | grep -q .; then
            log "Quick check: Failed services"
            can_notify_warning && { notify "System degraded" normal; update_warning_timestamp; } \
                                || log "Quick check: alert suppressed"
            issues=1
        fi
    fi

    local rc=0
    is_reboot_needed; rc=$?
    case $rc in
        0)
            if [[ "$REBOOT_NOTIFIED" != "true" ]]; then
                local reason offline_rc=0
                detect_offline_update_pending; offline_rc=$?
                if [[ $offline_rc -eq 0 ]]; then
                    reason="Update staged offline; reboot to apply."
                else
                    reason="Kernel updated to $(detect_installed_kernel); reboot recommended."
                fi
                log "Quick check: reboot needed — $reason"
                notify "🔁 RESTART REQUIRED!${NL}${NL}${reason}" critical 0
                set_reboot_notified "true" || log "WARNING: could not persist"
            fi
            ;;
        2) log "DEBUG: reboot state unknown" ;;
        *)
            [[ "$REBOOT_NOTIFIED" == "true" ]] && { set_reboot_notified "false" \
                || log "WARNING: could not clear notification"; }
            ;;
    esac
    return $issues
}

# ================= FETCH UPDATES (FIX 147) =================
fetch_pending_updates() {
    check_package_lock || { log "Package manager active; skipping fetch"; return 1; }

    if [[ "$DRY_RUN" != "true" ]]; then
        : > "$LISTS_DIR/dnf_list" 2>/dev/null || { log "ERROR: could not clear dnf_list"; return 1; }
        : > "$LISTS_DIR/flatpak_list" 2>/dev/null || { log "ERROR: could not clear flatpak_list"; return 1; }
    else
        : > "$LISTS_DIR/dnf_list" 2>/dev/null || true
        : > "$LISTS_DIR/flatpak_list" 2>/dev/null || true
    fi

    local tmp err dnf_rc=0 rc=0 fp_raw appstream_rc=0 freshness="unknown"
    tmp=$(mktemp_safe "$LISTS_DIR") || return 1
    err=$(mktemp_safe "$LISTS_DIR") || { rm -f "$tmp"; return 1; }

    if [[ "$DRY_RUN" == "true" ]]; then
        run_with_timeout "$TIMEOUT_SECONDS" sudo -n /usr/bin/dnf check-update >"$tmp" 2>"$err" || dnf_rc=$?
    else
        run_with_timeout "$TIMEOUT_SECONDS" sudo -n /usr/bin/dnf check-update --refresh >"$tmp" 2>"$err" || dnf_rc=$?
    fi

    case $dnf_rc in
        0) ;;
        100) log "DNF updates available" ;;
        *) log "DNF check-update failed (rc=$dnf_rc): $(head -c 300 "$err" | tr '\n' ' ')"
           rc=1 ;;
    esac

    if (( dnf_rc == 0 || dnf_rc == 100 )); then
        if ! awk -v pat="\\.(${ALLOWED_ARCHS})$" 'NF >= 3 && $1 ~ pat { print $1 " (" $2 ")" }' "$tmp" \
                >"$LISTS_DIR/dnf_list.new" 2>/dev/null; then
            log "ERROR: dnf parser write failed"; rm -f "$LISTS_DIR/dnf_list.new"; rc=1
        else
            local pc=0 cr=0 mr=0
            pc=$(wc -l < "$LISTS_DIR/dnf_list.new" 2>/dev/null || echo 0)
            if (( dnf_rc == 100 )); then
                cr=$(awk 'NF >= 3 && $1 ~ /\.[a-z0-9_]+$/ { n++ } END { print n+0 }' "$tmp")
                mr=$(( cr - pc ))
            fi
            if (( dnf_rc == 100 )) && [[ "$pc" -eq 0 ]]; then
                log "WARNING: DNF reported updates but parser found none"
                head -10 "$tmp" | while IFS= read -r l; do log_raw "  RAW: $l"; done
                rc=1; rm -f "$LISTS_DIR/dnf_list.new"
            elif [[ "$mr" -gt 0 ]]; then
                log "WARNING: DNF parser dropped $mr rows"
                head -10 "$tmp" | while IFS= read -r l; do log_raw "  RAW: $l"; done
                rc=1; rm -f "$LISTS_DIR/dnf_list.new"
            else
                mv -f "$LISTS_DIR/dnf_list.new" "$LISTS_DIR/dnf_list" 2>/dev/null || {
                    log "WARNING: could not commit dnf_list"
                    : > "$LISTS_DIR/dnf_list" 2>/dev/null || true
                    rc=1
                }
            fi
        fi
    fi

    if command -v flatpak >/dev/null 2>&1; then
        if [[ "$DRY_RUN" == "true" ]]; then
            freshness="dry-run"
        else
            MUTATING_IN_PROGRESS=true
            run_with_timeout "$TIMEOUT_SECONDS" flatpak update --appstream --noninteractive >>"$LOGFILE" 2>&1 || appstream_rc=$?
            MUTATING_IN_PROGRESS=false
            if [[ $appstream_rc -ne 0 ]]; then
                log "WARNING: appstream refresh failed; metadata may be stale"
                freshness="stale"
            else
                freshness="current"
            fi
        fi
        CURRENT_FLATPAK_FRESHNESS="$freshness"
        if [[ "$DRY_RUN" != "true" ]]; then
            safe_write_content "$FLATPAK_FRESHNESS_FILE" "$freshness" \
                || log "WARNING: freshness marker not persisted"
        fi

        fp_raw=$(mktemp_safe "$LISTS_DIR") || { log "ERROR: flatpak tempfile failed"; fp_raw=""; rc=1; }
        if [[ -n "$fp_raw" ]]; then
            if run_with_timeout "$TIMEOUT_SECONDS" flatpak remote-ls --updates --columns=application,version >"$fp_raw" 2>"$err"; then
                # [FIX 147] Relaxed validation: reject only NF>2 (multi-column
                # junk) and malformed IDs. Single-field rows (runtimes with no
                # version) are accepted.
                local bad=0
                bad=$(awk 'BEGIN{bad=0} NF==0{next} NF>2{bad++;next} $1!~/^[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)+$/{bad++;next} END{print bad+0}' "$fp_raw" 2>/dev/null || echo 0)
                if [[ "$bad" -gt 0 ]]; then
                    log "WARNING: flatpak output has $bad malformed rows"
                    : > "$LISTS_DIR/flatpak_list" 2>/dev/null || true; rc=1
                # [FIX 147] Parse: emit "name (no version)" for single-field rows.
                elif ! awk '{ if (NF >= 2 && $2 != "") print $1 " (" $2 ")"; else print $1 " (no version)" }' "$fp_raw" >"$LISTS_DIR/flatpak_list.new" 2>/dev/null; then
                    log "WARNING: flatpak parse failed"
                    : > "$LISTS_DIR/flatpak_list" 2>/dev/null || true; rc=1
                elif ! mv -f "$LISTS_DIR/flatpak_list.new" "$LISTS_DIR/flatpak_list" 2>/dev/null; then
                    log "WARNING: could not commit flatpak_list"
                    : > "$LISTS_DIR/flatpak_list" 2>/dev/null || true; rc=1
                fi
            else
                log "Flatpak remote-ls failed: $(head -c 200 "$err" | tr '\n' ' ')"
                : > "$LISTS_DIR/flatpak_list" 2>/dev/null || true; rc=1
            fi
            rm -f "$fp_raw"
        fi
    else
        : >"$LISTS_DIR/flatpak_list"
        CURRENT_FLATPAK_FRESHNESS="absent"
        [[ "$DRY_RUN" != "true" ]] && safe_write_content "$FLATPAK_FRESHNESS_FILE" "absent"
    fi

    rm -f "$tmp" "$err"
    return $rc
}

updates_available() { [[ -s "$LISTS_DIR/dnf_list" || -s "$LISTS_DIR/flatpak_list" ]]; }

# ================= UPDATE LIST / NOTIFICATIONS =================
build_update_list() {
    local dl="" fl="" dc=0 fc=0 max=$((MAX_NOTIFICATION_ITEMS > 0 ? MAX_NOTIFICATION_ITEMS : 1))
    if [[ -s "$LISTS_DIR/dnf_list" ]]; then
        dc=$(wc -l < "$LISTS_DIR/dnf_list")
        dl="📦 Packages ($dc):${NL}"
        local i=0
        while IFS= read -r line && [[ $i -lt $max ]]; do dl+="  • $line${NL}"; ((i++)); done < "$LISTS_DIR/dnf_list"
        [[ $dc -gt $max ]] && dl+="  ... and $((dc-max)) more${NL}"
    fi
    if [[ -s "$LISTS_DIR/flatpak_list" ]]; then
        fc=$(wc -l < "$LISTS_DIR/flatpak_list")
        fl="🟢 Flatpaks ($fc):${NL}"
        local i=0
        while IFS= read -r line && [[ $i -lt $max ]]; do fl+="  • $line${NL}"; ((i++)); done < "$LISTS_DIR/flatpak_list"
        [[ $fc -gt $max ]] && fl+="  ... and $((fc-max)) more${NL}"
    fi
    local c=""
    [[ -n "$dl" ]] && c="$dl"
    [[ -n "$fl" ]] && { [[ -n "$c" ]] && c+="${NL}"; c+="$fl"; }
    printf '%s\n' "$c"
}

notify_pending() {
    local ul dc=0 fc=0 total suffix=""
    ul=$(build_update_list)
    [[ -s "$LISTS_DIR/dnf_list" ]] && dc=$(wc -l < "$LISTS_DIR/dnf_list")
    [[ -s "$LISTS_DIR/flatpak_list" ]] && fc=$(wc -l < "$LISTS_DIR/flatpak_list")
    total=$((dc+fc))
    [[ "$CURRENT_FLATPAK_FRESHNESS" == "stale" ]] && suffix=" (Flatpak metadata may be stale)"
    if [[ -n "$ul" ]]; then
        notify_with_list "📦 Updates Detected" "Detected $total updates${suffix}.${NL}${NL}${ul}" "normal" 10000
    else
        notify "Found updates: $total items" normal
    fi
    [[ -s "$LISTS_DIR/dnf_list" ]] && { log_raw "Pending packages:"; while IFS= read -r line; do log_raw "  $line"; done < "$LISTS_DIR/dnf_list"; }
    [[ -s "$LISTS_DIR/flatpak_list" ]] && { log_raw "Pending flatpaks:"; while IFS= read -r line; do log_raw "  $line"; done < "$LISTS_DIR/flatpak_list"; }
}

notify_complete() {
    local ul dc=0 fc=0 total
    ul=$(build_update_list)
    [[ -s "$LISTS_DIR/dnf_list" ]] && dc=$(wc -l < "$LISTS_DIR/dnf_list")
    [[ -s "$LISTS_DIR/flatpak_list" ]] && fc=$(wc -l < "$LISTS_DIR/flatpak_list")
    total=$((dc+fc))
    [[ -n "$ul" ]] && notify_with_list "✅ Update Commands Completed" "Processed $total detected updates.${NL}${NL}${ul}" "normal" 10000 \
                   || notify "Update commands completed" normal
}

# ================= HISTORY =================
write_history_row() {
    [[ "$DRY_RUN" == "true" ]] && return 0
    printf '%s,%s,%s,%s,%s,%d,%d\n' "$(date '+%F')" "$1" "$2" "$3" "$4" "$5" "$6" >> "$HISTORY_LOG" 2>/dev/null \
        || { log "ERROR: failed to append history row"; return 1; }
}

log_detected_packages() {
    local drc="${1:-1}" frc="${2:-1}" d=$(date '+%Y-%m-%d')
    if [[ "$drc" == "0" && -s "$LISTS_DIR/dnf_list" ]]; then
        while IFS= read -r line; do
            printf '%s DNF-DETECTED %s\n' "$d" "$line" >> "$PACKAGE_LOG" 2>/dev/null \
                || log "WARNING: failed to log DNF: $line"
        done < "$LISTS_DIR/dnf_list"
    fi
    if [[ "$frc" == "0" && -s "$LISTS_DIR/flatpak_list" ]]; then
        while IFS= read -r line; do
            printf '%s Flatpak-DETECTED %s\n' "$d" "$line" >> "$PACKAGE_LOG" 2>/dev/null \
                || log "WARNING: failed to log Flatpak: $line"
        done < "$LISTS_DIR/flatpak_list"
    fi
}

# ================= CONTENTION =================
looks_like_lock_contention() {
    [[ -r "$1" ]] || return 1
    grep -qiE 'another (process|copy|transaction|instance)|yum|dnf.*lock|rpmdb|locked by|transaction in progress|packagekit|can.t lock' "$1"
}

# ================= RUN UPDATES =================
run_updates() {
    LAST_DNF_EXIT=""; LAST_ORIGINAL_DNF_EXIT=""; LAST_FLATPAK_EXIT=""; LAST_VERIFY_RC=""
    LAST_FALLBACK_USED=false; LAST_CLEANUP_FAILED=false; LAST_CLEANUP_ACTIONS=""

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY_RUN] Skipping updates."
        LAST_DNF_EXIT="dry-run"; LAST_FLATPAK_EXIT="dry-run"; LAST_VERIFY_RC="dry-run"
        return 0
    fi

    check_package_lock || { LAST_DNF_EXIT="locked"; LAST_FLATPAK_EXIT="skipped"; return 1; }

    local DNF_EXIT=1 FLATPAK_EXIT=1 UPDATE_SUCCESS=1 TSYNC
    TSYNC=$(mktemp_safe) || return 1

    sudo -n /usr/bin/true 2>/dev/null || {
        log "ERROR: no sudo"; LAST_DNF_EXIT="no-sudo"; LAST_FLATPAK_EXIT="no-sudo"
        rm -f "$TSYNC"; return 1
    }

    UPDATE_START_TS=$(date '+%Y-%m-%d %H:%M:%S')
    track_pre_update_state
    MUTATING_IN_PROGRESS=true

    ( exec 9>&-; while kill -0 "$$" 2>/dev/null; do sudo -n /usr/bin/true 2>/dev/null; sleep 60; done ) &
    KEEP_ALIVE_PID=$!

    log_raw "=============================="
    log_raw "Starting Nobara System Update"
    log_raw "=============================="

    run_with_timeout "$TIMEOUT_SECONDS" sudo -n /usr/bin/nobara-sync cli 2>&1 | tee -a "$LOGFILE" > "$TSYNC"
    DNF_EXIT=${PIPESTATUS[0]}
    LAST_ORIGINAL_DNF_EXIT="$DNF_EXIT"
    log_raw "Nobara-sync exit: $DNF_EXIT"
    [[ $DNF_EXIT -eq 124 ]] && log_raw "WARNING: nobara-sync exit 124 (consistent with timeout)"
    [[ $DNF_EXIT -eq 137 ]] && log_raw "WARNING: nobara-sync exit 137 (consistent with SIGKILL after timeout)"

    if [[ $DNF_EXIT -ne 0 && $DNF_EXIT -ne 124 && $DNF_EXIT -ne 137 ]] \
       && looks_like_lock_contention "$TSYNC"; then
        log "Contention detected; skipping cycle"
        LAST_DNF_EXIT="locked-by-other"; LAST_FLATPAK_EXIT="skipped"
        MUTATING_IN_PROGRESS=false; rm -f "$TSYNC"; cleanup_keepalive; return 1
    fi

    if [[ "$ENABLE_FALLBACK" != "true" ]]; then
        [[ $DNF_EXIT -ne 0 ]] && log "Fallback DISABLED; nobara-sync failed, no retry."
    elif [[ $DNF_EXIT -ne 0 && $DNF_EXIT -ne 124 && $DNF_EXIT -ne 137 ]] \
         && grep -qiE 'package conflicts prevent|nothing provides' "$TSYNC"; then
        log "WARNING: package conflict; fallback: ${FALLBACK_CMD[*]}"
        LAST_FALLBACK_USED=true
        run_with_timeout "$TIMEOUT_SECONDS" sudo -n "${FALLBACK_CMD[@]}" \
            --exclude=nobara-updater --exclude=drm-awaiter 2>&1 | tee -a "$LOGFILE" > "$TSYNC"
        DNF_EXIT=${PIPESTATUS[0]}
        log_raw "Fallback exit: $DNF_EXIT (original $LAST_ORIGINAL_DNF_EXIT)"
        [[ $DNF_EXIT -eq 124 ]] && log_raw "WARNING: fallback exit 124 (consistent with timeout)"
        [[ $DNF_EXIT -eq 137 ]] && log_raw "WARNING: fallback exit 137 (consistent with SIGKILL)"
    fi

    # [FIX 148] nobara-sync stages the transaction for the next restart and says
    # so in its result. Must stay after the fallback block (which overwrites
    # $TSYNC). A failed run (DNF_EXIT != 0) never creates the marker.
    if [[ $DNF_EXIT -eq 0 ]] \
       && grep -qE '"reboot_required": *true|Installation requires a restart' "$TSYNC" 2>/dev/null; then
        local boot_id was_staged=false
        boot_id=$(current_boot_id)
        update_already_staged && was_staged=true
        if [[ -z "$boot_id" ]]; then
            log "WARNING: boot ID unreadable; cannot record staged update"
        elif safe_write_content "$REBOOT_STAGED_FILE" "$boot_id"; then
            log "nobara-sync staged an update; reboot required to apply"
            # A fresh staging deserves a fresh notification.
            [[ "$was_staged" == "false" ]] && { set_reboot_notified "false" || true; }
        else
            log "WARNING: could not persist reboot_staged marker"
        fi
    fi

    log_blank; log_raw "=============================="; log_raw "Starting Flatpak Updates"; log_raw "=============================="

    local FP_OUT; FP_OUT=$(mktemp_safe) || FP_OUT=""
    if [[ -n "$FP_OUT" ]]; then
        run_with_timeout "$TIMEOUT_SECONDS" sudo -n /usr/bin/flatpak update -y --no-static-deltas 2>&1 | tee -a "$LOGFILE" > "$FP_OUT"
        FLATPAK_EXIT=${PIPESTATUS[0]}
    else
        run_with_timeout "$TIMEOUT_SECONDS" sudo -n /usr/bin/flatpak update -y --no-static-deltas 2>&1 | tee -a "$LOGFILE"
        FLATPAK_EXIT=${PIPESTATUS[0]}
    fi
    log_raw "Flatpak (system) exit: $FLATPAK_EXIT"
    [[ $FLATPAK_EXIT -eq 124 ]] && log_raw "WARNING: flatpak (system) exit 124 (consistent with timeout)"
    [[ $FLATPAK_EXIT -eq 137 ]] && log_raw "WARNING: flatpak (system) exit 137 (consistent with SIGKILL)"

    if [[ $FLATPAK_EXIT -ne 0 ]]; then
        local fc="unknown"
        [[ $FLATPAK_EXIT -eq 124 || $FLATPAK_EXIT -eq 137 ]] && fc="timeout_or_signal_ambiguous"
        [[ "$fc" == "unknown" && -n "$FP_OUT" ]] && grep -qiE 'network|resolve|connect|temporary failure' "$FP_OUT" 2>/dev/null && fc="network"
        [[ "$fc" == "unknown" && -n "$FP_OUT" ]] && grep -qiE 'corrupt|invalid|damaged|missing commit|broken' "$FP_OUT" 2>/dev/null && fc="corruption"
        log "Flatpak failure class: $fc"
        local do_repair=false
        [[ "$fc" == "corruption" ]] && do_repair=true
        [[ "$fc" == "unknown" && "$ALLOW_UNKNOWN_REPAIR" == "true" ]] && { log "Unknown; repair permitted by flag"; do_repair=true; }
        if $do_repair; then
            run_with_timeout "$TIMEOUT_SECONDS" sudo -n /usr/bin/flatpak repair --system >> "$LOGFILE" 2>&1 \
                || log "WARNING: repair --system failed"
            run_with_timeout "$TIMEOUT_SECONDS" flatpak repair --user >> "$LOGFILE" 2>&1 \
                || log "WARNING: repair --user failed"
        else
            log "Skipping repair (class '$fc')"
        fi
    fi
    [[ -n "$FP_OUT" ]] && rm -f "$FP_OUT"

    if [[ $FLATPAK_EXIT -eq 0 ]]; then
        run_with_timeout "$TIMEOUT_SECONDS" flatpak update --user -y 2>&1 | tee -a "$LOGFILE"
        FLATPAK_EXIT=${PIPESTATUS[0]}
        log_raw "Flatpak (user) exit: $FLATPAK_EXIT"
    fi

    LAST_DNF_EXIT="$DNF_EXIT"; LAST_FLATPAK_EXIT="$FLATPAK_EXIT"
    log_blank; log_raw "=============================="; log_raw "Update Summary"; log_raw "=============================="

    [[ "$LAST_FALLBACK_USED" == "true" ]] && \
        log_raw "NOTE: nobara-sync failed ($LAST_ORIGINAL_DNF_EXIT); fallback used ($DNF_EXIT)"

    if [[ $DNF_EXIT -eq 0 && $FLATPAK_EXIT -eq 0 ]]; then
        UPDATE_SUCCESS=0; log_raw "All update commands completed"
    elif [[ $DNF_EXIT -eq 0 && $FLATPAK_EXIT -ne 0 ]]; then
        log_raw "DNF ok; Flatpak failed ($FLATPAK_EXIT)"; alert_failure "Flatpak updates failed"
    elif [[ $DNF_EXIT -ne 0 && $FLATPAK_EXIT -eq 0 ]]; then
        log_raw "DNF/Nobara-sync failed ($DNF_EXIT)"; alert_failure "System update failed"
    else
        log_raw "Both failed"; alert_failure "All updates failed"
    fi

    [[ $DNF_EXIT -eq 0 || $FLATPAK_EXIT -eq 0 ]] && log_detected_packages "$DNF_EXIT" "$FLATPAK_EXIT"

    if [[ $UPDATE_SUCCESS -eq 0 ]]; then
        notify_complete
        if [[ "$ENABLE_AUTOREMOVE" == "true" ]]; then
            run_with_timeout "$TIMEOUT_SECONDS" sudo -n /usr/bin/dnf autoremove -y \
                --setopt=clean_requirements_on_remove=False 2>&1 | tee -a "$LOGFILE"
            [[ ${PIPESTATUS[0]} -ne 0 ]] && { LAST_CLEANUP_FAILED=true; LAST_CLEANUP_ACTIONS+="dnf-autoremove "; }
        else
            log "Skipping autoremove (disabled)"
        fi
        run_with_timeout "$TIMEOUT_SECONDS" sudo -n /usr/bin/dnf clean packages 2>&1 | tee -a "$LOGFILE"
        [[ ${PIPESTATUS[0]} -ne 0 ]] && { LAST_CLEANUP_FAILED=true; LAST_CLEANUP_ACTIONS+="dnf-clean-packages "; }
        run_with_timeout "$TIMEOUT_SECONDS" sudo -n /usr/bin/flatpak uninstall --unused -y 2>&1 | tee -a "$LOGFILE"
        [[ ${PIPESTATUS[0]} -ne 0 ]] && { LAST_CLEANUP_FAILED=true; LAST_CLEANUP_ACTIONS+="flatpak-uninstall-system "; }
        run_with_timeout "$TIMEOUT_SECONDS" flatpak uninstall --user --unused -y 2>&1 | tee -a "$LOGFILE"
        [[ ${PIPESTATUS[0]} -ne 0 ]] && { LAST_CLEANUP_FAILED=true; LAST_CLEANUP_ACTIONS+="flatpak-uninstall-user "; }
        [[ "$LAST_CLEANUP_FAILED" == "true" ]] && log "WARNING: cleanup failures: $LAST_CLEANUP_ACTIONS"
    fi

    MUTATING_IN_PROGRESS=false

    if [[ "$DNF_EXIT" != "dry-run" ]]; then
        uname -r > "$POST_UPDATE_KERNEL_FILE" 2>/dev/null || true
        [[ $UPDATE_SUCCESS -ne 0 ]] && log "DNF exit nonzero; verifying anyway"
        log_blank; log_raw "=============================="; log_raw "Post-Update Verification"; log_raw "=============================="
        local vrc=0
        verify_system_health; vrc=$?
        LAST_VERIFY_RC="$vrc"
        case $vrc in 0) log "Verify: HEALTHY" ;; 1) log "Verify: ISSUES" ;; 2) log "Verify: DEGRADED" ;; *) log "Verify: UNKNOWN ($vrc)" ;; esac
        post_update_security_check
    fi

    rm -f "$TSYNC" 2>/dev/null || true
    cleanup_keepalive
    return "$UPDATE_SUCCESS"
}

# ================= ROTATE LOGS =================
rotate_logs() {
    [[ "$DRY_RUN" == "true" ]] && return 0
    local sz max=$(( MAX_LOG_SIZE_MB * 1024 * 1024 )) dest
    sz=$(stat -c %s "$LOGFILE" 2>/dev/null || echo 0)
    if [[ "$sz" =~ ^[0-9]+$ ]] && (( sz > max )); then
        if dest=$(safe_archive_move "$LOGFILE" "nobara_update_log" "txt"); then
            log "Rotated log ($sz bytes) to $dest"
            : >> "$LOGFILE" 2>/dev/null || { echo "ERROR: cannot recreate log" >&2; return 1; }
        else
            log "WARNING: log rotation failed"
        fi
    fi
    find "$LOG_DIR/archive" -type f -name "nobara_update_log.*.txt" -mtime +"$MAX_LOG_AGE_DAYS" -delete 2>/dev/null || true
}

rotate_history() {
    [[ "$DRY_RUN" == "true" ]] && return 0
    local max=$(( MAX_HISTORY_SIZE_MB * 1024 * 1024 ))
    local f sz ext base dest new_file
    for f in "$HISTORY_LOG" "$PACKAGE_LOG"; do
        [[ -f "$f" ]] || continue
        sz=$(stat -c %s "$f" 2>/dev/null || echo 0)
        [[ "$sz" =~ ^[0-9]+$ ]] || continue
        (( sz <= max )) && continue
        ext="${f##*.}"; base=$(basename "$f" ".${ext}"); new_file="${f}.new.$$"
        if [[ "$f" == "$HISTORY_LOG" ]]; then
            printf '%s\n' "$HISTORY_HEADER" > "$new_file" 2>/dev/null || {
                log "ERROR: cannot create replacement history"; rm -f "$new_file"; continue; }
        else
            : > "$new_file" 2>/dev/null || {
                log "ERROR: cannot create replacement package log"; rm -f "$new_file"; continue; }
        fi
        if dest=$(safe_archive_move "$f" "$base" "$ext"); then
            if mv -f "$new_file" "$f" 2>/dev/null; then
                log "Rotated history ($sz bytes): $f -> $dest"
            else
                log "ERROR: could not install replacement; restoring"
                cp -f "$dest" "$f" 2>/dev/null && log "Recovered from $dest" \
                    || log "CRITICAL: could not restore $f; archive at $dest"
                rm -f "$new_file"
            fi
        else
            log "WARNING: could not archive $f; skipped"
            rm -f "$new_file"
        fi
    done
    find "$LOG_DIR/archive" -type f \
        \( -name "update_history.*.csv" -o -name "package_history.*.log" \) \
        -mtime +"$MAX_HISTORY_AGE_DAYS" -delete 2>/dev/null || true
}

# ================= SMART SLEEP =================
smart_sleep() {
    local d=$1 i=5 e=0
    while (( e < d )); do
        local r=$(( d - e ))
        (( r < i )) && { sleep "$r" 2>/dev/null || break; break; }
        sleep "$i" 2>/dev/null || break
        e=$(( e + i ))
    done
}

# ================= MAIN LOOP =================
main() {
    [[ "$DRY_RUN" == "true" ]] && log "Auto-update starting - DRY RUN (lists in $LISTS_DIR)" \
                               || log "Auto-update starting"
    [[ "$ENABLE_AUTOREMOVE" == "true" ]] && log "WARNING: autoremove ENABLED"
    log "Fallback: ENABLE_FALLBACK=$ENABLE_FALLBACK"
    log "Allow-unknown-repair: $ALLOW_UNKNOWN_REPAIR"
    log "Arch allowlist: $ALLOWED_ARCHS"

    local rd=60 md=3600 nxt=$(date +%s)

    while true; do
        if ! check_internet; then
            local os=$(date +%s) st=60 ms=3600 n=false
            log "🌐 No internet"
            can_notify_warning && { notify "🌐 No internet - postponing" normal 5000; update_warning_timestamp; }
            while ! check_internet; do
                local om=$(( ($(date +%s) - os) / 60 ))
                log "Still offline after ${om} min"
                if (( om >= 30 )) && [[ "$n" == "false" ]]; then
                    can_notify_warning && { notify "Still offline (30m)" normal 5000; update_warning_timestamp; n=true; }
                fi
                smart_sleep "$st"
                st=$(( st * 2 > ms ? ms : st * 2 ))
            done
            log "🌐 Internet restored"
            can_notify_restored && { notify "Internet restored" normal 5000; update_restored_timestamp; }
        fi

        if ! check_disk; then
            log "Disk check failed, retry ${rd}s"; smart_sleep "$rd"
            rd=$(( rd * 2 > md ? md : rd * 2 )); continue
        fi
        if ! check_battery; then
            log "Battery check failed, retry ${rd}s"; smart_sleep "$rd"
            rd=$(( rd * 2 > md ? md : rd * 2 )); continue
        fi
        rd=60

        if [[ "$DRY_RUN" != "true" ]] && update_already_staged; then
            # [FIX 148] Already staged this boot: re-running nobara-sync would
            # only re-stage the same transaction every cycle.
            log "Update already staged; waiting for reboot (skipping fetch/update)"
        elif ! fetch_pending_updates; then
            log "Fetch failed; skipping cycle"
            write_history_row "SKIP" "NOT-RUN" "SKIP" "no" 0 0
        elif updates_available; then
            local dc=0 fc=0
            [[ -s "$LISTS_DIR/dnf_list" ]] && dc=$(wc -l < "$LISTS_DIR/dnf_list")
            [[ -s "$LISTS_DIR/flatpak_list" ]] && fc=$(wc -l < "$LISTS_DIR/flatpak_list")

            notify_pending

            local tx="FAIL" hp="UNKNOWN" cl="SKIP" fb="no"

            if run_updates; then
                if [[ "$DRY_RUN" == "true" ]]; then
                    tx="DRY-RUN"; log "Dry-run completed"
                elif [[ "${LAST_FALLBACK_USED:-false}" == "true" ]]; then
                    tx="FALLBACK-OK"; log "Fallback completed; nobara-sync did not succeed"
                else
                    tx="OK"; log "Update cycle completed"
                fi
                update_transaction_success_timestamp
                if [[ "$tx" == "OK" ]]; then
                    update_nobara_sync_success_timestamp
                fi
            else
                if [[ "${LAST_DNF_EXIT:-}" == "locked" || "${LAST_DNF_EXIT:-}" == "locked-by-other" || "${LAST_DNF_EXIT:-}" == "no-sudo" ]]; then
                    tx="SKIP"; log "Cycle skipped (${LAST_DNF_EXIT})"
                else
                    tx="FAIL"; log "Cycle failed (dnf=${LAST_DNF_EXIT:-?} orig=${LAST_ORIGINAL_DNF_EXIT:-?} flatpak=${LAST_FLATPAK_EXIT:-?})"
                fi
            fi

            case "${LAST_VERIFY_RC:-__unset__}" in
                0) hp="HEALTHY" ;;
                1) hp="ISSUES" ;;
                2) hp="DEGRADED" ;;
                dry-run) hp="N/A" ;;
                __unset__|"") hp="NOT-RUN" ;;
                *) hp="UNKNOWN" ;;
            esac

            [[ "${LAST_CLEANUP_FAILED:-false}" == "true" ]] && cl="WARN" || \
                { [[ "$tx" == "OK" || "$tx" == "FALLBACK-OK" ]] && cl="OK" || cl="SKIP"; }
            [[ "${LAST_FALLBACK_USED:-false}" == "true" ]] && fb="yes"

            if [[ "$tx" == "OK" && "$hp" == "HEALTHY" ]]; then
                update_success_timestamp || log "WARNING: last_success timestamp failed"
            fi

            write_history_row "$tx" "$hp" "$cl" "$fb" "$dc" "$fc"
        else
            system_up_to_date
        fi

        quick_verify
        rotate_logs
        rotate_history

        local j=$((RANDOM % 120 - 60))
        local ai=$((3600 + j))
        nxt=$((nxt + ai))
        local nw=$(date +%s)
        (( nxt <= nw )) && { log "WARNING: scheduler behind; resetting"; nxt=$((nw + ai)); }
        local st=$((nxt - nw))
        [[ $st -gt 0 ]] && smart_sleep "$st"
    done
}

main "$@"
