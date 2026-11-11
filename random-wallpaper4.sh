#!/usr/bin/env bash
# ============================================================
# Random Wallpaper Script v4.5
# ============================================================
# Publication state machine:
#
#   pending          → atomic rename done; plasma-apply not yet confirmed
#   applied/committed → plasma succeeded; cleanup may be incomplete
#                       (recovery trusts journal and commits)
#   rollback_pending  → cache restored; plasma reapply unconfirmed
#
# Invariants:
#   - Journal is authoritative. It is never cleared while the
#     transaction is unresolved, and a failed clear is fatal for
#     the current run — the next startup will not silently
#     overwrite stale recovery info.
#   - Backup is preserved across every failure path until cleanup
#     is confirmed by either the live process or recovery.
#   - Missing backup in pending/rollback_pending when the journal
#     says prev_existed=true is treated as unrecoverable, not as
#     "assume success."
#   - No re-encoding is preserved on the source-PNG + overlay-off
#     path; all other paths re-encode to PNG (documented, by design).
# ============================================================

# ============================================================
# ENVIRONMENT SETUP
# ============================================================
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"

# ============================================================
# CONFIGURATION (all env-overridable)
# ============================================================
HISTORY_SIZE="${HISTORY_SIZE:-100000}"
RECENT_HISTORY_SIZE="${RECENT_HISTORY_SIZE:-100}"
SEARCH_LIMIT="${SEARCH_LIMIT:-100}"
SLEEP_INTERVAL="${SLEEP_INTERVAL:-60}"
DEVIOUSQ_TIMEOUT="${DEVIOUSQ_TIMEOUT:-30}"
WGET_TIMEOUT="${WGET_TIMEOUT:-15}"
WGET_TOTAL_TIMEOUT="${WGET_TOTAL_TIMEOUT:-30}"
IDENTIFY_TIMEOUT="${IDENTIFY_TIMEOUT:-10}"
OVERLAY_MAGICK_TIMEOUT="${OVERLAY_MAGICK_TIMEOUT:-20}"
PLASMA_APPLY_TIMEOUT="${PLASMA_APPLY_TIMEOUT:-30}"
PLASMA_ROLLBACK_TIMEOUT="${PLASMA_ROLLBACK_TIMEOUT:-10}"
MAX_IMAGE_FILE_SIZE="${MAX_IMAGE_FILE_SIZE:-52428800}"
MAX_RETRIES="${MAX_RETRIES:-3}"
LOG_MAX_SIZE="${LOG_MAX_SIZE:-10485760}"
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-30}"

HISTORY_MAX_LINE_BYTES="${HISTORY_MAX_LINE_BYTES:-512}"
DEVIOUSQ_MAX_OUTPUT_BYTES="${DEVIOUSQ_MAX_OUTPUT_BYTES:-1048576}"
MAX_URL_LENGTH="${MAX_URL_LENGTH:-2048}"
PIXABAY_API_KEY_MAX_LEN="${PIXABAY_API_KEY_MAX_LEN:-256}"

DEVIANTART_WEIGHT="${DEVIANTART_WEIGHT:-55}"
VARIETY_WEIGHT="${VARIETY_WEIGHT:-15}"
PIXABAY_WEIGHT="${PIXABAY_WEIGHT:-30}"

MAX_SAME_SOURCE="${MAX_SAME_SOURCE:-3}"
VARIETY_PAUSE_WHEN_DISABLED="${VARIETY_PAUSE_WHEN_DISABLED:-false}"

DEVIANTART_IMAGE_MIN_WIDTH="${DEVIANTART_IMAGE_MIN_WIDTH:-1920}"
DEVIANTART_IMAGE_MIN_HEIGHT="${DEVIANTART_IMAGE_MIN_HEIGHT:-1080}"
PIXABAY_IMAGE_MIN_WIDTH="${PIXABAY_IMAGE_MIN_WIDTH:-1280}"
PIXABAY_IMAGE_MIN_HEIGHT="${PIXABAY_IMAGE_MIN_HEIGHT:-720}"

DEVIANTART_REQUIRE_LANDSCAPE="${DEVIANTART_REQUIRE_LANDSCAPE:-false}"

DEVIANTART_TOKEN_MAX_DIM="${DEVIANTART_TOKEN_MAX_DIM:-20000}"
DEVIANTART_ALLOW_UNDECODABLE="${DEVIANTART_ALLOW_UNDECODABLE:-false}"

PIXABAY_API_KEY="${PIXABAY_API_KEY:-}"
PIXABAY_PER_PAGE="${PIXABAY_PER_PAGE:-50}"
PIXABAY_API_TIMEOUT="${PIXABAY_API_TIMEOUT:-15}"
PIXABAY_DL_CONNECT_TIMEOUT="${PIXABAY_DL_CONNECT_TIMEOUT:-10}"
PIXABAY_DL_TOTAL_TIMEOUT="${PIXABAY_DL_TOTAL_TIMEOUT:-45}"
PIXABAY_MAX_API_RESPONSE_SIZE="${PIXABAY_MAX_API_RESPONSE_SIZE:-10485760}"

PIXABAY_QUERIES=(
    "category:backgrounds" "category:fashion" "category:nature" "category:science"
    "category:education" "category:feelings" "category:health" "category:people"
    "category:religion" "category:places" "category:animals" "category:industry"
    "category:computer" "category:food" "category:sports" "category:transportation"
    "category:travel" "category:buildings" "category:business" "category:music"
    "term:live wallpaper" "term:wallpaper hd" "term:abstract background"
    "term:nature landscape" "term:ocean waves" "term:city night" "term:space nebula"
    "term:forest mist" "term:sunset clouds" "term:mountain peak" "term:autumn leaves"
    "term:aurora borealis" "term:underwater" "term:particle abstract" "term:aerial drone"
    "term:slow motion water" "term:northern lights" "term:desert dunes"
    "term:tropical beach" "term:winter snow" "term:spring blossom"
    "term:starry night sky" "term:macro flower"
)

FORTUNE_OVERLAY_ENABLED="${FORTUNE_OVERLAY_ENABLED:-true}"
FORTUNE_TARGET_ASPECT_W="${FORTUNE_TARGET_ASPECT_W:-16}"
FORTUNE_TARGET_ASPECT_H="${FORTUNE_TARGET_ASPECT_H:-9}"

FORTUNE_FONT="${FORTUNE_FONT:-DejaVu Serif}"
FORTUNE_FONT_SIZE="${FORTUNE_FONT_SIZE:-22}"
FORTUNE_FONT_MIN="${FORTUNE_FONT_MIN:-10}"
FORTUNE_FONT_MAX="${FORTUNE_FONT_MAX:-120}"
FORTUNE_TEXT_COLOR="${FORTUNE_TEXT_COLOR:-#ffffff}"
FORTUNE_MARGIN="${FORTUNE_MARGIN:-40}"
FORTUNE_MARGIN_MIN="${FORTUNE_MARGIN_MIN:-12}"
FORTUNE_MAX_BYTES="${FORTUNE_MAX_BYTES:-1024}"

FORTUNE_TEXT_SHADOW_ENABLED="${FORTUNE_TEXT_SHADOW_ENABLED:-false}"
FORTUNE_TEXT_SHADOW_COLOR="${FORTUNE_TEXT_SHADOW_COLOR:-#000000}"
FORTUNE_TEXT_SHADOW_OPACITY="${FORTUNE_TEXT_SHADOW_OPACITY:-65}"

FORTUNE_GLASS_BLUR="${FORTUNE_GLASS_BLUR:-20}"
FORTUNE_GLASS_BRIGHTNESS="${FORTUNE_GLASS_BRIGHTNESS:-60}"
FORTUNE_GLASS_SATURATION="${FORTUNE_GLASS_SATURATION:-10}"
FORTUNE_GLASS_TINT="${FORTUNE_GLASS_TINT:-#222222}"
FORTUNE_GLASS_TINT_STRENGTH="${FORTUNE_GLASS_TINT_STRENGTH:-60}"
FORTUNE_GLASS_ALPHA="${FORTUNE_GLASS_ALPHA:-25%}"

FORTUNE_BLOCK_WIDTH_PCT="${FORTUNE_BLOCK_WIDTH_PCT:-50}"
FORTUNE_BLOCK_MAX_PX="${FORTUNE_BLOCK_MAX_PX:-0}"
FORTUNE_BLOCK_MIN_PX="${FORTUNE_BLOCK_MIN_PX:-400}"

FORTUNE_VERTICAL_POSITION="${FORTUNE_VERTICAL_POSITION:-middle}"
FORTUNE_AUTO_ADJUST_POSITION="${FORTUNE_AUTO_ADJUST_POSITION:-true}"

# ============================================================
# PATHS & STATE
# ============================================================
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
STATE_DIR="${WALLPAPER_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/random-wallpaper}"

HISTORY_FILE="$STATE_DIR/wallpaper_history.txt"
RECENT_HISTORY_FILE="$STATE_DIR/wallpaper_recent.txt"
LOGFILE="$STATE_DIR/wallpaper.log"
LOCK_FILE="$CACHE_HOME/random_wallpaper.lock"

WALLPAPER_CACHE_DIR="$CACHE_HOME/random-wallpaper"
WALLPAPER_CURRENT="$WALLPAPER_CACHE_DIR/current.png"
PUBLISH_JOURNAL="$WALLPAPER_CACHE_DIR/.publish.journal"

umask 077
if ! mkdir -p "$STATE_DIR" "$CACHE_HOME" "$WALLPAPER_CACHE_DIR"; then
    echo "ERROR: Failed to create required directories" >&2
    exit 1
fi

_chmod_dir() {
    local d="$1" want="700"
    [ -d "$d" ] || return 0
    local cur
    cur=$(stat -c '%a' "$d" 2>/dev/null) || return 0
    [ "$cur" = "$want" ] && return 0
    chmod "$want" "$d" 2>/dev/null || true
}
_chmod_dir "$STATE_DIR"
_chmod_dir "$WALLPAPER_CACHE_DIR"

# ============================================================
# LOG ROTATION
# ============================================================
rotate_log() {
    if [ -f "$LOGFILE" ]; then
        local size
        size=$(stat -c%s "$LOGFILE" 2>/dev/null || echo 0)
        if [ "${size:-0}" -gt "$LOG_MAX_SIZE" ]; then
            local rotated="$LOGFILE.$(date +%Y%m%d_%H%M%S).$$"
            if mv -- "$LOGFILE" "$rotated"; then
                echo "$(date) - Log rotated (was ${size} bytes)" > "$LOGFILE"
            fi
        fi
    fi
    find "$STATE_DIR" -name 'wallpaper.log.*' -mtime +"$LOG_RETENTION_DAYS" -delete 2>/dev/null || true
}

# ============================================================
# GLOBAL STATE
# ============================================================
TMP_DIR=""
OVERLAY_TMP_ROOT=""
_PROBE_TMPDIR=""
_PROBE_PIDS=()
_VARIETY_PAUSED_BY_SCRIPT=false
_RECENT_TMP=""
_HISTORY_TMP=""
_STAGED_FILE=""
_PREV_FILE=""
_PUBLISH_PENDING=false
_PRESERVE_JOURNAL=false
SIGNAL_EXIT_CODE=0

# ============================================================
# SIGNAL TRAPS (deferred exit)
# ============================================================
_on_signal() {
    local code="$1"
    if [ "$SIGNAL_EXIT_CODE" -eq 0 ]; then
        SIGNAL_EXIT_CODE="$code"
    fi
}

trap '_on_signal 130' INT
trap '_on_signal 143' TERM
trap '_on_signal 129' HUP

# ============================================================
# JOURNAL HELPERS
# ============================================================
_fsync_cache_dir() {
    sync 2>/dev/null || true
}

_write_publish_journal() {
    local state="$1" prev_file="$2" prev_existed="$3" staged_file="$4"
    local tmp="$PUBLISH_JOURNAL.tmp.$$"
    {
        printf 'state=%s\n' "$state"
        printf 'prev_file=%s\n' "$prev_file"
        printf 'prev_existed=%s\n' "$prev_existed"
        printf 'staged_file=%s\n' "$staged_file"
        printf 'written_at=%s\n' "$(date -Is 2>/dev/null || date)"
    } > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
    _fsync_cache_dir
    mv -f -- "$tmp" "$PUBLISH_JOURNAL" 2>/dev/null || { rm -f "$tmp"; return 1; }
    _fsync_cache_dir
    return 0
}

# Retries once on failure. Journal write failures to the cache directory
# (same filesystem as everything else in the publication) are rare; if
# they still fail after retry, callers treat this as unrecoverable state.
_update_publish_journal_state() {
    local new_state="$1"
    local attempt tmp
    for attempt in 1 2; do
        [ -f "$PUBLISH_JOURNAL" ] || return 1
        tmp="$PUBLISH_JOURNAL.tmp.$$.$attempt"
        if awk -v s="$new_state" '
            /^state=/ { print "state=" s; next }
            { print }
        ' "$PUBLISH_JOURNAL" > "$tmp" 2>/dev/null; then
            _fsync_cache_dir
            if mv -f -- "$tmp" "$PUBLISH_JOURNAL" 2>/dev/null; then
                _fsync_cache_dir
                return 0
            fi
        fi
        rm -f "$tmp" 2>/dev/null || true
        [ "$attempt" -eq 1 ] && sleep 0.1
    done
    return 1
}

# Returns 0 only if the journal no longer exists afterwards.
_clear_publish_journal() {
    rm -f "$PUBLISH_JOURNAL" 2>/dev/null || true
    _fsync_cache_dir
    [ ! -e "$PUBLISH_JOURNAL" ]
}

_read_publish_journal() {
    PENDING_STATE=""
    PENDING_PREV_FILE=""
    PENDING_PREV_EXISTED=""
    PENDING_STAGED=""
    [ -f "$PUBLISH_JOURNAL" ] || return 1
    PENDING_STATE=$(sed -n 's/^state=//p'        "$PUBLISH_JOURNAL" 2>/dev/null | head -1)
    PENDING_PREV_FILE=$(sed -n 's/^prev_file=//p'    "$PUBLISH_JOURNAL" 2>/dev/null | head -1)
    PENDING_PREV_EXISTED=$(sed -n 's/^prev_existed=//p' "$PUBLISH_JOURNAL" 2>/dev/null | head -1)
    PENDING_STAGED=$(sed -n 's/^staged_file=//p' "$PUBLISH_JOURNAL" 2>/dev/null | head -1)
    return 0
}

