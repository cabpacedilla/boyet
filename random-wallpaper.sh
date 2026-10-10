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
HISTORY_SIZE=500000
SEARCH_LIMIT=100
SLEEP_INTERVAL=60
DEVIOUSQ_TIMEOUT=30
WGET_TIMEOUT=15
WGET_TOTAL_TIMEOUT=30
MAX_RETRIES=3
LOG_MAX_SIZE=10485760
LOG_RETENTION_DAYS=30

DEVIANTART_WEIGHT=30
VARIETY_WEIGHT=10
PIXABAY_WEIGHT=30
BING_WEIGHT=10

# MAX_SAME_SOURCE caps *successful consecutive picks of the same source*
# while ONLINE. Deliberate exception: while OFFLINE, Variety is the only
# reachable source, so the cap is not enforced offline.
MAX_SAME_SOURCE=3

# --- Pixabay ---
PIXABAY_API_KEY="${PIXABAY_API_KEY:-}"
PIXABAY_IMAGE_MIN_WIDTH=1920
PIXABAY_IMAGE_MIN_HEIGHT=1080
PIXABAY_PER_PAGE=50
PIXABAY_API_TIMEOUT=15
PIXABAY_DL_TIMEOUT=20
PIXABAY_DL_TOTAL_TIMEOUT=45

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

# --- Bing ---
BING_MAX_AGE_DAYS=7
BING_API_TIMEOUT=10
BING_DL_TIMEOUT=20
BING_DL_TOTAL_TIMEOUT=45

BING_MARKETS=(
    "en-US" "en-GB" "en-AU" "en-CA" "en-IN" "en-NZ" "en-ZA"
    "de-DE" "fr-FR" "es-ES" "it-IT" "pt-BR" "pt-PT" "nl-NL"
    "sv-SE" "no-NO" "da-DK" "fi-FI" "pl-PL" "tr-TR" "ru-RU"
    "el-GR" "cs-CZ" "hu-HU" "ro-RO" "uk-UA"
)

BING_ASIA_MARKETS=(
    "ja-JP" "zh-CN" "zh-TW" "zh-HK" "ko-KR"
    "hi-IN" "th-TH" "vi-VN" "id-ID" "ms-MY" "fil-PH"
)

# ============================================================
# PATHS & SETUP
# ============================================================
HISTORY_FILE="$HOME/scriptlogs/wallpaper_history.txt"
LOGFILE="$HOME/scriptlogs/wallpaper.log"
LOCK_FILE="$HOME/.cache/random_wallpaper.lock"

mkdir -p "$HOME/scriptlogs" "$(dirname "$LOCK_FILE")"

# ============================================================
# LOG ROTATION
# ============================================================
rotate_log() {
    if [ -f "$LOGFILE" ]; then
        local size
        size=$(stat -c%s "$LOGFILE" 2>/dev/null || echo 0)
        if [ "${size:-0}" -gt "$LOG_MAX_SIZE" ]; then
            mv "$LOGFILE" "$LOGFILE.$(date +%Y%m%d_%H%M%S)"
            echo "$(date) - Log rotated (was ${size} bytes)" > "$LOGFILE"
        fi
    fi
    find "$HOME/scriptlogs" -name 'wallpaper.log.*' -mtime +"$LOG_RETENTION_DAYS" -delete 2>/dev/null || true
}
rotate_log

# ============================================================
# SINGLE-INSTANCE LOCK + TEMP-FILE + PROBE + VARIETY CLEANUP
# ============================================================
CURRENT_TEMP=""
_PROBE_TMPDIR=""
_PROBE_PIDS=()      # each PID is also its PGID (probes run under setsid)
_VARIETY_PAUSED_BY_SCRIPT=false

# Idempotent probe cleanup. Each probe was launched under `setsid`,
# so its PID is also its PGID — TERM/KILL to -$pid signals the entire
# process group, which includes the curl child.
#
# Caveats (documented, not guaranteed by this script):
#   * TERM/KILL "terminate" the group; this script does not individually
#     reap every descendant. The subshell (session leader) is reaped by
#     `wait`; curl descendants are reparented and reaped by init.
#   * Very short PID-reuse race exists between the probe's exit and the
#     signal. Bounded by the short grace window; practically negligible.
#   * The early DNS/TCP pre-checks in check_internet are SYNCHRONOUS,
#     each individually bounded by `timeout` — see the comment there.
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

