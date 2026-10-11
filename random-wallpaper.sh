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
HISTORY_SIZE=100000
RECENT_HISTORY_SIZE=100
SEARCH_LIMIT=100
SLEEP_INTERVAL=60
DEVIOUSQ_TIMEOUT=30
WGET_TIMEOUT=15
WGET_TOTAL_TIMEOUT=30
IDENTIFY_TIMEOUT=10
MAX_IMAGE_FILE_SIZE=52428800   # 50 MB
MAX_RETRIES=3
LOG_MAX_SIZE=10485760
LOG_RETENTION_DAYS=30

HISTORY_MAX_LINE_BYTES=512
DEVIOUSQ_MAX_OUTPUT_BYTES=1048576
MAX_URL_LENGTH=2048
PIXABAY_API_KEY_MAX_LEN=256

DEVIANTART_WEIGHT=55
VARIETY_WEIGHT=15
PIXABAY_WEIGHT=30

MAX_SAME_SOURCE=3

# Higher quality for DeviantArt, free-key friendly for Pixabay
DEVIANTART_IMAGE_MIN_WIDTH=1920
DEVIANTART_IMAGE_MIN_HEIGHT=1080
PIXABAY_IMAGE_MIN_WIDTH=1280
PIXABAY_IMAGE_MIN_HEIGHT=720

DEVIANTART_TOKEN_MAX_DIM=20000
DEVIANTART_ALLOW_UNDECODABLE=false

PIXABAY_API_KEY="${PIXABAY_API_KEY:-}"
PIXABAY_PER_PAGE=50
PIXABAY_API_TIMEOUT=15
PIXABAY_DL_CONNECT_TIMEOUT=10
PIXABAY_DL_TOTAL_TIMEOUT=45
PIXABAY_MAX_API_RESPONSE_SIZE=10485760

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

# ============================================================
# PATHS & SETUP
# ============================================================
HISTORY_FILE="$HOME/scriptlogs/wallpaper_history.txt"
RECENT_HISTORY_FILE="$HOME/scriptlogs/wallpaper_recent.txt"
LOGFILE="$HOME/scriptlogs/wallpaper.log"
LOCK_FILE="$HOME/.cache/random_wallpaper.lock"

# Persistent wallpaper location. KDE will keep pointing at this file
# across script restarts and temp-dir cleanups, so the wallpaper will
# not silently revert to the Plasma default.
WALLPAPER_CACHE_DIR="$HOME/.cache/random-wallpaper"
WALLPAPER_CURRENT="$WALLPAPER_CACHE_DIR/current.jpg"

umask 077

if ! mkdir -p "$HOME/scriptlogs" "$(dirname "$LOCK_FILE")" "$WALLPAPER_CACHE_DIR"; then
    echo "ERROR: Failed to create required directories" >&2
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
                echo "$(date) - Log rotated (was ${size} bytes)" > "$LOGFILE"
            fi
        fi
    fi
    find "$HOME/scriptlogs" -name 'wallpaper.log.*' -mtime +"$LOG_RETENTION_DAYS" -delete 2>/dev/null || true
}

# ============================================================
# SINGLE-INSTANCE LOCK + TEMP DIR + CLEANUP
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
    local attempts=6 interval_s=0.4 i
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
    if [ "$_VARIETY_PAUSED_BY_SCRIPT" = true ] && [ -z "$(variety_pids)" ]; then
        if _restore_variety_verified; then
            echo "$(date) - Restored Variety on exit" >> "$LOGFILE"
        else
            echo "$(date) - WARNING: Variety not running after exit restore" >> "$LOGFILE"
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
    exit 1
}

for _f in "$HISTORY_FILE" "$RECENT_HISTORY_FILE"; do
    if ! { : >> "$_f"; } 2>/dev/null; then
        echo "$(date) - ERROR: Cannot open $_f for append" >> "$LOGFILE"
        exit 1
    fi
done
unset _f

