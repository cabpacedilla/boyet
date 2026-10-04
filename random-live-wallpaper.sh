#!/usr/bin/env bash
# ============================================================================
# Random Live Wallpaper Rotator — Pixabay-only, mpvpaper backend
#
# - Query rotation uses the shuffle-bag pattern: every query is used exactly
#   once per cycle, then the bag is reshuffled. Unproductive queries advance;
#   downstream failures (download/apply) do not, so they retry next cycle.
# - Multi-screen: mpvpaper spawns one player per output, so each monitor
#   decodes its own video independently. This avoids the single-decoder
#   limitation of the KDE Smart Video Wallpaper plugin, which would only
#   animate one screen at a time.
#
# Requirements:
#   - mpvpaper installed (COPR: caoturkey/Celestia or hermitfeather/hyprland)
#   - wlr-randr OR /sys/class/drm readable (fallback output detection)
#
# Environment:
#   PIXABAY_API_KEY  — required
# ============================================================================

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export PATH="$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"

# ============================================================
# CONFIGURATION
# ============================================================
HISTORY_SIZE=500000
SLEEP_INTERVAL=60
LOG_MAX_SIZE=10485760

PIXABAY_API_KEY="${PIXABAY_API_KEY:-}"

# Mixed bag: 20 categories + 24 curated free-text terms = 44 items per cycle.
# Each entry is "category:<name>" or "term:<free text>".
PIXABAY_QUERIES=(
    # --- Pixabay's official video categories (all 20) ---
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
    # --- Curated free-text terms ---
    "term:live wallpaper"
    "term:live wallpaper loop"
    "term:abstract live wallpaper"
    "term:nature landscape"
    "term:abstract background"
    "term:ocean waves loop"
    "term:city night timelapse"
    "term:space nebula"
    "term:forest rain"
    "term:sunset clouds"
    "term:mountain aerial"
    "term:autumn leaves"
    "term:aurora borealis"
    "term:underwater coral"
    "term:particle animation"
    "term:aerial drone"
    "term:slow motion water"
    "term:fireplace loop"
    "term:northern lights"
    "term:desert dunes"
    "term:tropical beach"
    "term:winter snow"
    "term:spring blossom"
    "term:starry night sky"
)

PIXABAY_VIDEO_MIN_WIDTH=1920
PIXABAY_VIDEO_MIN_DURATION=8
PIXABAY_VIDEO_MAX_DURATION=30
PIXABAY_PER_PAGE=50

# mpvpaper options — passed via -o "..."
#   no-audio        : mute
#   --loop          : loop the video
#   --panscan=1.0   : fill the screen (crop instead of letterbox)
#   --hwdec=auto-safe : use hardware decoding when available
#   --no-osc --no-osd-bar --no-input-default-bindings : hide mpv OSD
MPVPAPER_OPTS="no-audio --loop --panscan=1.0 --hwdec=auto-safe --no-osc --no-osd-bar --no-input-default-bindings"

LIVE_WALLPAPER_DIR="$HOME/Pictures/live-wallpapers"
MAX_LIVE_WALLPAPERS=20

# ============================================================
# PATHS & SETUP
# ============================================================
HISTORY_FILE="$HOME/scriptlogs/wallpaper_history.txt"
LOGFILE="$HOME/scriptlogs/wallpaper.log"
LOCK_FILE="$HOME/.cache/random_wallpaper.lock"

mkdir -p "$HOME/scriptlogs" "$(dirname "$LOCK_FILE")" "$LIVE_WALLPAPER_DIR"

# ============================================================
# LOG ROTATION
# ============================================================
rotate_log() {
    if [ -f "$LOGFILE" ]; then
        local size
        size=$(stat -c%s "$LOGFILE" 2>/dev/null \
            || stat -f%z "$LOGFILE" 2>/dev/null \
            || wc -c < "$LOGFILE" 2>/dev/null \
            || echo 0)
        if [ "${size:-0}" -gt "$LOG_MAX_SIZE" ]; then
            mv "$LOGFILE" "$LOGFILE.$(date +%Y%m%d_%H%M%S)"
            echo "$(date) - Log rotated (was ${size} bytes)" > "$LOGFILE"
        fi
    fi
}
rotate_log