# Attempt to restore Variety and verify *some* matching process is up.
# CONTRACT: this checks that at least one `variety` process is running
# after the launch attempt. It does not verify that the specific PID we
# spawned is the one alive — another process starting Variety during
# the readiness window would satisfy this check. That is sufficient
# for this script's purpose (Variety is running again), but callers
# must not assume instance-level ownership.
# Bounded: waits at most ~2 seconds.
_restore_variety_verified() {
    variety >/dev/null 2>&1 &
    sleep 2
    if [ -z "$(variety_pids)" ]; then
        return 1
    fi
    _VARIETY_PAUSED_BY_SCRIPT=false
    return 0
}

cleanup_on_exit() {
    local ec=$?
    cleanup_probes
    if [[ -n "${CURRENT_TEMP:-}" && -f "$CURRENT_TEMP" ]]; then
        rm -f "$CURRENT_TEMP" 2>/dev/null || true
    fi
    if [ "$_VARIETY_PAUSED_BY_SCRIPT" = true ] \
        && [ "${VARIETY_WEIGHT:-0}" -gt 0 ] \
        && [ -z "$(variety_pids)" ]; then
        if _restore_variety_verified; then
            echo "$(date) - Restored Variety on exit" >> "$LOGFILE"
        else
            echo "$(date) - WARNING: failed to restore Variety on exit" >> "$LOGFILE"
        fi
    fi
    echo "$(date) - SCRIPT EXITING (code=$ec)" >> "$LOGFILE"
    flock -u 9 2>/dev/null || true
    exec 9>&- 2>/dev/null || true
}

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "$(date) - Another instance is already running. Exiting." >> "$LOGFILE"
    exit 1
fi
trap cleanup_on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

echo "$(date) - Random Wallpaper Script Started" >> "$LOGFILE"
echo "$(date) - Weights: DA=$DEVIANTART_WEIGHT Variety=$VARIETY_WEIGHT Pixabay=$PIXABAY_WEIGHT Bing=$BING_WEIGHT" >> "$LOGFILE"