_validate_cache_path() {
    local p="$1" pat="$2"
    [ -z "$p" ] && return 1
    case "$p" in
        "$WALLPAPER_CACHE_DIR"/*) ;;
        *) return 1 ;;
    esac
    case "$p" in
        *..*) return 1 ;;
    esac
    local base
    base=$(basename -- "$p" 2>/dev/null) || return 1
    [[ "$base" =~ $pat ]] || return 1
    return 0
}

_validate_journal_contents() {
    case "$PENDING_STATE" in
        pending|applied|committed|rollback_pending) ;;
        *) return 1 ;;
    esac
    case "$PENDING_PREV_EXISTED" in
        true|false) ;;
        *) return 1 ;;
    esac
    if [ "$PENDING_PREV_EXISTED" = true ]; then
        _validate_cache_path "$PENDING_PREV_FILE" '^\.prev\.[0-9]+\.png$' || return 1
    else
        [ -z "$PENDING_PREV_FILE" ] || return 1
    fi
    if [ -n "$PENDING_STAGED" ]; then
        _validate_cache_path "$PENDING_STAGED" '^\.staged\.[0-9]+\.png$' || return 1
    fi
    return 0
}

# ============================================================
# RECOVERY
# ============================================================
# Journal-clear failure is ALWAYS fatal in a success path. This prevents
# startup from proceeding to a state where the next publication could
# overwrite a stale journal via _write_publish_journal.
_recover_pending_journal() {
    [ -f "$PUBLISH_JOURNAL" ] || return 0

    _read_publish_journal || {
        echo "$(date) - [Recovery] cannot read journal" >> "$LOGFILE"; return 1
    }

    if ! _validate_journal_contents; then
        echo "$(date) - [Recovery] journal failed validation (state=${PENDING_STATE:-?}); preserving" >> "$LOGFILE"
        return 1
    fi

    echo "$(date) - [Recovery] state=${PENDING_STATE} prev=${PENDING_PREV_FILE} existed=${PENDING_PREV_EXISTED}" >> "$LOGFILE"

    if [ -n "$PENDING_STAGED" ] && [ -f "$PENDING_STAGED" ]; then
        rm -f -- "$PENDING_STAGED" 2>/dev/null || true
        echo "$(date) - [Recovery] removed leftover staged file" >> "$LOGFILE"
    fi

    case "$PENDING_STATE" in
        applied|committed)
            # Plasma succeeded before the crash. Trust the journal: commit.
            if [ -n "$PENDING_PREV_FILE" ] && [ -f "$PENDING_PREV_FILE" ]; then
                rm -f -- "$PENDING_PREV_FILE" 2>/dev/null || true
            fi
            if ! _clear_publish_journal; then
                echo "$(date) - [Recovery] FATAL: cannot clear ${PENDING_STATE} journal" >> "$LOGFILE"
                return 1
            fi
            echo "$(date) - [Recovery] cleaned up ${PENDING_STATE} transaction" >> "$LOGFILE"
            return 0
            ;;
        rollback_pending)
            # Cache was restored; plasma reapply may not have confirmed.
            if [ "$PENDING_PREV_EXISTED" = true ]; then
                if [ -n "$PENDING_PREV_FILE" ] && [ -f "$PENDING_PREV_FILE" ]; then
                    if ! cp -f -- "$PENDING_PREV_FILE" "$WALLPAPER_CURRENT" 2>/dev/null; then
                        echo "$(date) - [Recovery] rollback_pending: cannot restore backup; FAIL CLOSED" >> "$LOGFILE"
                        return 1
                    fi
                    echo "$(date) - [Recovery] rollback_pending: restored backup" >> "$LOGFILE"
                else
                    # Backup missing but the journal says it should exist.
                    # A valid current.png does NOT prove it is the pre-crash
                    # image — it could be the aborted new publication.
                    echo "$(date) - [Recovery] rollback_pending: backup missing; FAIL CLOSED (manual intervention)" >> "$LOGFILE"
                    return 1
                fi
            fi
            if [ ! -s "$WALLPAPER_CURRENT" ] \
               || ! _run_identify -format '%w %h' "${WALLPAPER_CURRENT}[0]" >/dev/null 2>&1; then
                echo "$(date) - [Recovery] rollback_pending: current.png invalid; FAIL CLOSED" >> "$LOGFILE"
                return 1
            fi
            if timeout --kill-after=2s "${PLASMA_ROLLBACK_TIMEOUT}s" \
               plasma-apply-wallpaperimage "$WALLPAPER_CURRENT" 9>&- >/dev/null 2>&1; then
                echo "$(date) - [Recovery] rollback_pending resolved" >> "$LOGFILE"
                [ -n "$PENDING_PREV_FILE" ] && rm -f -- "$PENDING_PREV_FILE" 2>/dev/null || true
                if ! _clear_publish_journal; then
                    echo "$(date) - [Recovery] FATAL: cannot clear journal after rollback_pending success" >> "$LOGFILE"
                    return 1
                fi
                return 0
            fi
            echo "$(date) - [Recovery] rollback_pending: plasma reapply failed; preserving journal" >> "$LOGFILE"
            return 1
            ;;
        pending)
            if [ "$PENDING_PREV_EXISTED" = true ]; then
                if [ -n "$PENDING_PREV_FILE" ] && [ -f "$PENDING_PREV_FILE" ]; then
                    if ! cp -f -- "$PENDING_PREV_FILE" "$WALLPAPER_CURRENT" 2>/dev/null; then
                        echo "$(date) - [Recovery] pending: cannot restore backup; FAIL CLOSED" >> "$LOGFILE"
                        return 1
                    fi
                    echo "$(date) - [Recovery] pending: restored backup" >> "$LOGFILE"
                else
                    echo "$(date) - [Recovery] pending: backup missing; FAIL CLOSED (manual intervention)" >> "$LOGFILE"
                    return 1
                fi
                if [ ! -s "$WALLPAPER_CURRENT" ] \
                   || ! _run_identify -format '%w %h' "${WALLPAPER_CURRENT}[0]" >/dev/null 2>&1; then
                    echo "$(date) - [Recovery] pending: current.png invalid; FAIL CLOSED" >> "$LOGFILE"
                    return 1
                fi
                if timeout --kill-after=2s "${PLASMA_ROLLBACK_TIMEOUT}s" \
                   plasma-apply-wallpaperimage "$WALLPAPER_CURRENT" 9>&- >/dev/null 2>&1; then
                    echo "$(date) - [Recovery] pending resolved to previous image" >> "$LOGFILE"
                    [ -n "$PENDING_PREV_FILE" ] && rm -f -- "$PENDING_PREV_FILE" 2>/dev/null || true
                    if ! _clear_publish_journal; then
                        echo "$(date) - [Recovery] FATAL: cannot clear journal after pending success" >> "$LOGFILE"
                        return 1
                    fi
                    return 0
                fi
                # Plasma reapply failed — demote to rollback_pending so the
                # next startup (or the user) can retry cleanly.
                echo "$(date) - [Recovery] pending: plasma failed; marking rollback_pending" >> "$LOGFILE"
                _update_publish_journal_state "rollback_pending" || true
                return 1
            fi
            # prev_existed=false → first publication interrupted.
            # No image to restore; original KDE wallpaper state was never
            # captured (documented limitation).
            rm -f "$WALLPAPER_CURRENT" 2>/dev/null || true
            echo "$(date) - [Recovery] removed uncommitted first publication" >> "$LOGFILE"
            if ! _clear_publish_journal; then
                echo "$(date) - [Recovery] FATAL: cannot clear journal after first-publication cleanup" >> "$LOGFILE"
                return 1
            fi
            return 0
            ;;
    esac
}

# ============================================================
# ROLLBACK (single source of truth)
# ============================================================
# Uses `cp` (not `mv`) so the backup survives until plasma confirms the
# reapply. Any failure leaves the journal at rollback_pending and keeps
# the backup intact for the next attempt.
_rollback_publication() {
    echo "$(date) - [Rollback] start" >> "$LOGFILE"

    if ! _update_publish_journal_state "rollback_pending"; then
        echo "$(date) - [Rollback] FATAL: cannot write rollback_pending marker" >> "$LOGFILE"
        _PRESERVE_JOURNAL=true
        return 1
    fi
    _fsync_cache_dir

    if [ -n "$_PREV_FILE" ] && [ -f "$_PREV_FILE" ]; then
        if ! cp -f -- "$_PREV_FILE" "$WALLPAPER_CURRENT" 2>/dev/null; then
            echo "$(date) - [Rollback] FATAL: cannot restore cache; preserving backup" >> "$LOGFILE"
            _PRESERVE_JOURNAL=true
            return 1
        fi
        echo "$(date) - [Rollback] cache restored" >> "$LOGFILE"
    else
        rm -f "$WALLPAPER_CURRENT" 2>/dev/null || true
        _PUBLISH_PENDING=false
        echo "$(date) - [Rollback] removed uncommitted first publication" >> "$LOGFILE"
        if ! _clear_publish_journal; then
            echo "$(date) - [Rollback] FATAL: cannot clear journal after first-publication rollback" >> "$LOGFILE"
            _PRESERVE_JOURNAL=true
            return 1
        fi
        return 0
    fi

    if [ ! -s "$WALLPAPER_CURRENT" ] \
       || ! _run_identify -format '%w %h' "${WALLPAPER_CURRENT}[0]" >/dev/null 2>&1; then
        echo "$(date) - [Rollback] FATAL: restored current.png invalid; preserving backup" >> "$LOGFILE"
        _PRESERVE_JOURNAL=true
        return 1
    fi

    if timeout --kill-after=2s "${PLASMA_ROLLBACK_TIMEOUT}s" \
       plasma-apply-wallpaperimage "$WALLPAPER_CURRENT" 9>&- >/dev/null 2>&1; then
        echo "$(date) - [Rollback] plasma reapply succeeded" >> "$LOGFILE"
        _PUBLISH_PENDING=false
        [ -n "$_PREV_FILE" ] && rm -f "$_PREV_FILE" 2>/dev/null || true
        _PREV_FILE=""
        if ! _clear_publish_journal; then
            echo "$(date) - [Rollback] WARN: journal clear failed; recovery will resolve on next startup" >> "$LOGFILE"
        fi
        return 0
    fi

    echo "$(date) - [Rollback] FATAL: plasma reapply failed; journal at rollback_pending, backup preserved" >> "$LOGFILE"
    _PRESERVE_JOURNAL=true
    return 1
}

# ============================================================
# EXIT TRAP
# ============================================================
cleanup_on_exit() {
    local ec=$?

    # Decide whether rollback is needed based on BOTH the in-memory flag
    # AND the journal's persisted state. If the journal says applied or
    # committed, plasma already succeeded — do not roll back.
    local _need_rollback=false
    if [ "$_PUBLISH_PENDING" = true ]; then
        _need_rollback=true
        if [ -f "$PUBLISH_JOURNAL" ]; then
            local _jt_state
            _jt_state=$(sed -n 's/^state=//p' "$PUBLISH_JOURNAL" 2>/dev/null | head -1)
            case "$_jt_state" in
                applied|committed) _need_rollback=false ;;
            esac
        fi
    fi

    if [ "$_need_rollback" = true ] && declare -F _rollback_publication >/dev/null; then
        echo "$(date) - EXIT: rolling back pending publication (rc=$ec)" >> "$LOGFILE"
        _rollback_publication || true
    fi

    declare -F cleanup_probes >/dev/null && cleanup_probes

    if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
        rm -rf -- "$TMP_DIR" 2>/dev/null || true
    fi
    [ -n "$_RECENT_TMP" ] && rm -f "$_RECENT_TMP" 2>/dev/null || true
    [ -n "$_HISTORY_TMP" ] && rm -f "$_HISTORY_TMP" 2>/dev/null || true
    [ -n "$_STAGED_FILE" ] && rm -f "$_STAGED_FILE" 2>/dev/null || true

    # Journal tmp files from failed writes
    rm -f "$PUBLISH_JOURNAL".tmp.* 2>/dev/null || true

    if [ "$_PRESERVE_JOURNAL" != true ]; then
        [ -n "$_PREV_FILE" ] && rm -f "$_PREV_FILE" 2>/dev/null || true
    fi

    if [ "$_VARIETY_PAUSED_BY_SCRIPT" = true ] \
       && declare -F variety_pids >/dev/null \
       && [ -z "$(variety_pids)" ]; then
        if declare -F _restore_variety_verified >/dev/null && _restore_variety_verified; then
            echo "$(date) - Restored Variety on exit" >> "$LOGFILE"
        else
            echo "$(date) - WARNING: Variety not running after exit restore" >> "$LOGFILE"
        fi
    fi

    echo "$(date) - SCRIPT EXITING (code=$ec)" >> "$LOGFILE"
    flock -u 9 2>/dev/null || true
    exec 9>&- 2>/dev/null || true
}
trap cleanup_on_exit EXIT

# ============================================================
# CONFIG VALIDATION
# ============================================================
_validate_uint() {
    local name="$1" val="$2" min="${3:-0}" max="${4:-}"
    if ! [[ "$val" =~ ^[0-9]+$ ]]; then
        echo "$(date) - ERROR: $name must be a non-negative integer (got '$val')" >> "$LOGFILE"
        return 1
    fi
    if [ "${#val}" -gt 9 ]; then
        echo "$(date) - ERROR: $name exceeds numeric limits (got '$val')" >> "$LOGFILE"
        return 1
    fi
    if [[ "$val" =~ ^0[0-9]+$ ]]; then
        echo "$(date) - ERROR: $name must not have leading zeros (got '$val')" >> "$LOGFILE"
        return 1
    fi
    if [ "$val" -lt "$min" ]; then
        echo "$(date) - ERROR: $name must be >= $min (got $val)" >> "$LOGFILE"
        return 1
    fi
    if [ -n "$max" ] && [ "$val" -gt "$max" ]; then
        echo "$(date) - ERROR: $name must be <= $max (got $val)" >> "$LOGFILE"
        return 1
    fi
    return 0
}

_validate_bool() {
    local name="$1" val="$2"
    case "$val" in
        true|false) return 0 ;;
        *) echo "$(date) - ERROR: $name must be true or false (got '$val')" >> "$LOGFILE"; return 1 ;;
    esac
}

_validate_hexcolor() {
    local name="$1" val="$2"
    if ! [[ "$val" =~ ^#[0-9a-fA-F]{6}$ ]]; then
        echo "$(date) - ERROR: $name must be #RRGGBB (got '$val')" >> "$LOGFILE"
        return 1
    fi
    return 0
}

_validate_config() {
    local rc=0
    _validate_uint DEVIANTART_WEIGHT "$DEVIANTART_WEIGHT" 0 1000 || rc=1
    _validate_uint VARIETY_WEIGHT    "$VARIETY_WEIGHT"    0 1000 || rc=1
    _validate_uint PIXABAY_WEIGHT    "$PIXABAY_WEIGHT"    0 1000 || rc=1
    _validate_uint MAX_SAME_SOURCE "$MAX_SAME_SOURCE" 1 100 || rc=1
    _validate_uint MAX_RETRIES     "$MAX_RETRIES"     1 10 || rc=1
    _validate_uint SLEEP_INTERVAL  "$SLEEP_INTERVAL"  1 86400 || rc=1
    _validate_uint HISTORY_SIZE           "$HISTORY_SIZE"           1 1000000 || rc=1
    _validate_uint RECENT_HISTORY_SIZE    "$RECENT_HISTORY_SIZE"    1 10000 || rc=1
    _validate_uint HISTORY_MAX_LINE_BYTES "$HISTORY_MAX_LINE_BYTES" 32 65536 || rc=1
    _validate_uint SEARCH_LIMIT           "$SEARCH_LIMIT"           1 500 || rc=1
    _validate_uint MAX_IMAGE_FILE_SIZE    "$MAX_IMAGE_FILE_SIZE"    1024 999999999 || rc=1
    _validate_uint WGET_TIMEOUT           "$WGET_TIMEOUT"           1 300 || rc=1
    _validate_uint WGET_TOTAL_TIMEOUT     "$WGET_TOTAL_TIMEOUT"     1 300 || rc=1
    _validate_uint IDENTIFY_TIMEOUT       "$IDENTIFY_TIMEOUT"       1 60 || rc=1
    _validate_uint OVERLAY_MAGICK_TIMEOUT "$OVERLAY_MAGICK_TIMEOUT" 1 120 || rc=1
    _validate_uint PLASMA_APPLY_TIMEOUT   "$PLASMA_APPLY_TIMEOUT"   1 300 || rc=1
    _validate_uint PLASMA_ROLLBACK_TIMEOUT "$PLASMA_ROLLBACK_TIMEOUT" 1 300 || rc=1
    _validate_uint MAX_URL_LENGTH         "$MAX_URL_LENGTH"         64 65536 || rc=1
    _validate_uint DEVIOUSQ_MAX_OUTPUT_BYTES "$DEVIOUSQ_MAX_OUTPUT_BYTES" 4096 999999999 || rc=1
    _validate_uint DEVIOUSQ_TIMEOUT       "$DEVIOUSQ_TIMEOUT"       1 300 || rc=1
    _validate_uint PIXABAY_PER_PAGE              "$PIXABAY_PER_PAGE"              1 200 || rc=1
    _validate_uint PIXABAY_API_TIMEOUT           "$PIXABAY_API_TIMEOUT"           1 300 || rc=1
    _validate_uint PIXABAY_DL_CONNECT_TIMEOUT    "$PIXABAY_DL_CONNECT_TIMEOUT"    1 300 || rc=1
    _validate_uint PIXABAY_DL_TOTAL_TIMEOUT      "$PIXABAY_DL_TOTAL_TIMEOUT"      1 300 || rc=1
    _validate_uint PIXABAY_MAX_API_RESPONSE_SIZE "$PIXABAY_MAX_API_RESPONSE_SIZE" 1024 999999999 || rc=1
    _validate_uint PIXABAY_API_KEY_MAX_LEN       "$PIXABAY_API_KEY_MAX_LEN"       1 4096 || rc=1
    _validate_uint DEVIANTART_IMAGE_MIN_WIDTH  "$DEVIANTART_IMAGE_MIN_WIDTH"  64 || rc=1
    _validate_uint DEVIANTART_IMAGE_MIN_HEIGHT "$DEVIANTART_IMAGE_MIN_HEIGHT" 64 || rc=1
    _validate_uint PIXABAY_IMAGE_MIN_WIDTH     "$PIXABAY_IMAGE_MIN_WIDTH"     64 || rc=1
    _validate_uint PIXABAY_IMAGE_MIN_HEIGHT    "$PIXABAY_IMAGE_MIN_HEIGHT"    64 || rc=1
    _validate_uint DEVIANTART_TOKEN_MAX_DIM    "$DEVIANTART_TOKEN_MAX_DIM"    64 100000 || rc=1
    _validate_uint LOG_MAX_SIZE       "$LOG_MAX_SIZE"       1024 999999999 || rc=1
    _validate_uint LOG_RETENTION_DAYS "$LOG_RETENTION_DAYS" 1 3650 || rc=1
    _validate_bool FORTUNE_OVERLAY_ENABLED     "$FORTUNE_OVERLAY_ENABLED"     || rc=1
    _validate_bool FORTUNE_TEXT_SHADOW_ENABLED "$FORTUNE_TEXT_SHADOW_ENABLED" || rc=1
    _validate_bool FORTUNE_AUTO_ADJUST_POSITION "$FORTUNE_AUTO_ADJUST_POSITION" || rc=1
    _validate_bool VARIETY_PAUSE_WHEN_DISABLED "$VARIETY_PAUSE_WHEN_DISABLED" || rc=1
    _validate_bool DEVIANTART_ALLOW_UNDECODABLE "$DEVIANTART_ALLOW_UNDECODABLE" || rc=1
    _validate_bool DEVIANTART_REQUIRE_LANDSCAPE "$DEVIANTART_REQUIRE_LANDSCAPE" || rc=1
    _validate_uint FORTUNE_TARGET_ASPECT_W "$FORTUNE_TARGET_ASPECT_W" 1 || rc=1
    _validate_uint FORTUNE_TARGET_ASPECT_H "$FORTUNE_TARGET_ASPECT_H" 1 || rc=1
    _validate_uint FORTUNE_FONT_SIZE       "$FORTUNE_FONT_SIZE"       1 || rc=1
    _validate_uint FORTUNE_FONT_MIN        "$FORTUNE_FONT_MIN"        1 || rc=1
    _validate_uint FORTUNE_FONT_MAX        "$FORTUNE_FONT_MAX"        1 || rc=1
    _validate_uint FORTUNE_MARGIN          "$FORTUNE_MARGIN"          0 || rc=1
    _validate_uint FORTUNE_MARGIN_MIN      "$FORTUNE_MARGIN_MIN"      0 || rc=1
    _validate_uint FORTUNE_MAX_BYTES       "$FORTUNE_MAX_BYTES"       1 65536 || rc=1
    _validate_uint FORTUNE_BLOCK_WIDTH_PCT "$FORTUNE_BLOCK_WIDTH_PCT" 10 100 || rc=1
    _validate_uint FORTUNE_BLOCK_MIN_PX    "$FORTUNE_BLOCK_MIN_PX"    0 || rc=1
    _validate_uint FORTUNE_BLOCK_MAX_PX    "$FORTUNE_BLOCK_MAX_PX"    0 || rc=1
    _validate_uint FORTUNE_GLASS_BLUR              "$FORTUNE_GLASS_BLUR"          0 200 || rc=1
    _validate_uint FORTUNE_GLASS_BRIGHTNESS        "$FORTUNE_GLASS_BRIGHTNESS"    0 200 || rc=1
    _validate_uint FORTUNE_GLASS_SATURATION        "$FORTUNE_GLASS_SATURATION"    0 200 || rc=1
    _validate_uint FORTUNE_GLASS_TINT_STRENGTH     "$FORTUNE_GLASS_TINT_STRENGTH" 0 100 || rc=1
    _validate_uint FORTUNE_TEXT_SHADOW_OPACITY     "$FORTUNE_TEXT_SHADOW_OPACITY" 0 100 || rc=1
    if [ "$FORTUNE_FONT_MIN" -gt "$FORTUNE_FONT_MAX" ]; then
        echo "$(date) - ERROR: FORTUNE_FONT_MIN > FORTUNE_FONT_MAX" >> "$LOGFILE"; rc=1
    fi
    if ! [[ "$FORTUNE_GLASS_ALPHA" =~ ^([0-9]{1,2}|100)%$ ]]; then
        echo "$(date) - ERROR: FORTUNE_GLASS_ALPHA must be 0%..100% (got '$FORTUNE_GLASS_ALPHA')" >> "$LOGFILE"; rc=1
    fi
    _validate_hexcolor FORTUNE_TEXT_COLOR        "$FORTUNE_TEXT_COLOR"        || rc=1
    _validate_hexcolor FORTUNE_TEXT_SHADOW_COLOR "$FORTUNE_TEXT_SHADOW_COLOR" || rc=1
    _validate_hexcolor FORTUNE_GLASS_TINT        "$FORTUNE_GLASS_TINT"        || rc=1
    case "$FORTUNE_VERTICAL_POSITION" in
        top|middle) ;;
        *) echo "$(date) - ERROR: FORTUNE_VERTICAL_POSITION must be top or middle (got '$FORTUNE_VERTICAL_POSITION')" >> "$LOGFILE"; rc=1 ;;
    esac
    return "$rc"
}

if ! _validate_config; then
    echo "$(date) - ERROR: invalid configuration" >> "$LOGFILE"
    exit 1
fi

# ============================================================
# DEPENDENCY CHECK
# ============================================================
for cmd in flock timeout curl file stat awk grep head tail shuf \
           mktemp df pgrep find date wc cat sed seq setsid \
           sha256sum base64 cut cp mv identify tr readlink sync; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "$(date) - ERROR: required command not found: $cmd" >> "$LOGFILE"; exit 1
    }
done

if ! command -v plasma-apply-wallpaperimage >/dev/null 2>&1; then
    echo "$(date) - ERROR: plasma-apply-wallpaperimage not found" >> "$LOGFILE"; exit 1
fi

if [ -n "$PIXABAY_API_KEY" ]; then
    if [ "${#PIXABAY_API_KEY}" -gt "$PIXABAY_API_KEY_MAX_LEN" ]; then
        echo "$(date) - ERROR: PIXABAY_API_KEY too long — disabling Pixabay" >> "$LOGFILE"
        PIXABAY_API_KEY=""
    elif printf '%s' "$PIXABAY_API_KEY" | LC_ALL=C grep -q '[[:cntrl:]]'; then
        echo "$(date) - ERROR: PIXABAY_API_KEY has control chars — disabling Pixabay" >> "$LOGFILE"
        PIXABAY_API_KEY=""
    fi
fi

[ "$DEVIANTART_WEIGHT" -gt 0 ] && ! command -v deviousq >/dev/null 2>&1 && {
    echo "$(date) - WARNING: deviousq not found — disabling DeviantArt" >> "$LOGFILE"; DEVIANTART_WEIGHT=0
}
[ "$DEVIANTART_WEIGHT" -gt 0 ] && ! command -v jq >/dev/null 2>&1 && {
    echo "$(date) - WARNING: jq not found — disabling DeviantArt" >> "$LOGFILE"; DEVIANTART_WEIGHT=0
}
[ "$VARIETY_WEIGHT" -gt 0 ] && ! command -v variety >/dev/null 2>&1 && {
    echo "$(date) - WARNING: variety not found — disabling Variety" >> "$LOGFILE"; VARIETY_WEIGHT=0
}
if [ "$PIXABAY_WEIGHT" -gt 0 ]; then
    if [ -z "$PIXABAY_API_KEY" ]; then
        echo "$(date) - WARNING: PIXABAY_API_KEY unset — disabling Pixabay" >> "$LOGFILE"; PIXABAY_WEIGHT=0
    elif ! command -v jq >/dev/null 2>&1; then
        echo "$(date) - WARNING: jq not found — disabling Pixabay" >> "$LOGFILE"; PIXABAY_WEIGHT=0
    fi
fi
if { [ "$DEVIANTART_WEIGHT" -gt 0 ] || [ "$PIXABAY_WEIGHT" -gt 0 ]; } \
   && ! { command -v magick >/dev/null 2>&1 || command -v convert >/dev/null 2>&1; }; then
    echo "$(date) - ERROR: ImageMagick required for remote sources — disabling both" >> "$LOGFILE"
    DEVIANTART_WEIGHT=0; PIXABAY_WEIGHT=0
fi
if [ "$DEVIANTART_WEIGHT" -eq 0 ] && [ "$PIXABAY_WEIGHT" -eq 0 ] && [ "$VARIETY_WEIGHT" -eq 0 ]; then
    echo "$(date) - ERROR: no enabled sources" >> "$LOGFILE"; exit 1
fi

# ============================================================
# LOCK
# ============================================================
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "$(date) - Another instance is already running. Exiting." >> "$LOGFILE"
    exit 0
fi

rotate_log

# ============================================================
# TEMP DIRS + STARTUP RECOVERY
# ============================================================
TMP_DIR=$(mktemp -d /tmp/random_wallpaper.XXXXXX) || {
    echo "$(date) - ERROR: Failed to create temp directory" >> "$LOGFILE"; exit 1
}
OVERLAY_TMP_ROOT="$TMP_DIR/overlays"
mkdir -p "$OVERLAY_TMP_ROOT" || {
    echo "$(date) - ERROR: cannot create overlay temp root" >> "$LOGFILE"; exit 1
}

if ! _recover_pending_journal; then
    echo "$(date) - ERROR: pending publication journal could not be resolved" >> "$LOGFILE"
    echo "$(date) - ERROR: manual intervention required (see $PUBLISH_JOURNAL)" >> "$LOGFILE"
    exit 1
fi

# Only safe to sweep after recovery succeeded (backups referenced by a
# surviving journal must not be touched).
rm -f "$PUBLISH_JOURNAL".tmp.* 2>/dev/null || true
find "$WALLPAPER_CACHE_DIR" -maxdepth 1 -name '.staged.*.png' -mmin +60 -delete 2>/dev/null || true
find /tmp -maxdepth 1 -type d -name 'random_wallpaper.*' -mmin +1440 -user "$(id -un)" \
     -exec rm -rf {} + 2>/dev/null || true
while IFS= read -r -d '' f; do
    echo "$(date) - startup: removing orphaned prev image (age > 7d): $f" >> "$LOGFILE"
    rm -f -- "$f" 2>/dev/null || true
done < <(find "$WALLPAPER_CACHE_DIR" -maxdepth 1 -name '.prev.*.png' -mmin +10080 -print0 2>/dev/null)

for _f in "$HISTORY_FILE" "$RECENT_HISTORY_FILE"; do
    if ! { : >> "$_f"; } 2>/dev/null; then
        echo "$(date) - ERROR: Cannot open $_f for append" >> "$LOGFILE"
        exit 1
    fi
done
unset _f

echo "$(date) - Random Wallpaper Script Started (v4.5)" >> "$LOGFILE"
echo "$(date) - Weights: DA=$DEVIANTART_WEIGHT Variety=$VARIETY_WEIGHT Pixabay=$PIXABAY_WEIGHT (pause-when-disabled=$VARIETY_PAUSE_WHEN_DISABLED)" >> "$LOGFILE"
echo "$(date) - Persistent wallpaper: $WALLPAPER_CURRENT" >> "$LOGFILE"

# ============================================================
# HELPERS
# ============================================================
_curl_config_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

_magick_driver() {
    if command -v magick >/dev/null 2>&1; then printf '%s' "magick"; return 0; fi
    if command -v convert >/dev/null 2>&1; then printf '%s' "convert"; return 0; fi
    return 1
}

_run_magick() {
    local magick
    magick=$(_magick_driver) || return 1
    timeout --kill-after=2s "${OVERLAY_MAGICK_TIMEOUT}s" \
        "$magick" \
        -limit memory 256MiB -limit map 512MiB -limit disk 1GiB \
        -limit width 30000 -limit height 30000 -limit area 100000000 \
        "$@" 9>&-
}

_run_identify() {
    timeout --kill-after=2s "${IDENTIFY_TIMEOUT}s" \
        identify \
        -limit memory 256MiB -limit map 512MiB -limit disk 1GiB \
        -limit width 30000 -limit height 30000 -limit area 100000000 \
        "$@" 9>&-
}

interruptible_sleep() {
    local secs="$1" i
    for ((i = 0; i < secs; i++)); do
        [ "$SIGNAL_EXIT_CODE" -ne 0 ] && return 0
        sleep 1
    done
}

# ============================================================
# FORTUNE OVERLAY
# ============================================================
apply_fortune_overlay() {
    local image="$1"
    [ "$FORTUNE_OVERLAY_ENABLED" = true ] || return 0
    [ -s "$image" ] || return 1

    command -v fortune >/dev/null 2>&1 || {
        echo "$(date) - [Overlay] fortune not installed — skipping" >> "$LOGFILE"; return 1
    }
    _magick_driver >/dev/null 2>&1 || {
        echo "$(date) - [Overlay] ImageMagick not installed — skipping" >> "$LOGFILE"; return 1
    }

    local quote
    quote=$(fortune 2>/dev/null | head -c "$FORTUNE_MAX_BYTES")
    [ -n "$quote" ] || { echo "$(date) - [Overlay] empty fortune output" >> "$LOGFILE"; return 1; }

    local img_w img_h
    img_w=$(_run_identify -format '%w' "${image}[0]" 2>/dev/null) || img_w=""
    img_h=$(_run_identify -format '%h' "${image}[0]" 2>/dev/null) || img_h=""
    if ! [[ "$img_w" =~ ^[1-9][0-9]*$ && "$img_h" =~ ^[1-9][0-9]*$ ]]; then
        echo "$(date) - [Overlay] cannot read dimensions — skipping" >> "$LOGFILE"; return 1
    fi

    local visible_w is_wider_than_screen
    visible_w=$(( img_h * FORTUNE_TARGET_ASPECT_W / FORTUNE_TARGET_ASPECT_H ))
    if (( img_w < visible_w )); then
        visible_w=$img_w; is_wider_than_screen=false
    else
        is_wider_than_screen=true
    fi
    local scale_ref
    scale_ref=$(( visible_w * FORTUNE_TARGET_ASPECT_H / FORTUNE_TARGET_ASPECT_W ))
    [ "$scale_ref" -lt 1 ] && scale_ref=1

    local margin pad blur_sigma
    margin=$(( FORTUNE_MARGIN * scale_ref / 1080 ))
    [ "$margin" -lt "$FORTUNE_MARGIN_MIN" ] && margin=$FORTUNE_MARGIN_MIN
    pad=$(( 24 * scale_ref / 1080 )); [ "$pad" -lt 12 ] && pad=12
    blur_sigma=$(( FORTUNE_GLASS_BLUR * scale_ref / 1080 ))
    [ "$blur_sigma" -lt 4 ] && blur_sigma=4
    [ "$blur_sigma" -gt 60 ] && blur_sigma=60

    local font_size
    font_size=$(( FORTUNE_FONT_SIZE * scale_ref / 1080 ))
    [ "$font_size" -lt "$FORTUNE_FONT_MIN" ] && font_size=$FORTUNE_FONT_MIN
    [ "$font_size" -gt "$FORTUNE_FONT_MAX" ] && font_size=$FORTUNE_FONT_MAX

    local max_block_w
    max_block_w=$(( visible_w - 2 * pad - 2 * margin ))
    if [ "$max_block_w" -lt 100 ]; then
        echo "$(date) - [Overlay] visible_w=${visible_w} too narrow — skipping" >> "$LOGFILE"
        return 1
    fi

    local block_w
    block_w=$(( visible_w * FORTUNE_BLOCK_WIDTH_PCT / 100 ))
    [ "$block_w" -lt "$FORTUNE_BLOCK_MIN_PX" ] && block_w=$FORTUNE_BLOCK_MIN_PX
    if [ "${FORTUNE_BLOCK_MAX_PX:-0}" -gt 0 ] && [ "$block_w" -gt "$FORTUNE_BLOCK_MAX_PX" ]; then
        block_w=$FORTUNE_BLOCK_MAX_PX
    fi
    [ "$block_w" -gt "$max_block_w" ] && block_w=$max_block_w

    local vertical_position="$FORTUNE_VERTICAL_POSITION"
    if [ "$FORTUNE_AUTO_ADJUST_POSITION" = true ] \
       && [ "$is_wider_than_screen" = false ] \
       && [ "$vertical_position" = "top" ]; then
        vertical_position="middle"
    fi

    echo "$(date) - [Overlay] dims=${img_w}x${img_h} scale_ref=${scale_ref} visible_w=${visible_w} font=${font_size} block=${block_w} (max ${max_block_w}) margin=${margin} blur=${blur_sigma} pos=${vertical_position}" >> "$LOGFILE"

    local overlay_tmp
    overlay_tmp=$(mktemp -d "$OVERLAY_TMP_ROOT/op.XXXXXX") || return 1
    local tmp_txt="$overlay_tmp/quote.txt"
    local tmp_text_png="$overlay_tmp/text.png"
    local tmp_shadow_png="$overlay_tmp/shadow.png"
    local tmp_glass="$overlay_tmp/glass.png"
    local tmp_glass_masked="$overlay_tmp/glassmasked.png"
    local tmp_mask="$overlay_tmp/mask.png"
    local tmp_out="$overlay_tmp/final.png"
    local tmp_err="$overlay_tmp/pango.err"
    _overlay_cleanup() { rm -rf -- "$overlay_tmp" 2>/dev/null || true; }

    printf '%s' "$quote" \
        | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' > "$tmp_txt" \
        || { _overlay_cleanup; return 1; }

    if ! _run_magick -background none -fill "$FORTUNE_TEXT_COLOR" \
                     -font "$FORTUNE_FONT" -pointsize "$font_size" \
                     -size "${block_w}x" pango:@"$tmp_txt" \
                     -bordercolor none -border "${pad}x${pad}" \
                     "$tmp_text_png" 2>"$tmp_err"; then
        local pango_err
        pango_err=$(head -c 200 "$tmp_err" 2>/dev/null)
        echo "$(date) - [Overlay] pango render failed: ${pango_err:-unknown}" >> "$LOGFILE"
        _overlay_cleanup; return 1
    fi
    [ -s "$tmp_text_png" ] || { _overlay_cleanup; return 1; }

    if [ "$FORTUNE_TEXT_SHADOW_ENABLED" = true ]; then
        local shadow_alpha
        shadow_alpha=$(awk -v o="$FORTUNE_TEXT_SHADOW_OPACITY" 'BEGIN{printf "%.2f", o/100}')
        if ! _run_magick "$tmp_text_png" -fill "$FORTUNE_TEXT_SHADOW_COLOR" \
                -colorize 100 -channel A -evaluate multiply "${shadow_alpha}" +channel \
                "$tmp_shadow_png" 2>/dev/null; then
            rm -f "$tmp_shadow_png" 2>/dev/null || true
        fi
    fi

    local blk_w blk_h pos_x pos_y
    blk_w=$(_run_identify -format '%w' "$tmp_text_png" 2>/dev/null)
    blk_h=$(_run_identify -format '%h' "$tmp_text_png" 2>/dev/null)
    [ -n "$blk_w" ] && [ -n "$blk_h" ] || { _overlay_cleanup; return 1; }

    if [ "$blk_h" -gt $(( img_h - 2 * margin )) ]; then
        echo "$(date) - [Overlay] text height ${blk_h} exceeds available ${img_h}-2*${margin}; skipping" >> "$LOGFILE"
        _overlay_cleanup; return 1
    fi

    local visible_right
    visible_right=$(( (img_w + visible_w) / 2 ))
    pos_x=$(( visible_right - margin - blk_w ))
    case "$vertical_position" in
        top) pos_y=$margin ;;
        *)   pos_y=$(( (img_h - blk_h) / 2 )) ;;
    esac
    [ "$pos_x" -lt 0 ] && pos_x=0
    [ "$pos_y" -lt 0 ] && pos_y=0

    if ! _run_magick "${image}[0]" \
        -crop "${blk_w}x${blk_h}+${pos_x}+${pos_y}" +repage \
        -blur 0x"$blur_sigma" \
        -modulate "${FORTUNE_GLASS_BRIGHTNESS},${FORTUNE_GLASS_SATURATION},100" \
        -fill "$FORTUNE_GLASS_TINT" -colorize "$FORTUNE_GLASS_TINT_STRENGTH" \
        "$tmp_glass" 2>/dev/null; then
        echo "$(date) - [Overlay] glass crop failed" >> "$LOGFILE"; _overlay_cleanup; return 1
    fi
    [ -s "$tmp_glass" ] || { _overlay_cleanup; return 1; }

    _run_magick -size "${blk_w}x${blk_h}" xc:white \
        -alpha set -channel A -evaluate set "$FORTUNE_GLASS_ALPHA" +channel \
        "$tmp_mask" 2>/dev/null \
        || { _overlay_cleanup; return 1; }

    _run_magick "$tmp_glass" "$tmp_mask" \
        -compose CopyOpacity -composite "$tmp_glass_masked" 2>/dev/null \
        || { _overlay_cleanup; return 1; }
    [ -s "$tmp_glass_masked" ] || { _overlay_cleanup; return 1; }

    local shadow_off=$(( scale_ref / 1080 ))
    [ "$shadow_off" -lt 1 ] && shadow_off=1
    [ "$shadow_off" -gt 4 ] && shadow_off=4
    local shadow_x=$(( pos_x + shadow_off )) shadow_y=$(( pos_y + shadow_off ))

    local ok=false
    if [ -s "$tmp_shadow_png" ]; then
        if _run_magick "${image}[0]" \
            "$tmp_glass_masked" -geometry "+${pos_x}+${pos_y}" -composite \
            "$tmp_shadow_png"   -geometry "+${shadow_x}+${shadow_y}" -composite \
            "$tmp_text_png"     -geometry "+${pos_x}+${pos_y}" -composite \
            "$tmp_out" 2>/dev/null; then ok=true; fi
    else
        if _run_magick "${image}[0]" \
            "$tmp_glass_masked" -geometry "+${pos_x}+${pos_y}" -composite \
            "$tmp_text_png"     -geometry "+${pos_x}+${pos_y}" -composite \
            "$tmp_out" 2>/dev/null; then ok=true; fi
    fi

    if [ "$ok" = true ] && [ -s "$tmp_out" ] && mv -f -- "$tmp_out" "$image"; then
        _overlay_cleanup; return 0
    fi
    _overlay_cleanup; return 1
}

# ============================================================
# DEVIANTART TOKEN HELPERS
# ============================================================
_decode_da_token() {
    local url="$1" token payload dims max_w max_h
    token=$(printf '%s' "$url" | grep -oP 'token=\K[^&]+' 2>/dev/null) || return 1
    [ -z "$token" ] && return 1
    [[ "$token" =~ ^[^.]+\.[^.]+\.[^.]*$ ]] || return 1
    payload=$(printf '%s' "$token" | cut -d'.' -f2 | tr '_-' '/+')
    case $(( ${#payload} % 4 )) in
        2) payload="${payload}==" ;;
        3) payload="${payload}=" ;;
    esac
    dims=$(printf '%s' "$payload" | base64 -d 2>/dev/null \
        | jq -r '.obj[0][0] as $o
                 | [$o.width, $o.height]
                 | map(select(type == "number" or type == "string") | tostring)
                 | select(length == 2 and all(.[]; test("^(<=?)?[0-9]+$")))
                 | join(" ")' 2>/dev/null) || return 1
    [ -z "$dims" ] && return 1
    read -r max_w max_h <<< "$dims"
    [ -z "$max_w" ] || [ -z "$max_h" ] && return 1
    max_w="${max_w#<=}"; max_w="${max_w#<}"
    max_h="${max_h#<=}"; max_h="${max_h#<}"
    [[ "$max_w" =~ ^[0-9]+$ && "$max_h" =~ ^[0-9]+$ ]] || return 1
    [ "$max_w" -ge 1 ] && [ "$max_w" -le "$DEVIANTART_TOKEN_MAX_DIM" ] || return 1
    [ "$max_h" -ge 1 ] && [ "$max_h" -le "$DEVIANTART_TOKEN_MAX_DIM" ] || return 1
    printf '%s %s' "$max_w" "$max_h"
}

_da_identity() {
    local base="${1%%\?*}" h
    h=$(printf '%s' "$base" | sha256sum 2>/dev/null | awk '{print $1}')
    [ -n "$h" ] || return 1
    printf 'da://%s' "$h"
}

_DA_LOGGED_UNDECODABLE=false
_da_token_hd_ok() {
    local dims w h
    dims=$(_decode_da_token "$1") || {
        if [ "$_DA_LOGGED_UNDECODABLE" != true ]; then
            _DA_LOGGED_UNDECODABLE=true
            local _u="${1%%\?*}"
            echo "$(date) - [DeviantArt] candidate without decodable token: ${_u:0:160}" >> "$LOGFILE"
        fi
        [ "$DEVIANTART_ALLOW_UNDECODABLE" = true ] && return 0
        return 1
    }
    read -r w h <<< "$dims"
    if [ "$DEVIANTART_REQUIRE_LANDSCAPE" = true ]; then
        [ "$w" -ge "$DEVIANTART_IMAGE_MIN_WIDTH" ] \
            && [ "$h" -ge "$DEVIANTART_IMAGE_MIN_HEIGHT" ] && return 0
        return 1
    fi
    if { [ "$w" -ge "$DEVIANTART_IMAGE_MIN_WIDTH" ] && [ "$h" -ge "$DEVIANTART_IMAGE_MIN_HEIGHT" ]; } \
       || { [ "$w" -ge "$DEVIANTART_IMAGE_MIN_HEIGHT" ] && [ "$h" -ge "$DEVIANTART_IMAGE_MIN_WIDTH" ]; }; then
        return 0
    fi
    return 1
}

_rewrite_da_url() {
    local url="$1" max_dims max_w max_h
    max_dims=$(_decode_da_token "$url") || { printf '%s' "$url"; return 0; }
    read -r max_w max_h <<< "$max_dims"
    [ -z "$max_w" ] || [ -z "$max_h" ] && { printf '%s' "$url"; return 0; }
    printf '%s' "$url" | sed -E \
        "s#/v1/(fill|fit)/w_[0-9]+,h_[0-9]+#/v1/fill/w_${max_w},h_${max_h}#"
}

# ============================================================
# BOUNDED DOWNLOADS
# ============================================================
_download_bounded() {
    local url="$1" outfile="$2" max_bytes="$3" connect_timeout="$4" total_timeout="$5"
    local read_limit=$(( max_bytes + 1 )) rc=0
    rm -f "$outfile" 2>/dev/null || true
    timeout --kill-after=5s "${total_timeout}s" \
        bash -c '
            set -o pipefail
            curl -sSL --fail --proto "=https" --proto-redir "=https" \
                --connect-timeout "$1" "$2" | head -c "$3" > "$4"
        ' _ "$connect_timeout" "$url" "$read_limit" "$outfile" 9>&- 2>/dev/null || rc=$?
    local size
    size=$(stat -c%s "$outfile" 2>/dev/null || echo 0)
    [[ "$size" =~ ^[0-9]+$ ]] || size=0
    if [ "$size" -gt "$max_bytes" ]; then rm -f "$outfile"; return 2; fi
    if [ "$rc" -ne 0 ]; then rm -f "$outfile"; return 1; fi
    return 0
}

_download_api_bounded() {
    local config="$1" outfile="$2" max_bytes="$3" total_timeout="$4"
    local read_limit=$(( max_bytes + 1 )) rc=0
    rm -f "$outfile" 2>/dev/null || true
    printf '%s' "$config" \
        | timeout --kill-after=5s "${total_timeout}s" \
            bash -c '
                set -o pipefail
                curl -sS --fail --proto "=https" --proto-redir "=https" \
                    --max-time "$1" -K - | head -c "$2" > "$3"
            ' _ "$total_timeout" "$read_limit" "$outfile" 9>&- 2>/dev/null || rc=$?
    local size
    size=$(stat -c%s "$outfile" 2>/dev/null || echo 0)
    [[ "$size" =~ ^[0-9]+$ ]] || size=0
    if [ "$size" -gt "$max_bytes" ]; then rm -f "$outfile"; return 2; fi
    if [ "$rc" -ne 0 ]; then rm -f "$outfile"; return 1; fi
    return 0
}

is_valid_image_file() {
    local path="$1" mime
    mime=$(file --mime-type -b "$path" 2>/dev/null) || return 1
    case "$mime" in
        image/jpeg|image/png|image/webp|image/gif|image/avif) return 0 ;;
        *) return 1 ;;
    esac
}

_parse_image_dims() {
    local path="$1" dims w h
    HD_LAST_DIMS="" HD_LAST_WIDTH="" HD_LAST_HEIGHT=""
    command -v identify >/dev/null 2>&1 || return 3
    dims=$(_run_identify -format '%w %h' "${path}[0]" 2>/dev/null) || return 2
    [ -z "$dims" ] && return 2
    read -r w h <<< "$dims"
    [[ "$w" =~ ^[0-9]+$ && "$h" =~ ^[0-9]+$ ]] || return 2
    HD_LAST_DIMS="${w}x${h}"; HD_LAST_WIDTH="$w"; HD_LAST_HEIGHT="$h"
    return 0
}
HD_LAST_WIDTH=""; HD_LAST_HEIGHT=""

is_hd_image() {
    local path="$1" min_w="$2" min_h="$3" rc=0
    _parse_image_dims "$path" || rc=$?
    if [ "$rc" -eq 3 ]; then
        echo "$(date) - [Validate] identify unavailable — fail-closed" >> "$LOGFILE"; return 1
    fi
    [ "$rc" -eq 2 ] && return 2
    [ "$rc" -ne 0 ] && return 1
    local w="$HD_LAST_WIDTH" h="$HD_LAST_HEIGHT"
    if { [ "$w" -ge "$min_w" ] && [ "$h" -ge "$min_h" ]; } \
       || { [ "$w" -ge "$min_h" ] && [ "$h" -ge "$min_w" ]; }; then
        return 0
    fi
    return 1
}

is_landscape_hd_image() {
    local path="$1" min_w="$2" min_h="$3" rc=0
    _parse_image_dims "$path" || rc=$?
    if [ "$rc" -eq 3 ]; then
        echo "$(date) - [Validate] identify unavailable — fail-closed" >> "$LOGFILE"; return 1
    fi
    [ "$rc" -eq 2 ] && return 2
    [ "$rc" -ne 0 ] && return 1
    [ "$HD_LAST_WIDTH" -ge "$min_w" ] && [ "$HD_LAST_HEIGHT" -ge "$min_h" ] && return 0
    return 1
}

# ============================================================
# INTERNET CHECK
# ============================================================
INTERNET_CACHE_TTL=30
INTERNET_NEGATIVE_CACHE_TTL=10
INTERNET_CHECK_TIMEOUT=4
_internet_last_check=0
_internet_last_result=1

cleanup_probes() {
    local pid
    if [ "${#_PROBE_PIDS[@]}" -gt 0 ]; then
        for pid in "${_PROBE_PIDS[@]}"; do
            kill -TERM -"$pid" 2>/dev/null || true
            kill -TERM  "$pid" 2>/dev/null || true
        done
        sleep 0.2
        for pid in "${_PROBE_PIDS[@]}"; do
            kill -KILL -"$pid" 2>/dev/null || true
            kill -KILL  "$pid" 2>/dev/null || true
        done
        for pid in "${_PROBE_PIDS[@]}"; do
            wait "$pid" 2>/dev/null || true
        done
        _PROBE_PIDS=()
    fi
    if [ -n "$_PROBE_TMPDIR" ] && [ -d "$_PROBE_TMPDIR" ]; then
        rm -rf -- "$_PROBE_TMPDIR" 2>/dev/null || true
    fi
    _PROBE_TMPDIR=""
}

check_internet() {
    local now
    now=$(date +%s)
    local age=$((now - _internet_last_check))
    if [ "$_internet_last_result" -eq 0 ]; then
        [ "$age" -lt "$INTERNET_CACHE_TTL" ] && return 0
    else
        [ "$age" -lt "$INTERNET_NEGATIVE_CACHE_TTL" ] && return 1
    fi
    local -a endpoints=(
        "https://one.one.one.one/"
        "https://www.google.com/generate_204"
        "https://www.cloudflare.com/cdn-cgi/trace"
    )
    local -a probe_resolve=("one.one.one.one:443:1.1.1.1" "" "")
    local tmpdir
    tmpdir=$(mktemp -d "$TMP_DIR/probes.XXXXXX") || {
        _internet_last_check=$now; _internet_last_result=1; return 1
    }
    _PROBE_TMPDIR="$tmpdir"; _PROBE_PIDS=()
    local i=0 idx
    for idx in "${!endpoints[@]}"; do
        local ep="${endpoints[$idx]}" resolve="${probe_resolve[$idx]}"
        setsid bash -c '
            extra=()
            [ -n "$2" ] && extra=(--resolve "$2")
            if curl -fsS -o /dev/null --connect-timeout 2 --max-time "$1" \
                --no-keepalive --proto "=https" --proto-redir "=https" \
                ${extra[@]+"${extra[@]}"} -H "User-Agent: Mozilla/5.0" "$3" >/dev/null 2>&1; then
                echo ok > "$4/result_$5"
            fi
        ' _ "$INTERNET_CHECK_TIMEOUT" "$resolve" "$ep" "$tmpdir" "$i" 9>&- &
        _PROBE_PIDS+=($!)
        i=$((i + 1))
    done
    local success=1
    local deadline=$(( $(date +%s) + INTERNET_CHECK_TIMEOUT + 1 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        for f in "$tmpdir"/result_*; do
            if [ -f "$f" ] && [ "$(cat "$f" 2>/dev/null)" = "ok" ]; then success=0; break 2; fi
        done
        sleep 0.2
    done
    cleanup_probes
    _internet_last_check=$now; _internet_last_result=$success
    return $success
}

# ============================================================
# VARIETY
# ============================================================
# NOTE ON OWNERSHIP: this function matches any Variety process the user
# owns, not just ones this script launched. It is intentionally
# aggressive so that a manually started Variety cannot race remote
# fetches. If you do not want the script to touch a Variety you started
# yourself, set VARIETY_PAUSE_WHEN_DISABLED=true and VARIETY_WEIGHT=0,
# or simply do not run Variety alongside this script.
variety_pids() {
    local pid comm exe cmdline pid_dir
    for pid_dir in /proc/[0-9]*; do
        pid="${pid_dir#/proc/}"
        [ "$pid" = "$$" ] && continue
        comm=$(cat "/proc/$pid/comm" 2>/dev/null) || continue
        case "$comm" in
            variety) printf '%s\n' "$pid" ;;
            python|python3|python3.*)
                exe=$(readlink -f "/proc/$pid/exe" 2>/dev/null) || continue
                case "$exe" in
                    */python*)
                        cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null) || continue
                        printf '%s' "$cmdline" | grep -qE '(^|/)variety(\.py)?( |$)' && printf '%s\n' "$pid"
                        ;;
                esac
                ;;
        esac
    done
}