# ============================================================
# SINGLE-INSTANCE LOCK
# ============================================================
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "$(date) - Another instance is already running. Exiting." >> "$LOGFILE"
    exit 1
fi
trap 'ec=$?; echo "$(date) - SCRIPT EXITING (code=$ec)" >> "$LOGFILE"; flock -u 9; exec 9>&-' EXIT

echo "$(date) - Random Live Wallpaper Script Started (Pixabay-only, mpvpaper backend)" >> "$LOGFILE"

# ============================================================
# API KEY + DEPENDENCIES
# ============================================================
if [ -z "$PIXABAY_API_KEY" ]; then
    echo "$(date) - ERROR: PIXABAY_API_KEY not set" >> "$LOGFILE"
    echo "ERROR: PIXABAY_API_KEY not set" >&2
    exit 1
fi

for cmd in jq curl mpvpaper; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "$(date) - ERROR: required command not found: $cmd" >> "$LOGFILE"
        echo "ERROR: required command not found: $cmd" >&2
        exit 1
    fi
done

# ============================================================
# INTERNET CHECK (cached)
# ============================================================
INTERNET_CACHE_TTL=30
INTERNET_CHECK_TIMEOUT=4
INTERNET_DNS_TIMEOUT=2
_internet_last_check=0
_internet_last_result=1

check_internet() {
    local now; now=$(date +%s)
    if [ "$_internet_last_result" -eq 0 ]; then
        local age=$((now - _internet_last_check))
        [ "$age" -lt "$INTERNET_CACHE_TTL" ] && return 0
    fi
    if ! timeout "$INTERNET_DNS_TIMEOUT" getent hosts one.one.one.one >/dev/null 2>&1; then
        if ! timeout "$INTERNET_DNS_TIMEOUT" bash -c 'exec 3<>/dev/tcp/1.1.1.1/443' 2>/dev/null; then
            _internet_last_check=$now; _internet_last_result=1; return 1
        fi
    fi
    local endpoints=(
        "https://1.1.1.1"
        "https://www.google.com/generate_204"
        "https://www.cloudflare.com/cdn-cgi/trace"
    )
    local pids=() tmpdir; tmpdir=$(mktemp -d)
    local i=0
    for endpoint in "${endpoints[@]}"; do
        (
            if curl -fsI --connect-timeout 2 --max-time "$INTERNET_CHECK_TIMEOUT" \
                --no-keepalive -H "User-Agent: Mozilla/5.0" \
                "$endpoint" >/dev/null 2>&1; then
                echo "ok" > "$tmpdir/result_$i"
            fi
        ) &
        pids+=($!)
        i=$((i + 1))
    done
    local success=1
    for _ in $(seq 1 "$INTERNET_CHECK_TIMEOUT"); do
        for f in "$tmpdir"/result_*; do
            if [ -f "$f" ] && [ "$(cat "$f")" = "ok" ]; then
                success=0
                break 2
            fi
        done
        sleep 0.5
    done
    kill "${pids[@]}" 2>/dev/null
    wait "${pids[@]}" 2>/dev/null
    rm -rf "$tmpdir"
    _internet_last_check=$now
    _internet_last_result=$success
    return $success
}

# ============================================================
# HISTORY MANAGEMENT
# ============================================================
touch "$HISTORY_FILE"
declare -A HISTORY_CACHE

load_history() {
    HISTORY_CACHE=()
    local count=0
    if [ -f "$HISTORY_FILE" ]; then
        while IFS= read -r url; do
            if [ -n "$url" ]; then
                HISTORY_CACHE["$url"]=1
                ((count++))
            fi
        done < "$HISTORY_FILE"
    fi
    echo "$(date) - Loaded $count history entries into cache" >> "$LOGFILE"
}
load_history

