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
HISTORY_SIZE=2140000
SEARCH_LIMIT=100
SLEEP_INTERVAL=60
MAX_ATTEMPTS=100
DEVIOUSQ_TIMEOUT=30
WGET_TIMEOUT=15
WGET_TOTAL_TIMEOUT=30
MAX_RETRIES=3
LOG_MAX_SIZE=10485760

# Source weights
DEVIANTART_WEIGHT=60
VARIETY_WEIGHT=40
MAX_SAME_SOURCE=3

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
        if command -v stat >/dev/null 2>&1; then
            size=$(stat -c%s "$LOGFILE" 2>/dev/null || stat -f%z "$LOGFILE" 2>/dev/null)
        else
            size=$(wc -c < "$LOGFILE" 2>/dev/null || echo 0)
        fi
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
#~ exec 9>"$LOCK_FILE"
#~ if ! flock -n 9; then
    #~ echo "$(date) - Another instance is already running. Exiting."
    #~ exit 1
#~ fi
#~ trap 'flock -u 9; exec 9>&-' EXIT

echo "$(date) - Random Wallpaper Script Started" >> "$LOGFILE"
echo "$(date) - DA Weight: $DEVIANTART_WEIGHT, Variety Weight: $VARIETY_WEIGHT" >> "$LOGFILE"

# ============================================================
# DEPENDENCY CHECK
# ============================================================
if ! command -v plasma-apply-wallpaperimage >/dev/null 2>&1; then
    echo "$(date) - ERROR: plasma-apply-wallpaperimage not found" >> "$LOGFILE"
    echo "ERROR: plasma-apply-wallpaperimage not found" >&2
    exit 1
fi

if ! command -v deviousq >/dev/null 2>&1; then
    echo "$(date) - ERROR: deviousq not found" >> "$LOGFILE"
    echo "ERROR: deviousq not found" >&2
    exit 1
fi

# ============================================================
# INTERNET CHECK
# ============================================================
check_internet() {
    local endpoints=(
        "https://www.google.com"
        "https://www.cloudflare.com"
        "https://www.microsoft.com"
        "https://mirrors.fedoraproject.org"
    )
    
    for endpoint in "${endpoints[@]}"; do
        if curl -fsI --connect-timeout 5 --max-time 10 "$endpoint" >/dev/null 2>&1; then
            return 0
        fi
    done
    return 1
}

# ============================================================
# VARIETY MANAGEMENT (WITH PROCESS CONTROL)
# ============================================================

# Check if Variety is running
is_variety_running() {
    pgrep -f "variety" >/dev/null 2>&1
}

# Stop Variety completely (prevents conflicts)
stop_variety() {
    if is_variety_running; then
        pkill -f "variety" 2>/dev/null
        echo "$(date) - Stopped Variety process" >> "$LOGFILE"
        sleep 1  # Give it time to clean up
        return 0
    fi
    return 1
}

# Start Variety (if it was stopped)
start_variety() {
    if ! is_variety_running; then
        variety >/dev/null 2>&1 &
        echo "$(date) - Started Variety process" >> "$LOGFILE"
        sleep 1  # Give it time to initialize
        return 0
    fi
    return 1
}

# Use Variety (with process management)
use_variety() {
    if ! command -v variety >/dev/null 2>&1; then
        echo "$(date) - Variety not installed" >> "$LOGFILE"
        return 1
    fi
    
    # Make sure Variety is running
    if ! is_variety_running; then
        start_variety
    fi
    
    # Rotate wallpaper
    if variety --next >/dev/null 2>&1; then
        echo "$(date) - Variety wallpaper rotated" >> "$LOGFILE"
        return 0
    else
        echo "$(date) - Variety rotation failed" >> "$LOGFILE"
        return 1
    fi
}