stop_variety() {
    local pids pid killed_any=false i
    pids=$(variety_pids)
    if [ -z "$pids" ]; then _VARIETY_PAUSED_BY_SCRIPT=false; return 1; fi
    _VARIETY_PAUSED_BY_SCRIPT=true
    while IFS= read -r pid; do
        [ -n "$pid" ] && kill -TERM "$pid" 2>/dev/null && killed_any=true
    done <<< "$pids"
    for i in $(seq 1 15); do sleep 0.2; [ -z "$(variety_pids)" ] && break; done
    pids=$(variety_pids)
    if [ -n "$pids" ]; then
        echo "$(date) - Variety did not stop after 3s; SIGKILL" >> "$LOGFILE"
        while IFS= read -r pid; do [ -n "$pid" ] && kill -KILL "$pid" 2>/dev/null; done <<< "$pids"
        sleep 0.3
    fi
    if [ -z "$(variety_pids)" ]; then
        echo "$(date) - Stopped Variety" >> "$LOGFILE"; return 0
    fi
    [ "$killed_any" = true ] && echo "$(date) - Partial Variety termination" >> "$LOGFILE" \
        || _VARIETY_PAUSED_BY_SCRIPT=false
    return 1
}

_restore_variety_verified() {
    local attempts=6 interval_s=0.4 i
    variety --next >/dev/null 2>&1 9>&- &
    for ((i = 0; i < attempts; i++)); do
        sleep "$interval_s"
        if [ -n "$(variety_pids)" ]; then _VARIETY_PAUSED_BY_SCRIPT=false; return 0; fi
    done
    return 1
}