echo "$(date) - Random Wallpaper Script Started (stable Variety policy)" >> "$LOGFILE"
echo "$(date) - Weights: DA=$DEVIANTART_WEIGHT Variety=$VARIETY_WEIGHT Pixabay=$PIXABAY_WEIGHT" >> "$LOGFILE"
echo "$(date) - Image bounds: DA ${DEVIANTART_IMAGE_MIN_WIDTH}x${DEVIANTART_IMAGE_MIN_HEIGHT}, Pixabay ${PIXABAY_IMAGE_MIN_WIDTH}x${PIXABAY_IMAGE_MIN_HEIGHT}" >> "$LOGFILE"
echo "$(date) - Persistent wallpaper path: $WALLPAPER_CURRENT" >> "$LOGFILE"

# ============================================================
# HELPERS
# ============================================================
_curl_config_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

_decode_da_token() {
    local url="$1"
    local token payload dims max_w max_h

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
    [ -z "$max_w" ] && return 1
    [ -z "$max_h" ] && return 1

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
    [ -z "$max_w" ] || [ -z "$max_h" ] && { printf '%s' "$url"; return 0; }

    printf '%s' "$url" | sed -E \
        "s#/v1/(fill|fit)/w_[0-9]+,h_[0-9]+#/v1/fill/w_${max_w},h_${max_h}#"
}

_download_bounded() {
    local url="$1" outfile="$2" max_bytes="$3" connect_timeout="$4" total_timeout="$5"
    local read_limit=$(( max_bytes + 1 )) rc=0

    rm -f "$outfile" 2>/dev/null || true

    timeout --kill-after=5s "${total_timeout}s" \
        bash -c '
            set -o pipefail
            curl -sSL --fail --proto "=https" --proto-redir "=https" \
                --connect-timeout "$1" "$2" | head -c "$3" > "$4"
        ' _ "$connect_timeout" "$url" "$read_limit" "$outfile" 2>/dev/null || rc=$?

    if [ "$rc" -ne 0 ]; then
        rm -f "$outfile" 2>/dev/null || true
        return 1
    fi

    local size
    size=$(stat -c%s "$outfile" 2>/dev/null) || { rm -f "$outfile"; return 1; }
    [[ "$size" =~ ^[0-9]+$ ]] || { rm -f "$outfile"; return 1; }
    [ "$size" -gt "$max_bytes" ] && { rm -f "$outfile"; return 1; }
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
            ' _ "$total_timeout" "$read_limit" "$outfile" 2>/dev/null || rc=$?

    if [ "$rc" -ne 0 ]; then
        rm -f "$outfile" 2>/dev/null || true
        return 1
    fi

    local size
    size=$(stat -c%s "$outfile" 2>/dev/null) || { rm -f "$outfile"; return 1; }
    [[ "$size" =~ ^[0-9]+$ ]] || { rm -f "$outfile"; return 1; }
    [ "$size" -gt "$max_bytes" ] && { rm -f "$outfile"; return 1; }
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

    command -v identify >/dev/null 2>&1 || return 1

    dims=$(timeout --kill-after=2s "${IDENTIFY_TIMEOUT}s" \
        identify -limit memory 256MiB -limit map 512MiB -limit disk 1GiB \
                 -limit width 30000 -limit height 30000 \
                 -format '%w %h' "${path}[0]" 2>/dev/null) || return 2
    [ -z "$dims" ] && return 2

    read -r w h <<< "$dims"
    [[ "$w" =~ ^[0-9]+$ && "$h" =~ ^[0-9]+$ ]] || return 2

    HD_LAST_DIMS="${w}x${h}"
    HD_LAST_WIDTH="$w"
    HD_LAST_HEIGHT="$h"
    return 0
}
HD_LAST_WIDTH=""
HD_LAST_HEIGHT=""

is_hd_image() {
    local path="$1" min_w="$2" min_h="$3" rc=0
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
    local path="$1" min_w="$2" min_h="$3" rc=0
    _parse_image_dims "$path" || rc=$?
    [ "$rc" -eq 1 ] && return 0
    [ "$rc" -eq 2 ] && return 2

    [ "$HD_LAST_WIDTH" -ge "$min_w" ] && [ "$HD_LAST_HEIGHT" -ge "$min_h" ] && return 0
    return 1
}