add_to_history() {
    local key="$1"
    [ -z "$key" ] && return 1

    HISTORY_CACHE["$key"]=1
    echo "$key" >> "$HISTORY_FILE"

    local line_count
    line_count=$(wc -l < "$HISTORY_FILE" 2>/dev/null || echo 0)
    if [ "$line_count" -gt "$((HISTORY_SIZE * 2))" ]; then
        tail -n "$HISTORY_SIZE" "$HISTORY_FILE" > "$HISTORY_FILE.tmp" && \
            mv "$HISTORY_FILE.tmp" "$HISTORY_FILE"
        echo "$(date) - Trimmed history to $HISTORY_SIZE entries" >> "$LOGFILE"
        load_history
    fi
    return 0
}

is_in_history() {
    local key="$1"
    [ -z "$key" ] && return 2
    if [[ ${HISTORY_CACHE["$key"]+_} ]]; then
        return 0
    fi
    return 1
}

# ============================================================
# OUTPUT DETECTION
#
# Returns one Wayland output name per line (e.g. HDMI-A-1, eDP-1, DP-1).
# Prefers wlr-randr for authoritative Wayland-side enumeration; falls
# back to reading DRM connector status directly from sysfs.
# ============================================================
get_outputs() {
    if command -v wlr-randr >/dev/null 2>&1; then
        # `wlr-randr` output: first column of each top-level line is the name
        local out
        out=$(wlr-randr 2>/dev/null | awk '/^[^ \t]/ {print $1}')
        if [ -n "$out" ]; then
            printf '%s\n' "$out"
            return 0
        fi
    fi
    # Fallback: /sys/class/drm/cardN-CONNECTOR/status
    local s d
    for s in /sys/class/drm/card*-*/status; do
        [ -f "$s" ] || continue
        if [ "$(cat "$s" 2>/dev/null)" = "connected" ]; then
            d=$(dirname "$s")
            printf '%s\n' "${d##*/}" | sed 's/^card[0-9]*-//'
        fi
    done
}

# ============================================================
# APPLY VIDEO WALLPAPER — via mpvpaper, one process per output
#
# mpvpaper attaches to the wlr-layer-shell background layer on
# each output and decodes the video independently. This is what
# makes multi-screen playback work where the KDE video wallpaper
# plugin would only animate one screen at a time.
# ============================================================
apply_video_wallpaper() {
    local video_path="$1"
    [ -f "$video_path" ] || return 1

    # Kill any previous mpvpaper instances so we don't stack processes
    pkill -x mpvpaper 2>/dev/null
    sleep 0.5

    local outputs
    outputs=$(get_outputs)
    if [ -z "$outputs" ]; then
        echo "$(date) - [Pixabay] No connected outputs detected" >> "$LOGFILE"
        return 1
    fi

    local n=0
    while IFS= read -r out; do
        [ -z "$out" ] && continue
        mpvpaper -o "$MPVPAPER_OPTS" "$out" "$video_path" >/dev/null 2>&1 &
        n=$((n + 1))
    done <<< "$outputs"

    # Give mpvpaper a moment to attach
    sleep 1

    if ! pgrep -x mpvpaper >/dev/null 2>&1; then
        echo "$(date) - [Pixabay] mpvpaper died immediately after launch" >> "$LOGFILE"
        return 1
    fi

    local running
    running=$(pgrep -xc mpvpaper 2>/dev/null || echo 0)
    echo "$(date) - [Pixabay] mpvpaper active: $running process(es) for $n output(s): $(echo "$outputs" | tr '\n' ' ')" >> "$LOGFILE"
    return 0
}

# ============================================================
# QUERY ROTATION (shuffle bag)
#
# - SHUFFLED_QUERIES holds the current cycle's random order.
# - QUERY_INDEX points at the next item to consume.
# - advance_query_index() moves the pointer and reshuffles when the
#   bag is exhausted. Called on success and on "no suitable hits".
# - Downstream failures (download/apply) do NOT advance — the same
#   query retries next cycle.
# ============================================================
declare -a SHUFFLED_QUERIES=()
QUERY_INDEX=0

