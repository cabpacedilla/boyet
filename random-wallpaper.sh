#!/usr/bin/env bash

# ============================================================
# ENVIRONMENT SETUP
# ============================================================
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export PATH="$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"

# ============================================================
# CONFIGURATION
# ============================================================
# HISTORY_SIZE is a maintenance threshold, not a hard disk bound: the file
# is appended to and trimmed back once it exceeds 2x this many lines.
# Entries are short fixed-format identifiers (see _da_identity), so memory
# for the in-RAM associative array stays modest at this size.
HISTORY_SIZE=100000
RECENT_HISTORY_SIZE=100
SEARCH_LIMIT=100
SLEEP_INTERVAL=60
DEVIOUSQ_TIMEOUT=30
WGET_TIMEOUT=15
WGET_TOTAL_TIMEOUT=30
IDENTIFY_TIMEOUT=10
# MAX_IMAGE_FILE_SIZE bounds writes to the output file during transfer.
# The download helper pipes curl through `head -c (MAX+1)`, so the
# output file can never exceed MAX+1 bytes. Files larger than MAX are
# rejected. Note: this limits disk writes; it does not guarantee that
# the network transfer stops the exact instant the limit is crossed —
# a small amount of data may already be buffered in the pipe.
MAX_IMAGE_FILE_SIZE=52428800   # 50 MB
MAX_RETRIES=3
LOG_MAX_SIZE=10485760
LOG_RETENTION_DAYS=30

# Maximum bytes kept per line when loading the long-term history file,
# and the maximum length of an identifier accepted for recording.
HISTORY_MAX_LINE_BYTES=512

# Upper bounds on external input.
DEVIOUSQ_MAX_OUTPUT_BYTES=1048576   # 1 MiB captured from deviousq
MAX_URL_LENGTH=2048                 # longest candidate URL accepted
PIXABAY_API_KEY_MAX_LEN=256

DEVIANTART_WEIGHT=55
VARIETY_WEIGHT=15
PIXABAY_WEIGHT=30

MAX_SAME_SOURCE=3

DEVIANTART_IMAGE_MIN_WIDTH=1920
DEVIANTART_IMAGE_MIN_HEIGHT=1080
PIXABAY_IMAGE_MIN_WIDTH=1280
PIXABAY_IMAGE_MIN_HEIGHT=720

# Sanity bounds for decoded DeviantArt token dimensions.
DEVIANTART_TOKEN_MAX_DIM=20000

# Candidates whose URL has no decodable token cannot be upgraded past the
# preview size; in practice they download as small previews (e.g. 344x450,
# 800x800) that fail the HD check. By default they are skipped BEFORE
# download. Set to true to allow them and let the post-download check decide.
DEVIANTART_ALLOW_UNDECODABLE=false

# --- DeviantArt ---
# DeviantArt's content_url field points to a resized preview. The URL
# contains a JWT token that authorizes access up to specific maximum
# dimensions per image. We decode the token, extract those maximums,
# and rewrite the resize parameters so we get full resolution.
#
# FALLBACK POLICY: URL rewriting is best-effort. If the token cannot be
# decoded, or if the URL doesn't match the expected /v1/fill/ or
# /v1/fit/ pattern, the URL passes through unchanged and we download
# the preview. The local HD check may then reject it. To make
# full-resolution retrieval mandatory, treat a failed rewrite as a
# source failure instead of falling back.

# --- Pixabay ---
# Landscape-only sourcing. The API query and jq filter require
# imageWidth >= 1920 AND imageHeight >= 1080, AND the downloaded file is
# re-validated with is_landscape_hd_image().
#
# IMAGEMAGICK DEPENDENCY: the landscape-only policy is enforced only
# when ImageMagick's `identify` command is available. When identify is
# missing, both dimension checks return 0 (permissive). If
# landscape-only is a hard requirement, disable Pixabay when identify
# is unavailable. The startup log records this explicitly.
PIXABAY_API_KEY="${PIXABAY_API_KEY:-}"
PIXABAY_PER_PAGE=50
PIXABAY_API_TIMEOUT=15
PIXABAY_DL_CONNECT_TIMEOUT=10
PIXABAY_DL_TOTAL_TIMEOUT=45
PIXABAY_MAX_API_RESPONSE_SIZE=10485760   # 10 MB

PIXABAY_QUERIES=(
    "category:backgrounds"
    "category:fashion"
    "category:nature"
    "category:science"
    "category:education"
    "category:feelings"
    "category:health"
    "category:people"
    "category:religion"
    "category:places"
    "category:animals"
    "category:industry"
    "category:computer"
    "category:food"
    "category:sports"
    "category:transportation"
    "category:travel"
    "category:buildings"
    "category:business"
    "category:music"
    "term:live wallpaper"
    "term:wallpaper hd"
    "term:abstract background"
    "term:nature landscape"
    "term:ocean waves"
    "term:city night"
    "term:space nebula"
    "term:forest mist"
    "term:sunset clouds"
    "term:mountain peak"
    "term:autumn leaves"
    "term:aurora borealis"
    "term:underwater"
    "term:particle abstract"
    "term:aerial drone"
    "term:slow motion water"
    "term:northern lights"
    "term:desert dunes"
    "term:tropical beach"
    "term:winter snow"
    "term:spring blossom"
    "term:starry night sky"
    "term:macro flower"
)

# ============================================================
# PATHS & SETUP
# ============================================================
HISTORY_FILE="$HOME/scriptlogs/wallpaper_history.txt"
RECENT_HISTORY_FILE="$HOME/scriptlogs/wallpaper_recent.txt"
LOGFILE="$HOME/scriptlogs/wallpaper.log"
LOCK_FILE="$HOME/.cache/random_wallpaper.lock"

# History and log files may hold source identifiers; keep them private.
umask 077

if ! mkdir -p "$HOME/scriptlogs" "$(dirname "$LOCK_FILE")"; then
    echo "ERROR: Failed to create required directories ($HOME/scriptlogs, $(dirname "$LOCK_FILE"))" >&2
    exit 1
fi

# ============================================================
# LOG ROTATION
# ============================================================
rotate_log() {
    if [ -f "$LOGFILE" ]; then
        local size
        size=$(stat -c%s "$LOGFILE" 2>/dev/null || echo 0)
        if [ "${size:-0}" -gt "$LOG_MAX_SIZE" ]; then
            local rotated="$LOGFILE.$(date +%Y%m%d_%H%M%S)"
            if mv -- "$LOGFILE" "$rotated"; then
                if ! echo "$(date) - Log rotated (was ${size} bytes)" > "$LOGFILE"; then
                    echo "$(date) - ERROR: Log rotation succeeded but new log creation failed" >&2
                fi
            else
                echo "$(date) - ERROR: Log rotation failed; retaining current log" >&2
            fi
        fi
    fi
    find "$HOME/scriptlogs" -name 'wallpaper.log.*' -mtime +"$LOG_RETENTION_DAYS" -delete 2>/dev/null || true
}

# ============================================================
# SINGLE-INSTANCE LOCK + SCRIPT-OWNED TEMP DIR + CLEANUP
# ============================================================
TMP_DIR=""
_PROBE_TMPDIR=""
_PROBE_PIDS=()
_VARIETY_PAUSED_BY_SCRIPT=false
_RECENT_TMP=""
_HISTORY_TMP=""

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

_restore_variety_verified() {
    local attempts=6 interval_s=0.5 i
    variety >/dev/null 2>&1 &
    for ((i = 0; i < attempts; i++)); do
        sleep "$interval_s"
        if [ -n "$(variety_pids)" ]; then
            _VARIETY_PAUSED_BY_SCRIPT=false
            return 0
        fi
    done
    return 1
}

cleanup_on_exit() {
    local ec=$?
    cleanup_probes
    if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
        rm -rf -- "$TMP_DIR" 2>/dev/null || true
    fi
    [ -n "$_RECENT_TMP" ] && rm -f "$_RECENT_TMP" 2>/dev/null || true
    [ -n "$_HISTORY_TMP" ] && rm -f "$_HISTORY_TMP" 2>/dev/null || true
    if [ "$_VARIETY_PAUSED_BY_SCRIPT" = true ] \
        && [ -z "$(variety_pids)" ]; then
        if _restore_variety_verified; then
            echo "$(date) - Restored Variety on exit" >> "$LOGFILE"
        else
            echo "$(date) - WARNING: Variety not running after exit restore window (launch may be delayed)" >> "$LOGFILE"
        fi
    fi
    echo "$(date) - SCRIPT EXITING (code=$ec)" >> "$LOGFILE"
    flock -u 9 2>/dev/null || true
    exec 9>&- 2>/dev/null || true
}

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "$(date) - Another instance is already running. Exiting." >> "$LOGFILE"
    exit 0