start_variety() {
    if [ -n "$(variety_pids)" ]; then _VARIETY_PAUSED_BY_SCRIPT=false; return 1; fi
    if _restore_variety_verified; then echo "$(date) - Started Variety" >> "$LOGFILE"; return 0; fi
    echo "$(date) - Variety launch failed" >> "$LOGFILE"; return 1
}

_ensure_variety_running() {
    local tag="$1"
    start_variety >/dev/null 2>&1 || true
    if [ -n "$(variety_pids)" ]; then
        echo "$(date) - [$tag] Variety running" >> "$LOGFILE"; return 0
    fi
    echo "$(date) - [$tag] WARNING: Variety not running" >> "$LOGFILE"; return 1
}

use_variety() {
    command -v variety >/dev/null 2>&1 || { echo "$(date) - Variety not installed" >> "$LOGFILE"; return 1; }
    [ -z "$(variety_pids)" ] && { start_variety || return 1; }
    if variety --next >/dev/null 2>&1 9>&-; then
        echo "$(date) - Variety rotated" >> "$LOGFILE"; return 0
    fi
    echo "$(date) - Variety rotation failed" >> "$LOGFILE"; return 1
}

_prepare_variety_pause() {
    VARIETY_WAS_RUNNING=false
    if [ "${VARIETY_WEIGHT:-0}" -le 0 ] && [ "${VARIETY_PAUSE_WHEN_DISABLED:-false}" != true ]; then
        return 0
    fi
    command -v variety >/dev/null 2>&1 || return 0
    [ -z "$(variety_pids)" ] && return 0
    if stop_variety; then VARIETY_WAS_RUNNING=true; return 0; fi
    return 1
}

