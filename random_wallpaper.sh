#!/usr/bin/env bash
set -uo pipefail

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"

# ============================================================
# SINGLE-INSTANCE LOCK
# ============================================================
#~ LOCK_FILE="$HOME/.cache/random_wallpaper.lock"
#~ mkdir -p "$(dirname "$LOCK_FILE")"
#~ exec 9>"$LOCK_FILE"
#~ if ! flock -n 9; then
    #~ echo "$(date) - Another instance is already running. Exiting."
    #~ exit 1
#~ fi
#~ trap 'flock -u 9; exec 9>&-' EXIT

# ============================================================
# RANDOM WALLPAPER SCRIPT - WEIGHTED RANDOM SOURCE SELECTION
# ============================================================
#
# DESCRIPTION:
#   Randomly selects between DeviantArt and Variety with weighted
#   probabilities (60/40 by default) and enforces a maximum streak
#   to prevent long runs of the same source. Falls back to
#   Variety-only when offline. Fallback respects streak limits.
#
# DEPENDENCIES:
#   - deviousq      - Command-line DeviantArt search tool
#   - plasma-apply-wallpaperimage - KDE Plasma wallpaper setter
#   - wget          - For downloading images
#   - Variety       - OPTIONAL for local wallpaper rotation
#   - timeout       - Coreutils utility (usually installed)
#
# HOW IT WORKS:
#   1. Internet Check - Quick connectivity test (2s timeout)
#   2. Offline Mode - Variety only with random delays
#   3. Online Mode - Weighted random source selection:
#      - 60% chance DeviantArt, 40% chance Variety
#      - Enforces max 3 consecutive uses of same source
#      - Fallback respects streak limits
#   4. Random Timing - Each change waits MIN_INTERVAL-MAX_INTERVAL
#   5. Instant Fallback - If primary fails, moves to secondary if allowed
#   6. Category Cycling - Shuffles categories, advances only on success
#
# NOTE: The actual resulting wallpaper distribution may differ from the
#       weighted selection due to fallbacks and forced streak transitions.
# NOTE: MAX_SAME_SOURCE applies only while ONLINE.
#       Offline mode intentionally permits unlimited Variety rotations.
#       If only one source is enabled, MAX_SAME_SOURCE is informational only.
# NOTE: A source with weight 0 is completely disabled (no selection, no fallback).
# NOTE: Categories are only advanced when a DeviantArt wallpaper is successfully set.
# NOTE: History remembers the last HISTORY_SIZE URLs. Old URLs become eligible again.
# NOTE: Internet detection uses GET requests for better reliability with some networks.

# ============================================================
# CONFIGURATION
# ============================================================
HISTORY_SIZE=2140000            # Reduced for performance
SEARCH_LIMIT=100              # Fetch 100 results per search
MAX_ATTEMPTS=100              # Try up to 100 random candidates
DEVIUSQ_TIMEOUT=30            # Timeout for deviousq in seconds
WGET_TIMEOUT=15               # Timeout for wget in seconds
WGET_TOTAL_TIMEOUT=30         # Total wall-clock timeout for wget

# Random timing intervals (seconds)
MIN_INTERVAL=45
MAX_INTERVAL=180

# Weighted source selection (online only)
# A weight of 0 completely disables that source (no selection, no fallback)
DEVIANTART_WEIGHT=60
VARIETY_WEIGHT=40
MAX_SAME_SOURCE=3

# ============================================================
# PATHS & SETUP
# ============================================================
HISTORY_FILE="$HOME/scriptlogs/wallpaper_history.txt"
LOGFILE="$HOME/scriptlogs/wallpaper.log"
TEMP_DIR="${XDG_RUNTIME_DIR:-/tmp}/random-wallpaper"

# Validate critical directory creation
if ! mkdir -p "$HOME/scriptlogs" "$TEMP_DIR" 2>/dev/null; then
    echo "ERROR: Failed to create required directories" >&2
    exit 1
fi

# Ensure history file exists and is writable
if ! touch "$HISTORY_FILE" 2>/dev/null; then
    echo "ERROR: Failed to create history file at $HISTORY_FILE" >&2
    exit 1
fi