fi
trap cleanup_on_exit EXIT
trap 'exit 0' INT
trap 'exit 0' TERM

rotate_log

TMP_DIR=$(mktemp -d /tmp/random_wallpaper.XXXXXX) || {
    echo "$(date) - ERROR: Failed to create temp directory" >> "$LOGFILE"
    echo "ERROR: Failed to create temp directory" >&2
    exit 1
}

for _f in "$HISTORY_FILE" "$RECENT_HISTORY_FILE"; do
    if ! { : >> "$_f"; } 2>/dev/null; then
        echo "$(date) - ERROR: Cannot open $_f for append" >> "$LOGFILE"
        echo "ERROR: Cannot open $_f for append" >&2
        exit 1
    fi
done
unset _f

echo "$(date) - Random Wallpaper Script Started" >> "$LOGFILE"
echo "$(date) - Weights: DA=$DEVIANTART_WEIGHT Variety=$VARIETY_WEIGHT Pixabay=$PIXABAY_WEIGHT" >> "$LOGFILE"
echo "$(date) - Recent-history window: $RECENT_HISTORY_SIZE entries" >> "$LOGFILE"
echo "$(date) - Temp directory: $TMP_DIR" >> "$LOGFILE"
echo "$(date) - Image bounds: DA ${DEVIANTART_IMAGE_MIN_WIDTH}x${DEVIANTART_IMAGE_MIN_HEIGHT}, Pixabay ${PIXABAY_IMAGE_MIN_WIDTH}x${PIXABAY_IMAGE_MIN_HEIGHT}, max ${MAX_IMAGE_FILE_SIZE} bytes" >> "$LOGFILE"
echo "$(date) - History persistence is best-effort (not transactional with wallpaper application)" >> "$LOGFILE"

# ============================================================
# HELPERS
# ============================================================
_curl_config_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# Decode the DeviantArt JWT payload and print "<max_w> <max_h>".
# Width and height come from a single jq parse so they always describe
# the same object. Only a leading comparison prefix ("<" or "<=") is
# stripped from each value; characters elsewhere are never deleted, so
# malformed values fail the integer check instead of being "repaired".
_decode_da_token() {
    local url="$1"
    local token payload dims max_w max_h

    token=$(printf '%s' "$url" | grep -oP 'token=\K[^&]+' 2>/dev/null) || return 1
    [ -z "$token" ] && return 1
    # Expect three dot-separated JWT segments.
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
    [ -z "$max_w" ] && return 1
    [ -z "$max_h" ] && return 1

    # Strip only a leading comparison prefix.
    max_w="${max_w#<=}"; max_w="${max_w#<}"
    max_h="${max_h#<=}"; max_h="${max_h#<}"

    [[ "$max_w" =~ ^[0-9]+$ && "$max_h" =~ ^[0-9]+$ ]] || return 1
    [ "$max_w" -ge 1 ] && [ "$max_w" -le "$DEVIANTART_TOKEN_MAX_DIM" ] || return 1
    [ "$max_h" -ge 1 ] && [ "$max_h" -le "$DEVIANTART_TOKEN_MAX_DIM" ] || return 1

    printf '%s %s' "$max_w" "$max_h"
}

# Stable, token-free identity for a DeviantArt image: sha256 of the ORIGINAL
# content_url with its query string (which carries the access token)
# removed. This is what history/recent store and compare, so the
# token-bearing download URL is never persisted.
_da_identity() {
    local base="${1%%\?*}" h
    h=$(printf '%s' "$base" | sha256sum 2>/dev/null | awk '{print $1}')
    [ -n "$h" ] || return 1
    printf 'da://%s' "$h"
}

# Pre-download size screen using the maximum dimensions authorised by the
# URL's token (the same ones _rewrite_da_url upgrades to). Returns 0 if the
# image can reach the configured minimum (either orientation, matching
# is_hd_image), 1 if it cannot. If the token cannot be decoded the
# candidate is skipped unless DEVIANTART_ALLOW_UNDECODABLE=true (the
# post-download HD check applies either way). The first such candidate per
# fetch is logged with its query string (which holds the token) removed.
_DA_LOGGED_UNDECODABLE=false
_da_token_hd_ok() {
    local dims w h
    dims=$(_decode_da_token "$1") || {
        if [ "$_DA_LOGGED_UNDECODABLE" != true ]; then
            _DA_LOGGED_UNDECODABLE=true
            local _u="${1%%\?*}"
            echo "$(date) - [DeviantArt] Sample candidate without decodable token: ${_u:0:160}" >> "$LOGFILE"
        fi
        [ "$DEVIANTART_ALLOW_UNDECODABLE" = true ] && return 0
        return 1
    }
    read -r w h <<< "$dims"
    if { [ "$w" -ge "$DEVIANTART_IMAGE_MIN_WIDTH" ] && [ "$h" -ge "$DEVIANTART_IMAGE_MIN_HEIGHT" ]; } \
       || { [ "$w" -ge "$DEVIANTART_IMAGE_MIN_HEIGHT" ] && [ "$h" -ge "$DEVIANTART_IMAGE_MIN_WIDTH" ]; }; then
        return 0
    fi
    return 1
}

_rewrite_da_url() {
    local url="$1"
    local max_dims max_w max_h

    max_dims=$(_decode_da_token "$url") || {
        printf '%s' "$url"
        return 0
    }
    read -r max_w max_h <<< "$max_dims"

    [ -z "$max_w" ] && { printf '%s' "$url"; return 0; }
    [ -z "$max_h" ] && { printf '%s' "$url"; return 0; }

    printf '%s' "$url" | sed -E \
        "s#/v1/(fill|fit)/w_[0-9]+,h_[0-9]+#/v1/fill/w_${max_w},h_${max_h}#"
}

# Bounded URL download.
#
# The output file receives at most max_bytes + 1 bytes: curl streams
# into `head -c (max_bytes + 1)`, which exits after reading that many
# bytes and closes the pipe. curl receives SIGPIPE on the next write;
# with `set -o pipefail`, the pipeline exits non-zero. Files >max_bytes
# are rejected by the post-download size check.
#
# curl is restricted to HTTPS for the initial request AND for every
# redirect (--proto / --proto-redir), so a redirect cannot downgrade
# the transfer to plain HTTP.
#
# A small amount of data may already be in flight when head exits; the
# file on disk still cannot exceed max_bytes + 1.
_download_bounded() {
    local url="$1"
    local outfile="$2"
    local max_bytes="$3"
    local connect_timeout="$4"
    local total_timeout="$5"
    local read_limit=$(( max_bytes + 1 ))
    local rc=0

    rm -f "$outfile" 2>/dev/null || true

    timeout --kill-after=5s "${total_timeout}s" \
        bash -c '
            set -o pipefail
            curl -sSL --fail \
                --proto "=https" \
                --proto-redir "=https" \
                --connect-timeout "$1" "$2" \
                | head -c "$3" > "$4"
        ' _ "$connect_timeout" "$url" "$read_limit" "$outfile" 2>/dev/null || rc=$?

    if [ "$rc" -ne 0 ]; then
        rm -f "$outfile" 2>/dev/null || true
        return 1
    fi

    local size
    if ! size=$(stat -c%s "$outfile" 2>/dev/null); then
        rm -f "$outfile" 2>/dev/null || true
        return 1
    fi
    if [[ ! "$size" =~ ^[0-9]+$ ]]; then
        rm -f "$outfile" 2>/dev/null || true
        return 1
    fi
    if [ "$size" -gt "$max_bytes" ]; then
        rm -f "$outfile" 2>/dev/null || true
        return 1
    fi

    return 0
}

# Bounded API download with curl config from stdin.
# HTTPS-only, including redirects (the URL itself comes from the config).
_download_api_bounded() {
    local config="$1"
    local outfile="$2"
    local max_bytes="$3"
    local total_timeout="$4"
    local read_limit=$(( max_bytes + 1 ))
    local rc=0

    rm -f "$outfile" 2>/dev/null || true

    printf '%s' "$config" \
        | timeout --kill-after=5s "${total_timeout}s" \
            bash -c '
                set -o pipefail
                curl -sS --fail \
                    --proto "=https" \
                    --proto-redir "=https" \
                    --max-time "$1" -K - \
                    | head -c "$2" > "$3"
            ' _ "$total_timeout" "$read_limit" "$outfile" 2>/dev/null || rc=$?

    if [ "$rc" -ne 0 ]; then
        rm -f "$outfile" 2>/dev/null || true
        return 1
    fi

    local size
    if ! size=$(stat -c%s "$outfile" 2>/dev/null); then
        rm -f "$outfile" 2>/dev/null || true
        return 1
    fi
    if [[ ! "$size" =~ ^[0-9]+$ ]]; then
        rm -f "$outfile" 2>/dev/null || true
        return 1
    fi
    if [ "$size" -gt "$max_bytes" ]; then
        rm -f "$outfile" 2>/dev/null || true
        return 1
    fi

    return 0
}