# ============================================================
# CATEGORIES & QUERIES
# ============================================================
CATEGORIES=(
    "3d art" "cgi" "blender" "maya" "cinema 4d" "zbrush"
    "abstract" "geometric" "minimalist" "modern art" "contemporary art"
    "animation" "gif" "motion graphics" "animated" "cartoon animation"
    "animals" "wildlife" "birds" "cats" "dogs" "horses" "wolves" "foxes"
    "fantasy creatures" "mythical animals" "dragons" "unicorns" "griffins"
    "fantasy" "creatures" "monsters" "beasts"
    "graffiti" "street art" "mural" "tagging" "spray paint"
    "illustration" "digital painting" "concept art" "character design"
    "pop art" "surreal" "surrealism" "magical realism"
    "fractal" "mandelbrot" "generative art" "algorithmic"
    "mixed media" "digital collage" "photomanipulation" "photo manipulation"
    "pixel art" "8-bit" "16-bit" "retro gaming"
    "vector" "vector art" "flat design" "minimal vector"
    "body art" "face painting" "makeup art" "cosplay"
    "collage" "paper art" "origami" "papercut"
    "pencil drawing" "charcoal" "ink sketch" "sketch" "doodle"
    "printmaking" "linocut" "etching" "woodcut"
    "landscapes" "scenery" "nature" "natural" "wilderness"
    "forest" "mountain" "mountains" "valley" "canyon"
    "sunset" "sunrise" "golden hour" "dusk" "dawn"
    "seascape" "ocean" "beach" "coast" "waves" "water"
    "cityscape" "urban" "city" "skyline" "metropolis"
    "architecture" "buildings" "structures" "monuments"
    "countryside" "rural" "farm" "pastoral"
    "desert" "arid" "sand dunes" "oasis"
    "tropical" "jungle" "rainforest" "exotic"
    "arctic" "snow" "ice" "winter landscape"
    "autumn" "fall" "autumn leaves" "harvest"
    "winter" "snow" "ice" "frost" "christmas"
    "spring" "bloom" "cherry blossom" "flowers"
    "summer" "beach" "sun" "vacation"
    "rain" "storm" "lightning" "thunder" "clouds" "fog" "mist"
    "sci-fi" "science fiction" "space art" "space" "cosmos"
    "nebula" "galaxy" "aurora" "stars" "planets" "constellations"
    "cyberpunk" "synthwave" "vaporwave" "retrowave" "outrun"
    "space opera" "interstellar" "astronaut" "alien" "ufo"
    "dragon" "castle" "mythical" "magical" "enchanting"
    "wizard" "sorcerer" "mage" "spell" "magic"
    "knight" "warrior" "battle" "medieval" "fantasy art"
    "fairy" "elf" "dwarf" "orc" "goblin" "troll"
    "goddess" "god" "deity" "mythology" "norse" "greek"
    "demon" "angel" "heaven" "hell" "divine"
    "portraits" "portrait" "face" "expressions"
    "people" "human" "person" "figure"
    "political" "politics" "activism" "social"
    "conceptual" "concept" "ideas" "philosophical"
    "emotional" "feelings" "mood" "atmosphere"
    "dark" "gothic" "macabre" "dark art" "creepy"
    "vintage" "retro" "old school" "classic"
    "photography" "photographer" "lens" "capture"
    "street photography" "candid" "urban life"
    "macro" "close up" "detail" "texture"
    "monochrome" "black and white" "grayscale" "sepia"
    "long exposure" "night photography" "light trails"
    "anime" "manga" "fanart anime" "kawaii" "chibi"
    "japanese" "japan" "samurai" "ninja" "geisha"
    "studio ghibli" "hayao miyazaki" "anime landscape"
    "manga style" "comic style" "webcomic"
    "cartoon" "comic" "webcomic" "comic strip"
    "marvel" "dc comics" "superhero" "villain"
    "fan art" "marvel fanart" "star wars fanart" "harry potter fanart"
    "disney" "pixar" "dreamworks" "animation studio"
    "jewelry" "woodwork" "sculpture" "glass art" "ceramics"
    "pottery" "clay" "stone" "metal" "welding"
    "fiber art" "textile" "weaving" "embroidery"
    "calligraphy" "lettering" "typography"
    "glitch art" "glitch" "corruption" "digital distortion"
    "double exposure" "multiple exposure" "layered"
    "light painting" "light art" "neon" "glow"
    "holographic" "iridescent" "prismatic"
    "dreamy" "dream" "nightmare" "subconscious"
    "peaceful" "serene" "calm" "tranquil"
    "mysterious" "mystery" "unknown" "occult"
    "romantic" "love" "passion" "tenderness"
    "nostalgic" "memory" "past" "reminisce"
)