echo "$(date) - Weighted Random Wallpaper Script Started" >> "$LOGFILE"
echo "$(date) - History size: $HISTORY_SIZE, Interval: $MIN_INTERVAL-$MAX_INTERVAL sec" >> "$LOGFILE"
echo "$(date) - DA Weight: $DEVIANTART_WEIGHT, Variety Weight: $VARIETY_WEIGHT, Max Streak: $MAX_SAME_SOURCE" >> "$LOGFILE"

# ============================================================
# DEPENDENCY VALIDATION
# ============================================================
REQUIRED_COMMANDS=(
    curl
    file
    flock
    mktemp
    shuf
    timeout
    wget
    deviousq
    plasma-apply-wallpaperimage
)

for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: Required command not found: $cmd" >&2
        exit 1
    fi
done

if ! command -v variety >/dev/null 2>&1; then
    echo "$(date) - WARNING: Variety is not installed; Variety operations will fail" >> "$LOGFILE"
fi

# ============================================================
# CONFIGURATION VALIDATION
# ============================================================
if (( MIN_INTERVAL > MAX_INTERVAL )); then
    echo "ERROR: MIN_INTERVAL ($MIN_INTERVAL) cannot exceed MAX_INTERVAL ($MAX_INTERVAL)" >&2
    exit 1
fi

if (( MIN_INTERVAL < 1 )); then
    echo "ERROR: MIN_INTERVAL ($MIN_INTERVAL) must be at least 1" >&2
    exit 1
fi

if (( DEVIANTART_WEIGHT < 0 || VARIETY_WEIGHT < 0 )); then
    echo "ERROR: Source weights cannot be negative" >&2
    exit 1
fi

if (( DEVIANTART_WEIGHT + VARIETY_WEIGHT == 0 )); then
    echo "ERROR: At least one source weight must be > 0" >&2
    exit 1
fi

if (( MAX_SAME_SOURCE < 1 )); then
    echo "ERROR: MAX_SAME_SOURCE ($MAX_SAME_SOURCE) must be at least 1" >&2
    exit 1
fi

# ============================================================
# ALL CATEGORIES KEYWORD POOL (Duplicates removed)
# ============================================================
CATEGORIES=(
    "3d art" "cgi" "blender" "maya"
    "abstract" "geometric" "minimalist"
    "animation" "gif" "motion graphics"
    "animals" "fantasy" "graffiti" "illustration"
    "landscapes" "scenery" "nature"
    "portraits" "political"
    "pop art" "sci-fi" "space art"
    "still life" "surreal"
    "fractal" "mandelbrot"
    "mixed media" "digital collage"
    "photomanipulation" "photo manipulation"
    "pixel art" "8-bit" "16-bit"
    "vector" "vector art" "flat design"
    "body art" "face painting"
    "collage" "paper art"
    "pencil drawing" "charcoal" "ink sketch"
    "printmaking" "linocut" "etching"
    "architecture" "cityscape" "urban"
    "conceptual" "dark" "emotional"
    "seascape" "ocean" "beach"
    "macro" "monochrome" "black and white"
    "street photography"
    "anime" "manga" "fanart anime" "kawaii"
    "cartoon" "comic" "webcomic"
    "fan art" "marvel fanart" "star wars fanart" "harry potter fanart"
    "jewelry" "woodwork" "sculpture" "glass art"
    "cyberpunk" "synthwave" "vaporwave"
    "nebula" "galaxy" "aurora"
    "dragon" "castle" "mythical" "magical"
    "forest" "mountain" "sunset" "sunrise"
    "cherry blossom" "autumn" "winter"
)

# ============================================================
# CATEGORY CYCLING (Random Permutation without replacement)
# Advances only on successful wallpaper application.
# ============================================================
shuffle_categories() {
    mapfile -t SHUFFLED_CATEGORIES < <(
        printf '%s\n' "${CATEGORIES[@]}" | shuf
    )
    CAT_INDEX=0
}

shuffle_categories

# ============================================================
# RELIABLE INTERNET CHECK - FAST TIMEOUT WITH GET
# ============================================================
check_internet() {
    local endpoints=(
        "https://www.google.com"
        "https://www.cloudflare.com"
        "https://www.microsoft.com"
        "https://mirrors.fedoraproject.org"
    )
    
    for endpoint in "${endpoints[@]}"; do
        # Use GET with --max-time for better reliability with some networks
        if curl -f -s --connect-timeout 2 --max-time 3 -o /dev/null "$endpoint" 2>/dev/null; then
            return 0
        fi
    done
    return 1
}