# ============================================================
# IMAGE VALIDATION HELPERS
# ============================================================
is_valid_image_file() {
    local path="$1"
    local mime
    mime=$(file --mime-type -b "$path" 2>/dev/null) || return 1
    case "$mime" in
        image/jpeg|image/png|image/webp|image/gif|image/avif)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

_parse_image_dims() {
    local path="$1"
    local dims w h

    HD_LAST_DIMS=""
    HD_LAST_WIDTH=""
    HD_LAST_HEIGHT=""

    if ! command -v identify >/dev/null 2>&1; then
        return 1
    fi

    dims=$(timeout --kill-after=2s "${IDENTIFY_TIMEOUT}s" \
        identify -limit memory 256MiB -limit map 512MiB -limit disk 1GiB \
                 -limit width 30000 -limit height 30000 \
                 -format '%w %h' "${path}[0]" 2>/dev/null) || return 2
    [ -z "$dims" ] && return 2

    read -r w h <<< "$dims"
    [ -z "$w" ] && return 2
    [ -z "$h" ] && return 2

    [[ "$w" =~ ^[0-9]+$ && "$h" =~ ^[0-9]+$ ]] || return 2

    HD_LAST_DIMS="${w}x${h}"
    HD_LAST_WIDTH="$w"
    HD_LAST_HEIGHT="$h"
    return 0
}
HD_LAST_WIDTH=""
HD_LAST_HEIGHT=""

is_hd_image() {
    local path="$1" min_w="$2" min_h="$3"
    local rc=0

    _parse_image_dims "$path" || rc=$?
    [ "$rc" -eq 1 ] && return 0
    [ "$rc" -eq 2 ] && return 2

    local w="$HD_LAST_WIDTH" h="$HD_LAST_HEIGHT"
    if { [ "$w" -ge "$min_w" ] && [ "$h" -ge "$min_h" ]; } \
       || { [ "$w" -ge "$min_h" ] && [ "$h" -ge "$min_w" ]; }; then
        return 0
    fi
    return 1
}

is_landscape_hd_image() {
    local path="$1" min_w="$2" min_h="$3"
    local rc=0

    _parse_image_dims "$path" || rc=$?
    [ "$rc" -eq 1 ] && return 0
    [ "$rc" -eq 2 ] && return 2

    if [ "$HD_LAST_WIDTH" -ge "$min_w" ] && [ "$HD_LAST_HEIGHT" -ge "$min_h" ]; then
        return 0
    fi
    return 1
}

# ============================================================
# DEPENDENCY CHECK
# ============================================================
for cmd in flock timeout curl file stat awk grep head tail shuf \
           mktemp df pgrep find date wc cat sed seq setsid \
           sha256sum base64 cut; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "$(date) - ERROR: required command not found: $cmd" >> "$LOGFILE"
        echo "ERROR: required command not found: $cmd" >&2
        exit 1
    fi
done

if ! command -v plasma-apply-wallpaperimage >/dev/null 2>&1; then
    echo "$(date) - ERROR: plasma-apply-wallpaperimage not found" >> "$LOGFILE"
    echo "ERROR: plasma-apply-wallpaperimage not found" >&2
    exit 1
fi

if [ "$DEVIANTART_WEIGHT" -gt 0 ] && ! command -v deviousq >/dev/null 2>&1; then
    echo "$(date) - WARNING: deviousq not found — disabling DeviantArt" >> "$LOGFILE"
    DEVIANTART_WEIGHT=0
fi

if [ "$DEVIANTART_WEIGHT" -gt 0 ] && ! command -v jq >/dev/null 2>&1; then
    echo "$(date) - WARNING: jq not found — disabling DeviantArt" >> "$LOGFILE"
    DEVIANTART_WEIGHT=0
fi

if [ "$VARIETY_WEIGHT" -gt 0 ] && ! command -v variety >/dev/null 2>&1; then
    echo "$(date) - WARNING: variety not found — disabling Variety" >> "$LOGFILE"
    VARIETY_WEIGHT=0
fi

if [ "$PIXABAY_WEIGHT" -gt 0 ]; then
    if [ -z "$PIXABAY_API_KEY" ]; then
        echo "$(date) - WARNING: PIXABAY_API_KEY not set — disabling Pixabay" >> "$LOGFILE"
        PIXABAY_WEIGHT=0
    elif [[ "$PIXABAY_API_KEY" =~ [[:cntrl:]] ]]; then
        echo "$(date) - ERROR: PIXABAY_API_KEY contains control characters — disabling Pixabay" >> "$LOGFILE"
        PIXABAY_WEIGHT=0
    elif [ "${#PIXABAY_API_KEY}" -gt "$PIXABAY_API_KEY_MAX_LEN" ]; then
        echo "$(date) - ERROR: PIXABAY_API_KEY exceeds ${PIXABAY_API_KEY_MAX_LEN} chars — disabling Pixabay" >> "$LOGFILE"
        PIXABAY_WEIGHT=0
    elif ! command -v jq >/dev/null 2>&1; then
        echo "$(date) - WARNING: jq not found — disabling Pixabay" >> "$LOGFILE"
        PIXABAY_WEIGHT=0
    fi
fi

if [ "$DEVIANTART_WEIGHT" -eq 0 ] && [ "$PIXABAY_WEIGHT" -eq 0 ] \
   && [ "$VARIETY_WEIGHT" -eq 0 ]; then
    echo "$(date) - ERROR: no enabled sources" >> "$LOGFILE"
    echo "ERROR: no enabled sources" >&2
    exit 1
fi

if ! command -v identify >/dev/null 2>&1; then
    if [ "$DEVIANTART_WEIGHT" -gt 0 ] || [ "$PIXABAY_WEIGHT" -gt 0 ]; then
        echo "$(date) - WARNING: identify (ImageMagick) not found — HD dimension checks are BEST-EFFORT, not enforced." >> "$LOGFILE"
    fi
    if [ "$PIXABAY_WEIGHT" -gt 0 ]; then
        echo "$(date) - WARNING: Pixabay landscape-only policy is BEST-EFFORT without ImageMagick" >> "$LOGFILE"
    fi
fi

# ============================================================
# INTERNET CHECK
# ============================================================
INTERNET_CACHE_TTL=30
INTERNET_CHECK_TIMEOUT=4

_internet_last_check=0
_internet_last_result=1

