#!/usr/bin/env bash

# ============================================================
# RANDOM WALLPAPER SCRIPT
# ============================================================

# ============================================================
# CONFIGURATION
# ============================================================
HISTORY_SIZE=2140000         # ~4 years of unique wallpapers (1 change/min)
SEARCH_LIMIT=100             # Fetch 100 results per search
SLEEP_INTERVAL=60            # Seconds between wallpaper changes
MAX_ATTEMPTS=100             # Try up to 100 random candidates before fallback

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
shuffle_categories() {
    SHUFFLED_CATEGORIES=(
        $(printf "%s\n" "${CATEGORIES[@]}" | shuf)
    )

    CAT_INDEX=0
}

shuffle_categories

# ============================================================
# HISTORY FUNCTIONS
# ============================================================
touch "$HISTORY_FILE"

# Add URL to history and keep only the newest HISTORY_SIZE entries
add_to_history() {
    local url="$1"

    echo "$url" >> "$HISTORY_FILE"

    tail -n "$HISTORY_SIZE" "$HISTORY_FILE" > "$HISTORY_FILE.tmp"

    mv "$HISTORY_FILE.tmp" "$HISTORY_FILE"
}

# Check whether a URL is already in history
is_in_history() {
    local url="$1"

    grep -Fxq "$url" "$HISTORY_FILE" 2>/dev/null
}

# ============================================================
# MAIN LOOP
# ============================================================
while true; do

    # --------------------------------------------------------
    # 1. PICK NEXT CATEGORY
    # --------------------------------------------------------

    SEARCH_TERM="${SHUFFLED_CATEGORIES[$CAT_INDEX]}"
    CAT_INDEX=$((CAT_INDEX + 1))

    # Finished a complete category cycle
    if [ "$CAT_INDEX" -ge "${#SHUFFLED_CATEGORIES[@]}" ]; then

        echo "$(date) - Finished a full category cycle. Reshuffling..." \
            >> "$LOGFILE"

        shuffle_categories

        SEARCH_TERM="${SHUFFLED_CATEGORIES[0]}"
        CAT_INDEX=1
    fi

    echo "$(date) - Searching for: '$SEARCH_TERM'" >> "$LOGFILE"

    # --------------------------------------------------------
    # 2. FETCH SEARCH RESULTS
    # --------------------------------------------------------

    URL_LIST=$(
        deviousq \
            --medium image \
            --rating nonadult \
            --return-field content_url \
            --limit "$SEARCH_LIMIT" \
            "$SEARCH_TERM" \
            2>/dev/null
    )

    if [ -z "$URL_LIST" ]; then

        echo "$(date) - No results for '$SEARCH_TERM'. Retrying..." \
            >> "$LOGFILE"

        sleep "$SLEEP_INTERVAL"
        continue
    fi

    # --------------------------------------------------------
    # 3. RANDOMLY TRY UP TO MAX_ATTEMPTS CANDIDATES
    # --------------------------------------------------------

    RANDOM_URL=""

    for attempt in $(seq 1 "$MAX_ATTEMPTS"); do

        CANDIDATE=$(printf '%s\n' "$URL_LIST" | shuf -n 1)

        if [ -n "$CANDIDATE" ] && ! is_in_history "$CANDIDATE"; then

            RANDOM_URL="$CANDIDATE"

            echo "$(date) - Found unseen URL on attempt $attempt/$MAX_ATTEMPTS" \
                >> "$LOGFILE"

            break
        fi
    done

    # --------------------------------------------------------
    # 4. RANDOMIZED UNSEEN FALLBACK
    # --------------------------------------------------------
    #
    # If random sampling did not find an unseen URL, inspect
    # the remaining result pool and randomly select an unseen
    # URL.
    #
    # --------------------------------------------------------

    if [ -z "$RANDOM_URL" ]; then

        RANDOM_URL=$(
            printf '%s\n' "$URL_LIST" |
            grep -v -F -f "$HISTORY_FILE" |
            shuf -n 1
        )

        if [ -n "$RANDOM_URL" ]; then
            echo "$(date) - Random unseen fallback selected." \
                >> "$LOGFILE"
        fi
    fi

    # --------------------------------------------------------
    # 5. ULTIMATE FALLBACK
    # --------------------------------------------------------
    #
    # This only occurs when every returned URL is already in
    # the history file.
    #
    # Random selection is still used to distribute repeats.
    #
    # --------------------------------------------------------

    if [ -z "$RANDOM_URL" ]; then

        RANDOM_URL=$(printf '%s\n' "$URL_LIST" | shuf -n 1)

        echo "$(date) - WARNING: All results are already in history. Using random repeat." \
            >> "$LOGFILE"
    fi

    # --------------------------------------------------------
    # 6. DOWNLOAD AND SET WALLPAPER
    # --------------------------------------------------------

    if [ -n "$RANDOM_URL" ]; then

        TIMESTAMP=$(date +%s)
        WALLPAPER_FILE="/tmp/wallpaper_${TIMESTAMP}.jpg"

        if wget -q -O "$WALLPAPER_FILE" "$RANDOM_URL"; then

            if plasma-apply-wallpaperimage \
                "$WALLPAPER_FILE" >/dev/null 2>&1; then

                add_to_history "$RANDOM_URL"

                echo "$(date) - Wallpaper set from '$SEARCH_TERM' (file: $WALLPAPER_FILE)" \
                    >> "$LOGFILE"

            else

                echo "$(date) - ERROR: Failed to apply wallpaper from $RANDOM_URL" \
                    >> "$LOGFILE"

                rm -f "$WALLPAPER_FILE"
            fi

        else

            echo "$(date) - ERROR: Failed to download image from $RANDOM_URL" \
                >> "$LOGFILE"

            rm -f "$WALLPAPER_FILE"
        fi

    else

        echo "$(date) - No valid image found. Retrying..." \
            >> "$LOGFILE"
    fi

    # --------------------------------------------------------
    # 7. CLEAN UP OLD WALLPAPER FILES
    # --------------------------------------------------------

    find /tmp \
        -name "wallpaper_*.jpg" \
        -mtime +1 \
        -delete \
        2>/dev/null

    sleep "$SLEEP_INTERVAL"

done