# ============================================================
# DEPENDENCY CHECK
# ============================================================
for cmd in flock timeout curl file stat awk grep head tail shuf \
           mktemp df pgrep find date wc cat sed seq setsid \
           sha256sum base64 cut cp; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "$(date) - ERROR: required command not found: $cmd" >> "$LOGFILE"
        exit 1
    fi
done

if ! command -v plasma-apply-wallpaperimage >/dev/null 2>&1; then
    echo "$(date) - ERROR: plasma-apply-wallpaperimage not found" >> "$LOGFILE"
    exit 1
fi

[ "$DEVIANTART_WEIGHT" -gt 0 ] && ! command -v deviousq >/dev/null 2>&1 && {
    echo "$(date) - WARNING: deviousq not found — disabling DeviantArt" >> "$LOGFILE"
    DEVIANTART_WEIGHT=0
}
[ "$DEVIANTART_WEIGHT" -gt 0 ] && ! command -v jq >/dev/null 2>&1 && {
    echo "$(date) - WARNING: jq not found — disabling DeviantArt" >> "$LOGFILE"
    DEVIANTART_WEIGHT=0
}
[ "$VARIETY_WEIGHT" -gt 0 ] && ! command -v variety >/dev/null 2>&1 && {
    echo "$(date) - WARNING: variety not found — disabling Variety" >> "$LOGFILE"
    VARIETY_WEIGHT=0
}

if [ "$PIXABAY_WEIGHT" -gt 0 ]; then
    if [ -z "$PIXABAY_API_KEY" ]; then
        echo "$(date) - WARNING: PIXABAY_API_KEY not set — disabling Pixabay" >> "$LOGFILE"
        PIXABAY_WEIGHT=0
    elif ! command -v jq >/dev/null 2>&1; then
        echo "$(date) - WARNING: jq not found — disabling Pixabay" >> "$LOGFILE"
        PIXABAY_WEIGHT=0
    fi
fi

if [ "$DEVIANTART_WEIGHT" -eq 0 ] && [ "$PIXABAY_WEIGHT" -eq 0 ] && [ "$VARIETY_WEIGHT" -eq 0 ]; then
    echo "$(date) - ERROR: no enabled sources" >> "$LOGFILE"
    exit 1
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
        [ "$age" -lt "$INTERNET_CACHE_TTL" ] && return 0
    fi

    local -a endpoints=(
        "https://one.one.one.one/"
        "https://www.google.com/generate_204"
        "https://www.cloudflare.com/cdn-cgi/trace"
    )
    local -a probe_resolve=("one.one.one.one:443:1.1.1.1" "" "")

    local tmpdir
    tmpdir=$(mktemp -d "$TMP_DIR/probes.XXXXXX") || {
        _internet_last_check=$now
        _internet_last_result=1
        return 1
    }
    _PROBE_TMPDIR="$tmpdir"
    _PROBE_PIDS=()

    local i=0 idx
    for idx in "${!endpoints[@]}"; do
        local ep="${endpoints[$idx]}"
        local resolve="${probe_resolve[$idx]}"
        setsid bash -c '
            extra=()
            [ -n "$2" ] && extra=(--resolve "$2")
            if curl -fsS -o /dev/null --connect-timeout 2 --max-time "$1" \
                --no-keepalive --proto "=https" --proto-redir "=https" \
                ${extra[@]+"${extra[@]}"} -H "User-Agent: Mozilla/5.0" "$3" >/dev/null 2>&1; then
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
        sleep 0.2
    done

    cleanup_probes
    _internet_last_check=$now
    _internet_last_result=$success
    return $success
}

# ============================================================
# VARIETY MANAGEMENT
# ============================================================
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
        [ -n "$pid" ] && kill -TERM "$pid" 2>/dev/null && killed_any=true
    done <<< "$pids"
    sleep 0.8
    pids=$(variety_pids)
    if [ -n "$pids" ]; then
        while IFS= read -r pid; do
            [ -n "$pid" ] && kill -KILL "$pid" 2>/dev/null && killed_any=true
        done <<< "$pids"
        sleep 0.3
    fi

    if [ -z "$(variety_pids)" ]; then
        echo "$(date) - Stopped Variety process(es)" >> "$LOGFILE"
        return 0
    fi
    if [ "$killed_any" = true ]; then
        echo "$(date) - Partial Variety termination (flag kept)" >> "$LOGFILE"
    else
        _VARIETY_PAUSED_BY_SCRIPT=false
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
    echo "$(date) - [$tag] WARNING: Variety not running after fetch" >> "$LOGFILE"
    return 1
}