check_internet() {
    local now
    now=$(date +%s)

    if [ "$_internet_last_result" -eq 0 ]; then
        local age=$((now - _internet_last_check))
        if [ "$age" -lt "$INTERNET_CACHE_TTL" ]; then
            return 0
        fi
    fi

    local -a endpoints=(
        "https://one.one.one.one/"
        "https://www.google.com/generate_204"
        "https://www.cloudflare.com/cdn-cgi/trace"
    )
    # Optional host:port:address override per endpoint (empty = none).
    local -a probe_resolve=(
        "one.one.one.one:443:1.1.1.1"
        ""
        ""
    )

    local tmpdir
    tmpdir=$(mktemp -d "$TMP_DIR/probes.XXXXXX") || {
        _internet_last_check=$now
        _internet_last_result=1
        return 1
    }
    _PROBE_TMPDIR="$tmpdir"
    _PROBE_PIDS=()

    # Values are passed as positional arguments to bash -c, not
    # interpolated into the script text. The optional --resolve option
    # is built as an array inside the child, so nothing relies on
    # unquoted word splitting or pathname expansion.
    local i=0 idx
    for idx in "${!endpoints[@]}"; do
        local ep="${endpoints[$idx]}"
        local resolve="${probe_resolve[$idx]}"
        setsid bash -c '
            extra=()
            [ -n "$2" ] && extra=(--resolve "$2")
            if curl -fsS -o /dev/null \
                --connect-timeout 2 \
                --max-time "$1" \
                --no-keepalive \
                --proto "=https" \
                --proto-redir "=https" \
                ${extra[@]+"${extra[@]}"} \
                -H "User-Agent: Mozilla/5.0" \
                "$3" >/dev/null 2>&1; then
                echo ok > "$4/result_$5"
            fi
        ' _ "$INTERNET_CHECK_TIMEOUT" "$resolve" "$ep" "$tmpdir" "$i" &
        _PROBE_PIDS+=($!)
        i=$((i + 1))
    done

    local success=1
    local deadline=$(( $(date +%s) + INTERNET_CHECK_TIMEOUT + 1 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        for f in "$tmpdir"/result_*; do
            if [ -f "$f" ] && [ "$(cat "$f" 2>/dev/null)" = "ok" ]; then
                success=0
                break 2
            fi
        done
        sleep 0.25
    done

    cleanup_probes

    _internet_last_check=$now
    _internet_last_result=$success
    return $success
}

# ============================================================
# VARIETY MANAGEMENT
# ============================================================
# Variety is a Python program, so its process comm is usually python3 (or
# "variety" for a wrapper), not necessarily "variety". pgrep -f narrows by
# command line; we then require a plausible comm and exclude this shell,
# so an unrelated process that merely mentions /usr/bin/variety in its
# arguments (an editor, a pager) is never signalled.
variety_pids() {
    local pid comm
    while IFS= read -r pid; do
        [ -z "$pid" ] && continue
        [ "$pid" = "$$" ] && continue
        comm=$(cat "/proc/$pid/comm" 2>/dev/null) || continue
        case "$comm" in
            variety|python|python3|python3.*) printf '%s\n' "$pid" ;;
        esac
    done < <(pgrep -f '(^|/)variety( |$)' 2>/dev/null)
}

stop_variety() {
    local pids pid killed_any=false
    pids=$(variety_pids)
    if [ -z "$pids" ]; then
        _VARIETY_PAUSED_BY_SCRIPT=false
        return 1
    fi

    _VARIETY_PAUSED_BY_SCRIPT=true

    while IFS= read -r pid; do
        if [ -n "$pid" ] && kill -TERM "$pid" 2>/dev/null; then
            killed_any=true
        fi
    done <<< "$pids"
    sleep 1
    pids=$(variety_pids)
    if [ -n "$pids" ]; then
        while IFS= read -r pid; do
            if [ -n "$pid" ] && kill -KILL "$pid" 2>/dev/null; then
                killed_any=true
            fi
        done <<< "$pids"
        sleep 0.5
    fi

    if [ -z "$(variety_pids)" ]; then
        echo "$(date) - Stopped Variety process(es)" >> "$LOGFILE"
        return 0
    fi

    if [ "$killed_any" = true ]; then
        echo "$(date) - Failed to stop Variety cleanly (partial termination; flag retained for exit recovery)" >> "$LOGFILE"
    else
        _VARIETY_PAUSED_BY_SCRIPT=false
        echo "$(date) - Failed to stop Variety (no signals delivered)" >> "$LOGFILE"
    fi
    return 1
}

start_variety() {
    if [ -n "$(variety_pids)" ]; then
        _VARIETY_PAUSED_BY_SCRIPT=false
        return 1
    fi
    if _restore_variety_verified; then
        echo "$(date) - Started Variety process" >> "$LOGFILE"
        return 0
    fi
    echo "$(date) - Variety launch failed" >> "$LOGFILE"
    return 1
}

_ensure_variety_running() {
    local tag="$1"
    start_variety >/dev/null 2>&1 || true
    if [ -n "$(variety_pids)" ]; then
        echo "$(date) - [$tag] Variety is running after fetch" >> "$LOGFILE"
        return 0
    fi
    echo "$(date) - [$tag] WARNING: Variety is not running after fetch" >> "$LOGFILE"
    return 1
}

use_variety() {
    if ! command -v variety >/dev/null 2>&1; then
        echo "$(date) - Variety not installed" >> "$LOGFILE"
        return 1
    fi

    if [ -z "$(variety_pids)" ]; then
        if ! start_variety; then
            echo "$(date) - Variety startup failed; skipping rotation" >> "$LOGFILE"
            return 1
        fi
    fi

    if variety --next >/dev/null 2>&1; then
        echo "$(date) - Variety rotated (its own random pick)" >> "$LOGFILE"
        return 0
    fi

    echo "$(date) - Variety rotation failed" >> "$LOGFILE"
    return 1
}

# Pause Variety before a DeviantArt/Pixabay fetch so it cannot overwrite
# the wallpaper mid-fetch.
#
# POLICY: when Variety is disabled as a source (VARIETY_WEIGHT <= 0), the
# script leaves any independently running Variety instance untouched, so
# it never stops it and _VARIETY_PAUSED_BY_SCRIPT stays false. Restoration
# (cleanup_on_exit and the fetchers) depends only on whether THIS script
# stopped Variety (_VARIETY_PAUSED_BY_SCRIPT / variety_was_running), never
# on the current weight. Trade-off: a running Variety may change the
# wallpaper on its own timer. To pause it anyway, remove the early return
# below.
_prepare_variety_pause() {
    VARIETY_WAS_RUNNING=false

    if [ "${VARIETY_WEIGHT:-0}" -le 0 ]; then
        return 0
    fi

    if [ -z "$(variety_pids)" ]; then
        return 0
    fi

    if stop_variety; then
        VARIETY_WAS_RUNNING=true
        return 0
    fi

    return 1
}

# ============================================================
# DEVIANTART CATEGORIES
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

# ============================================================
# CATEGORY / QUERY / SOURCE CYCLING
# ============================================================
shuffle_categories() {
    mapfile -t SHUFFLED_CATEGORIES < <(printf '%s\n' "${CATEGORIES[@]}" | shuf)
    CAT_INDEX=0
}
shuffle_categories

advance_category() {
    CAT_INDEX=$((CAT_INDEX + 1))
    if [ "$CAT_INDEX" -ge "${#SHUFFLED_CATEGORIES[@]}" ]; then
        echo "$(date) - [DeviantArt] Finished category cycle. Reshuffling..." >> "$LOGFILE"
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
        echo "$(date) - [Pixabay] Finished query cycle. Reshuffling..." >> "$LOGFILE"
        shuffle_pixabay_queries
    fi
}

declare -a SHUFFLED_SOURCES=()
SOURCE_INDEX=0

_gcd() {
    local a="$1" b="$2" t
    while [ "$b" -ne 0 ]; do
        t=$((a % b))
        a=$b
        b=$t
    done
    printf '%s' "$a"
}

build_source_deck() {
    local -a names=()
    local -a weights=()

    [ "$DEVIANTART_WEIGHT" -gt 0 ] && { names+=("deviantart"); weights+=("$DEVIANTART_WEIGHT"); }
    [ "$VARIETY_WEIGHT"    -gt 0 ] && { names+=("variety");    weights+=("$VARIETY_WEIGHT"); }
    [ "$PIXABAY_WEIGHT"    -gt 0 ] && { names+=("pixabay");    weights+=("$PIXABAY_WEIGHT"); }

    if [ "${#names[@]}" -eq 0 ]; then
        SHUFFLED_SOURCES=()
        SOURCE_INDEX=0
        return 1
    fi

    local g="${weights[0]}"
    local w
    for w in "${weights[@]:1}"; do
        g=$(_gcd "$g" "$w")
    done
    [ "$g" -lt 1 ] && g=1

    local -a deck=()
    local i count
    for i in "${!names[@]}"; do
        count=$(( ${weights[$i]} / g ))
        [ "$count" -lt 1 ] && count=1
        for _ in $(seq 1 "$count"); do
            deck+=("${names[$i]}")
        done
    done

    mapfile -t SHUFFLED_SOURCES < <(printf '%s\n' "${deck[@]}" | shuf)
    SOURCE_INDEX=0
    echo "$(date) - [Sources] Reshuffled deck of ${#SHUFFLED_SOURCES[@]} slots (weights DA=$DEVIANTART_WEIGHT Var=$VARIETY_WEIGHT Pix=$PIXABAY_WEIGHT)" >> "$LOGFILE"
}

advance_source_deck() {
    SOURCE_INDEX=$((SOURCE_INDEX + 1))
    if [ "$SOURCE_INDEX" -ge "${#SHUFFLED_SOURCES[@]}" ]; then
        echo "$(date) - [Sources] Finished deck cycle. Reshuffling..." >> "$LOGFILE"
        build_source_deck
    fi
}

# ============================================================
# HISTORY MANAGEMENT
# ============================================================
declare -A HISTORY_CACHE

declare -a RECENT_ORDERED=()
declare -A RECENT_BY_ID
declare -A RECENT_BY_HASH
_RECENT_DIRTY=false
_RECENT_RETRY_FAILS=0

_rebuild_maps_from_ordered() {
    RECENT_BY_ID=()
    RECENT_BY_HASH=()

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
    local entry="$1"
    [ -z "$entry" ] && return 1
    RECENT_ORDERED+=("$entry")
    local n=${#RECENT_ORDERED[@]}
    if [ "$n" -gt "$RECENT_HISTORY_SIZE" ]; then
        RECENT_ORDERED=("${RECENT_ORDERED[@]:$((n - RECENT_HISTORY_SIZE))}")
    fi
    _rebuild_maps_from_ordered
}

_persist_recent_window() {
    _RECENT_TMP=$(mktemp "$RECENT_HISTORY_FILE.XXXXXX") || {
        _RECENT_TMP=""
        return 1
    }
    if ! printf '%s\n' "${RECENT_ORDERED[@]}" > "$_RECENT_TMP"; then
        rm -f "$_RECENT_TMP" 2>/dev/null || true
        _RECENT_TMP=""
        return 1
    fi
    if ! mv -f "$_RECENT_TMP" "$RECENT_HISTORY_FILE"; then
        rm -f "$_RECENT_TMP" 2>/dev/null || true
        _RECENT_TMP=""
        return 1
    fi
    _RECENT_TMP=""
    _RECENT_DIRTY=false
    _RECENT_RETRY_FAILS=0
    return 0
}

# Load long-term history. Only the last HISTORY_SIZE lines are loaded
# into memory, and each line is truncated to HISTORY_MAX_LINE_BYTES, so
# startup memory is bounded in both line count and per-line size
# regardless of how large or corrupted the on-disk file has become.
# On read failure, the existing cache is preserved.
load_history() {
    if [ ! -e "$HISTORY_FILE" ]; then
        HISTORY_CACHE=()
        echo "$(date) - No long-term history file yet" >> "$LOGFILE"
        return 0
    fi

    if [ ! -r "$HISTORY_FILE" ]; then
        echo "$(date) - ERROR: Long-term history file not readable; keeping existing cache" >> "$LOGFILE"
        return 1
    fi

    local existing
    if ! existing=$(set -o pipefail
                    tail -n "$HISTORY_SIZE" "$HISTORY_FILE" 2>/dev/null \
                    | cut -b1-"$HISTORY_MAX_LINE_BYTES" 2>/dev/null); then
        echo "$(date) - ERROR: Failed to read long-term history; keeping existing cache" >> "$LOGFILE"
        return 1
    fi

    local -a lines=()
    if [ -n "$existing" ]; then
        mapfile -t lines <<< "$existing"
    fi

    HISTORY_CACHE=()
    local count=0 url
    for url in "${lines[@]}"; do
        [ -z "$url" ] && continue
        HISTORY_CACHE["$url"]=1
        ((count++))
    done
    echo "$(date) - Loaded $count history entries into cache" >> "$LOGFILE"
    return 0
}
load_history

load_recent_history() {
    if [ "$_RECENT_DIRTY" = true ]; then
        if _persist_recent_window; then
            echo "$(date) - Persisted pending recent-history window before reload" >> "$LOGFILE"
        else
            echo "$(date) - WARNING: Recent window is dirty and could not be persisted; keeping in-memory window and skipping reload" >> "$LOGFILE"
            return 1
        fi
    fi

    if [ ! -e "$RECENT_HISTORY_FILE" ]; then
        RECENT_ORDERED=()
        _rebuild_maps_from_ordered
        echo "$(date) - No recent-history file yet" >> "$LOGFILE"
        return 0
    fi

    if [ ! -r "$RECENT_HISTORY_FILE" ]; then
        echo "$(date) - ERROR: Recent-history file not readable; keeping existing window" >> "$LOGFILE"
        return 1
    fi

    local existing
    if ! existing=$(set -o pipefail
                    tail -n "$RECENT_HISTORY_SIZE" "$RECENT_HISTORY_FILE" 2>/dev/null \
                    | cut -b1-"$MAX_URL_LENGTH" 2>/dev/null); then
        echo "$(date) - ERROR: Failed to read recent history; keeping existing window" >> "$LOGFILE"
        return 1
    fi

    local -a new_ordered=()
    if [ -n "$existing" ]; then
        mapfile -t new_ordered <<< "$existing"
    fi
    # Drop malformed entries: a source key is required, and the hash
    # field, if present, must be a full SHA-256 hex digest. This also
    # discards lines whose hash was cut off by the length limit.
    local -a valid_ordered=()
    local _l _s _h
    for _l in "${new_ordered[@]}"; do
        [ -z "$_l" ] && continue
        # Split on the first tab explicitly (read would strip a leading tab).
        _s="${_l%%$'\t'*}"
        if [[ "$_l" == *$'\t'* ]]; then _h="${_l#*$'\t'}"; else _h=""; fi
        [ -z "$_s" ] && continue
        if [ -n "$_h" ] && ! [[ "$_h" =~ ^[0-9a-f]{64}$ ]]; then
            continue
        fi
        valid_ordered+=("$_l")
    done
    new_ordered=("${valid_ordered[@]}")

    local n=${#new_ordered[@]}
    if [ "$n" -gt "$RECENT_HISTORY_SIZE" ]; then
        new_ordered=("${new_ordered[@]:$((n - RECENT_HISTORY_SIZE))}")
    fi

    RECENT_ORDERED=("${new_ordered[@]}")
    _rebuild_maps_from_ordered
    echo "$(date) - Loaded ${#RECENT_ORDERED[@]} recent-history entries" >> "$LOGFILE"
    return 0
}
load_recent_history

add_to_history() {
    local url="$1"
    if [ -z "$url" ]; then
        return 1
    fi
    if [ "${#url}" -gt "$HISTORY_MAX_LINE_BYTES" ] || [[ "$url" == *$'\n'* ]]; then
        echo "$(date) - ERROR: Refusing to record oversized or multi-line history entry (${#url} chars)" >> "$LOGFILE"
        return 1
    fi

    if ! printf '%s\n' "$url" >> "$HISTORY_FILE"; then
        echo "$(date) - ERROR: Failed to append long-term history: $url" >> "$LOGFILE"
        return 1
    fi

    HISTORY_CACHE["$url"]=1

    local line_count
    line_count=$(wc -l < "$HISTORY_FILE" 2>/dev/null || echo 0)
    if [ "$line_count" -gt "$((HISTORY_SIZE * 2))" ]; then
        _HISTORY_TMP=$(mktemp "$HISTORY_FILE.XXXXXX") || {
            _HISTORY_TMP=""
            echo "$(date) - ERROR: Failed to create history trim temp; skipping trim" >> "$LOGFILE"
            return 0
        }
        if tail -n "$HISTORY_SIZE" "$HISTORY_FILE" > "$_HISTORY_TMP" \
            && mv -f "$_HISTORY_TMP" "$HISTORY_FILE"; then
            _HISTORY_TMP=""
            echo "$(date) - Trimmed history to $HISTORY_SIZE entries" >> "$LOGFILE"
            load_history
        else
            rm -f "$_HISTORY_TMP" 2>/dev/null || true
            _HISTORY_TMP=""
            echo "$(date) - ERROR: Failed to trim long-term history; leaving file as-is" >> "$LOGFILE"
        fi
    fi

    return 0
}

add_to_recent() {
    local source_key="$1"
    local content_hash="${2:-}"
    [ -z "$source_key" ] && return 1

    _append_to_recent_window "$(printf '%s\t%s' "$source_key" "$content_hash")"
    _RECENT_DIRTY=true

    if _persist_recent_window; then
        return 0
    fi

    echo "$(date) - ERROR: Failed to persist recent history; window retained in memory (will retry)" >> "$LOGFILE"
    return 1
}

is_in_history() {
    local url="$1"
    if [ -z "$url" ]; then
        return 2
    fi
    if [[ -v HISTORY_CACHE["$url"] ]]; then
        return 0
    else
        return 1
    fi
}

recent_has_id() {
    local key="$1"
    [ -z "$key" ] && return 2
    [[ -v RECENT_BY_ID["$key"] ]] && return 0
    return 1
}

recent_has_hash() {
    local h="$1"
    [ -z "$h" ] && return 2
    [[ -v RECENT_BY_HASH["$h"] ]] && return 0
    return 1
}

# ============================================================
# DEVIANTART FETCHER
# ============================================================
fetch_deviantart() {
    [ "$DEVIANTART_WEIGHT" -le 0 ] && return 1

    if ! _prepare_variety_pause; then
        echo "$(date) - [DeviantArt] Aborting: Variety still running" >> "$LOGFILE"
        if [ "$_VARIETY_PAUSED_BY_SCRIPT" = true ]; then
            _ensure_variety_running "DeviantArt"
        fi
        return 1
    fi
    local variety_was_running="$VARIETY_WAS_RUNNING"
    [ "$variety_was_running" = true ] && echo "$(date) - [DeviantArt] Paused Variety for DeviantArt" >> "$LOGFILE"

    local current_category="${SHUFFLED_CATEGORIES[$CAT_INDEX]}"
    echo "$(date) - [DeviantArt] Searching: '$current_category'" >> "$LOGFILE"

    local URL_LIST=""
    local RETRY_COUNT=0

    while [ -z "$URL_LIST" ] && [ "$RETRY_COUNT" -lt "$MAX_RETRIES" ]; do
        if [ "$RETRY_COUNT" -gt 0 ]; then
            echo "$(date) - [DeviantArt] Retry $RETRY_COUNT/$MAX_RETRIES" >> "$LOGFILE"
            sleep 5
        fi

        # NOTE: deviousq's --min-width/--min-height are deliberately NOT used:
        # in practice they return zero results. Size is enforced instead by
        # _da_token_hd_ok (token limits, before download) and by the
        # post-download HD check.
        URL_LIST=$(timeout --kill-after=5s "${DEVIOUSQ_TIMEOUT}s" deviousq \
            --medium image \
            --rating nonadult \
            --return-field content_url \
            --limit "$SEARCH_LIMIT" \
            "$current_category" \
            2>/dev/null \
            | head -c "$DEVIOUSQ_MAX_OUTPUT_BYTES"
            exit "${PIPESTATUS[0]}")

        local exit_code=$?
        if [ $exit_code -eq 141 ]; then
            # head closed the pipe at the byte limit (SIGPIPE): keep the
            # output so far; a possibly partial last line is dropped below.
            echo "$(date) - [DeviantArt] deviousq output reached ${DEVIOUSQ_MAX_OUTPUT_BYTES}-byte cap" >> "$LOGFILE"
        elif [ $exit_code -eq 124 ] || [ $exit_code -eq 137 ]; then
            echo "$(date) - [DeviantArt] ERROR: deviousq timed out (exit=$exit_code)" >> "$LOGFILE"
            URL_LIST=""
        elif [ $exit_code -ne 0 ]; then
            echo "$(date) - [DeviantArt] ERROR: deviousq exited non-zero (exit=$exit_code)" >> "$LOGFILE"
            URL_LIST=""
        fi

        RETRY_COUNT=$((RETRY_COUNT + 1))
    done

    if [ -z "$URL_LIST" ]; then
        echo "$(date) - [DeviantArt] No results after $MAX_RETRIES attempts — advancing category" >> "$LOGFILE"
        advance_category
        [ "$variety_was_running" = true ] && _ensure_variety_running "DeviantArt"
        return 1
    fi

    # If the cap was hit, the final line may be cut mid-URL: discard it.
    if [ "${#URL_LIST}" -ge "$((DEVIOUSQ_MAX_OUTPUT_BYTES - 1))" ]; then
        URL_LIST=$(printf '%s\n' "$URL_LIST" | sed '$d')
    fi

    local VALID_URLS
    VALID_URLS=$(printf '%s\n' "$URL_LIST" | grep -E '^https://' \
        | awk -v m="$MAX_URL_LENGTH" 'length($0) <= m' | head -100)

    if [ -z "$VALID_URLS" ]; then
        echo "$(date) - [DeviantArt] No valid HTTPS URLs found — advancing category" >> "$LOGFILE"
        advance_category
        [ "$variety_was_running" = true ] && _ensure_variety_running "DeviantArt"
        return 1
    fi

    local URL_COUNT
    URL_COUNT=$(printf '%s\n' "$VALID_URLS" | wc -l)
    echo "$(date) - [DeviantArt] Found $URL_COUNT URLs" >> "$LOGFILE"

    # RANDOM_URL is the (token-bearing) URL used only for downloading.
    # SOURCE_ID is the stable, token-free identity used for history and
    # recent-window deduplication, computed from the ORIGINAL url before
    # any rewriting.
    local RANDOM_URL="" SOURCE_ID="" cand_id small_skipped=0
    _DA_LOGGED_UNDECODABLE=false
    local SHUFFLED_URLS
    mapfile -t SHUFFLED_URLS < <(printf '%s\n' "$VALID_URLS" | shuf)

    for url in "${SHUFFLED_URLS[@]}"; do
        cand_id=$(_da_identity "$url") || continue
        if ! is_in_history "$cand_id" && ! recent_has_id "$cand_id"; then
            if ! _da_token_hd_ok "$url"; then
                small_skipped=$((small_skipped + 1))
                continue
            fi
            RANDOM_URL="$url"
            SOURCE_ID="$cand_id"
            echo "$(date) - [DeviantArt] Found unseen image" >> "$LOGFILE"
            break
        fi
    done

    if [ -z "$RANDOM_URL" ]; then
        for url in "${SHUFFLED_URLS[@]}"; do
            cand_id=$(_da_identity "$url") || continue
            if ! recent_has_id "$cand_id"; then
                if ! _da_token_hd_ok "$url"; then
                    small_skipped=$((small_skipped + 1))
                    continue
                fi
                RANDOM_URL="$url"
                SOURCE_ID="$cand_id"
                echo "$(date) - [DeviantArt] Long-term repeat (outside recent window)" >> "$LOGFILE"
                break
            fi
        done
    fi

    if [ -z "$RANDOM_URL" ]; then
        echo "$(date) - [DeviantArt] No eligible candidates (seen recently or below HD; ${small_skipped} skipped as below HD or without a usable token) — advancing category" >> "$LOGFILE"
        advance_category
        [ "$variety_was_running" = true ] && _ensure_variety_running "DeviantArt"
        return 1
    fi

    local REWRITTEN_URL
    REWRITTEN_URL=$(_rewrite_da_url "$RANDOM_URL")
    if [ "$REWRITTEN_URL" != "$RANDOM_URL" ]; then
        echo "$(date) - [DeviantArt] Rewrote URL to token max resolution" >> "$LOGFILE"
    fi
    RANDOM_URL="$REWRITTEN_URL"

    local WALLPAPER_FILE="$TMP_DIR/wallpaper_$$.jpg"

    echo "$(date) - [DeviantArt] Downloading..." >> "$LOGFILE"

    local AVAILABLE
    AVAILABLE=$(df -k "$TMP_DIR" 2>/dev/null | awk 'NR==2 {print $4}')
    if [ -n "$AVAILABLE" ] && [ "$AVAILABLE" -lt 10240 ]; then
        echo "$(date) - WARNING: Low disk space in $TMP_DIR (${AVAILABLE} KB free)" >> "$LOGFILE"
    fi

    local success=false

    if _download_bounded "$RANDOM_URL" "$WALLPAPER_FILE" \
        "$MAX_IMAGE_FILE_SIZE" "$WGET_TIMEOUT" "$WGET_TOTAL_TIMEOUT"; then

        local file_type=""
        local file_size=0
        local validation_ok=false
        local file_hash=""

        file_type=$(file -b "$WALLPAPER_FILE" 2>/dev/null)
        file_size=$(stat -c%s "$WALLPAPER_FILE" 2>/dev/null || echo 0)
        file_size=${file_size:-0}

        if is_valid_image_file "$WALLPAPER_FILE"; then
            if [ "$file_size" -gt 1024 ]; then
                validation_ok=true
            else
                echo "$(date) - [DeviantArt] ERROR: File too small (${file_size} bytes)" >> "$LOGFILE"
            fi
        else
            echo "$(date) - [DeviantArt] ERROR: Not a supported raster image (detected: ${file_type:-unknown})" >> "$LOGFILE"
        fi

        if [ "$validation_ok" = true ]; then
            local hd_rc=0
            is_hd_image "$WALLPAPER_FILE" \
                "$DEVIANTART_IMAGE_MIN_WIDTH" "$DEVIANTART_IMAGE_MIN_HEIGHT" || hd_rc=$?
            if [ "$hd_rc" -eq 1 ]; then
                echo "$(date) - [DeviantArt] ERROR: Image below HD (${HD_LAST_DIMS:-unknown}) — advancing category" >> "$LOGFILE"
                validation_ok=false
            elif [ "$hd_rc" -eq 2 ]; then
                echo "$(date) - [DeviantArt] ERROR: Image decoder check failed or returned malformed dimensions — advancing category" >> "$LOGFILE"
                validation_ok=false
            fi
        fi

        if [ "$validation_ok" = true ]; then
            file_hash=$(sha256sum "$WALLPAPER_FILE" 2>/dev/null | awk '{print $1}')
            if [ -z "$file_hash" ]; then
                echo "$(date) - [DeviantArt] WARNING: sha256sum returned empty; cross-source dedup unavailable for this image" >> "$LOGFILE"
            elif recent_has_hash "$file_hash"; then
                echo "$(date) - [DeviantArt] Cross-source duplicate (hash in recent window) — advancing category" >> "$LOGFILE"
                validation_ok=false
            fi
        fi

        if [ "$validation_ok" = true ]; then
            if plasma-apply-wallpaperimage "$WALLPAPER_FILE" >/dev/null 2>&1; then
                if ! add_to_history "$SOURCE_ID"; then
                    echo "$(date) - WARNING: [DeviantArt] Wallpaper applied, but long-term history append failed" >> "$LOGFILE"
                fi
                if ! add_to_recent "$SOURCE_ID" "$file_hash"; then
                    echo "$(date) - WARNING: [DeviantArt] Wallpaper applied, but recent-history is UNPERSISTED (kept in memory, will retry on next successful write or periodic reload)" >> "$LOGFILE"
                fi
                echo "$(date) - [DeviantArt] Wallpaper set from '$current_category' (${file_type}, ${file_size} bytes)" >> "$LOGFILE"
                success=true
                advance_category
            else
                echo "$(date) - [DeviantArt] ERROR: KDE rejected image — advancing category" >> "$LOGFILE"
                advance_category
            fi
        else
            advance_category
        fi

        rm -f "$WALLPAPER_FILE"
    else
        echo "$(date) - [DeviantArt] ERROR: Download failed (timeout/size/transfer) — advancing category" >> "$LOGFILE"
        rm -f "$WALLPAPER_FILE"
        advance_category
    fi

    if [ "$variety_was_running" = true ]; then
        _ensure_variety_running "DeviantArt"
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
        echo "$(date) - [Pixabay] Aborting: Variety still running" >> "$LOGFILE"
        if [ "$_VARIETY_PAUSED_BY_SCRIPT" = true ]; then
            _ensure_variety_running "Pixabay"
        fi
        return 1
    fi
    local variety_was_running="$VARIETY_WAS_RUNNING"
    [ "$variety_was_running" = true ] && echo "$(date) - [Pixabay] Paused Variety for Pixabay" >> "$LOGFILE"

    local query="${SHUFFLED_PIXABAY_QUERIES[$PIXABAY_QUERY_INDEX]}"
    echo "$(date) - [Pixabay] Query: '$query' (slot $((PIXABAY_QUERY_INDEX + 1))/${#SHUFFLED_PIXABAY_QUERIES[@]})" >> "$LOGFILE"

    local api_url
    case "$query" in
        category:*)
            local cat="${query#category:}"
            api_url="https://pixabay.com/api/?key=${PIXABAY_API_KEY}&category=${cat}&image_type=photo&min_width=${PIXABAY_IMAGE_MIN_WIDTH}&per_page=${PIXABAY_PER_PAGE}&safesearch=true"
            ;;
        term:*)
            local t="${query#term:}"
            local enc
            enc=$(printf '%s' "$t" | jq -sRr @uri)
            api_url="https://pixabay.com/api/?key=${PIXABAY_API_KEY}&q=${enc}&image_type=photo&min_width=${PIXABAY_IMAGE_MIN_WIDTH}&per_page=${PIXABAY_PER_PAGE}&safesearch=true"
            ;;
        *)
            echo "$(date) - [Pixabay] Malformed query: '$query' — advancing" >> "$LOGFILE"
            advance_pixabay_query
            [ "$variety_was_running" = true ] && _ensure_variety_running "Pixabay"
            return 1
            ;;
    esac

    local api_response_file="$TMP_DIR/pixabay_api_$$.json"
    local escaped_url
    escaped_url=$(_curl_config_escape "$api_url")
    local api_config
    api_config=$(printf 'url = "%s"\n' "$escaped_url")

    if ! _download_api_bounded "$api_config" "$api_response_file" \
        "$PIXABAY_MAX_API_RESPONSE_SIZE" "$PIXABAY_API_TIMEOUT"; then
        echo "$(date) - [Pixabay] API request failed for '$query' — advancing" >> "$LOGFILE"
        rm -f "$api_response_file"
        advance_pixabay_query
        [ "$variety_was_running" = true ] && _ensure_variety_running "Pixabay"
        return 1
    fi

    local api_size
    if ! api_size=$(stat -c%s "$api_response_file" 2>/dev/null) \
        || [[ ! "$api_size" =~ ^[0-9]+$ ]]; then
        echo "$(date) - [Pixabay] ERROR: Cannot determine API response size — advancing" >> "$LOGFILE"
        rm -f "$api_response_file"
        advance_pixabay_query
        [ "$variety_was_running" = true ] && _ensure_variety_running "Pixabay"
        return 1
    fi
    if [ "$api_size" -gt "$PIXABAY_MAX_API_RESPONSE_SIZE" ]; then
        echo "$(date) - [Pixabay] API response too large (${api_size} bytes) for '$query' — advancing" >> "$LOGFILE"
        rm -f "$api_response_file"
        advance_pixabay_query
        [ "$variety_was_running" = true ] && _ensure_variety_running "Pixabay"
        return 1
    fi

    # Validate the JSON shape and extract hits directly from the file
    # (avoids loading the full response into a shell variable).
    if ! jq -e 'type == "object" and (.hits | type == "array")' \
        "$api_response_file" >/dev/null 2>&1; then
        echo "$(date) - [Pixabay] Invalid API response shape — advancing" >> "$LOGFILE"
        rm -f "$api_response_file"
        advance_pixabay_query
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

    if [ -z "$hits" ]; then
        echo "$(date) - [Pixabay] No suitable images for '$query' — advancing" >> "$LOGFILE"
        advance_pixabay_query
        [ "$variety_was_running" = true ] && _ensure_variety_running "Pixabay"
        return 1
    fi

    local hit_count
    hit_count=$(printf '%s\n' "$hits" | wc -l)
    echo "$(date) - [Pixabay] $hit_count images after filter" >> "$LOGFILE"

    local shuffled_hits
    shuffled_hits=$(printf '%s\n' "$hits" | shuf)

    local chosen_id="" chosen_url=""

    while IFS=$'\t' read -r id url; do
        [ -z "$id" ] && continue
        if ! is_in_history "pixabay://${id}" && ! recent_has_id "pixabay://${id}"; then
            chosen_id="$id"
            chosen_url="$url"
            break
        fi
    done <<< "$shuffled_hits"

    if [ -z "$chosen_id" ]; then
        while IFS=$'\t' read -r id url; do
            [ -z "$id" ] && continue
            if ! recent_has_id "pixabay://${id}"; then
                chosen_id="$id"
                chosen_url="$url"
                echo "$(date) - [Pixabay] Long-term repeat (outside recent window): $id" >> "$LOGFILE"
                break
            fi
        done <<< "$shuffled_hits"
    fi

    if [ -z "$chosen_id" ]; then
        echo "$(date) - [Pixabay] All candidates in recent window — advancing" >> "$LOGFILE"
        advance_pixabay_query
        [ "$variety_was_running" = true ] && _ensure_variety_running "Pixabay"
        return 1
    fi

    local WALLPAPER_FILE="$TMP_DIR/pixabay_$$.jpg"
    echo "$(date) - [Pixabay] Downloading $chosen_id..." >> "$LOGFILE"

    local success=false
    if _download_bounded "$chosen_url" "$WALLPAPER_FILE" \
        "$MAX_IMAGE_FILE_SIZE" "$PIXABAY_DL_CONNECT_TIMEOUT" "$PIXABAY_DL_TOTAL_TIMEOUT"; then

        local file_type=""
        local file_size=0
        local validation_ok=false
        local file_hash=""

        file_type=$(file -b "$WALLPAPER_FILE" 2>/dev/null)
        file_size=$(stat -c%s "$WALLPAPER_FILE" 2>/dev/null || echo 0)
        file_size=${file_size:-0}

        if is_valid_image_file "$WALLPAPER_FILE"; then
            if [ "$file_size" -gt 1024 ]; then
                validation_ok=true
            else
                echo "$(date) - [Pixabay] ERROR: File too small (${file_size} bytes)" >> "$LOGFILE"
            fi
        else
            echo "$(date) - [Pixabay] ERROR: Not a supported raster image (detected: ${file_type:-unknown})" >> "$LOGFILE"
        fi

        if [ "$validation_ok" = true ]; then
            local hd_rc=0
            is_landscape_hd_image "$WALLPAPER_FILE" \
                "$PIXABAY_IMAGE_MIN_WIDTH" "$PIXABAY_IMAGE_MIN_HEIGHT" || hd_rc=$?
            if [ "$hd_rc" -eq 1 ]; then
                echo "$(date) - [Pixabay] ERROR: Downloaded image is not landscape HD (${HD_LAST_DIMS:-unknown}) — advancing" >> "$LOGFILE"
                validation_ok=false
            elif [ "$hd_rc" -eq 2 ]; then
                echo "$(date) - [Pixabay] ERROR: Image decoder check failed or returned malformed dimensions — advancing" >> "$LOGFILE"
                validation_ok=false
            fi
        fi

        if [ "$validation_ok" = true ]; then
            file_hash=$(sha256sum "$WALLPAPER_FILE" 2>/dev/null | awk '{print $1}')
            if [ -z "$file_hash" ]; then
                echo "$(date) - [Pixabay] WARNING: sha256sum returned empty; cross-source dedup unavailable for this image" >> "$LOGFILE"
            elif recent_has_hash "$file_hash"; then
                echo "$(date) - [Pixabay] Cross-source duplicate (hash in recent window) — advancing" >> "$LOGFILE"
                validation_ok=false
            fi
        fi

        if [ "$validation_ok" = true ]; then
            if plasma-apply-wallpaperimage "$WALLPAPER_FILE" >/dev/null 2>&1; then
                if ! add_to_history "pixabay://${chosen_id}"; then
                    echo "$(date) - WARNING: [Pixabay] Wallpaper applied, but long-term history append failed" >> "$LOGFILE"
                fi
                if ! add_to_recent "pixabay://${chosen_id}" "$file_hash"; then
                    echo "$(date) - WARNING: [Pixabay] Wallpaper applied, but recent-history is UNPERSISTED (kept in memory, will retry on next successful write or periodic reload)" >> "$LOGFILE"
                fi
                echo "$(date) - [Pixabay] Wallpaper set from '$query' (id=$chosen_id, ${file_type}, ${file_size} bytes)" >> "$LOGFILE"
                success=true
                advance_pixabay_query
            else
                echo "$(date) - [Pixabay] ERROR: KDE rejected image" >> "$LOGFILE"
                advance_pixabay_query
            fi
        else
            advance_pixabay_query
        fi

        rm -f "$WALLPAPER_FILE"
    else
        echo "$(date) - [Pixabay] ERROR: Download failed (timeout/size/transfer) — advancing query" >> "$LOGFILE"
        rm -f "$WALLPAPER_FILE"
        advance_pixabay_query
    fi

    if [ "$variety_was_running" = true ]; then
        _ensure_variety_running "Pixabay"
    fi

    [ "$success" = true ] && return 0 || return 1
}

