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

DEVIANTART_WEIGHT=40
VARIETY_WEIGHT=20
PIXABAY_WEIGHT=40
MAX_SAME_SOURCE=3

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
# SINGLE-INSTANCE LOCK + TEMP-FILE CLEANUP
# ============================================================
CURRENT_TEMP=""

cleanup_on_exit() {
    local ec=$?
    if [[ -n "${CURRENT_TEMP:-}" && -f "$CURRENT_TEMP" ]]; then
        rm -f "$CURRENT_TEMP" 2>/dev/null || true
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

echo "$(date) - Random Wallpaper Script Started" >> "$LOGFILE"
echo "$(date) - Weights: DA=$DEVIANTART_WEIGHT Variety=$VARIETY_WEIGHT Pixabay=$PIXABAY_WEIGHT" >> "$LOGFILE"

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
           mktemp df pgrep pkill find date wc cat; do
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

if [ "$DEVIANTART_WEIGHT" -eq 0 ] && [ "$PIXABAY_WEIGHT" -eq 0 ] && [ "$VARIETY_WEIGHT" -eq 0 ]; then
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

    local pids=()
    local tmpdir
    tmpdir=$(mktemp -d) || return 1

    local i=0
    for endpoint in "${endpoints[@]}"; do
        (
            if curl -fsI \
                --connect-timeout 2 \
                --max-time "$INTERNET_CHECK_TIMEOUT" \
                --no-keepalive \
                -H "User-Agent: Mozilla/5.0" \
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
# VARIETY MANAGEMENT
# ============================================================
is_variety_running() {
    pgrep -f '(^|/)variety( |$)' >/dev/null 2>&1
}

stop_variety() {
    if is_variety_running; then
        pkill -f '(^|/)variety( |$)' 2>/dev/null
        echo "$(date) - Stopped Variety process" >> "$LOGFILE"
        sleep 1
        return 0
    fi
    return 1
}

start_variety() {
    if ! is_variety_running; then
        variety >/dev/null 2>&1 &
        echo "$(date) - Started Variety process" >> "$LOGFILE"
        sleep 2
        return 0
    fi
    return 1
}

use_variety() {
    if ! command -v variety >/dev/null 2>&1; then
        echo "$(date) - Variety not installed" >> "$LOGFILE"
        return 1
    fi

    if ! is_variety_running; then
        start_variety
    fi

    if variety --next >/dev/null 2>&1; then
        echo "$(date) - Variety wallpaper rotated" >> "$LOGFILE"
        return 0
    else
        echo "$(date) - Variety rotation failed" >> "$LOGFILE"
        return 1
    fi
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
# CATEGORY / QUERY CYCLING
# ============================================================
shuffle_categories() {
    mapfile -t SHUFFLED_CATEGORIES < <(printf '%s\n' "${CATEGORIES[@]}" | shuf)
    CAT_INDEX=0
}
shuffle_categories

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

    local variety_was_running=false
    if is_variety_running; then
        variety_was_running=true
        stop_variety
        echo "$(date) - [DeviantArt] Paused Variety for DeviantArt" >> "$LOGFILE"
    fi

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
        CAT_INDEX=$((CAT_INDEX + 1))
        if [ "$CAT_INDEX" -ge "${#SHUFFLED_CATEGORIES[@]}" ]; then
            shuffle_categories
        fi
        [ "$variety_was_running" = true ] && [ "$VARIETY_WEIGHT" -gt 0 ] && start_variety
        return 1
    fi

    local VALID_URLS
    VALID_URLS=$(printf '%s\n' "$URL_LIST" | grep -E '^https?://' | head -100)

    if [ -z "$VALID_URLS" ]; then
        echo "$(date) - [DeviantArt] No valid URLs found" >> "$LOGFILE"
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

                CAT_INDEX=$((CAT_INDEX + 1))
                if [ "$CAT_INDEX" -ge "${#SHUFFLED_CATEGORIES[@]}" ]; then
                    echo "$(date) - [DeviantArt] Finished category cycle. Reshuffling..." >> "$LOGFILE"
                    shuffle_categories
                fi
            else
                echo "$(date) - [DeviantArt] ERROR: KDE rejected image" >> "$LOGFILE"
            fi
        fi

        rm -f "$WALLPAPER_FILE"
        CURRENT_TEMP=""
    else
        echo "$(date) - [DeviantArt] ERROR: Download failed" >> "$LOGFILE"
        rm -f "$WALLPAPER_FILE"
        CURRENT_TEMP=""
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

    local variety_was_running=false
    if is_variety_running; then
        variety_was_running=true
        stop_variety
        echo "$(date) - [Pixabay] Paused Variety for Pixabay" >> "$LOGFILE"
    fi

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
        echo "$(date) - [Pixabay] API request failed (curl rc=$curl_rc) for '$query'" >> "$LOGFILE"
        [ "$variety_was_running" = true ] && [ "$VARIETY_WEIGHT" -gt 0 ] && start_variety
        return 1
    fi

    if [ -z "$response" ]; then
        echo "$(date) - [Pixabay] Empty API response for '$query'" >> "$LOGFILE"
        [ "$variety_was_running" = true ] && [ "$VARIETY_WEIGHT" -gt 0 ] && start_variety
        return 1
    fi

    local hits
    hits=$(printf '%s' "$response" | jq -r '
        .hits[]
        | select(.largeImageURL != null)
        | select(.imageWidth  >= '"$PIXABAY_IMAGE_MIN_WIDTH"')
        | select(.imageHeight >= '"$PIXABAY_IMAGE_MIN_HEIGHT"')
        | select(.isLowQuality == false)
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
        [ "$variety_was_running" = true ] && [ "$VARIETY_WEIGHT" -gt 0 ] && start_variety
        return 1
    }

    local WALLPAPER_FILE
    WALLPAPER_FILE=$(mktemp /tmp/pixabay_XXXXXX.jpg) || {
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
            fi
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
    if (( rand < da )); then
        echo "deviantart"
    elif (( rand < da + va )); then
        echo "variety"
    else
        echo "pixabay"
    fi
}

select_source() {
    select_source_except ""
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
        pool+=("$s")
    done
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

    if [ "$SAME_SOURCE_COUNT" -ge "$MAX_SAME_SOURCE" ] && [ -n "$CURRENT_SOURCE" ]; then
        SELECTED_SOURCE=$(select_source_except "$CURRENT_SOURCE")
        if [ -n "$SELECTED_SOURCE" ]; then
            echo "$(date) - Max streak ($MAX_SAME_SOURCE) reached for $CURRENT_SOURCE — forcing $SELECTED_SOURCE" >> "$LOGFILE"
        fi
    fi

    if [ -z "$SELECTED_SOURCE" ]; then
        SELECTED_SOURCE=$(select_source)
    fi

    echo "$(date) - Selected $SELECTED_SOURCE (streak: $SAME_SOURCE_COUNT/$MAX_SAME_SOURCE)" >> "$LOGFILE"

    SUCCESS=false
    SOURCE_USED=""

    if is_source_enabled "$SELECTED_SOURCE" && try_source "$SELECTED_SOURCE"; then
        SUCCESS=true
        SOURCE_USED="$SELECTED_SOURCE"
    else
        for alt in $(other_sources "$SELECTED_SOURCE"); do
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

    if [ $((RANDOM % 50)) -eq 0 ]; then
        load_history
        echo "$(date) - Periodic history cache reloaded" >> "$LOGFILE"
    fi

done