shuffle_categories() {
    mapfile -t SHUFFLED_CATEGORIES < <(printf '%s\n' "${CATEGORIES[@]}" | shuf)
    CAT_INDEX=0
}
shuffle_categories

advance_category() {
    CAT_INDEX=$((CAT_INDEX + 1))
    if [ "$CAT_INDEX" -ge "${#SHUFFLED_CATEGORIES[@]}" ]; then
        echo "$(date) - [DeviantArt] cycle done, reshuffling" >> "$LOGFILE"
        shuffle_categories
    fi
}

declare -a SHUFFLED_PIXABAY_QUERIES=()
PIXABAY_QUERY_INDEX=0

shuffle_pixabay_queries() {
    mapfile -t SHUFFLED_PIXABAY_QUERIES < <(printf '%s\n' "${PIXABAY_QUERIES[@]}" | shuf)
    PIXABAY_QUERY_INDEX=0
    echo "$(date) - [Pixabay] Reshuffled ${#SHUFFLED_PIXABAY_QUERIES[@]} queries" >> "$LOGFILE"
}
shuffle_pixabay_queries

advance_pixabay_query() {
    PIXABAY_QUERY_INDEX=$((PIXABAY_QUERY_INDEX + 1))
    if [ "$PIXABAY_QUERY_INDEX" -ge "${#SHUFFLED_PIXABAY_QUERIES[@]}" ]; then
        echo "$(date) - [Pixabay] cycle done, reshuffling" >> "$LOGFILE"
        shuffle_pixabay_queries
    fi
}

declare -a SHUFFLED_SOURCES=()
SOURCE_INDEX=0

_gcd() { local a="$1" b="$2" t; while [ "$b" -ne 0 ]; do t=$((a % b)); a=$b; b=$t; done; printf '%s' "$a"; }

build_source_deck() {
    local -a names=() weights=()
    [ "$DEVIANTART_WEIGHT" -gt 0 ] && { names+=("deviantart"); weights+=("$DEVIANTART_WEIGHT"); }
    [ "$VARIETY_WEIGHT"    -gt 0 ] && { names+=("variety");    weights+=("$VARIETY_WEIGHT"); }
    [ "$PIXABAY_WEIGHT"    -gt 0 ] && { names+=("pixabay");    weights+=("$PIXABAY_WEIGHT"); }
    [ "${#names[@]}" -eq 0 ] && { SHUFFLED_SOURCES=(); SOURCE_INDEX=0; return 1; }
    local g="${weights[0]}" w
    for w in "${weights[@]:1}"; do g=$(_gcd "$g" "$w"); done
    [ "$g" -lt 1 ] && g=1
    local -a deck=()
    local i count
    for i in "${!names[@]}"; do
        count=$(( ${weights[$i]} / g ))
        [ "$count" -lt 1 ] && count=1
        for _ in $(seq 1 "$count"); do deck+=("${names[$i]}"); done
    done
    mapfile -t SHUFFLED_SOURCES < <(printf '%s\n' "${deck[@]}" | shuf)
    SOURCE_INDEX=0
    echo "$(date) - [Sources] deck of ${#SHUFFLED_SOURCES[@]} slots" >> "$LOGFILE"
}

advance_source_deck() {
    SOURCE_INDEX=$((SOURCE_INDEX + 1))
    if [ "$SOURCE_INDEX" -ge "${#SHUFFLED_SOURCES[@]}" ]; then
        echo "$(date) - [Sources] cycle done, reshuffling" >> "$LOGFILE"
        build_source_deck
    fi
}

# ============================================================
# HISTORY
# ============================================================
declare -A HISTORY_CACHE
declare -a RECENT_ORDERED=()
declare -A RECENT_BY_ID RECENT_BY_HASH
_RECENT_DIRTY=false
_RECENT_RETRY_FAILS=0

_rebuild_maps_from_ordered() {
    RECENT_BY_ID=(); RECENT_BY_HASH=()
    local line src h
    for line in "${RECENT_ORDERED[@]}"; do
        [ -z "$line" ] && continue
        IFS=$'\t' read -r src h <<< "$line"
        [ -z "$src" ] && continue
        RECENT_BY_ID["$src"]=1
        [ -n "$h" ] && RECENT_BY_HASH["$h"]=1
    done
}