# ============================================================
# SOURCE SELECTION
# ============================================================
CURRENT_SOURCE=""
SAME_SOURCE_COUNT=0

select_source_except() {
    local exclude="${1:-}"
    local da=$DEVIANTART_WEIGHT
    local va=$VARIETY_WEIGHT
    local px=$PIXABAY_WEIGHT

    case "$exclude" in
        deviantart) da=0 ;;
        variety)    va=0 ;;
        pixabay)    px=0 ;;
    esac

    local total=$((da + va + px))
    (( total <= 0 )) && { echo ""; return; }

    local rand=$((RANDOM % total))
    if   (( rand < da )); then           echo "deviantart"
    elif (( rand < da + va )); then      echo "variety"
    else                                 echo "pixabay"
    fi
}

select_source() {
    if [ "${#SHUFFLED_SOURCES[@]}" -eq 0 ]; then
        build_source_deck || {
            SELECTED_SOURCE=""
            return 1
        }
    fi
    SELECTED_SOURCE="${SHUFFLED_SOURCES[$SOURCE_INDEX]}"
    advance_source_deck
    return 0
}

update_source_state() {
    if [ "$1" = "$CURRENT_SOURCE" ]; then
        SAME_SOURCE_COUNT=$((SAME_SOURCE_COUNT + 1))
    else
        CURRENT_SOURCE="$1"
        SAME_SOURCE_COUNT=1
    fi
}