shuffle_queries() {
    mapfile -t SHUFFLED_QUERIES < <(printf '%s\n' "${PIXABAY_QUERIES[@]}" | shuf)
    QUERY_INDEX=0
    echo "$(date) - [Pixabay] Reshuffled ${#SHUFFLED_QUERIES[@]} queries" >> "$LOGFILE"
}
shuffle_queries

advance_query_index() {
    QUERY_INDEX=$((QUERY_INDEX + 1))
    if [ "$QUERY_INDEX" -ge "${#SHUFFLED_QUERIES[@]}" ]; then
        echo "$(date) - [Pixabay] Finished query cycle. Reshuffling..." >> "$LOGFILE"
        shuffle_queries
    fi
}

# ============================================================
# PIXABAY FETCHER
# ============================================================
fetch_pixabay() {
    local query="${SHUFFLED_QUERIES[$QUERY_INDEX]}"
    echo "$(date) - [Pixabay] Query: '$query' (slot $((QUERY_INDEX + 1))/${#SHUFFLED_QUERIES[@]})" >> "$LOGFILE"

    # --- Build API URL from prefixed query ---
    local api_url
    case "$query" in
        category:*)
            local cat="${query#category:}"
            api_url="https://pixabay.com/api/videos/?key=${PIXABAY_API_KEY}&category=${cat}&video_type=film&min_width=${PIXABAY_VIDEO_MIN_WIDTH}&per_page=${PIXABAY_PER_PAGE}&safesearch=true"
            ;;
        term:*)
            local t="${query#term:}"
            local enc
            enc=$(printf '%s' "$t" | jq -sRr @uri)
            api_url="https://pixabay.com/api/videos/?key=${PIXABAY_API_KEY}&q=${enc}&video_type=film&min_width=${PIXABAY_VIDEO_MIN_WIDTH}&per_page=${PIXABAY_PER_PAGE}&safesearch=true"
            ;;
        *)
            echo "$(date) - [Pixabay] Malformed query: '$query' — advancing" >> "$LOGFILE"
            advance_query_index
            return 1
            ;;
    esac

    local response
    response=$(curl -sS --max-time 15 "$api_url")
    if [ -z "$response" ]; then
        # Empty curl response is transient; do NOT advance (retry next cycle).
        echo "$(date) - [Pixabay] Empty API response for '$query'" >> "$LOGFILE"
        return 1
    fi

    local hits
    hits=$(printf '%s' "$response" | jq -r "
        .hits[]
        | select(.videos.large.width > .videos.large.height)
        | select(.duration >= ${PIXABAY_VIDEO_MIN_DURATION} and .duration <= ${PIXABAY_VIDEO_MAX_DURATION})
        | \"\(.id)\t\(.videos.large.url)\"
    ")

    if [ -z "$hits" ]; then
        # Query yielded nothing usable — advance.
        echo "$(date) - [Pixabay] No suitable videos for '$query' — advancing" >> "$LOGFILE"
        advance_query_index
        return 1
    fi

    local hit_count
    hit_count=$(printf '%s\n' "$hits" | wc -l)
    echo "$(date) - [Pixabay] $hit_count landscape clips after filter" >> "$LOGFILE"

    # --- Pick first unseen, else uniform random repeat ---
    local chosen_id="" chosen_url=""
    while IFS=$'\t' read -r id url; do
        [ -z "$id" ] && continue
        if ! is_in_history "pixabay://${id}"; then
            chosen_id="$id"
            chosen_url="$url"
            break
        fi
    done <<< "$hits"

    if [ -z "$chosen_id" ]; then
        local line
        line=$(printf '%s\n' "$hits" | shuf | head -1)
        chosen_id="${line%%$'\t'*}"
        chosen_url="${line#*$'\t'}"
        echo "$(date) - [Pixabay] All seen for '$query', using repeat: $chosen_id" >> "$LOGFILE"
    fi

    [ -z "$chosen_id" ] && { echo "$(date) - [Pixabay] No candidate id" >> "$LOGFILE"; return 1; }

    # --- Download if not cached ---
    mkdir -p "$LIVE_WALLPAPER_DIR"
    local out_file="$LIVE_WALLPAPER_DIR/pixabay-${chosen_id}.mp4"

    if [ ! -f "$out_file" ] || [ "$(stat -c%s "$out_file" 2>/dev/null || echo 0)" -lt 100000 ]; then
        echo "$(date) - [Pixabay] Downloading $chosen_id..." >> "$LOGFILE"
        if ! timeout 90 curl -sSL -o "$out_file.tmp" "$chosen_url"; then
            echo "$(date) - [Pixabay] Download failed — will retry same query next cycle" >> "$LOGFILE"
            rm -f "$out_file.tmp"
            return 1     # do NOT advance
        fi
        mv "$out_file.tmp" "$out_file"
    fi

    local size
    size=$(stat -c%s "$out_file" 2>/dev/null || echo 0)
    if [ "$size" -lt 100000 ]; then
        echo "$(date) - [Pixabay] File too small ($size bytes) — will retry next cycle" >> "$LOGFILE"
        rm -f "$out_file"
        return 1     # do NOT advance
    fi

    # --- Apply — this is the success site; advance on 0 ---
    if apply_video_wallpaper "$out_file"; then
        add_to_history "pixabay://${chosen_id}"
        echo "$(date) - [Pixabay] Applied '$query' (id=$chosen_id, ${size} bytes)" >> "$LOGFILE"

        # Prune old videos (keep MAX_LIVE_WALLPAPERS newest)
        find "$LIVE_WALLPAPER_DIR" -name 'pixabay-*.mp4' -type f -printf '%T@ %p\n' 2>/dev/null \
            | sort -rn | tail -n +$((MAX_LIVE_WALLPAPERS + 1)) | cut -d' ' -f2- \
            | xargs -r rm -f

        advance_query_index
        return 0
    else
        echo "$(date) - [Pixabay] Apply failed — will retry same query next cycle" >> "$LOGFILE"
        return 1     # do NOT advance
    fi
}