# ============================================================
# MIME VALIDATION HELPER
# ============================================================
is_valid_image_file() {
    local path="$1"
    local mime
    mime=$(file --mime-type -b "$path" 2>/dev/null) || return 1
    [[ "$mime" == image/* ]]
}

# ============================================================
# DEPENDENCY CHECK
# ============================================================
for cmd in flock timeout curl wget file stat awk grep head tail shuf \
           mktemp df pgrep pkill find date wc cat sed seq setsid; do
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

if [ "$VARIETY_WEIGHT" -gt 0 ] && ! command -v variety >/dev/null 2>&1; then
    echo "$(date) - WARNING: variety not found — disabling Variety" >> "$LOGFILE"
    VARIETY_WEIGHT=0
fi

if [ "$PIXABAY_WEIGHT" -gt 0 ]; then
    if [ -z "$PIXABAY_API_KEY" ]; then
        echo "$(date) - WARNING: PIXABAY_API_KEY not set — disabling Pixabay" >> "$LOGFILE"
        PIXABAY_WEIGHT=0
    else
        if ! command -v jq >/dev/null 2>&1; then
            echo "$(date) - WARNING: jq not found — disabling Pixabay" >> "$LOGFILE"
            PIXABAY_WEIGHT=0
        fi
    fi
fi

if [ "$BING_WEIGHT" -gt 0 ]; then
    if ! command -v jq >/dev/null 2>&1; then
        echo "$(date) - WARNING: jq not found — disabling Bing" >> "$LOGFILE"
        BING_WEIGHT=0
    fi
fi

if [ "$DEVIANTART_WEIGHT" -eq 0 ] && [ "$PIXABAY_WEIGHT" -eq 0 ] \
   && [ "$VARIETY_WEIGHT" -eq 0 ] && [ "$BING_WEIGHT" -eq 0 ]; then
    echo "$(date) - ERROR: no enabled sources" >> "$LOGFILE"
    echo "ERROR: no enabled sources" >&2
    exit 1
fi

# ============================================================
# INTERNET CHECK
# ============================================================
INTERNET_CACHE_TTL=30
INTERNET_CHECK_TIMEOUT=4
INTERNET_DNS_TIMEOUT=2

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

    # Synchronous pre-checks. Each is INDIVIDUALLY bounded by `timeout`;
    # there is no strict end-to-end deadline for the pair. Worst case is
    # roughly 2 * INTERNET_DNS_TIMEOUT = 4s plus process-startup overhead.
    # They run in the foreground, so they cannot outlive this shell — the
    # exit trap does not need to track them.
    if ! timeout "$INTERNET_DNS_TIMEOUT" getent hosts one.one.one.one >/dev/null 2>&1; then
        if ! timeout "$INTERNET_DNS_TIMEOUT" bash -c 'exec 3<>/dev/tcp/1.1.1.1/443' 2>/dev/null; then
            _internet_last_check=$now
            _internet_last_result=1
            return 1
        fi
    fi

    local endpoints=(
        "https://1.1.1.1"
        "https://www.google.com/generate_204"
        "https://www.cloudflare.com/cdn-cgi/trace"
    )

    local tmpdir
    tmpdir=$(mktemp -d) || {
        _internet_last_check=$now
        _internet_last_result=1
        return 1
    }
    _PROBE_TMPDIR="$tmpdir"
    _PROBE_PIDS=()

    # Each probe runs under setsid so its PID is its PGID. Verify on
    # Nobara with: ps -o pid,pgid,sid,cmd -p $pid
    # (expect pid == pgid == sid for the bash probe).
    local i=0
    for endpoint in "${endpoints[@]}"; do
        setsid bash -c "
            if curl -fsI \
                --connect-timeout 2 \
                --max-time $INTERNET_CHECK_TIMEOUT \
                --no-keepalive \
                -H 'User-Agent: Mozilla/5.0' \
                '$endpoint' >/dev/null 2>&1; then
                echo ok > '$tmpdir/result_$i'
            fi
        " &
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
# Variety is a full wallpaper application with its own random
# rotation logic configured in its GUI. The script only:
#   1. Ensures the app is running.
#   2. Asks it to advance to its next pick.
#   3. Reports success/failure.
#
# OWNERSHIP NOTE: stop_variety terminates whatever `variety` process is
# running, regardless of who launched it. This is intentional — Variety
# would otherwise overwrite the wallpaper we just set. We only *restart*
# Variety from cleanup_on_exit if we ourselves paused it and it is no
# longer running.
variety_pids() {
    pgrep -f '(^|/)variety( |$)' 2>/dev/null
}

stop_variety() {
    local pids pid
    pids=$(variety_pids)
    if [ -z "$pids" ]; then
        _VARIETY_PAUSED_BY_SCRIPT=false
        return 1
    fi
    while IFS= read -r pid; do
        [ -n "$pid" ] && kill -TERM "$pid" 2>/dev/null || true
    done <<< "$pids"
    sleep 1
    pids=$(variety_pids)
    if [ -n "$pids" ]; then
        while IFS= read -r pid; do
            [ -n "$pid" ] && kill -KILL "$pid" 2>/dev/null || true
        done <<< "$pids"
        sleep 0.5
    fi
    if [ -z "$(variety_pids)" ]; then
        _VARIETY_PAUSED_BY_SCRIPT=true
        echo "$(date) - Stopped Variety process(es)" >> "$LOGFILE"
        return 0
    fi
    _VARIETY_PAUSED_BY_SCRIPT=false
    echo "$(date) - Failed to stop Variety (still running after TERM+KILL)" >> "$LOGFILE"
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

use_variety() {
    if ! command -v variety >/dev/null 2>&1; then
        echo "$(date) - Variety not installed" >> "$LOGFILE"
        return 1
    fi

    if [ -z "$(variety_pids)" ]; then
        start_variety
    fi

    if variety --next >/dev/null 2>&1; then
        echo "$(date) - Variety rotated (its own random pick)" >> "$LOGFILE"
        return 0
    fi

    echo "$(date) - Variety rotation failed" >> "$LOGFILE"
    return 1
}

# Pause Variety for an external fetch.
#
# CRITICAL: must be called DIRECTLY, not via $(...). The function relies
# on stop_variety mutating _VARIETY_PAUSED_BY_SCRIPT in the CURRENT
# shell — a subshell would discard that change and the EXIT trap would
# not know Variety is paused.
#
# Result is communicated via the global VARIETY_WAS_RUNNING:
#   * returns 0 and VARIETY_WAS_RUNNING=false → Variety was not running,
#     nothing to restore
#   * returns 0 and VARIETY_WAS_RUNNING=true  → Variety was running and
#     was successfully stopped
#   * returns non-zero                        → Variety was running but
#     could not be stopped; caller must abort
_prepare_variety_pause() {
    VARIETY_WAS_RUNNING=false

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

declare -a SHUFFLED_BING_QUERIES=()
BING_QUERY_INDEX=0

shuffle_bing_queries() {
    local -a all=()
    local mkt idx

    for mkt in "${BING_MARKETS[@]}"; do
        for idx in $(seq 0 "$BING_MAX_AGE_DAYS"); do
            all+=("official|${mkt}|${idx}")
        done
    done

    for mkt in "${BING_ASIA_MARKETS[@]}"; do
        for idx in $(seq 0 "$BING_MAX_AGE_DAYS"); do
            all+=("asia|${mkt}|${idx}")
        done
    done

    all+=("community")

    mapfile -t SHUFFLED_BING_QUERIES < <(printf '%s\n' "${all[@]}" | shuf)
    BING_QUERY_INDEX=0
    echo "$(date) - [Bing] Reshuffled ${#SHUFFLED_BING_QUERIES[@]} queries" >> "$LOGFILE"
}
shuffle_bing_queries

advance_bing_query() {
    BING_QUERY_INDEX=$((BING_QUERY_INDEX + 1))
    if [ "$BING_QUERY_INDEX" -ge "${#SHUFFLED_BING_QUERIES[@]}" ]; then
        echo "$(date) - [Bing] Finished query cycle. Reshuffling..." >> "$LOGFILE"
        shuffle_bing_queries
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
    [ "$BING_WEIGHT"       -gt 0 ] && { names+=("bing");       weights+=("$BING_WEIGHT"); }

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
    echo "$(date) - [Sources] Reshuffled deck of ${#SHUFFLED_SOURCES[@]} slots (weights DA=$DEVIANTART_WEIGHT Var=$VARIETY_WEIGHT Pix=$PIXABAY_WEIGHT Bing=$BING_WEIGHT)" >> "$LOGFILE"
}
build_source_deck

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
    local url="$1"
    if [ -z "$url" ]; then
        return 1
    fi

    HISTORY_CACHE["$url"]=1
    echo "$url" >> "$HISTORY_FILE"

    local line_count
    line_count=$(wc -l < "$HISTORY_FILE" 2>/dev/null || echo 0)
    if [ "$line_count" -gt "$((HISTORY_SIZE * 2))" ]; then
        tail -n "$HISTORY_SIZE" "$HISTORY_FILE" > "$HISTORY_FILE.tmp" && mv "$HISTORY_FILE.tmp" "$HISTORY_FILE"
        echo "$(date) - Trimmed history to $HISTORY_SIZE entries" >> "$LOGFILE"
        load_history
    fi

    return 0
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

# ============================================================
# DEVIANTART FETCHER
# ============================================================
fetch_deviantart() {
    [ "$DEVIANTART_WEIGHT" -le 0 ] && return 1

    # NOTE: _prepare_variety_pause is called directly (not via $()).
    # Its result is read from $VARIETY_WAS_RUNNING after the call.
    if ! _prepare_variety_pause; then
        echo "$(date) - [DeviantArt] Aborting: Variety still running" >> "$LOGFILE"
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

        URL_LIST=$(timeout --kill-after=5s "${DEVIOUSQ_TIMEOUT}s" deviousq \
            --medium image \
            --rating nonadult \
            --return-field content_url \
            --limit "$SEARCH_LIMIT" \
            "$current_category" \
            2>/dev/null)

        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            echo "$(date) - [DeviantArt] ERROR: deviousq timed out" >> "$LOGFILE"
            URL_LIST=""
        fi

        RETRY_COUNT=$((RETRY_COUNT + 1))
    done

    if [ -z "$URL_LIST" ]; then
        echo "$(date) - [DeviantArt] No results after $MAX_RETRIES attempts — advancing category" >> "$LOGFILE"
        advance_category
        [ "$variety_was_running" = true ] && [ "$VARIETY_WEIGHT" -gt 0 ] && start_variety
        return 1
    fi

    local VALID_URLS
    VALID_URLS=$(printf '%s\n' "$URL_LIST" | grep -E '^https?://' | head -100)

    if [ -z "$VALID_URLS" ]; then
        echo "$(date) - [DeviantArt] No valid URLs found — advancing category" >> "$LOGFILE"
        advance_category
        [ "$variety_was_running" = true ] && [ "$VARIETY_WEIGHT" -gt 0 ] && start_variety
        return 1
    fi

    local URL_COUNT
    URL_COUNT=$(printf '%s\n' "$VALID_URLS" | wc -l)
    echo "$(date) - [DeviantArt] Found $URL_COUNT URLs" >> "$LOGFILE"

    local RANDOM_URL=""
    local SHUFFLED_URLS
    mapfile -t SHUFFLED_URLS < <(printf '%s\n' "$VALID_URLS" | shuf)

    for url in "${SHUFFLED_URLS[@]}"; do
        if ! is_in_history "$url"; then
            RANDOM_URL="$url"
            echo "$(date) - [DeviantArt] Found unseen URL" >> "$LOGFILE"
            break
        fi
    done

    if [ -z "$RANDOM_URL" ]; then
        RANDOM_URL="${SHUFFLED_URLS[$((RANDOM % ${#SHUFFLED_URLS[@]}))]}"
        echo "$(date) - [DeviantArt] WARNING: Using random repeat" >> "$LOGFILE"
    fi

    local WALLPAPER_FILE
    WALLPAPER_FILE=$(mktemp /tmp/wallpaper_XXXXXX.jpg) || {
        advance_category
        [ "$variety_was_running" = true ] && [ "$VARIETY_WEIGHT" -gt 0 ] && start_variety
        return 1
    }
    CURRENT_TEMP="$WALLPAPER_FILE"

    echo "$(date) - [DeviantArt] Downloading..." >> "$LOGFILE"

    local AVAILABLE
    AVAILABLE=$(df -k /tmp 2>/dev/null | awk 'NR==2 {print $4}')
    if [ -n "$AVAILABLE" ] && [ "$AVAILABLE" -lt 10240 ]; then
        echo "$(date) - WARNING: Low disk space in /tmp" >> "$LOGFILE"
        find /tmp -name "wallpaper_*" -mmin +5 -delete 2>/dev/null
    fi

    local success=false

    if timeout "${WGET_TOTAL_TIMEOUT}s" wget -q --timeout="${WGET_TIMEOUT}" \
        -O "$WALLPAPER_FILE" "$RANDOM_URL" 2>/dev/null; then

        local file_type=""
        local file_size=0
        local validation_ok=false

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
            echo "$(date) - [DeviantArt] ERROR: Not a valid image (detected: ${file_type:-unknown})" >> "$LOGFILE"
        fi

        if [ "$validation_ok" = true ] && command -v identify >/dev/null 2>&1; then
            if ! identify "$WALLPAPER_FILE" >/dev/null 2>&1; then
                echo "$(date) - [DeviantArt] ERROR: Image failed decoder check" >> "$LOGFILE"
                validation_ok=false
            fi
        fi

        if [ "$validation_ok" = true ]; then
            if plasma-apply-wallpaperimage "$WALLPAPER_FILE" >/dev/null 2>&1; then
                add_to_history "$RANDOM_URL"
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
        CURRENT_TEMP=""
    else
        echo "$(date) - [DeviantArt] ERROR: Download failed — advancing category" >> "$LOGFILE"
        rm -f "$WALLPAPER_FILE"
        CURRENT_TEMP=""
        advance_category
    fi

    if [ "$variety_was_running" = true ] && [ "$VARIETY_WEIGHT" -gt 0 ] && [ "$success" != true ]; then
        start_variety
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
        echo "$(date) - [Pixabay] Aborting: Variety still running" >> "$LOGFILE"
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
            [ "$variety_was_running" = true ] && [ "$VARIETY_WEIGHT" -gt 0 ] && start_variety
            return 1
            ;;
    esac

    local response
    response=$(curl -sS --fail --max-time "$PIXABAY_API_TIMEOUT" "$api_url" 2>/dev/null)
    local curl_rc=$?

    if [ $curl_rc -ne 0 ]; then
        echo "$(date) - [Pixabay] API request failed (curl rc=$curl_rc) for '$query' — advancing" >> "$LOGFILE"
        advance_pixabay_query
        [ "$variety_was_running" = true ] && [ "$VARIETY_WEIGHT" -gt 0 ] && start_variety
        return 1
    fi

    if [ -z "$response" ]; then
        echo "$(date) - [Pixabay] Empty API response for '$query' — advancing" >> "$LOGFILE"
        advance_pixabay_query
        [ "$variety_was_running" = true ] && [ "$VARIETY_WEIGHT" -gt 0 ] && start_variety
        return 1
    fi

    if ! printf '%s' "$response" | jq -e 'type == "object" and (.hits | type == "array")' >/dev/null 2>&1; then
        echo "$(date) - [Pixabay] Invalid API response shape — advancing" >> "$LOGFILE"
        advance_pixabay_query
        [ "$variety_was_running" = true ] && [ "$VARIETY_WEIGHT" -gt 0 ] && start_variety
        return 1
    fi

    local hits
    hits=$(printf '%s' "$response" | jq -r '
        .hits[]
        | select(.largeImageURL != null)
        | select(.imageWidth  >= '"$PIXABAY_IMAGE_MIN_WIDTH"')
        | select(.imageHeight >= '"$PIXABAY_IMAGE_MIN_HEIGHT"')
        | "\(.id)\t\(.largeImageURL)"
    ')

    if [ -z "$hits" ]; then
        echo "$(date) - [Pixabay] No suitable images for '$query' — advancing" >> "$LOGFILE"
        advance_pixabay_query
        [ "$variety_was_running" = true ] && [ "$VARIETY_WEIGHT" -gt 0 ] && start_variety
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
        if ! is_in_history "pixabay://${id}"; then
            chosen_id="$id"
            chosen_url="$url"
            break
        fi
    done <<< "$shuffled_hits"

    if [ -z "$chosen_id" ]; then
        local line
        line=$(printf '%s\n' "$shuffled_hits" | head -1)
        chosen_id="${line%%$'\t'*}"
        chosen_url="${line#*$'\t'}"
        echo "$(date) - [Pixabay] All seen for '$query', using repeat: $chosen_id" >> "$LOGFILE"
    fi

    [ -z "$chosen_id" ] && {
        advance_pixabay_query
        [ "$variety_was_running" = true ] && [ "$VARIETY_WEIGHT" -gt 0 ] && start_variety
        return 1
    }

    local WALLPAPER_FILE
    WALLPAPER_FILE=$(mktemp /tmp/pixabay_XXXXXX.jpg) || {
        advance_pixabay_query
        [ "$variety_was_running" = true ] && [ "$VARIETY_WEIGHT" -gt 0 ] && start_variety
        return 1
    }
    CURRENT_TEMP="$WALLPAPER_FILE"
    echo "$(date) - [Pixabay] Downloading $chosen_id..." >> "$LOGFILE"

    local success=false
    if timeout "${PIXABAY_DL_TOTAL_TIMEOUT}s" curl -sSL --max-time "${PIXABAY_DL_TIMEOUT}" \
        -o "$WALLPAPER_FILE" "$chosen_url"; then

        local file_type=""
        local file_size=0
        local validation_ok=false

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
            echo "$(date) - [Pixabay] ERROR: Not a valid image (detected: ${file_type:-unknown})" >> "$LOGFILE"
        fi

        if [ "$validation_ok" = true ] && command -v identify >/dev/null 2>&1; then
            if ! identify "$WALLPAPER_FILE" >/dev/null 2>&1; then
                echo "$(date) - [Pixabay] ERROR: Image failed decoder check" >> "$LOGFILE"
                validation_ok=false
            fi
        fi

        if [ "$validation_ok" = true ]; then
            if plasma-apply-wallpaperimage "$WALLPAPER_FILE" >/dev/null 2>&1; then
                add_to_history "pixabay://${chosen_id}"
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
        CURRENT_TEMP=""
    else
        echo "$(date) - [Pixabay] ERROR: Download failed — advancing query to avoid retrying same URL" >> "$LOGFILE"
        rm -f "$WALLPAPER_FILE"
        CURRENT_TEMP=""
        advance_pixabay_query
    fi

    if [ "$variety_was_running" = true ] && [ "$VARIETY_WEIGHT" -gt 0 ] && [ "$success" != true ]; then
        start_variety
        echo "$(date) - [Pixabay] Restarted Variety after failure" >> "$LOGFILE"
    fi

    [ "$success" = true ] && return 0 || return 1
}

# ============================================================
# BING FETCHER  (official + asia + community)
# ============================================================
_bing_history_key() {
    local url="$1"
    local key
    key=$(printf '%s' "$url" \
        | sed -E 's#^.*[?&]id=([^&]+).*$#\1#; s#\.jpg.*$##; s#_(UHD|[0-9]+x[0-9]+)$##')
    printf 'bing://%s' "$key"
}

_bing_try() {
    local entry="$1"
    local sub mkt idx
    IFS='|' read -r sub mkt idx <<< "$entry"

    local image_url="" source_label=""

    case "$sub" in
        official)
            local response
            response=$(curl -sSL --fail --max-time "$BING_API_TIMEOUT" \
                "https://www.bing.com/HPImageArchive.aspx?format=js&idx=${idx}&n=1&mkt=${mkt}" 2>/dev/null)
            [ -z "$response" ] && { echo "$(date) - [Bing:official] Empty response (mkt=$mkt idx=$idx)" >> "$LOGFILE"; return 1; }
            local urlbase
            urlbase=$(printf '%s' "$response" | jq -r '.images[0].urlbase // empty')
            [ -z "$urlbase" ] && { echo "$(date) - [Bing:official] No urlbase (mkt=$mkt idx=$idx)" >> "$LOGFILE"; return 1; }
            image_url="https://www.bing.com${urlbase}_UHD.jpg"
            source_label="official ($mkt idx=$idx)"
            ;;
        asia)
            local response
            response=$(curl -sSL --fail --max-time "$BING_API_TIMEOUT" \
                "https://www.bing.com/HPImageArchive.aspx?format=js&idx=${idx}&n=1&mkt=${mkt}" 2>/dev/null)
            [ -z "$response" ] && { echo "$(date) - [Bing:asia] Empty response (mkt=$mkt idx=$idx)" >> "$LOGFILE"; return 1; }
            local urlbase
            urlbase=$(printf '%s' "$response" | jq -r '.images[0].urlbase // empty')
            [ -z "$urlbase" ] && { echo "$(date) - [Bing:asia] No urlbase (mkt=$mkt idx=$idx)" >> "$LOGFILE"; return 1; }
            image_url="https://www.bing.com${urlbase}_UHD.jpg"
            source_label="asia ($mkt idx=$idx)"
            ;;
        community)
            local response
            response=$(curl -sSL --fail --max-time "$BING_API_TIMEOUT" \
                "https://bing.biturl.top/?resolution=UHD&index=random&format=json" 2>/dev/null)
            [ -z "$response" ] && { echo "$(date) - [Bing:community] Empty response" >> "$LOGFILE"; return 1; }
            image_url=$(printf '%s' "$response" | jq -r '.url // empty')
            [ -z "$image_url" ] && { echo "$(date) - [Bing:community] No URL" >> "$LOGFILE"; return 1; }
            case "$image_url" in
                https://*) ;;
                *) echo "$(date) - [Bing:community] Rejected non-HTTPS URL: $image_url" >> "$LOGFILE"; return 1 ;;
            esac
            source_label="community"
            ;;
        *) return 1 ;;
    esac

    local history_key
    history_key=$(_bing_history_key "$image_url")

    if is_in_history "$history_key"; then
        echo "$(date) - [Bing:$sub] Already in history ($history_key) — skipping" >> "$LOGFILE"
        return 1
    fi

    echo "$(date) - [Bing:$sub] Chosen $source_label — $image_url" >> "$LOGFILE"

    local WALLPAPER_FILE
    WALLPAPER_FILE=$(mktemp /tmp/bing_XXXXXX.jpg) || return 1
    CURRENT_TEMP="$WALLPAPER_FILE"

    local success=false
    if timeout "${BING_DL_TOTAL_TIMEOUT}s" curl -sSL --fail --max-time "${BING_DL_TIMEOUT}" \
        -o "$WALLPAPER_FILE" "$image_url"; then

        local file_type="" file_size=0 validation_ok=false

        file_type=$(file -b "$WALLPAPER_FILE" 2>/dev/null)
        file_size=$(stat -c%s "$WALLPAPER_FILE" 2>/dev/null || echo 0)
        file_size=${file_size:-0}

        if is_valid_image_file "$WALLPAPER_FILE"; then
            if [ "$file_size" -gt 1024 ]; then
                validation_ok=true
            else
                echo "$(date) - [Bing:$sub] ERROR: File too small (${file_size} bytes)" >> "$LOGFILE"
            fi
        else
            echo "$(date) - [Bing:$sub] ERROR: Not a valid image (detected: ${file_type:-unknown})" >> "$LOGFILE"
        fi

        if [ "$validation_ok" = true ] && command -v identify >/dev/null 2>&1; then
            if ! identify "$WALLPAPER_FILE" >/dev/null 2>&1; then
                echo "$(date) - [Bing:$sub] ERROR: Image failed decoder check" >> "$LOGFILE"
                validation_ok=false
            fi
        fi

        if [ "$validation_ok" = true ]; then
            if plasma-apply-wallpaperimage "$WALLPAPER_FILE" >/dev/null 2>&1; then
                add_to_history "$history_key"
                echo "$(date) - [Bing:$sub] Wallpaper set from $source_label (${file_type}, ${file_size} bytes)" >> "$LOGFILE"
                success=true
            else
                echo "$(date) - [Bing:$sub] ERROR: KDE rejected image" >> "$LOGFILE"
            fi
        fi

        rm -f "$WALLPAPER_FILE"
        CURRENT_TEMP=""
    else
        echo "$(date) - [Bing:$sub] ERROR: Download failed" >> "$LOGFILE"
        rm -f "$WALLPAPER_FILE"
        CURRENT_TEMP=""
    fi

    [ "$success" = true ] && return 0 || return 1
}

fetch_bing() {
    [ "$BING_WEIGHT" -le 0 ] && return 1

    if ! _prepare_variety_pause; then
        echo "$(date) - [Bing] Aborting: Variety still running" >> "$LOGFILE"
        return 1
    fi
    local variety_was_running="$VARIETY_WAS_RUNNING"
    [ "$variety_was_running" = true ] && echo "$(date) - [Bing] Paused Variety for Bing" >> "$LOGFILE"

    local entry="${SHUFFLED_BING_QUERIES[$BING_QUERY_INDEX]}"
    echo "$(date) - [Bing] Slot $((BING_QUERY_INDEX + 1))/${#SHUFFLED_BING_QUERIES[@]}: $entry" >> "$LOGFILE"

    local success=false
    if _bing_try "$entry"; then
        success=true
    fi

    advance_bing_query

    if [ "$variety_was_running" = true ] && [ "$VARIETY_WEIGHT" -gt 0 ] && [ "$success" != true ]; then
        start_variety
        echo "$(date) - [Bing] Restarted Variety after failure" >> "$LOGFILE"
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
    local bg=$BING_WEIGHT

    case "$exclude" in
        deviantart) da=0 ;;
        variety)    va=0 ;;
        pixabay)    px=0 ;;
        bing)       bg=0 ;;
    esac

    local total=$((da + va + px + bg))
    (( total <= 0 )) && { echo ""; return; }

    local rand=$((RANDOM % total))
    if   (( rand < da )); then           echo "deviantart"
    elif (( rand < da + va )); then      echo "variety"
    elif (( rand < da + va + px )); then echo "pixabay"
    else                                 echo "bing"
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
    for s in deviantart variety pixabay bing; do
        [ "$s" = "$exclude" ] && continue
        pool+=("$s")
    done
    printf '%s\n' "${pool[@]}" | shuf
}

try_source() {
    case "$1" in
        deviantart) fetch_deviantart ;;
        pixabay)    fetch_pixabay ;;
        bing)       fetch_bing ;;
        variety)    [ "$VARIETY_WEIGHT" -gt 0 ] && use_variety || return 1 ;;
        *)          return 1 ;;
    esac
}

is_source_enabled() {
    case "$1" in
        deviantart) [ "$DEVIANTART_WEIGHT" -gt 0 ] ;;
        pixabay)    [ "$PIXABAY_WEIGHT"    -gt 0 ] ;;
        bing)       [ "$BING_WEIGHT"       -gt 0 ] ;;
        variety)    [ "$VARIETY_WEIGHT"    -gt 0 ] ;;
        *)          return 1 ;;
    esac
}

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
        for alt in $(other_sources "$SELECTED_SOURCE"); do
            if [ "$STREAK_OVERRIDE" = true ] && [ "$alt" = "$CURRENT_SOURCE" ]; then
                continue
            fi
            is_source_enabled "$alt" || continue
            if try_source "$alt"; then
                SUCCESS=true
                SOURCE_USED="$alt"
                echo "$(date) - $SELECTED_SOURCE failed — fell back to $alt" >> "$LOGFILE"
                break
            fi
        done
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

    find /tmp -name "wallpaper_*" -mmin +1440 -delete 2>/dev/null
    find /tmp -name "pixabay_*"   -mmin +1440 -delete 2>/dev/null
    find /tmp -name "bing_*"      -mmin +1440 -delete 2>/dev/null

    if [ $((RANDOM % 50)) -eq 0 ]; then
        load_history
        echo "$(date) - Periodic history cache reloaded" >> "$LOGFILE"
    fi

done