# ============================================================
# ALL DEVIANTART CATEGORIES
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
# CATEGORY CYCLING
# ============================================================
shuffle_categories() {
    SHUFFLED_CATEGORIES=($(printf '%s\n' "${CATEGORIES[@]}" | shuf))
    CAT_INDEX=0
}
shuffle_categories

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
            if [[ "$url" =~ ^https?:// ]]; then
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
        {
            tail -n "$HISTORY_SIZE" "$HISTORY_FILE"
        } > "$HISTORY_FILE.tmp" && mv "$HISTORY_FILE.tmp" "$HISTORY_FILE"
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
    if [[ ${HISTORY_CACHE["$url"]+_} ]]; then
        return 0
    else
        return 1
    fi
}

# ============================================================
# URL VALIDATION
# ============================================================
is_valid_image_url() {
    local url="$1"
    [[ "$url" =~ ^https?://[^/]+/.+\.(jpg|jpeg|png|gif|webp|bmp|svg) ]]
}

# ============================================================
# DEVIANTART FETCHER (WITH VARIETY MANAGEMENT)
# ============================================================
fetch_deviantart() {
    # IMPORTANT: Stop Variety before using DeviantArt to prevent conflicts
    local variety_was_running=false
    
    if is_variety_running; then
        variety_was_running=true
        stop_variety
        echo "$(date) - [DeviantArt] Paused Variety for DeviantArt" >> "$LOGFILE"
    fi
    
    local current_category="${SHUFFLED_CATEGORIES[$CAT_INDEX]}"
    
    echo "$(date) - [DeviantArt] Searching: '$current_category'" >> "$LOGFILE"
    
    URL_LIST=""
    RETRY_COUNT=0
    
    while [ -z "$URL_LIST" ] && [ "$RETRY_COUNT" -lt "$MAX_RETRIES" ]; do
        if [ "$RETRY_COUNT" -gt 0 ]; then
            echo "$(date) - [DeviantArt] Retry $RETRY_COUNT/$MAX_RETRIES" >> "$LOGFILE"
            sleep 5
        fi
        
        URL_LIST=$(timeout "${DEVIOUSQ_TIMEOUT}s" deviousq \
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
        echo "$(date) - [DeviantArt] No results after $MAX_RETRIES attempts" >> "$LOGFILE"
        
        # Restore Variety if it was running
        if [ "$variety_was_running" = true ] && [ "$VARIETY_WEIGHT" -gt 0 ]; then
            start_variety
            echo "$(date) - [DeviantArt] Restarted Variety" >> "$LOGFILE"
        fi
        return 1
    fi
    
    VALID_URLS=$(printf '%s\n' "$URL_LIST" | grep -E '^https?://' | grep -E '\.(jpg|jpeg|png|gif|webp|bmp|svg)' | head -100)
    
    if [ -z "$VALID_URLS" ]; then
        echo "$(date) - [DeviantArt] No valid image URLs found" >> "$LOGFILE"
        if [ "$variety_was_running" = true ] && [ "$VARIETY_WEIGHT" -gt 0 ]; then
            start_variety
            echo "$(date) - [DeviantArt] Restarted Variety" >> "$LOGFILE"
        fi
        return 1
    fi
    
    URL_COUNT=$(printf '%s\n' "$VALID_URLS" | wc -l)
    echo "$(date) - [DeviantArt] Found $URL_COUNT valid image URLs" >> "$LOGFILE"

    RANDOM_URL=""
    SHUFFLED_URLS=($(printf '%s\n' "$VALID_URLS" | shuf))
    
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

    TIMESTAMP=$(date +%s)
    WALLPAPER_FILE="/tmp/wallpaper_${TIMESTAMP}.jpg"

    echo "$(date) - [DeviantArt] Downloading..." >> "$LOGFILE"

    AVAILABLE=$(df -k /tmp 2>/dev/null | awk 'NR==2 {print $4}')
    if [ -n "$AVAILABLE" ] && [ "$AVAILABLE" -lt 10240 ]; then
        echo "$(date) - WARNING: Low disk space in /tmp" >> "$LOGFILE"
        find /tmp -name "wallpaper_*.jpg" -mmin +5 -delete 2>/dev/null
    fi

    local success=false
    
    if timeout "${WGET_TOTAL_TIMEOUT}s" wget -q --timeout="${WGET_TIMEOUT}" \
        -O "$WALLPAPER_FILE" "$RANDOM_URL" 2>/dev/null; then
        
        if file "$WALLPAPER_FILE" 2>/dev/null | grep -qiE 'image|jpeg|jpg|png|gif|webp|bmp'; then
            if plasma-apply-wallpaperimage "$WALLPAPER_FILE" >/dev/null 2>&1; then
                add_to_history "$RANDOM_URL"
                echo "$(date) - [DeviantArt] Wallpaper set from '$current_category'" >> "$LOGFILE"
                success=true
                
                # Advance category
                CAT_INDEX=$((CAT_INDEX + 1))
                if [ "$CAT_INDEX" -ge "${#SHUFFLED_CATEGORIES[@]}" ]; then
                    echo "$(date) - [DeviantArt] Finished category cycle. Reshuffling..." >> "$LOGFILE"
                    shuffle_categories
                fi
            else
                echo "$(date) - [DeviantArt] ERROR: KDE rejected image" >> "$LOGFILE"
            fi
        else
            echo "$(date) - [DeviantArt] ERROR: Not a valid image" >> "$LOGFILE"
        fi
        rm -f "$WALLPAPER_FILE"
    else
        echo "$(date) - [DeviantArt] ERROR: Download failed" >> "$LOGFILE"
    fi
    
    # Restore Variety if it was running AND we're not going to use it immediately
    # (and if Variety weight > 0)
    if [ "$variety_was_running" = true ] && [ "$VARIETY_WEIGHT" -gt 0 ]; then
        # Only restart if DeviantArt succeeded, or if we want Variety as fallback
        if [ "$success" = true ]; then
            # Don't restart immediately - let the main loop handle it
            echo "$(date) - [DeviantArt] Variety will be restarted when needed" >> "$LOGFILE"
        else
            # Restart Variety since DeviantArt failed
            start_variety
            echo "$(date) - [DeviantArt] Restarted Variety after failure" >> "$LOGFILE"
        fi
    fi
    
    return 0
}

# ============================================================
# SOURCE SELECTION
# ============================================================
CURRENT_SOURCE=""
SAME_SOURCE_COUNT=0

select_source() {
    local total_weight=$((DEVIANTART_WEIGHT + VARIETY_WEIGHT))
    local rand=$((RANDOM % total_weight))
    
    if [ $rand -lt "$DEVIANTART_WEIGHT" ]; then
        echo "deviantart"
    else
        echo "variety"
    fi
}

get_opposite_source() {
    if [ "$1" = "deviantart" ]; then
        echo "variety"
    else
        echo "deviantart"
    fi
}

update_source_state() {
    if [ "$1" = "$CURRENT_SOURCE" ]; then
        SAME_SOURCE_COUNT=$((SAME_SOURCE_COUNT + 1))
    else
        CURRENT_SOURCE="$1"
        SAME_SOURCE_COUNT=1
    fi
}

# ============================================================
# MAIN LOOP
# ============================================================
IS_ONLINE=false

while true; do
    rotate_log

    # --------------------------------------------------------
    # CHECK INTERNET
    # --------------------------------------------------------
    if ! check_internet; then
        if [ "$IS_ONLINE" = true ]; then
            echo "$(date) - Internet lost - switching to Variety only" >> "$LOGFILE"
            IS_ONLINE=false
        fi
        
        echo "$(date) - [Offline] Using Variety" >> "$LOGFILE"
        if use_variety; then
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

    # --------------------------------------------------------
    # SELECT SOURCE
    # --------------------------------------------------------
    if [ "$SAME_SOURCE_COUNT" -ge "$MAX_SAME_SOURCE" ] && [ -n "$CURRENT_SOURCE" ]; then
        SELECTED_SOURCE=$(get_opposite_source "$CURRENT_SOURCE")
        echo "$(date) - Max streak ($MAX_SAME_SOURCE) reached for $CURRENT_SOURCE - forcing $SELECTED_SOURCE" >> "$LOGFILE"
    else
        SELECTED_SOURCE=$(select_source)
    fi
    
    echo "$(date) - Selected $SELECTED_SOURCE (streak: $SAME_SOURCE_COUNT/$MAX_SAME_SOURCE)" >> "$LOGFILE"

    # --------------------------------------------------------
    # EXECUTE SELECTED SOURCE
    # --------------------------------------------------------
    SUCCESS=false

    if [ "$SELECTED_SOURCE" = "deviantart" ]; then
        if fetch_deviantart; then
            update_source_state "deviantart"
            SUCCESS=true
        else
            echo "$(date) - DeviantArt failed - trying Variety fallback" >> "$LOGFILE"
            if use_variety; then
                update_source_state "variety"
                SUCCESS=true
            fi
        fi
    else
        if use_variety; then
            update_source_state "variety"
            SUCCESS=true
        else
            echo "$(date) - Variety failed - trying DeviantArt fallback" >> "$LOGFILE"
            if fetch_deviantart; then
                update_source_state "deviantart"
                SUCCESS=true
            fi
        fi
    fi

    # --------------------------------------------------------
    # HANDLE SUCCESS/FAILURE
    # --------------------------------------------------------
    if [ "$SUCCESS" = true ]; then
        echo "$(date) - [Success] Source: $CURRENT_SOURCE (streak: $SAME_SOURCE_COUNT/$MAX_SAME_SOURCE)" >> "$LOGFILE"
        sleep "$SLEEP_INTERVAL"
    else
        echo "$(date) - Both sources failed, waiting 30s" >> "$LOGFILE"
        sleep 30
    fi

    # --------------------------------------------------------
    # PERIODIC TASKS
    # --------------------------------------------------------
    find /tmp -name "wallpaper_*.jpg" -mtime +1 -delete 2>/dev/null
    
    if [ $((RANDOM % 50)) -eq 0 ]; then
        load_history
        echo "$(date) - Periodic history cache reloaded" >> "$LOGFILE"
    fi

done