_append_to_recent_window() {
    local entry="$1"; [ -z "$entry" ] && return 1
    RECENT_ORDERED+=("$entry")
    local n=${#RECENT_ORDERED[@]}
    [ "$n" -gt "$RECENT_HISTORY_SIZE" ] && RECENT_ORDERED=("${RECENT_ORDERED[@]:$((n - RECENT_HISTORY_SIZE))}")
    _rebuild_maps_from_ordered
}

_persist_recent_window() {
    _RECENT_TMP=$(mktemp "$RECENT_HISTORY_FILE.XXXXXX") || { _RECENT_TMP=""; return 1; }
    if ! printf '%s\n' "${RECENT_ORDERED[@]}" > "$_RECENT_TMP"; then
        rm -f "$_RECENT_TMP"; _RECENT_TMP=""; return 1
    fi
    if ! mv -f "$_RECENT_TMP" "$RECENT_HISTORY_FILE"; then
        rm -f "$_RECENT_TMP"; _RECENT_TMP=""; return 1
    fi
    _RECENT_TMP=""; _RECENT_DIRTY=false; _RECENT_RETRY_FAILS=0
    return 0
}

load_history() {
    if [ ! -e "$HISTORY_FILE" ]; then HISTORY_CACHE=(); return 1; fi
    if [ ! -r "$HISTORY_FILE" ]; then return 2; fi
    local existing
    existing=$(set -o pipefail; tail -n "$HISTORY_SIZE" "$HISTORY_FILE" 2>/dev/null \
               | cut -b1-"$HISTORY_MAX_LINE_BYTES" 2>/dev/null)
    local pipe_rc=$?
    [ "$pipe_rc" -ne 0 ] && return 2
    local -a lines=()
    [ -n "$existing" ] && mapfile -t lines <<< "$existing"
    HISTORY_CACHE=()
    local count=0 url
    for url in "${lines[@]}"; do
        [ -z "$url" ] && continue
        HISTORY_CACHE["$url"]=1
        ((count++))
    done
    echo "$(date) - Loaded $count history entries" >> "$LOGFILE"
    return 0
}

load_recent_history() {
    if [ "$_RECENT_DIRTY" = true ]; then _persist_recent_window || return 1; fi
    if [ ! -e "$RECENT_HISTORY_FILE" ]; then
        RECENT_ORDERED=(); _rebuild_maps_from_ordered; return 1
    fi
    if [ ! -r "$RECENT_HISTORY_FILE" ]; then return 2; fi
    local existing
    existing=$(set -o pipefail; tail -n "$RECENT_HISTORY_SIZE" "$RECENT_HISTORY_FILE" 2>/dev/null \
               | cut -b1-"$MAX_URL_LENGTH" 2>/dev/null)
    local pipe_rc=$?
    [ "$pipe_rc" -ne 0 ] && return 2
    local -a new_ordered=()
    [ -n "$existing" ] && mapfile -t new_ordered <<< "$existing"
    local -a valid_ordered=()
    local _l _s _h discarded=0
    for _l in "${new_ordered[@]}"; do
        [ -z "$_l" ] && continue
        _s="${_l%%$'\t'*}"
        if [[ "$_l" == *$'\t'* ]]; then _h="${_l#*$'\t'}"; else _h=""; fi
        [ -z "$_s" ] && { discarded=$((discarded+1)); continue; }
        if [ -n "$_h" ] && ! [[ "$_h" =~ ^[0-9a-f]{64}$ ]]; then
            discarded=$((discarded+1)); continue
        fi
        valid_ordered+=("$_l")
    done
    new_ordered=("${valid_ordered[@]}")
    if [ "$discarded" -gt 0 ]; then
        echo "$(date) - [Recent] discarded $discarded malformed entries" >> "$LOGFILE"
    fi
    local n=${#new_ordered[@]}
    [ "$n" -gt "$RECENT_HISTORY_SIZE" ] && new_ordered=("${new_ordered[@]:$((n - RECENT_HISTORY_SIZE))}")
    RECENT_ORDERED=("${new_ordered[@]}")
    _rebuild_maps_from_ordered
    echo "$(date) - Loaded ${#RECENT_ORDERED[@]} recent entries" >> "$LOGFILE"
    return 0
}

_hist_rc=0
load_history || _hist_rc=$?
if [ "$_hist_rc" -eq 2 ]; then
    echo "$(date) - ERROR: history file unreadable; failing closed (fix $HISTORY_FILE)" >> "$LOGFILE"
    exit 1
fi
_rhist_rc=0
load_recent_history || _rhist_rc=$?
if [ "$_rhist_rc" -eq 2 ]; then
    echo "$(date) - ERROR: recent-history file unreadable; failing closed" >> "$LOGFILE"
    exit 1
fi

add_to_history() {
    local url="$1"
    [ -z "$url" ] && return 1
    [ "${#url}" -gt "$HISTORY_MAX_LINE_BYTES" ] || [[ "$url" == *$'\n'* ]] && return 1
    printf '%s\n' "$url" >> "$HISTORY_FILE" || return 1
    HISTORY_CACHE["$url"]=1
    local line_count
    line_count=$(wc -l < "$HISTORY_FILE" 2>/dev/null || echo 0)
    if [ "$line_count" -gt "$((HISTORY_SIZE * 2))" ]; then
        _HISTORY_TMP=$(mktemp "$HISTORY_FILE.XXXXXX") || return 0
        if tail -n "$HISTORY_SIZE" "$HISTORY_FILE" > "$_HISTORY_TMP" && mv -f "$_HISTORY_TMP" "$HISTORY_FILE"; then
            _HISTORY_TMP=""; load_history || true
        else
            rm -f "$_HISTORY_TMP"; _HISTORY_TMP=""
        fi
    fi
    return 0
}

add_to_recent() {
    local source_key="$1" content_hash="${2:-}"
    [ -z "$source_key" ] && return 1
    _append_to_recent_window "$(printf '%s\t%s' "$source_key" "$content_hash")"
    _RECENT_DIRTY=true
    _persist_recent_window || return 1
    return 0
}

is_in_history() {
    local url="$1"; [ -z "$url" ] && return 2
    [[ -v HISTORY_CACHE["$url"] ]] && return 0
    return 1
}
recent_has_id() {
    local key="$1"; [ -z "$key" ] && return 2
    [[ -v RECENT_BY_ID["$key"] ]] && return 0
    return 1
}
recent_has_hash() {
    local h="$1"; [ -z "$h" ] && return 2
    [[ -v RECENT_BY_HASH["$h"] ]] && return 0
    return 1
}

# ============================================================
# WALLPAPER PUBLICATION (transaction)
# ============================================================
_publish_wallpaper() {
    local src="$1"
    local staged="$WALLPAPER_CACHE_DIR/.staged.$$.png"
    local prev="$WALLPAPER_CACHE_DIR/.prev.$$.png"
    _STAGED_FILE="$staged"
    _PREV_FILE=""
    _PUBLISH_PENDING=false

    # ---- 1. Frame-0 extraction to PNG ----
    local src_mime
    src_mime=$(file --mime-type -b "$src" 2>/dev/null || echo "")
    if [ "$src_mime" = "image/png" ] && [ "$FORTUNE_OVERLAY_ENABLED" != true ]; then
        if ! cp -f -- "$src" "$staged" 2>/dev/null; then
            echo "$(date) - [Publish] PNG passthrough copy failed" >> "$LOGFILE"
            rm -f "$staged" 2>/dev/null || true; _STAGED_FILE=""
            return 1
        fi
    else
        if ! _run_magick "${src}[0]" +repage "$staged" 2>/dev/null; then
            echo "$(date) - [Publish] frame-0 extraction failed" >> "$LOGFILE"
            rm -f "$staged" 2>/dev/null || true; _STAGED_FILE=""
            return 1
        fi
    fi
    [ -s "$staged" ] || {
        echo "$(date) - [Publish] missing output after extraction" >> "$LOGFILE"
        rm -f "$staged" 2>/dev/null || true; _STAGED_FILE=""
        return 1
    }

    # ---- 2. Postcondition: single frame ----
    local frames
    frames=$(_run_identify -format '%n' "$staged" 2>/dev/null) || frames=""
    if [ "$frames" != "1" ]; then
        echo "$(date) - [Publish] expected 1 frame, got '${frames:-?}'" >> "$LOGFILE"
        rm -f "$staged" 2>/dev/null || true; _STAGED_FILE=""
        return 1
    fi

    # ---- 3. Overlay (optional) ----
    if [ "$FORTUNE_OVERLAY_ENABLED" = true ]; then
        if apply_fortune_overlay "$staged"; then
            echo "$(date) - [Publish] overlay applied" >> "$LOGFILE"
        else
            echo "$(date) - [Publish] overlay skipped" >> "$LOGFILE"
        fi
    fi

    # ---- 4. Signal check ----
    if [ "$SIGNAL_EXIT_CODE" -ne 0 ]; then
        echo "$(date) - [Publish] signal pending; aborting" >> "$LOGFILE"
        rm -f "$staged" 2>/dev/null || true; _STAGED_FILE=""
        return 1
    fi

    # ---- 5. Backup current (abort if fails) ----
    local prev_existed=false
    if [ -f "$WALLPAPER_CURRENT" ]; then
        prev_existed=true
        if ! cp -f -- "$WALLPAPER_CURRENT" "$prev" 2>/dev/null; then
            echo "$(date) - [Publish] cannot backup current; ABORTING" >> "$LOGFILE"
            rm -f "$staged" "$prev" 2>/dev/null || true
            _STAGED_FILE=""
            return 1
        fi
        _PREV_FILE="$prev"
    fi

    # ---- 6. Journal pending ----
    if ! _write_publish_journal "pending" "$_PREV_FILE" "$prev_existed" "$staged"; then
        echo "$(date) - [Publish] cannot write journal; ABORTING" >> "$LOGFILE"
        rm -f "$staged" "$prev" 2>/dev/null || true
        _STAGED_FILE=""; _PREV_FILE=""
        return 1
    fi
    _PUBLISH_PENDING=true

    # ---- 7. Atomic rename ----
    if ! mv -f -- "$staged" "$WALLPAPER_CURRENT"; then
        echo "$(date) - [Publish] atomic rename failed" >> "$LOGFILE"
        _PUBLISH_PENDING=false
        rm -f "$staged" "$prev" 2>/dev/null || true
        _clear_publish_journal
        _STAGED_FILE=""; _PREV_FILE=""
        return 1
    fi
    _STAGED_FILE=""
    _fsync_cache_dir

    # ---- 8. Postcondition: published image valid ----
    if [ ! -s "$WALLPAPER_CURRENT" ] \
       || ! _run_identify -format '%w %h' "${WALLPAPER_CURRENT}[0]" >/dev/null 2>&1; then
        echo "$(date) - [Publish] published image invalid; rolling back" >> "$LOGFILE"
        _rollback_publication || true
        return 1
    fi

    # ---- 9. Apply to Plasma ----
    local plasma_ok=false
    if timeout --kill-after=2s "${PLASMA_APPLY_TIMEOUT}s" \
       plasma-apply-wallpaperimage "$WALLPAPER_CURRENT" 9>&- >/dev/null 2>&1; then
        plasma_ok=true
    fi

    # ---- 9a. Signal check after plasma-apply returns ----
    # If a signal arrived during plasma-apply, do not proceed to commit;
    # roll back so exit trap and next-startup recovery agree.
    if [ "$plasma_ok" = true ] && [ "$SIGNAL_EXIT_CODE" -ne 0 ]; then
        echo "$(date) - [Publish] signal during plasma-apply; rolling back" >> "$LOGFILE"
        _rollback_publication || true
        return 1
    fi

    # ---- 10. Commit ----
    if [ "$plasma_ok" = true ]; then
        # Persist `committed` BEFORE relaxing in-memory safety. If this
        # write fails, the journal stays at `pending`; we deliberately
        # KEEP `_PUBLISH_PENDING=true` so the exit trap will roll back —
        # but we also do NOT delete the backup, and we do NOT clear
        # anything. The next startup's recovery will make a conservative
        # decision based on `pending`.
        if _update_publish_journal_state "committed"; then
            _PUBLISH_PENDING=false
            [ -n "$_PREV_FILE" ] && rm -f "$_PREV_FILE" 2>/dev/null || true
            _PREV_FILE=""
            if ! _clear_publish_journal; then
                echo "$(date) - [Publish] WARN: journal clear failed after commit; recovery will resolve on next startup" >> "$LOGFILE"
            fi
            return 0
        fi
        # Cannot persist committed state. This is the C1 scenario:
        # journal stays `pending`, backup preserved. Fail closed for
        # subsequent startup logic by NOT clearing the journal.
        echo "$(date) - [Publish] FATAL: cannot persist committed state; journal stuck at pending" >> "$LOGFILE"
        echo "$(date) - [Publish] FATAL: next startup recovery may roll back (see journal)" >> "$LOGFILE"
        _PRESERVE_JOURNAL=true
        _PUBLISH_PENDING=false
        return 0
    fi

    # ---- 11. Rollback ----
    echo "$(date) - [Publish] plasma-apply failed; initiating rollback" >> "$LOGFILE"
    _rollback_publication || true
    return 1
}

# ============================================================
# DEVIANTART FETCHER
# ============================================================
fetch_deviantart() {
    [ "$DEVIANTART_WEIGHT" -le 0 ] && return 1

    if ! _prepare_variety_pause; then
        echo "$(date) - [DeviantArt] Variety still running — aborting" >> "$LOGFILE"
        [ "$_VARIETY_PAUSED_BY_SCRIPT" = true ] && _ensure_variety_running "DeviantArt"
        return 1
    fi
    local variety_was_running="$VARIETY_WAS_RUNNING"
    [ "$variety_was_running" = true ] && echo "$(date) - [DeviantArt] Paused Variety" >> "$LOGFILE"

    local current_category="${SHUFFLED_CATEGORIES[$CAT_INDEX]}"
    echo "$(date) - [DeviantArt] Searching: '$current_category'" >> "$LOGFILE"

    local URL_LIST="" RETRY_COUNT=0
    while [ -z "$URL_LIST" ] && [ "$RETRY_COUNT" -lt "$MAX_RETRIES" ]; do
        if [ "$RETRY_COUNT" -gt 0 ]; then
            echo "$(date) - [DeviantArt] Retry $RETRY_COUNT" >> "$LOGFILE"
            interruptible_sleep 3
            [ "$SIGNAL_EXIT_CODE" -ne 0 ] && return 1
        fi
        URL_LIST=$(timeout --kill-after=5s "${DEVIOUSQ_TIMEOUT}s" deviousq \
            --medium image --rating nonadult --return-field content_url \
            --limit "$SEARCH_LIMIT" "$current_category" 2>/dev/null \
            | head -c "$DEVIOUSQ_MAX_OUTPUT_BYTES"
            exit "${PIPESTATUS[0]}")
        local exit_code=$?
        if [ $exit_code -eq 141 ]; then
            echo "$(date) - [DeviantArt] Output capped" >> "$LOGFILE"
        elif [ $exit_code -eq 124 ] || [ $exit_code -eq 137 ]; then
            echo "$(date) - [DeviantArt] Timed out" >> "$LOGFILE"; URL_LIST=""
        elif [ $exit_code -ne 0 ]; then URL_LIST=""; fi
        RETRY_COUNT=$((RETRY_COUNT + 1))
    done

    if [ -z "$URL_LIST" ]; then
        advance_category
        [ "$variety_was_running" = true ] && _ensure_variety_running "DeviantArt"
        return 1
    fi

    [ "${#URL_LIST}" -ge "$((DEVIOUSQ_MAX_OUTPUT_BYTES - 1))" ] && URL_LIST=$(printf '%s\n' "$URL_LIST" | sed '$d')

    local VALID_URLS
    VALID_URLS=$(printf '%s\n' "$URL_LIST" | grep -E '^https://' \
        | awk -v m="$MAX_URL_LENGTH" 'length($0) <= m' | head -100)

    if [ -z "$VALID_URLS" ]; then
        advance_category
        [ "$variety_was_running" = true ] && _ensure_variety_running "DeviantArt"
        return 1
    fi

    local RANDOM_URL="" SOURCE_ID="" cand_id small_skipped=0 url
    _DA_LOGGED_UNDECODABLE=false
    local -a SHUFFLED_URLS
    mapfile -t SHUFFLED_URLS < <(printf '%s\n' "$VALID_URLS" | shuf)

    for url in "${SHUFFLED_URLS[@]}"; do
        cand_id=$(_da_identity "$url") || continue
        if ! is_in_history "$cand_id" && ! recent_has_id "$cand_id"; then
            if ! _da_token_hd_ok "$url"; then small_skipped=$((small_skipped+1)); continue; fi
            RANDOM_URL="$url"; SOURCE_ID="$cand_id"
            echo "$(date) - [DeviantArt] Found unseen image" >> "$LOGFILE"
            break
        fi
    done

    if [ -z "$RANDOM_URL" ]; then
        for url in "${SHUFFLED_URLS[@]}"; do
            cand_id=$(_da_identity "$url") || continue
            if ! recent_has_id "$cand_id"; then
                if ! _da_token_hd_ok "$url"; then small_skipped=$((small_skipped+1)); continue; fi
                RANDOM_URL="$url"; SOURCE_ID="$cand_id"
                echo "$(date) - [DeviantArt] Long-term repeat" >> "$LOGFILE"
                break
            fi
        done
    fi

    if [ -z "$RANDOM_URL" ]; then
        echo "$(date) - [DeviantArt] No eligible candidates (${small_skipped} skipped)" >> "$LOGFILE"
        advance_category
        [ "$variety_was_running" = true ] && _ensure_variety_running "DeviantArt"
        return 1
    fi

    local REWRITTEN_URL
    REWRITTEN_URL=$(_rewrite_da_url "$RANDOM_URL")
    [ "$REWRITTEN_URL" != "$RANDOM_URL" ] && echo "$(date) - [DeviantArt] URL rewritten to max" >> "$LOGFILE"
    RANDOM_URL="$REWRITTEN_URL"

    local WALLPAPER_FILE="$TMP_DIR/wallpaper_$$.jpg"
    echo "$(date) - [DeviantArt] Downloading..." >> "$LOGFILE"

    local success=false dl_rc=0
    _download_bounded "$RANDOM_URL" "$WALLPAPER_FILE" \
        "$MAX_IMAGE_FILE_SIZE" "$WGET_TIMEOUT" "$WGET_TOTAL_TIMEOUT"
    dl_rc=$?

    if [ "$dl_rc" -eq 2 ]; then
        echo "$(date) - [DeviantArt] Image exceeds size cap (permanent)" >> "$LOGFILE"
        rm -f "$WALLPAPER_FILE"; advance_category
    elif [ "$dl_rc" -eq 0 ]; then
        local file_size=0 validation_ok=false file_hash=""
        file_size=$(stat -c%s "$WALLPAPER_FILE" 2>/dev/null || echo 0)
        if is_valid_image_file "$WALLPAPER_FILE" && [ "$file_size" -gt 1024 ]; then validation_ok=true; fi
        if [ "$validation_ok" = true ]; then
            if [ "$DEVIANTART_REQUIRE_LANDSCAPE" = true ]; then
                is_landscape_hd_image "$WALLPAPER_FILE" "$DEVIANTART_IMAGE_MIN_WIDTH" "$DEVIANTART_IMAGE_MIN_HEIGHT" \
                    || validation_ok=false
            else
                is_hd_image "$WALLPAPER_FILE" "$DEVIANTART_IMAGE_MIN_WIDTH" "$DEVIANTART_IMAGE_MIN_HEIGHT" \
                    || validation_ok=false
            fi
        fi
        if [ "$validation_ok" = true ]; then
            file_hash=$(sha256sum "$WALLPAPER_FILE" 2>/dev/null | awk '{print $1}')
            [ -n "$file_hash" ] && recent_has_hash "$file_hash" && validation_ok=false
        fi
        if [ "$validation_ok" = true ]; then
            if _publish_wallpaper "$WALLPAPER_FILE"; then
                add_to_history "$SOURCE_ID" || echo "$(date) - [DeviantArt] WARN: history write failed" >> "$LOGFILE"
                add_to_recent "$SOURCE_ID" "$file_hash" || echo "$(date) - [DeviantArt] WARN: recent write failed" >> "$LOGFILE"
                echo "$(date) - [DeviantArt] Wallpaper set from '$current_category' (${file_size} bytes)" >> "$LOGFILE"
                success=true
            fi
            advance_category
        else
            advance_category
        fi
        rm -f "$WALLPAPER_FILE"
    else
        echo "$(date) - [DeviantArt] Download failed" >> "$LOGFILE"
        rm -f "$WALLPAPER_FILE"; advance_category
    fi

    if [ "$variety_was_running" = true ] && [ "$success" != true ]; then
        _ensure_variety_running "DeviantArt"
        echo "$(date) - [DeviantArt] Restarted Variety after failure" >> "$LOGFILE"
    fi

    [ "$success" = true ] && return 0 || return 1
}

# ============================================================
# PIXABAY FETCHER
# ============================================================
fetch_pixabay() {
    [ "$PIXABAY_WEIGHT" -le 0 ] && return 1
    [ -z "$PIXABAY_API_KEY" ] && return 1

    if ! _prepare_variety_pause; then
        echo "$(date) - [Pixabay] Variety still running — aborting" >> "$LOGFILE"
        [ "$_VARIETY_PAUSED_BY_SCRIPT" = true ] && _ensure_variety_running "Pixabay"
        return 1
    fi
    local variety_was_running="$VARIETY_WAS_RUNNING"
    [ "$variety_was_running" = true ] && echo "$(date) - [Pixabay] Paused Variety" >> "$LOGFILE"

    local query="${SHUFFLED_PIXABAY_QUERIES[$PIXABAY_QUERY_INDEX]}"
    echo "$(date) - [Pixabay] Query: '$query'" >> "$LOGFILE"

    local api_url
    case "$query" in
        category:*)
            local cat="${query#category:}"
            api_url="https://pixabay.com/api/?key=${PIXABAY_API_KEY}&category=${cat}&image_type=photo&min_width=${PIXABAY_IMAGE_MIN_WIDTH}&per_page=${PIXABAY_PER_PAGE}&safesearch=true"
            ;;
        term:*)
            local t="${query#term:}" enc
            enc=$(printf '%s' "$t" | jq -sRr @uri)
            api_url="https://pixabay.com/api/?key=${PIXABAY_API_KEY}&q=${enc}&image_type=photo&min_width=${PIXABAY_IMAGE_MIN_WIDTH}&per_page=${PIXABAY_PER_PAGE}&safesearch=true"
            ;;
        *)
            advance_pixabay_query
            [ "$variety_was_running" = true ] && _ensure_variety_running "Pixabay"
            return 1
            ;;
    esac

    if printf '%s' "$api_url" | LC_ALL=C grep -q '[[:cntrl:]]'; then
        echo "$(date) - [Pixabay] API URL contains control chars; advancing" >> "$LOGFILE"
        advance_pixabay_query
        [ "$variety_was_running" = true ] && _ensure_variety_running "Pixabay"
        return 1
    fi

    local api_response_file="$TMP_DIR/pixabay_api_$$.json"
    local escaped_url api_config
    escaped_url=$(_curl_config_escape "$api_url")
    api_config=$(printf 'url = "%s"\n' "$escaped_url")

    local api_retry=0 api_ok=false api_rc=0
    while [ "$api_retry" -lt "$MAX_RETRIES" ]; do
        [ "$SIGNAL_EXIT_CODE" -ne 0 ] && break
        _download_api_bounded "$api_config" "$api_response_file" \
            "$PIXABAY_MAX_API_RESPONSE_SIZE" "$PIXABAY_API_TIMEOUT"
        api_rc=$?
        if [ "$api_rc" -eq 0 ]; then api_ok=true; break; fi
        if [ "$api_rc" -eq 2 ]; then
            echo "$(date) - [Pixabay] API response exceeds cap (permanent)" >> "$LOGFILE"; break
        fi
        api_retry=$((api_retry + 1))
        [ "$api_retry" -lt "$MAX_RETRIES" ] && interruptible_sleep 2
    done

    if [ "$api_ok" != true ] || \
       ! jq -e 'type == "object" and (.hits | type == "array")' "$api_response_file" >/dev/null 2>&1; then
        rm -f "$api_response_file"; advance_pixabay_query
        [ "$variety_was_running" = true ] && _ensure_variety_running "Pixabay"
        return 1
    fi

    local hits
    hits=$(jq -r '
        .hits[]
        | select((.id | type) == "number")
        | select((.largeImageURL | type) == "string")
        | select(.largeImageURL | startswith("https://"))
        | select((.largeImageURL | length) <= '"$MAX_URL_LENGTH"')
        | select((.imageWidth  | type) == "number" and .imageWidth  >= '"$PIXABAY_IMAGE_MIN_WIDTH"')
        | select((.imageHeight | type) == "number" and .imageHeight >= '"$PIXABAY_IMAGE_MIN_HEIGHT"')
        | select(.imageWidth > .imageHeight)
        | "\(.id)\t\(.largeImageURL)"
    ' "$api_response_file")
    rm -f "$api_response_file"

    if [ -z "$hits" ]; then
        echo "$(date) - [Pixabay] No suitable images" >> "$LOGFILE"
        advance_pixabay_query
        [ "$variety_was_running" = true ] && _ensure_variety_running "Pixabay"
        return 1
    fi

    local shuffled_hits chosen_id="" chosen_url=""
    shuffled_hits=$(printf '%s\n' "$hits" | shuf)

    while IFS=$'\t' read -r id url; do
        [ -z "$id" ] && continue
        if ! is_in_history "pixabay://${id}" && ! recent_has_id "pixabay://${id}"; then
            chosen_id="$id"; chosen_url="$url"; break
        fi
    done <<< "$shuffled_hits"

    if [ -z "$chosen_id" ]; then
        while IFS=$'\t' read -r id url; do
            [ -z "$id" ] && continue
            if ! recent_has_id "pixabay://${id}"; then
                chosen_id="$id"; chosen_url="$url"; break
            fi
        done <<< "$shuffled_hits"
    fi

    if [ -z "$chosen_id" ]; then
        advance_pixabay_query
        [ "$variety_was_running" = true ] && _ensure_variety_running "Pixabay"
        return 1
    fi

    local WALLPAPER_FILE="$TMP_DIR/pixabay_$$.jpg"
    echo "$(date) - [Pixabay] Downloading $chosen_id..." >> "$LOGFILE"

    local success=false dl_ok=false dl_retry=0 dl_delay=2 dl_rc=0
    while [ "$dl_retry" -lt "$MAX_RETRIES" ]; do
        [ "$SIGNAL_EXIT_CODE" -ne 0 ] && break
        _download_bounded "$chosen_url" "$WALLPAPER_FILE" \
            "$MAX_IMAGE_FILE_SIZE" "$PIXABAY_DL_CONNECT_TIMEOUT" "$PIXABAY_DL_TOTAL_TIMEOUT"
        dl_rc=$?
        if [ "$dl_rc" -eq 0 ]; then dl_ok=true; break; fi
        if [ "$dl_rc" -eq 2 ]; then
            echo "$(date) - [Pixabay] Image exceeds cap (permanent)" >> "$LOGFILE"; break
        fi
        dl_retry=$((dl_retry + 1))
        if [ "$dl_retry" -lt "$MAX_RETRIES" ]; then
            echo "$(date) - [Pixabay] Download failed (rc=$dl_rc), retry in ${dl_delay}s" >> "$LOGFILE"
            interruptible_sleep "$dl_delay"; dl_delay=$((dl_delay * 2))
        fi
    done

    if [ "$dl_ok" = true ]; then
        local file_size=0 validation_ok=false file_hash=""
        file_size=$(stat -c%s "$WALLPAPER_FILE" 2>/dev/null || echo 0)
        if is_valid_image_file "$WALLPAPER_FILE" && [ "$file_size" -gt 1024 ]; then validation_ok=true; fi
        if [ "$validation_ok" = true ]; then
            is_landscape_hd_image "$WALLPAPER_FILE" "$PIXABAY_IMAGE_MIN_WIDTH" "$PIXABAY_IMAGE_MIN_HEIGHT" \
                || validation_ok=false
        fi
        if [ "$validation_ok" = true ]; then
            file_hash=$(sha256sum "$WALLPAPER_FILE" 2>/dev/null | awk '{print $1}')
            [ -n "$file_hash" ] && recent_has_hash "$file_hash" && validation_ok=false
        fi
        if [ "$validation_ok" = true ]; then
            if _publish_wallpaper "$WALLPAPER_FILE"; then
                add_to_history "pixabay://${chosen_id}" || echo "$(date) - [Pixabay] WARN: history write failed" >> "$LOGFILE"
                add_to_recent "pixabay://${chosen_id}" "$file_hash" || echo "$(date) - [Pixabay] WARN: recent write failed" >> "$LOGFILE"
                echo "$(date) - [Pixabay] Wallpaper set from '$query' (id=$chosen_id)" >> "$LOGFILE"
                success=true
            fi
            advance_pixabay_query
        else
            advance_pixabay_query
        fi
        rm -f "$WALLPAPER_FILE"
    else
        echo "$(date) - [Pixabay] Download failed after retries" >> "$LOGFILE"
        rm -f "$WALLPAPER_FILE"; advance_pixabay_query
    fi

    if [ "$variety_was_running" = true ] && [ "$success" != true ]; then
        _ensure_variety_running "Pixabay"
        echo "$(date) - [Pixabay] Restarted Variety after failure" >> "$LOGFILE"
    fi

    [ "$success" = true ] && return 0 || return 1
}