# ============================================================
# CLEANUP ON EXIT — kill mpvpaper when the script stops
# ============================================================
cleanup_mpvpaper() {
    pkill -x mpvpaper 2>/dev/null || true
}
trap 'ec=$?; cleanup_mpvpaper; echo "$(date) - SCRIPT EXITING (code=$ec)" >> "$LOGFILE"; flock -u 9; exec 9>&-' EXIT

# ============================================================
# MAIN LOOP
# ============================================================
IS_ONLINE=false

while true; do
    echo "$(date) - heartbeat (pid=$$)" >> "$LOGFILE"
    rotate_log

    if ! check_internet; then
        if [ "$IS_ONLINE" = true ]; then
            echo "$(date) - Internet lost — rotation suspended" >> "$LOGFILE"
            IS_ONLINE=false
        fi
        echo "$(date) - [Offline] Waiting for connectivity" >> "$LOGFILE"
        sleep "$SLEEP_INTERVAL"
        continue
    fi

    if [ "$IS_ONLINE" = false ]; then
        echo "$(date) - Internet restored" >> "$LOGFILE"
        IS_ONLINE=true
    fi

    if fetch_pixabay; then
        sleep "$SLEEP_INTERVAL"
    else
        echo "$(date) - Pixabay fetch failed, retrying in 30s" >> "$LOGFILE"
        sleep 30
    fi

    # Periodic history reload
    if [ $((RANDOM % 50)) -eq 0 ]; then
        load_history
        echo "$(date) - Periodic history cache reloaded" >> "$LOGFILE"
    fi
done