other_sources() {
    local exclude="$1"
    local pool=()
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

# ============================================================
# BUILD SOURCE DECK (after dependency checks)
# ============================================================
build_source_deck || exit 1

# ============================================================
# MAIN LOOP
# ============================================================
IS_ONLINE=false

while true; do
    echo "$(date) - heartbeat (pid=$$)" >> "$LOGFILE"
    rotate_log

    if ! check_internet; then
        if [ "$IS_ONLINE" = true ]; then
            echo "$(date) - Internet lost — switching to Variety only" >> "$LOGFILE"
            IS_ONLINE=false
        fi

        echo "$(date) - [Offline] Using Variety" >> "$LOGFILE"
        if [ "$VARIETY_WEIGHT" -gt 0 ] && use_variety; then
            update_source_state "variety"
            sleep "$SLEEP_INTERVAL"
        else
            echo "$(date) - Offline: Variety failed, waiting 60s" >> "$LOGFILE"
            sleep 60
        fi
        continue
    fi

    if [ "$IS_ONLINE" = false ]; then
        echo "$(date) - Internet restored" >> "$LOGFILE"
        IS_ONLINE=true
        CURRENT_SOURCE=""
        SAME_SOURCE_COUNT=0
    fi

    SELECTED_SOURCE=""
    STREAK_OVERRIDE=false

    if [ "$SAME_SOURCE_COUNT" -ge "$MAX_SAME_SOURCE" ] && [ -n "$CURRENT_SOURCE" ]; then
        SELECTED_SOURCE=$(select_source_except "$CURRENT_SOURCE")
        if [ -n "$SELECTED_SOURCE" ]; then
            STREAK_OVERRIDE=true
            echo "$(date) - Max streak ($MAX_SAME_SOURCE) reached for $CURRENT_SOURCE — forcing $SELECTED_SOURCE" >> "$LOGFILE"
        else
            echo "$(date) - Streak cap ($MAX_SAME_SOURCE) reached for $CURRENT_SOURCE; no alternative source enabled — waiting 60s" >> "$LOGFILE"
            sleep 60
            continue
        fi
    fi

    if [ -z "$SELECTED_SOURCE" ]; then
        select_source || SELECTED_SOURCE=""
    fi

    echo "$(date) - Selected $SELECTED_SOURCE (streak: $SAME_SOURCE_COUNT/$MAX_SAME_SOURCE)" >> "$LOGFILE"

    SUCCESS=false
    SOURCE_USED=""

    if is_source_enabled "$SELECTED_SOURCE" && try_source "$SELECTED_SOURCE"; then
        SUCCESS=true
        SOURCE_USED="$SELECTED_SOURCE"
    else
        while IFS= read -r alt; do
            [ -z "$alt" ] && continue
            if [ "$SAME_SOURCE_COUNT" -ge "$MAX_SAME_SOURCE" ] \
                && [ "$alt" = "$CURRENT_SOURCE" ]; then
                continue
            fi
            if try_source "$alt"; then
                SUCCESS=true
                SOURCE_USED="$alt"
                echo "$(date) - $SELECTED_SOURCE failed — fell back to $alt" >> "$LOGFILE"
                break
            fi
        done < <(other_sources "$SELECTED_SOURCE")
    fi

    if [ "$SUCCESS" = true ]; then
        update_source_state "$SOURCE_USED"
        if [ "$SAME_SOURCE_COUNT" -gt "$MAX_SAME_SOURCE" ]; then
            SAME_SOURCE_COUNT="$MAX_SAME_SOURCE"
        fi
        echo "$(date) - [Success] Source: $SOURCE_USED (streak: $SAME_SOURCE_COUNT/$MAX_SAME_SOURCE)" >> "$LOGFILE"
        sleep "$SLEEP_INTERVAL"
    else
        echo "$(date) - All sources failed, waiting 30s" >> "$LOGFILE"
        sleep 30
    fi

    if [ "$_RECENT_DIRTY" = true ]; then
        if [ "$_RECENT_RETRY_FAILS" -lt 5 ] || [ $((RANDOM % 5)) -eq 0 ]; then
            if _persist_recent_window; then
                echo "$(date) - Persisted pending recent-history window" >> "$LOGFILE"
            else
                _RECENT_RETRY_FAILS=$((_RECENT_RETRY_FAILS + 1))
            fi
        fi
    fi

    if [ $((RANDOM % 50)) -eq 0 ]; then
        history_ok=true
        recent_ok=true

        load_history || history_ok=false
        load_recent_history || recent_ok=false

        if [ "$history_ok" = true ] && [ "$recent_ok" = true ]; then
            echo "$(date) - Periodic history caches reloaded" >> "$LOGFILE"
        else
            echo "$(date) - WARNING: Periodic history refresh incomplete (long-term=$history_ok recent=$recent_ok)" >> "$LOGFILE"
        fi
    fi

done