# ============================================================
# SOURCE SELECTION
# ============================================================
CURRENT_SOURCE=""
SAME_SOURCE_COUNT=0
CANDIDATES=()

select_source() {
    if [ "${#SHUFFLED_SOURCES[@]}" -eq 0 ]; then
        build_source_deck || { SELECTED_SOURCE=""; return 1; }
    fi
    SELECTED_SOURCE="${SHUFFLED_SOURCES[$SOURCE_INDEX]}"
    advance_source_deck
    return 0
}

update_source_state() {
    if [ "$1" = "$CURRENT_SOURCE" ]; then
        SAME_SOURCE_COUNT=$((SAME_SOURCE_COUNT + 1))
    else
        CURRENT_SOURCE="$1"; SAME_SOURCE_COUNT=1
    fi
}

other_sources() {
    local exclude="$1" pool=() s
    for s in deviantart variety pixabay; do
        [ "$s" = "$exclude" ] && continue
        is_source_enabled "$s" || continue
        pool+=("$s")
    done
    [ "${#pool[@]}" -eq 0 ] && return 0
    printf '%s\n' "${pool[@]}" | shuf
}

try_source() {
    case "$1" in
        deviantart) fetch_deviantart ;;
        pixabay)    fetch_pixabay ;;
        variety)    [ "$VARIETY_WEIGHT" -gt 0 ] && use_variety || return 1 ;;
        *)          return 1 ;;
    esac
}

is_source_enabled() {
    case "$1" in
        deviantart) [ "$DEVIANTART_WEIGHT" -gt 0 ] ;;
        pixabay)    [ "$PIXABAY_WEIGHT"    -gt 0 ] ;;
        variety)    [ "$VARIETY_WEIGHT"    -gt 0 ] ;;
        *)          return 1 ;;
    esac
}

build_source_deck || exit 1

# ============================================================
# STARTUP WARNING
# ============================================================
if [ "${VARIETY_WEIGHT:-0}" -le 0 ] && [ "${VARIETY_PAUSE_WHEN_DISABLED:-false}" != true ] \
   && command -v variety >/dev/null 2>&1 && [ -n "$(variety_pids 2>/dev/null)" ]; then
    echo "$(date) - WARNING: Variety is running; VARIETY_PAUSE_WHEN_DISABLED=false means remote wallpapers may be overwritten by Variety" >> "$LOGFILE"
fi

# ============================================================
# MAIN LOOP
# ============================================================
IS_ONLINE=false

_build_candidate_list() {
    CANDIDATES=()
    if [ "$SAME_SOURCE_COUNT" -ge "$MAX_SAME_SOURCE" ] && [ -n "$CURRENT_SOURCE" ]; then
        local alt
        while IFS= read -r alt; do
            [ -n "$alt" ] && CANDIDATES+=("$alt")
        done < <(other_sources "$CURRENT_SOURCE")
    fi
    if [ "${#CANDIDATES[@]}" -eq 0 ]; then
        if select_source && [ -n "$SELECTED_SOURCE" ]; then
            CANDIDATES+=("$SELECTED_SOURCE")
        fi
    fi
    local s already c
    for s in deviantart variety pixabay; do
        is_source_enabled "$s" || continue
        already=false
        for c in "${CANDIDATES[@]}"; do
            if [ "$c" = "$s" ]; then already=true; break; fi
        done
        [ "$already" = false ] && CANDIDATES+=("$s")
    done
}

while true; do
    [ "$SIGNAL_EXIT_CODE" -ne 0 ] && break

    echo "$(date) - heartbeat (pid=$$)" >> "$LOGFILE"
    rotate_log

    if ! check_internet; then
        if [ "$IS_ONLINE" = true ]; then
            echo "$(date) - Internet lost — Variety only" >> "$LOGFILE"; IS_ONLINE=false
        fi
        if [ "$VARIETY_WEIGHT" -gt 0 ] && use_variety; then
            update_source_state "variety"
            interruptible_sleep "$SLEEP_INTERVAL"
        else
            interruptible_sleep 30
        fi
        continue
    fi

    if [ "$IS_ONLINE" = false ]; then
        echo "$(date) - Internet restored" >> "$LOGFILE"
        IS_ONLINE=true; CURRENT_SOURCE=""; SAME_SOURCE_COUNT=0
    fi

    _build_candidate_list

    if [ "${#CANDIDATES[@]}" -eq 0 ]; then
        echo "$(date) - no candidates available" >> "$LOGFILE"
        interruptible_sleep 20; continue
    fi

    echo "$(date) - Candidates (streak $SAME_SOURCE_COUNT/$MAX_SAME_SOURCE, current=$CURRENT_SOURCE): ${CANDIDATES[*]}" >> "$LOGFILE"

    SUCCESS=false; SOURCE_USED=""; local_cand=""
    for local_cand in "${CANDIDATES[@]}"; do
        [ "$SIGNAL_EXIT_CODE" -ne 0 ] && break
        if try_source "$local_cand"; then
            SUCCESS=true; SOURCE_USED="$local_cand"; break
        fi
    done

    if [ "$SUCCESS" = true ]; then
        if [ "$SOURCE_USED" = "$CURRENT_SOURCE" ] && [ "$SAME_SOURCE_COUNT" -ge "$MAX_SAME_SOURCE" ]; then
            echo "$(date) - WARNING: $SOURCE_USED reused beyond MAX_SAME_SOURCE=$MAX_SAME_SOURCE (all alternatives failed)" >> "$LOGFILE"
        fi
        update_source_state "$SOURCE_USED"
        [ "$SAME_SOURCE_COUNT" -gt "$MAX_SAME_SOURCE" ] && SAME_SOURCE_COUNT="$MAX_SAME_SOURCE"
        echo "$(date) - [Success] Source: $SOURCE_USED (streak $SAME_SOURCE_COUNT/$MAX_SAME_SOURCE)" >> "$LOGFILE"
        interruptible_sleep "$SLEEP_INTERVAL"
    else
        echo "$(date) - all candidates failed" >> "$LOGFILE"
        interruptible_sleep 20
    fi

    if [ "$_RECENT_DIRTY" = true ]; then
        if [ "$_RECENT_RETRY_FAILS" -lt 5 ] || [ $((RANDOM % 5)) -eq 0 ]; then
            _persist_recent_window || _RECENT_RETRY_FAILS=$((_RECENT_RETRY_FAILS + 1))
        fi
    fi

    if [ $((RANDOM % 50)) -eq 0 ]; then
        _h_rc=0; load_history || _h_rc=$?
        [ "$_h_rc" -eq 2 ] && echo "$(date) - WARN: history reload found unreadable file" >> "$LOGFILE"
        _r_rc=0; load_recent_history || _r_rc=$?
        [ "$_r_rc" -eq 2 ] && echo "$(date) - WARN: recent reload found unreadable file" >> "$LOGFILE"
    fi
done

exit "$SIGNAL_EXIT_CODE"