use_variety() {
    if ! command -v variety >/dev/null 2>&1; then
        echo "$(date) - Variety not installed" >> "$LOGFILE"
        return 1
    fi
    if [ -z "$(variety_pids)" ]; then
        start_variety || return 1
    fi
    if variety --next >/dev/null 2>&1; then
        echo "$(date) - Variety rotated (its own random pick)" >> "$LOGFILE"
        return 0
    fi
    echo "$(date) - Variety rotation failed" >> "$LOGFILE"
    return 1
}

_prepare_variety_pause() {
    VARIETY_WAS_RUNNING=false
    [ "${VARIETY_WEIGHT:-0}" -le 0 ] && return 0
    [ -z "$(variety_pids)" ] && return 0
    if stop_variety; then
        VARIETY_WAS_RUNNING=true
        return 0
    fi
    return 1
}

# ============================================================
# CATEGORIES / QUERIES / SOURCE DECK
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
        t=$((a % b)); a=$b; b=$t
    done
    printf '%s' "$a"
}

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
    echo "$(date) - [Sources] Reshuffled deck of ${#SHUFFLED_SOURCES[@]} slots" >> "$LOGFILE"
}

advance_source_deck() {
    SOURCE_INDEX=$((SOURCE_INDEX + 1))
    if [ "$SOURCE_INDEX" -ge "${#SHUFFLED_SOURCES[@]}" ]; then
        echo "$(date) - [Sources] Finished deck cycle. Reshuffling..." >> "$LOGFILE"
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
    _RECENT_TMP=$(mktemp "$RECENT_HISTORY_FILE.XXXXXX") || { _RECENT_TMP=""; return 1; }
    if ! printf '%s\n' "${RECENT_ORDERED[@]}" > "$_RECENT_TMP"; then
        rm -f "$_RECENT_TMP"; _RECENT_TMP=""; return 1
    fi
    if ! mv -f "$_RECENT_TMP" "$RECENT_HISTORY_FILE"; then
        rm -f "$_RECENT_TMP"; _RECENT_TMP=""; return 1
    fi
    _RECENT_TMP=""
    _RECENT_DIRTY=false
    _RECENT_RETRY_FAILS=0
    return 0
}