# ============================================================
# VARIETY MANAGEMENT
# ============================================================
use_variety() {
    if ! command -v variety >/dev/null 2>&1; then
        echo "$(date) - WARNING: Variety is not installed" >> "$LOGFILE"
        return 1
    fi
    
    # Redirect all output to ensure clean stdout
    variety >/dev/null 2>&1
    local result=$?
    
    if [ $result -eq 0 ]; then
        echo "$(date) - [Variety] Wallpaper rotation command accepted" >> "$LOGFILE"
        return 0
    else
        echo "$(date) - [Variety] Failed to rotate wallpaper (exit: $result)" >> "$LOGFILE"
        return 1
    fi
}

# ============================================================
# HISTORY MANAGEMENT - Using associative array for speed
# ============================================================
declare -A HISTORY_CACHE

load_history() {
    if [ -f "$HISTORY_FILE" ]; then
        HISTORY_CACHE=()
        
        while IFS= read -r url; do
            # Skip empty or malformed URLs
            if [ -n "$url" ] && [[ "$url" =~ ^https?:// ]]; then
                HISTORY_CACHE["$url"]=1
            fi
        done < "$HISTORY_FILE"
        
        echo "$(date) - Loaded ${#HISTORY_CACHE[@]} valid history entries" >> "$LOGFILE"
    else
        touch "$HISTORY_FILE"
        echo "$(date) - Created new history file" >> "$LOGFILE"
    fi
}

add_to_history() {
    local url="$1"
    
    # Validate URL before storing
    if [ -z "$url" ] || ! [[ "$url" =~ ^https?:// ]]; then
        echo "$(date) - WARNING: Attempted to add invalid URL to history: $url" >> "$LOGFILE"
        return 1
    fi
    
    HISTORY_CACHE["$url"]=1
    echo "$url" >> "$HISTORY_FILE"
    
    local line_count=$(wc -l < "$HISTORY_FILE" 2>/dev/null || echo 0)
    if [ "$line_count" -gt "$((HISTORY_SIZE * 2))" ]; then
        # Use a temporary file with random suffix for safety
        local temp_file="${HISTORY_FILE}.tmp.$$"
        tail -n "$HISTORY_SIZE" "$HISTORY_FILE" > "$temp_file"
        mv "$temp_file" "$HISTORY_FILE"
        echo "$(date) - Trimmed history to $HISTORY_SIZE entries (old URLs become eligible again)" >> "$LOGFILE"
        load_history
    fi
}

is_in_history() {
    local url="$1"
    # Guard against empty or malformed URLs
    if [ -z "$url" ]; then
        return 1
    fi
    [[ ${HISTORY_CACHE["$url"]+_} ]]
}

load_history

# ============================================================
# DEVIANTART WALLPAPER FETCHER
# Advances category only on successful wallpaper application.
# ============================================================
fetch_deviantart_wallpaper() {
    # Use current category (don't advance yet)
    local current_category="${SHUFFLED_CATEGORIES[$CAT_INDEX]}"
    
    echo "$(date) - [DeviantArt] Searching: '$current_category'" >> "$LOGFILE"
    
    # Fetch results with timeout to prevent hanging
    local URL_LIST
    URL_LIST=$(timeout "${DEVIUSQ_TIMEOUT}s" deviousq \
        --medium image \
        --rating nonadult \
        --return-field content_url \
        --limit "$SEARCH_LIMIT" \
        "$current_category" \
        2>/dev/null)
    
    if [ -z "$URL_LIST" ]; then
        echo "$(date) - [DeviantArt] No results or timeout for '$current_category'" >> "$LOGFILE"
        return 1
    fi
    
    mapfile -t URL_ARRAY <<< "$URL_LIST"
    
    # Safety check for empty array
    if [ "${#URL_ARRAY[@]}" -eq 0 ]; then
        echo "$(date) - [DeviantArt] ERROR: Empty URL array" >> "$LOGFILE"
        return 1
    fi
    
    # Find unseen URL - random sampling with early exit
    local RANDOM_URL=""
    local attempt
    
    for ((attempt = 1; attempt <= MAX_ATTEMPTS; attempt++)); do
        local CANDIDATE
        CANDIDATE="${URL_ARRAY[$((RANDOM % ${#URL_ARRAY[@]}))]}"
        if [ -n "$CANDIDATE" ] && ! is_in_history "$CANDIDATE"; then
            RANDOM_URL="$CANDIDATE"
            echo "$(date) - [DeviantArt] Found unseen URL (attempt $attempt)" >> "$LOGFILE"
            break
        fi
    done
    
    # Fallback: iterate through all URLs if random sampling failed
    if [ -z "$RANDOM_URL" ]; then
        for candidate in "${URL_ARRAY[@]}"; do
            if ! is_in_history "$candidate"; then
                RANDOM_URL="$candidate"
                echo "$(date) - [DeviantArt] Fallback: found unseen URL" >> "$LOGFILE"
                break
            fi
        done
    fi
    
    # Ultimate fallback: random repeat
    if [ -z "$RANDOM_URL" ]; then
        RANDOM_URL="${URL_ARRAY[$((RANDOM % ${#URL_ARRAY[@]}))]}"
        echo "$(date) - [DeviantArt] WARNING: Using random repeat" >> "$LOGFILE"
    fi
    
    # Download and apply - use dedicated temp directory
    if [ -n "$RANDOM_URL" ]; then
        local TEMP_FILE
        TEMP_FILE=$(mktemp "$TEMP_DIR/wallpaper_XXXXXX.jpg" 2>/dev/null)
        
        if [ -z "$TEMP_FILE" ]; then
            echo "$(date) - [DeviantArt] ERROR: mktemp failed" >> "$LOGFILE"
            return 1
        fi
        
        # Download with total timeout and all output suppressed
        local wget_exit=0
        timeout "${WGET_TOTAL_TIMEOUT}s" wget -q --timeout="${WGET_TIMEOUT}" --tries=1 -O "$TEMP_FILE" "$RANDOM_URL" 2>/dev/null || wget_exit=$?
        
        if [ $wget_exit -eq 0 ]; then
            # Determine actual file type
            local MIME_TYPE
            MIME_TYPE=$(file -b --mime-type "$TEMP_FILE" 2>/dev/null)
            
            if [[ "$MIME_TYPE" == image/* ]]; then
                if plasma-apply-wallpaperimage "$TEMP_FILE" >/dev/null 2>&1; then
                    add_to_history "$RANDOM_URL"
                    echo "$(date) - [DeviantArt] Wallpaper set from '$current_category'" >> "$LOGFILE"
                    rm -f "$TEMP_FILE"
                    
                    # ADVANCE CATEGORY ONLY ON SUCCESS
                    CAT_INDEX=$((CAT_INDEX + 1))
                    if [ "$CAT_INDEX" -ge "${#SHUFFLED_CATEGORIES[@]}" ]; then
                        echo "$(date) - [DeviantArt] Finished full category cycle. Reshuffling..." >> "$LOGFILE"
                        shuffle_categories
                    fi
                    
                    return 0
                else
                    echo "$(date) - [DeviantArt] ERROR: Failed to apply wallpaper" >> "$LOGFILE"
                fi
            else
                echo "$(date) - [DeviantArt] ERROR: Not an image (MIME: $MIME_TYPE)" >> "$LOGFILE"
            fi
            rm -f "$TEMP_FILE"
            return 1
        else
            # Report specific wget error
            if [ $wget_exit -eq 124 ]; then
                echo "$(date) - [DeviantArt] ERROR: Download timed out (${WGET_TOTAL_TIMEOUT}s total)" >> "$LOGFILE"
            else
                echo "$(date) - [DeviantArt] ERROR: Download failed (wget exit: $wget_exit)" >> "$LOGFILE"
            fi
            rm -f "$TEMP_FILE"
            return 1
        fi
    fi
    
    return 1
}

# ============================================================
# RANDOM SOURCE SELECTION (ONLINE ONLY)
# ============================================================
select_source() {
    # Only select from sources with positive weight
    if [ "$DEVIANTART_WEIGHT" -eq 0 ] && [ "$VARIETY_WEIGHT" -gt 0 ]; then
        printf '%s\n' "variety"
        return 0
    fi
    
    if [ "$VARIETY_WEIGHT" -eq 0 ] && [ "$DEVIANTART_WEIGHT" -gt 0 ]; then
        printf '%s\n' "deviantart"
        return 0
    fi
    
    local total_weight=$((DEVIANTART_WEIGHT + VARIETY_WEIGHT))
    local rand=$((RANDOM % total_weight))
    
    if [ $rand -lt $DEVIANTART_WEIGHT ]; then
        printf '%s\n' "deviantart"
    else
        printf '%s\n' "variety"
    fi
}

# ============================================================
# GET OPPOSITE SOURCE (Respects zero weights)
# ============================================================
get_opposite_source() {
    local source="$1"
    
    if [ "$source" = "deviantart" ]; then
        # Only return variety if it has positive weight
        if [ "$VARIETY_WEIGHT" -gt 0 ]; then
            printf '%s\n' "variety"
        else
            printf '%s\n' "deviantart"
        fi
    else
        # Only return deviantart if it has positive weight
        if [ "$DEVIANTART_WEIGHT" -gt 0 ]; then
            printf '%s\n' "deviantart"
        else
            printf '%s\n' "variety"
        fi
    fi
}

# ============================================================
# UPDATE SUCCESSFUL SOURCE STATE
# ============================================================
update_source_state() {
    local source="$1"
    
    if [ "$source" = "$CURRENT_SOURCE" ]; then
        SAME_SOURCE_COUNT=$((SAME_SOURCE_COUNT + 1))
    else
        CURRENT_SOURCE="$source"
        SAME_SOURCE_COUNT=1
    fi
}

# ============================================================
# ATTEMPT SOURCE WITH STREAK-AWARE FALLBACK
# Accepts a single argument: the primary source to attempt.
# Returns the actual successful source on stdout.
# Returns 1 if both sources fail or fallback is blocked.
# ============================================================
attempt_source_with_fallback() {
    local primary_source="$1"
    local fallback_source

    if [ "$primary_source" = "deviantart" ]; then
        fallback_source="variety"

        if fetch_deviantart_wallpaper; then
            printf '%s\n' "deviantart"
            return 0
        fi

        echo "$(date) - [DeviantArt] Failed - considering Variety fallback" >> "$LOGFILE"
    else
        fallback_source="deviantart"

        if use_variety; then
            printf '%s\n' "variety"
            return 0
        fi

        echo "$(date) - [Variety] Failed - considering DeviantArt fallback" >> "$LOGFILE"
    fi

    # Check if fallback source has positive weight
    if [ "$fallback_source" = "variety" ] && [ "$VARIETY_WEIGHT" -eq 0 ]; then
        echo "$(date) - Fallback to Variety disabled (weight=0)" >> "$LOGFILE"
        return 1
    fi
    
    if [ "$fallback_source" = "deviantart" ] && [ "$DEVIANTART_WEIGHT" -eq 0 ]; then
        echo "$(date) - Fallback to DeviantArt disabled (weight=0)" >> "$LOGFILE"
        return 1
    fi

    # Never allow fallback to create a streak longer than MAX_SAME_SOURCE.
    if [ "$CURRENT_SOURCE" = "$fallback_source" ] &&
       [ "$SAME_SOURCE_COUNT" -ge "$MAX_SAME_SOURCE" ]; then

        echo "$(date) - Fallback to $fallback_source would exceed streak limit ($MAX_SAME_SOURCE) - skipping" >> "$LOGFILE"
        return 1
    fi

    if [ "$fallback_source" = "variety" ]; then
        if use_variety; then
            printf '%s\n' "variety"
            return 0
        fi
    else
        if fetch_deviantart_wallpaper; then
            printf '%s\n' "deviantart"
            return 0
        fi
    fi

    echo "$(date) - [$fallback_source] Fallback also failed" >> "$LOGFILE"
    return 1
}

# ============================================================
# RANDOM DELAY
# ============================================================
random_delay() {
    local delay=$((MIN_INTERVAL + RANDOM % (MAX_INTERVAL - MIN_INTERVAL + 1)))
    echo "$(date) - Sleeping for $delay seconds" >> "$LOGFILE"
    sleep "$delay"
}

# ============================================================
# STATE VARIABLES
# ============================================================
IS_ONLINE=false
CURRENT_SOURCE=""  # "deviantart" or "variety" or ""
SAME_SOURCE_COUNT=0

# ============================================================
# MAIN LOOP - WEIGHTED RANDOM WITH STREAK LIMITING
# ============================================================
while true; do
    # --------------------------------------------------------
    # CLEANUP - dedicated temp directory
    # --------------------------------------------------------
    find "$TEMP_DIR" -type f -name 'wallpaper_*.jpg' -mtime +1 -delete 2>/dev/null
    
    # --------------------------------------------------------
    # CHECK INTERNET CONNECTIVITY
    # --------------------------------------------------------
    if check_internet; then
        # Online state
        if [ "$IS_ONLINE" = false ]; then
            echo "$(date) - ONLINE: Internet detected" >> "$LOGFILE"
            IS_ONLINE=true
            # Reset state when coming online
            CURRENT_SOURCE=""
            SAME_SOURCE_COUNT=0
        fi
        
        # ----------------------------------------------------
        # SELECT SOURCE WITH STREAK LIMIT
        # ----------------------------------------------------
        SELECTED_SOURCE=""
        
        # If we've hit the max streak, force the opposite source
        if [ "$SAME_SOURCE_COUNT" -ge "$MAX_SAME_SOURCE" ] && [ -n "$CURRENT_SOURCE" ]; then
            OPPOSITE_SOURCE=$(get_opposite_source "$CURRENT_SOURCE")
            
            if [ "$OPPOSITE_SOURCE" != "$CURRENT_SOURCE" ]; then
                SELECTED_SOURCE="$OPPOSITE_SOURCE"
                echo "$(date) - Max streak ($MAX_SAME_SOURCE) reached for $CURRENT_SOURCE - forcing $SELECTED_SOURCE" >> "$LOGFILE"
            else
                SELECTED_SOURCE="$CURRENT_SOURCE"
                echo "$(date) - Max streak ($MAX_SAME_SOURCE) reached, but no alternate source is enabled - continuing with $SELECTED_SOURCE" >> "$LOGFILE"
            fi
        else
            # Normal weighted random selection
            SELECTED_SOURCE=$(select_source)
        fi
        
        echo "$(date) - [Online] Selected $SELECTED_SOURCE (current streak: $SAME_SOURCE_COUNT/$MAX_SAME_SOURCE)" >> "$LOGFILE"
        
        # ----------------------------------------------------
        # EXECUTE SELECTED SOURCE WITH STREAK-AWARE FALLBACK
        # ----------------------------------------------------
        success=false
        ACTUAL_SOURCE=""

        if ACTUAL_SOURCE=$(attempt_source_with_fallback "$SELECTED_SOURCE"); then
            success=true
            
            # Update state using the source that actually changed
            # the wallpaper, not merely the source we originally selected.
            update_source_state "$ACTUAL_SOURCE"
            
            echo "$(date) - [Success] Source: $ACTUAL_SOURCE (streak: $SAME_SOURCE_COUNT/$MAX_SAME_SOURCE)" >> "$LOGFILE"
        fi
        
        # ----------------------------------------------------
        # WAIT WITH RANDOM DELAY
        # ----------------------------------------------------
        if [ "$success" = true ]; then
            random_delay
        else
            echo "$(date) - Both modes failed or fallback was blocked, waiting 30 seconds" >> "$LOGFILE"
            sleep 30
        fi
        
    else
        # Offline state - Variety ONLY
        if [ "$IS_ONLINE" = true ]; then
            echo "$(date) - OFFLINE: Internet lost - switching to Variety-only" >> "$LOGFILE"
            IS_ONLINE=false
        fi
        
        echo "$(date) - [Offline] Using Variety" >> "$LOGFILE"
        
        if use_variety; then
            # Update state only for tracking purposes (streak not enforced offline)
            if [ "$CURRENT_SOURCE" = "variety" ]; then
                SAME_SOURCE_COUNT=$((SAME_SOURCE_COUNT + 1))
            else
                CURRENT_SOURCE="variety"
                SAME_SOURCE_COUNT=1
            fi
            random_delay
        else
            echo "$(date) - [Offline] Variety failed, waiting 60 seconds" >> "$LOGFILE"
            sleep 60
        fi
    fi
done
