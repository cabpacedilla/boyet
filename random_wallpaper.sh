#!/usr/bin/env bash

# ============================================================
# CONFIGURATION
# ============================================================
HISTORY_SIZE=2140000         # ~4 years of unique wallpapers (1 change/min)
SEARCH_LIMIT=100             # Fetch 100 results per search (needed for large history)
SLEEP_INTERVAL=60            # Seconds between wallpaper changes
MAX_ATTEMPTS=20              # How many random URLs to try before falling back

# ============================================================
# ALL CATEGORIES KEYWORD POOL
# ============================================================
CATEGORIES=(
    "3d art" "cgi" "blender" "maya"
    "abstract" "geometric" "minimalist"
    "animation" "gif" "motion graphics"
    "animals" "fantasy" "graffiti" "illustration"
    "landscapes" "scenery" "nature"
    "people" "portraits" "political"
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
    "people" "street photography"
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
# PATHS & SETUP
# ============================================================
HISTORY_FILE="$HOME/scriptlogs/wallpaper_history.txt"
LOGFILE="$HOME/scriptlogs/wallpaper.log"
mkdir -p "$HOME/scriptlogs"

echo "$(date) - Random Wallpaper Script Started (History size: $HISTORY_SIZE)" >> "$LOGFILE"

# ============================================================
# CATEGORY CYCLING (Random Permutation without replacement)
# ============================================================
# Shuffle the category list into a random order
shuffle_categories() {
    # Convert array to lines, shuffle, then back to array
    SHUFFLED_CATEGORIES=($(printf "%s\n" "${CATEGORIES[@]}" | shuf))
    CAT_INDEX=0
}

# Initial shuffle
shuffle_categories

# ============================================================
# HISTORY FUNCTIONS
# ============================================================
# Ensure history file exists
touch "$HISTORY_FILE"

# Add a URL to history, keep only the last $HISTORY_SIZE entries
add_to_history() {
    local url="$1"
    echo "$url" >> "$HISTORY_FILE"
    tail -n "$HISTORY_SIZE" "$HISTORY_FILE" > "$HISTORY_FILE.tmp"
    mv "$HISTORY_FILE.tmp" "$HISTORY_FILE"
}

# Check if a URL is already in history
is_in_history() {
    local url="$1"
    grep -Fxq "$url" "$HISTORY_FILE" 2>/dev/null
}

# ============================================================
# MAIN LOOP
# ============================================================
while true; do
    # 1. Pick the next category from the shuffled deck
    SEARCH_TERM="${SHUFFLED_CATEGORIES[$CAT_INDEX]}"
    CAT_INDEX=$((CAT_INDEX + 1))

    # If we reached the end of the deck, reshuffle and reset
    if [ $CAT_INDEX -ge ${#SHUFFLED_CATEGORIES[@]} ]; then
        echo "$(date) - Finished a full category cycle. Reshuffling..." >> "$LOGFILE"
        shuffle_categories
        # Take the first category of the new cycle
        SEARCH_TERM="${SHUFFLED_CATEGORIES[0]}"
        CAT_INDEX=1
    fi

    echo "$(date) - Searching for: '$SEARCH_TERM'" >> "$LOGFILE"

    # 2. Fetch search results
    URL_LIST=$(deviousq --medium image --rating nonadult --return-field content_url --limit "$SEARCH_LIMIT" "$SEARCH_TERM" 2>/dev/null)

    if [ -z "$URL_LIST" ]; then
        echo "$(date) - No results for '$SEARCH_TERM'. Retrying..." >> "$LOGFILE"
        sleep "$SLEEP_INTERVAL"
        continue
    fi

    # 3. Try up to MAX_ATTEMPTS times to find a URL not in history
    RANDOM_URL=""
    for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
        CANDIDATE=$(echo "$URL_LIST" | shuf -n 1)
        if [ -n "$CANDIDATE" ] && ! is_in_history "$CANDIDATE"; then
            RANDOM_URL="$CANDIDATE"
            break
        fi
    done

    # 4. If still empty, fallback: pick the first URL not in history
    if [ -z "$RANDOM_URL" ]; then
        RANDOM_URL=$(echo "$URL_LIST" | grep -v -F -f "$HISTORY_FILE" | head -n 1)
    fi

    # 5. Ultimate fallback: just take the first URL (may repeat)
    if [ -z "$RANDOM_URL" ]; then
        RANDOM_URL=$(echo "$URL_LIST" | head -n 1)
        echo "$(date) - WARNING: All results in history. Using first result (will repeat)." >> "$LOGFILE"
    fi

    # 6. Download and set wallpaper
    if [ -n "$RANDOM_URL" ]; then
        TIMESTAMP=$(date +%s)
        WALLPAPER_FILE="/tmp/wallpaper_${TIMESTAMP}.jpg"

        wget -q -O "$WALLPAPER_FILE" "$RANDOM_URL"
        if [ $? -eq 0 ]; then
            plasma-apply-wallpaperimage "$WALLPAPER_FILE" > /dev/null 2>&1
            add_to_history "$RANDOM_URL"
            echo "$(date) - Wallpaper set from '$SEARCH_TERM' (file: $WALLPAPER_FILE)" >> "$LOGFILE"
        else
            echo "$(date) - ERROR: Failed to download image from $RANDOM_URL" >> "$LOGFILE"
        fi
    else
        echo "$(date) - No valid image found. Retrying..." >> "$LOGFILE"
    fi

    # 7. Clean up old wallpaper files (keep last 24 hours)
    find /tmp -name "wallpaper_*.jpg" -mtime +1 -delete 2>/dev/null

    sleep "$SLEEP_INTERVAL"
done