load_history() {
    if [ ! -e "$HISTORY_FILE" ]; then
        HISTORY_CACHE=()
        return 0
    fi
    [ ! -r "$HISTORY_FILE" ] && return 1

    local existing
    existing=$(set -o pipefail; tail -n "$HISTORY_SIZE" "$HISTORY_FILE" 2>/dev/null \
               | cut -b1-"$HISTORY_MAX_LINE_BYTES" 2>/dev/null) || return 1

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
load_history

load_recent_history() {
    if [ "$_RECENT_DIRTY" = true ]; then
        _persist_recent_window || return 1
    fi
    if [ ! -e "$RECENT_HISTORY_FILE" ]; then
        RECENT_ORDERED=()
        _rebuild_maps_from_ordered
        return 0
    fi
    [ ! -r "$RECENT_HISTORY_FILE" ] && return 1

    local existing
    existing=$(set -o pipefail; tail -n "$RECENT_HISTORY_SIZE" "$RECENT_HISTORY_FILE" 2>/dev/null \
               | cut -b1-"$MAX_URL_LENGTH" 2>/dev/null) || return 1

    local -a new_ordered=()
    [ -n "$existing" ] && mapfile -t new_ordered <<< "$existing"

    local -a valid_ordered=()
    local _l _s _h
    for _l in "${new_ordered[@]}"; do
        [ -z "$_l" ] && continue
        _s="${_l%%$'\t'*}"
        if [[ "$_l" == *$'\t'* ]]; then _h="${_l#*$'\t'}"; else _h=""; fi
        [ -z "$_s" ] && continue
        if [ -n "$_h" ] && ! [[ "$_h" =~ ^[0-9a-f]{64}$ ]]; then continue; fi
        valid_ordered+=("$_l")
    done
    new_ordered=("${valid_ordered[@]}")

    local n=${#new_ordered[@]}
    [ "$n" -gt "$RECENT_HISTORY_SIZE" ] && new_ordered=("${new_ordered[@]:$((n - RECENT_HISTORY_SIZE))}")

    RECENT_ORDERED=("${new_ordered[@]}")
    _rebuild_maps_from_ordered
    echo "$(date) - Loaded ${#RECENT_ORDERED[@]} recent-history entries" >> "$LOGFILE"
    return 0
}
load_recent_history

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
            _HISTORY_TMP=""
            load_history
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
    local url="$1"
    [ -z "$url" ] && return 2
    [[ -v HISTORY_CACHE["$url"] ]] && return 0
    return 1
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
# DEVIANTART FETCHER  (Variety restarted ONLY on failure)
# ============================================================
fetch_deviantart() {
    [ "$DEVIANTART_WEIGHT" -le 0 ] && return 1

    if ! _prepare_variety_pause; then
        echo "$(date) - [DeviantArt] Aborting: Variety still running" >> "$LOGFILE"
        [ "$_VARIETY_PAUSED_BY_SCRIPT" = true ] && _ensure_variety_running "DeviantArt"
        return 1
    fi
    local variety_was_running="$VARIETY_WAS_RUNNING"
    [ "$variety_was_running" = true ] && echo "$(date) - [DeviantArt] Paused Variety" >> "$LOGFILE"

    local current_category="${SHUFFLED_CATEGORIES[$CAT_INDEX]}"
    echo "$(date) - [DeviantArt] Searching: '$current_category'" >> "$LOGFILE"

    local URL_LIST="" RETRY_COUNT=0
    while [ -z "$URL_LIST" ] && [ "$RETRY_COUNT" -lt "$MAX_RETRIES" ]; do
        [ "$RETRY_COUNT" -gt 0 ] && { echo "$(date) - [DeviantArt] Retry $RETRY_COUNT" >> "$LOGFILE"; sleep 3; }

        URL_LIST=$(timeout --kill-after=5s "${DEVIOUSQ_TIMEOUT}s" deviousq \
            --medium image --rating nonadult --return-field content_url \
            --limit "$SEARCH_LIMIT" "$current_category" 2>/dev/null \
            | head -c "$DEVIOUSQ_MAX_OUTPUT_BYTES"
            exit "${PIPESTATUS[0]}")

        local exit_code=$?
        if [ $exit_code -eq 141 ]; then
            echo "$(date) - [DeviantArt] Output capped" >> "$LOGFILE"
        elif [ $exit_code -eq 124 ] || [ $exit_code -eq 137 ]; then
            echo "$(date) - [DeviantArt] Timed out" >> "$LOGFILE"
            URL_LIST=""
        elif [ $exit_code -ne 0 ]; then
            URL_LIST=""
        fi
        RETRY_COUNT=$((RETRY_COUNT + 1))
    done

    if [ -z "$URL_LIST" ]; then
        echo "$(date) - [DeviantArt] No results — advancing" >> "$LOGFILE"
        advance_category
        if [ "$variety_was_running" = true ]; then
            _ensure_variety_running "DeviantArt"
            echo "$(date) - [DeviantArt] Restarted Variety after failure" >> "$LOGFILE"
        fi
        return 1
    fi

    if [ "${#URL_LIST}" -ge "$((DEVIOUSQ_MAX_OUTPUT_BYTES - 1))" ]; then
        URL_LIST=$(printf '%s\n' "$URL_LIST" | sed '$d')
    fi

    local VALID_URLS
    VALID_URLS=$(printf '%s\n' "$URL_LIST" | grep -E '^https://' \
        | awk -v m="$MAX_URL_LENGTH" 'length($0) <= m' | head -100)

    if [ -z "$VALID_URLS" ]; then
        advance_category
        if [ "$variety_was_running" = true ]; then
            _ensure_variety_running "DeviantArt"
            echo "$(date) - [DeviantArt] Restarted Variety after failure" >> "$LOGFILE"
        fi
        return 1
    fi

    local URL_COUNT
    URL_COUNT=$(printf '%s\n' "$VALID_URLS" | wc -l)
    echo "$(date) - [DeviantArt] Found $URL_COUNT URLs" >> "$LOGFILE"

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
                echo "$(date) - [DeviantArt] Long-term repeat" >> "$LOGFILE"
                break
            fi
        done
    fi

    if [ -z "$RANDOM_URL" ]; then
        echo "$(date) - [DeviantArt] No eligible candidates (${small_skipped} skipped) — advancing" >> "$LOGFILE"
        advance_category
        if [ "$variety_was_running" = true ]; then
            _ensure_variety_running "DeviantArt"
            echo "$(date) - [DeviantArt] Restarted Variety after failure" >> "$LOGFILE"
        fi
        return 1
    fi

    local REWRITTEN_URL
    REWRITTEN_URL=$(_rewrite_da_url "$RANDOM_URL")
    [ "$REWRITTEN_URL" != "$RANDOM_URL" ] && echo "$(date) - [DeviantArt] Rewrote URL to token max resolution" >> "$LOGFILE"
    RANDOM_URL="$REWRITTEN_URL"

    local WALLPAPER_FILE="$TMP_DIR/wallpaper_$$.jpg"
    echo "$(date) - [DeviantArt] Downloading..." >> "$LOGFILE"

    local success=false
    if _download_bounded "$RANDOM_URL" "$WALLPAPER_FILE" \
        "$MAX_IMAGE_FILE_SIZE" "$WGET_TIMEOUT" "$WGET_TOTAL_TIMEOUT"; then

        local file_type file_size=0 validation_ok=false file_hash=""
        file_type=$(file -b "$WALLPAPER_FILE" 2>/dev/null)
        file_size=$(stat -c%s "$WALLPAPER_FILE" 2>/dev/null || echo 0)

        if is_valid_image_file "$WALLPAPER_FILE" && [ "$file_size" -gt 1024 ]; then
            validation_ok=true
        fi

        if [ "$validation_ok" = true ]; then
            local hd_rc=0
            is_hd_image "$WALLPAPER_FILE" "$DEVIANTART_IMAGE_MIN_WIDTH" "$DEVIANTART_IMAGE_MIN_HEIGHT" || hd_rc=$?
            [ "$hd_rc" -ne 0 ] && validation_ok=false
        fi

        if [ "$validation_ok" = true ]; then
            file_hash=$(sha256sum "$WALLPAPER_FILE" 2>/dev/null | awk '{print $1}')
            [ -n "$file_hash" ] && recent_has_hash "$file_hash" && validation_ok=false
        fi

        if [ "$validation_ok" = true ]; then
            # Persist a copy so KDE keeps a valid path across temp-dir cleanup.
            if cp -f -- "$WALLPAPER_FILE" "$WALLPAPER_CURRENT" 2>/dev/null \
               && plasma-apply-wallpaperimage "$WALLPAPER_CURRENT" >/dev/null 2>&1; then
                add_to_history "$SOURCE_ID" || true
                add_to_recent "$SOURCE_ID" "$file_hash" || true
                echo "$(date) - [DeviantArt] Wallpaper set from '$current_category' (${file_size} bytes)" >> "$LOGFILE"
                success=true
                advance_category
            else
                advance_category
            fi
        else
            advance_category
        fi
        rm -f "$WALLPAPER_FILE"
    else
        echo "$(date) - [DeviantArt] Download failed — advancing" >> "$LOGFILE"
        rm -f "$WALLPAPER_FILE"
        advance_category
    fi

    # === STABLE POLICY: restart Variety ONLY on failure ===
    if [ "$variety_was_running" = true ] && [ "$success" != true ]; then
        _ensure_variety_running "DeviantArt"
        echo "$(date) - [DeviantArt] Restarted Variety after failure" >> "$LOGFILE"
    fi

    [ "$success" = true ] && return 0 || return 1
}

# ============================================================
# PIXABAY FETCHER  (Variety restarted ONLY on failure)
# ============================================================
fetch_pixabay() {
    [ "$PIXABAY_WEIGHT" -le 0 ] && return 1
    [ -z "$PIXABAY_API_KEY" ] && return 1

    if ! _prepare_variety_pause; then
        echo "$(date) - [Pixabay] Aborting: Variety still running" >> "$LOGFILE"
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
            local t="${query#term:}"
            local enc
            enc=$(printf '%s' "$t" | jq -sRr @uri)
            api_url="https://pixabay.com/api/?key=${PIXABAY_API_KEY}&q=${enc}&image_type=photo&min_width=${PIXABAY_IMAGE_MIN_WIDTH}&per_page=${PIXABAY_PER_PAGE}&safesearch=true"
            ;;
        *)
            advance_pixabay_query
            if [ "$variety_was_running" = true ]; then
                _ensure_variety_running "Pixabay"
                echo "$(date) - [Pixabay] Restarted Variety after failure" >> "$LOGFILE"
            fi
            return 1
            ;;
    esac

    local api_response_file="$TMP_DIR/pixabay_api_$$.json"
    local escaped_url api_config
    escaped_url=$(_curl_config_escape "$api_url")
    api_config=$(printf 'url = "%s"\n' "$escaped_url")

    if ! _download_api_bounded "$api_config" "$api_response_file" \
        "$PIXABAY_MAX_API_RESPONSE_SIZE" "$PIXABAY_API_TIMEOUT"; then
        advance_pixabay_query
        if [ "$variety_was_running" = true ]; then
            _ensure_variety_running "Pixabay"
            echo "$(date) - [Pixabay] Restarted Variety after failure" >> "$LOGFILE"
        fi
        return 1
    fi

    if ! jq -e 'type == "object" and (.hits | type == "array")' "$api_response_file" >/dev/null 2>&1; then
        rm -f "$api_response_file"
        advance_pixabay_query
        if [ "$variety_was_running" = true ]; then
            _ensure_variety_running "Pixabay"
            echo "$(date) - [Pixabay] Restarted Variety after failure" >> "$LOGFILE"
        fi
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
        echo "$(date) - [Pixabay] No suitable images — advancing" >> "$LOGFILE"
        advance_pixabay_query
        if [ "$variety_was_running" = true ]; then
            _ensure_variety_running "Pixabay"
            echo "$(date) - [Pixabay] Restarted Variety after failure" >> "$LOGFILE"
        fi
        return 1
    fi

    local hit_count
    hit_count=$(printf '%s\n' "$hits" | wc -l)
    echo "$(date) - [Pixabay] $hit_count images after filter" >> "$LOGFILE"

    local shuffled_hits chosen_id="" chosen_url=""
    shuffled_hits=$(printf '%s\n' "$hits" | shuf)

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
                break
            fi
        done <<< "$shuffled_hits"
    fi

    if [ -z "$chosen_id" ]; then
        advance_pixabay_query
        if [ "$variety_was_running" = true ]; then
            _ensure_variety_running "Pixabay"
            echo "$(date) - [Pixabay] Restarted Variety after failure" >> "$LOGFILE"
        fi
        return 1
    fi

    local WALLPAPER_FILE="$TMP_DIR/pixabay_$$.jpg"
    echo "$(date) - [Pixabay] Downloading $chosen_id..." >> "$LOGFILE"

    local success=false
    if _download_bounded "$chosen_url" "$WALLPAPER_FILE" \
        "$MAX_IMAGE_FILE_SIZE" "$PIXABAY_DL_CONNECT_TIMEOUT" "$PIXABAY_DL_TOTAL_TIMEOUT"; then

        local file_type file_size=0 validation_ok=false file_hash=""
        file_type=$(file -b "$WALLPAPER_FILE" 2>/dev/null)
        file_size=$(stat -c%s "$WALLPAPER_FILE" 2>/dev/null || echo 0)

        if is_valid_image_file "$WALLPAPER_FILE" && [ "$file_size" -gt 1024 ]; then
            validation_ok=true
        fi

        if [ "$validation_ok" = true ]; then
            local hd_rc=0
            is_landscape_hd_image "$WALLPAPER_FILE" "$PIXABAY_IMAGE_MIN_WIDTH" "$PIXABAY_IMAGE_MIN_HEIGHT" || hd_rc=$?
            [ "$hd_rc" -ne 0 ] && validation_ok=false
        fi

        if [ "$validation_ok" = true ]; then
            file_hash=$(sha256sum "$WALLPAPER_FILE" 2>/dev/null | awk '{print $1}')
            [ -n "$file_hash" ] && recent_has_hash "$file_hash" && validation_ok=false
        fi

        if [ "$validation_ok" = true ]; then
            # Persist a copy so KDE keeps a valid path across temp-dir cleanup.
            if cp -f -- "$WALLPAPER_FILE" "$WALLPAPER_CURRENT" 2>/dev/null \
               && plasma-apply-wallpaperimage "$WALLPAPER_CURRENT" >/dev/null 2>&1; then
                add_to_history "pixabay://${chosen_id}" || true
                add_to_recent "pixabay://${chosen_id}" "$file_hash" || true
                echo "$(date) - [Pixabay] Wallpaper set from '$query' (id=$chosen_id)" >> "$LOGFILE"
                success=true
                advance_pixabay_query
            else
                advance_pixabay_query
            fi
        else
            advance_pixabay_query
        fi
        rm -f "$WALLPAPER_FILE"
    else
        echo "$(date) - [Pixabay] Download failed — advancing" >> "$LOGFILE"
        rm -f "$WALLPAPER_FILE"
        advance_pixabay_query
    fi

    # === STABLE POLICY: restart Variety ONLY on failure ===
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

select_source_except() {
    local exclude="${1:-}"
    local da=$DEVIANTART_WEIGHT va=$VARIETY_WEIGHT px=$PIXABAY_WEIGHT
    case "$exclude" in
        deviantart) da=0 ;;
        variety)    va=0 ;;
        pixabay)    px=0 ;;
    esac
    local total=$((da + va + px))
    (( total <= 0 )) && { echo ""; return; }
    local rand=$((RANDOM % total))
    if   (( rand < da )); then echo "deviantart"
    elif (( rand < da + va )); then echo "variety"
    else echo "pixabay"
    fi
}

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
        if [ "$VARIETY_WEIGHT" -gt 0 ] && use_variety; then
            update_source_state "variety"
            sleep "$SLEEP_INTERVAL"
        else
            sleep 30
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
    if [ "$SAME_SOURCE_COUNT" -ge "$MAX_SAME_SOURCE" ] && [ -n "$CURRENT_SOURCE" ]; then
        SELECTED_SOURCE=$(select_source_except "$CURRENT_SOURCE")
        if [ -n "$SELECTED_SOURCE" ]; then
            echo "$(date) - Max streak reached for $CURRENT_SOURCE — forcing $SELECTED_SOURCE" >> "$LOGFILE"
        else
            sleep 30
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
            if [ "$SAME_SOURCE_COUNT" -ge "$MAX_SAME_SOURCE" ] && [ "$alt" = "$CURRENT_SOURCE" ]; then
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
        [ "$SAME_SOURCE_COUNT" -gt "$MAX_SAME_SOURCE" ] && SAME_SOURCE_COUNT="$MAX_SAME_SOURCE"
        echo "$(date) - [Success] Source: $SOURCE_USED (streak: $SAME_SOURCE_COUNT/$MAX_SAME_SOURCE)" >> "$LOGFILE"
        sleep "$SLEEP_INTERVAL"
    else
        echo "$(date) - All sources failed, waiting 20s" >> "$LOGFILE"
        sleep 20
    fi

    if [ "$_RECENT_DIRTY" = true ]; then
        if [ "$_RECENT_RETRY_FAILS" -lt 5 ] || [ $((RANDOM % 5)) -eq 0 ]; then
            _persist_recent_window || _RECENT_RETRY_FAILS=$((_RECENT_RETRY_FAILS + 1))
        fi
    fi

    if [ $((RANDOM % 50)) -eq 0 ]; then
        load_history || true
        load_recent_history || true
    fi
done
