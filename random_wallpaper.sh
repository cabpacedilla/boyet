#!/usr/bin/env bash
set -Eeuo pipefail

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"

# ============================================================
# VALIDATE HOME
# ============================================================
if [ -z "${HOME:-}" ] || [ ! -d "$HOME" ]; then
    echo "ERROR: HOME is not set or is not a valid directory" >&2
    exit 1
fi

# ============================================================
# CONFIGURATION - MUST BE DEFINED BEFORE ANY LOGGING
# ============================================================
HISTORY_SIZE=50000
SEARCH_LIMIT=100
MAX_ATTEMPTS=100
DEVIOUSQ_TIMEOUT=30
WGET_TIMEOUT=15
WGET_TOTAL_TIMEOUT=30

MIN_INTERVAL=45
MAX_INTERVAL=180

DEVIANTART_WEIGHT=60
VARIETY_WEIGHT=40
MAX_SAME_SOURCE=3

# ============================================================
# PATHS & SETUP
# ============================================================
# Create directories BEFORE touching files
if ! mkdir -p "$HOME/scriptlogs" 2>/dev/null; then
    echo "ERROR: Failed to create required directories" >&2
    exit 1
fi

# Secure scriptlogs directory - enforce 700
if ! chmod 700 "$HOME/scriptlogs" 2>/dev/null; then
    echo "ERROR: Failed to secure scriptlogs permissions" >&2
    exit 1
fi

LOGFILE="$HOME/scriptlogs/wallpaper.log"
HISTORY_FILE="$HOME/scriptlogs/wallpaper_history.txt"
DB_FILE="$HOME/scriptlogs/wallpaper_history.db"

# Create private temporary directory
TEMP_DIR=""
TEMP_DIR=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/random-wallpaper.XXXXXX" 2>/dev/null)
if [ -z "$TEMP_DIR" ] || [ ! -d "$TEMP_DIR" ]; then
    echo "ERROR: Failed to create private temporary directory" >&2
    exit 1
fi

# Secure temporary directory - enforce 700
if ! chmod 700 "$TEMP_DIR" 2>/dev/null; then
    echo "ERROR: Failed to secure temporary directory" >&2
    exit 1
fi

# ============================================================
# SINGLE-INSTANCE LOCK
# ============================================================
LOCK_FILE="$HOME/.cache/random_wallpaper.lock"
if ! mkdir -p "$(dirname "$LOCK_FILE")" 2>/dev/null; then
    echo "ERROR: Failed to create lock directory" >&2
    exit 1
fi

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "$(date) - Another instance is already running. Exiting."
    exit 1
fi

# ============================================================
# CLEANUP FUNCTION
# ============================================================
cleanup() {
    local exit_code=$?
    
    if [ -n "${LOGFILE:-}" ]; then
        echo "$(date) - Cleaning up (exit code: $exit_code)" >> "$LOGFILE" 2>/dev/null || true
    fi
    
    # Remove temporary directory
    if [ -n "${TEMP_DIR:-}" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR" 2>/dev/null || true
    fi
    
    # Release lock
    flock -u 9 2>/dev/null || true
    exec 9>&- 2>/dev/null || true
    
    exit $exit_code
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

# ============================================================
# NOW LOGGING IS SAFE - All variables are defined
# ============================================================
echo "$(date) - Weighted Random Wallpaper Script Started" >> "$LOGFILE"
echo "$(date) - History size: $HISTORY_SIZE, Interval: $MIN_INTERVAL-$MAX_INTERVAL sec" >> "$LOGFILE"
echo "$(date) - DA Weight: $DEVIANTART_WEIGHT, Variety Weight: $VARIETY_WEIGHT, Max Streak: $MAX_SAME_SOURCE" >> "$LOGFILE"
echo "$(date) - Temporary directory: $TEMP_DIR" >> "$LOGFILE"

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
    sha256sum
    awk
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

if (( SEARCH_LIMIT < 1 )); then
    echo "ERROR: SEARCH_LIMIT ($SEARCH_LIMIT) must be at least 1" >&2
    exit 1
fi

if (( MAX_ATTEMPTS < 1 )); then
    echo "ERROR: MAX_ATTEMPTS ($MAX_ATTEMPTS) must be at least 1" >&2
    exit 1
fi

if (( DEVIOUSQ_TIMEOUT < 1 )); then
    echo "ERROR: DEVIOUSQ_TIMEOUT ($DEVIOUSQ_TIMEOUT) must be at least 1" >&2
    exit 1
fi

if (( WGET_TIMEOUT < 1 )); then
    echo "ERROR: WGET_TIMEOUT ($WGET_TIMEOUT) must be at least 1" >&2
    exit 1
fi

if (( WGET_TOTAL_TIMEOUT < 1 )); then
    echo "ERROR: WGET_TOTAL_TIMEOUT ($WGET_TOTAL_TIMEOUT) must be at least 1" >&2
    exit 1
fi

if (( HISTORY_SIZE < 1 )); then
    echo "ERROR: HISTORY_SIZE ($HISTORY_SIZE) must be at least 1" >&2
    exit 1
fi

# ============================================================
# CATEGORIES
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
# CATEGORY CYCLING
# ============================================================
shuffle_categories() {
    mapfile -t SHUFFLED_CATEGORIES < <(
        printf '%s\n' "${CATEGORIES[@]}" | shuf
    )
    CAT_INDEX=0
}

shuffle_categories

# ============================================================
# INTERNET CHECK
# ============================================================
check_internet() {
    if curl -f -s --connect-timeout 2 --max-time 3 -o /dev/null "https://www.google.com" 2>/dev/null; then
        return 0
    fi
    return 1
}

# ============================================================
# URL VALIDATION & HASHING
# ============================================================
validate_url() {
    local url="$1"
    [[ "$url" =~ ^https?://[^/]+ ]]
}

hash_url() {
    local url="$1"
    printf '%s' "$url" | sha256sum | awk '{print $1}'
}

# ============================================================
# SECURE FILE PERMISSIONS
# ============================================================
secure_file() {
    local file="$1"
    if [ -f "$file" ]; then
        if ! chmod 600 "$file" 2>/dev/null; then
            echo "ERROR: Failed to secure permissions on $file" >&2
            return 1
        fi
    fi
    return 0
}

# ============================================================
# HISTORY MANAGEMENT
# ============================================================
USE_SQLITE=false

if command -v sqlite3 >/dev/null 2>&1; then
    USE_SQLITE=true
    echo "$(date) - Using SQLite history database with SHA-256 hashes" >> "$LOGFILE"
    
    if [ ! -f "$DB_FILE" ]; then
        echo "$(date) - Creating SQLite database..." >> "$LOGFILE"
        if ! sqlite3 "$DB_FILE" "CREATE TABLE history (hash TEXT PRIMARY KEY, timestamp INTEGER);" 2>/dev/null; then
            echo "ERROR: Failed to initialize SQLite database" >&2
            exit 1
        fi
        
        if ! chmod 600 "$DB_FILE" 2>/dev/null; then
            echo "ERROR: Failed to secure SQLite database permissions" >&2
            exit 1
        fi
        
        # Migrate existing history file if it exists
        if [ -f "$HISTORY_FILE" ] && [ -s "$HISTORY_FILE" ]; then
            echo "$(date) - Migrating existing history file to SQLite..." >> "$LOGFILE"
            migrated_count=0
            migration_timestamp=$(date +%s)
            
            sql_statements="BEGIN IMMEDIATE;"
            while IFS= read -r url; do
                if [ -n "$url" ] && validate_url "$url"; then
                    url_hash=$(hash_url "$url")
                    timestamp=$((migration_timestamp + migrated_count))
                    sql_statements="${sql_statements}INSERT OR REPLACE INTO history (hash, timestamp) VALUES ('$url_hash', $timestamp);"
                    migrated_count=$((migrated_count + 1))
                fi
            done < "$HISTORY_FILE"
            
            sql_statements="${sql_statements}DELETE FROM history WHERE hash IN (SELECT hash FROM history ORDER BY timestamp DESC LIMIT -1 OFFSET $HISTORY_SIZE);"
            sql_statements="${sql_statements}COMMIT;"
            
            if echo "$sql_statements" | sqlite3 "$DB_FILE" 2>/dev/null; then
                echo "$(date) - Migrated $migrated_count entries to SQLite" >> "$LOGFILE"
                mv "$HISTORY_FILE" "${HISTORY_FILE}.migrated.$(date +%s)" 2>/dev/null || true
            else
                echo "$(date) - ERROR: Migration failed" >> "$LOGFILE"
                exit 1
            fi
        fi
    else
        if ! secure_file "$DB_FILE"; then
            echo "ERROR: Failed to secure existing SQLite database" >&2
            exit 1
        fi
    fi
    
    add_to_history() {
        local url="$1"
        if [ -z "$url" ] || ! validate_url "$url"; then
            echo "$(date) - WARNING: Invalid URL for history: $url" >> "$LOGFILE"
            return 1
        fi
        
        url_hash=$(hash_url "$url")
        timestamp=$(date +%s)
        
        if sqlite3 "$DB_FILE" <<SQL 2>/dev/null
BEGIN IMMEDIATE;
INSERT OR REPLACE INTO history (hash, timestamp) VALUES ('$url_hash', $timestamp);
DELETE FROM history WHERE hash IN (SELECT hash FROM history ORDER BY timestamp DESC LIMIT -1 OFFSET $HISTORY_SIZE);
COMMIT;
SQL
        then
            return 0
        else
            echo "$(date) - ERROR: SQLite transaction failed" >> "$LOGFILE"
            return 1
        fi
    }
    
    is_in_history() {
        local url="$1"
        if [ -z "$url" ]; then
            return 2
        fi
        
        url_hash=$(hash_url "$url")
        count=""
        if ! count=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM history WHERE hash='$url_hash';" 2>/dev/null); then
            echo "$(date) - ERROR: SQLite history query failed" >> "$LOGFILE"
            return 2
        fi
        
        if [[ ! "$count" =~ ^[0-9]+$ ]]; then
            echo "$(date) - ERROR: Invalid SQLite count output: '$count'" >> "$LOGFILE"
            return 2
        fi
        
        if [ "$count" -gt 0 ]; then
            return 0
        else
            return 1
        fi
    }
    
    load_history() {
        count=""
        if ! count=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM history;" 2>/dev/null); then
            echo "$(date) - ERROR: SQLite history count query failed" >> "$LOGFILE"
            return 1
        fi
        
        if [[ ! "$count" =~ ^[0-9]+$ ]]; then
            echo "$(date) - ERROR: Invalid SQLite count output: '$count'" >> "$LOGFILE"
            return 1
        fi
        
        echo "$(date) - SQLite history contains $count entries" >> "$LOGFILE"
        return 0
    }
    load_history
    
else
    USE_SQLITE=false
    echo "$(date) - WARNING: sqlite3 not found, using file-based history" >> "$LOGFILE"
    
    if ! touch "$HISTORY_FILE" 2>/dev/null; then
        echo "ERROR: Failed to create history file at $HISTORY_FILE" >&2
        exit 1
    fi
    
    if ! secure_file "$HISTORY_FILE"; then
        echo "ERROR: Failed to secure history file" >&2
        exit 1
    fi
    
    declare -A HISTORY_CACHE
    
    load_history() {
        if [ -f "$HISTORY_FILE" ]; then
            HISTORY_CACHE=()
            count=0
            while IFS= read -r url; do
                if [ -n "$url" ] && validate_url "$url"; then
                    HISTORY_CACHE["$url"]=1
                    count=$((count + 1))
                fi
            done < "$HISTORY_FILE"
            echo "$(date) - Loaded $count valid history entries into cache" >> "$LOGFILE"
        fi
    }
    
    add_to_history() {
        local url="$1"
        if [ -z "$url" ] || ! validate_url "$url"; then
            echo "$(date) - WARNING: Invalid URL for history: $url" >> "$LOGFILE"
            return 1
        fi
        
        HISTORY_CACHE["$url"]=1
        echo "$url" >> "$HISTORY_FILE"
        
        line_count=$(wc -l < "$HISTORY_FILE" 2>/dev/null || echo 0)
        if [ "$line_count" -gt "$((HISTORY_SIZE * 2))" ]; then
            temp_file=""
            temp_file=$(mktemp "${HISTORY_FILE}.tmp.XXXXXX" 2>/dev/null)
            if [ -z "$temp_file" ]; then
                echo "$(date) - ERROR: Failed to create temporary file for history" >> "$LOGFILE"
                return 1
            fi
            tail -n "$HISTORY_SIZE" "$HISTORY_FILE" > "$temp_file"
            if ! mv -- "$temp_file" "$HISTORY_FILE"; then
                echo "$(date) - ERROR: Failed to replace history file" >> "$LOGFILE"
                rm -f -- "$temp_file"
                return 1
            fi
            if ! secure_file "$HISTORY_FILE"; then
                echo "$(date) - ERROR: Failed to secure trimmed history file" >> "$LOGFILE"
                return 1
            fi
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
    
    load_history
fi

# Secure log file
if ! secure_file "$LOGFILE"; then
    echo "ERROR: Failed to secure log file permissions" >&2
    exit 1
fi

# ============================================================
# VARIETY MANAGEMENT
# ============================================================
use_variety() {
    if ! command -v variety >/dev/null 2>&1; then
        echo "$(date) - WARNING: Variety is not installed" >> "$LOGFILE"
        return 1
    fi
    
    variety --next >/dev/null 2>&1
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
# DEVIANTART WALLPAPER FETCHER
# ============================================================
fetch_deviantart_wallpaper() {
    current_category="${SHUFFLED_CATEGORIES[$CAT_INDEX]}"
    
    echo "$(date) - [DeviantArt] Searching: '$current_category'" >> "$LOGFILE"
    
    URL_LIST=""
    URL_LIST=$(timeout "${DEVIOUSQ_TIMEOUT}s" deviousq \
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
    
    if [ "${#URL_ARRAY[@]}" -eq 0 ]; then
        echo "$(date) - [DeviantArt] ERROR: Empty URL array" >> "$LOGFILE"
        return 1
    fi
    
    RANDOM_URL=""
    
    for ((attempt = 1; attempt <= MAX_ATTEMPTS; attempt++)); do
        CANDIDATE=""
        CANDIDATE="${URL_ARRAY[$((RANDOM % ${#URL_ARRAY[@]}))]}"
        if [ -n "$CANDIDATE" ] && validate_url "$CANDIDATE"; then
            if is_in_history "$CANDIDATE"; then
                history_status=0
            else
                history_status=$?
            fi
            
            case "$history_status" in
                0) continue ;;
                1)
                    RANDOM_URL="$CANDIDATE"
                    echo "$(date) - [DeviantArt] Found unseen URL (attempt $attempt)" >> "$LOGFILE"
                    break
                    ;;
                2)
                    echo "$(date) - [DeviantArt] WARNING: History check failed for URL" >> "$LOGFILE"
                    continue
                    ;;
                *)
                    continue
                    ;;
            esac
        fi
    done
    
    if [ -z "$RANDOM_URL" ]; then
        for candidate in "${URL_ARRAY[@]}"; do
            if validate_url "$candidate"; then
                if is_in_history "$candidate"; then
                    history_status=0
                else
                    history_status=$?
                fi
                
                case "$history_status" in
                    0) continue ;;
                    1)
                        RANDOM_URL="$candidate"
                        echo "$(date) - [DeviantArt] Fallback: found unseen URL" >> "$LOGFILE"
                        break
                        ;;
                    2)
                        echo "$(date) - [DeviantArt] WARNING: History check failed for URL" >> "$LOGFILE"
                        continue
                        ;;
                    *) continue ;;
                esac
            fi
        done
    fi
    
    if [ -z "$RANDOM_URL" ]; then
        RANDOM_URL="${URL_ARRAY[$((RANDOM % ${#URL_ARRAY[@]}))]}"
        echo "$(date) - [DeviantArt] WARNING: Using random repeat" >> "$LOGFILE"
    fi
    
    if ! validate_url "$RANDOM_URL"; then
        echo "$(date) - [DeviantArt] ERROR: Invalid URL: $RANDOM_URL" >> "$LOGFILE"
        return 1
    fi
    
    TEMP_FILE=""
    TEMP_FILE=$(mktemp "$TEMP_DIR/wallpaper_XXXXXX.jpg" 2>/dev/null)
    
    if [ -z "$TEMP_FILE" ]; then
        echo "$(date) - [DeviantArt] ERROR: mktemp failed" >> "$LOGFILE"
        return 1
    fi
    
    wget_exit=0
    timeout "${WGET_TOTAL_TIMEOUT}s" wget -q --timeout="${WGET_TIMEOUT}" --tries=1 -O "$TEMP_FILE" -- "$RANDOM_URL" 2>/dev/null || wget_exit=$?
    
    if [ $wget_exit -eq 0 ]; then
        MIME_TYPE=""
        MIME_TYPE=$(file -b --mime-type "$TEMP_FILE" 2>/dev/null)
        
        if [[ "$MIME_TYPE" == image/* ]]; then
            if plasma-apply-wallpaperimage "$TEMP_FILE" >/dev/null 2>&1; then
                if ! add_to_history "$RANDOM_URL"; then
                    echo "$(date) - [DeviantArt] WARNING: Wallpaper applied but history update failed" >> "$LOGFILE"
                fi
                
                echo "$(date) - [DeviantArt] Wallpaper set from '$current_category'" >> "$LOGFILE"
                rm -f "$TEMP_FILE"
                
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
        if [ $wget_exit -eq 124 ]; then
            echo "$(date) - [DeviantArt] ERROR: Download timed out (${WGET_TOTAL_TIMEOUT}s total)" >> "$LOGFILE"
        else
            echo "$(date) - [DeviantArt] ERROR: Download failed (wget exit: $wget_exit)" >> "$LOGFILE"
        fi
        rm -f "$TEMP_FILE"
        return 1
    fi
}

# ============================================================
# SOURCE SELECTION
# ============================================================
select_source() {
    if [ "$DEVIANTART_WEIGHT" -eq 0 ] && [ "$VARIETY_WEIGHT" -gt 0 ]; then
        printf '%s\n' "variety"
        return 0
    fi
    
    if [ "$VARIETY_WEIGHT" -eq 0 ] && [ "$DEVIANTART_WEIGHT" -gt 0 ]; then
        printf '%s\n' "deviantart"
        return 0
    fi
    
    total_weight=$((DEVIANTART_WEIGHT + VARIETY_WEIGHT))
    rand=$((RANDOM % total_weight))
    
    if [ $rand -lt $DEVIANTART_WEIGHT ]; then
        printf '%s\n' "deviantart"
    else
        printf '%s\n' "variety"
    fi
}

get_opposite_source() {
    local source="$1"
    
    if [ "$source" = "deviantart" ]; then
        if [ "$VARIETY_WEIGHT" -gt 0 ]; then
            printf '%s\n' "variety"
        else
            printf '%s\n' "deviantart"
        fi
    else
        if [ "$DEVIANTART_WEIGHT" -gt 0 ]; then
            printf '%s\n' "deviantart"
        else
            printf '%s\n' "variety"
        fi
    fi
}

# ============================================================
# STATE MANAGEMENT
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
# FALLBACK HANDLER
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

    if [ "$fallback_source" = "variety" ] && [ "$VARIETY_WEIGHT" -eq 0 ]; then
        echo "$(date) - Fallback to Variety disabled (weight=0)" >> "$LOGFILE"
        return 1
    fi
    
    if [ "$fallback_source" = "deviantart" ] && [ "$DEVIANTART_WEIGHT" -eq 0 ]; then
        echo "$(date) - Fallback to DeviantArt disabled (weight=0)" >> "$LOGFILE"
        return 1
    fi

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
    delay=$((MIN_INTERVAL + RANDOM % (MAX_INTERVAL - MIN_INTERVAL + 1)))
    echo "$(date) - Sleeping for $delay seconds" >> "$LOGFILE"
    sleep "$delay"
}

# ============================================================
# STATE VARIABLES
# ============================================================
IS_ONLINE=false
CURRENT_SOURCE=""
SAME_SOURCE_COUNT=0

# ============================================================
# MAIN LOOP
# ============================================================
while true; do
    find "$TEMP_DIR" -type f -name 'wallpaper_*.jpg' -mtime +1 -delete 2>/dev/null
    
    if check_internet; then
        if [ "$IS_ONLINE" = false ]; then
            echo "$(date) - ONLINE: Internet detected" >> "$LOGFILE"
            IS_ONLINE=true
            CURRENT_SOURCE=""
            SAME_SOURCE_COUNT=0
        fi
        
        SELECTED_SOURCE=""
        
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
            SELECTED_SOURCE=$(select_source)
        fi
        
        echo "$(date) - [Online] Selected $SELECTED_SOURCE (current streak: $SAME_SOURCE_COUNT/$MAX_SAME_SOURCE)" >> "$LOGFILE"
        
        success=false
        ACTUAL_SOURCE=""

        if ACTUAL_SOURCE=$(attempt_source_with_fallback "$SELECTED_SOURCE"); then
            success=true
            update_source_state "$ACTUAL_SOURCE"
            echo "$(date) - [Success] Source: $ACTUAL_SOURCE (streak: $SAME_SOURCE_COUNT/$MAX_SAME_SOURCE)" >> "$LOGFILE"
        fi
        
        if [ "$success" = true ]; then
            random_delay
        else
            echo "$(date) - Both modes failed or fallback was blocked, waiting 30 seconds" >> "$LOGFILE"
            sleep 30
        fi
        
    else
        if [ "$IS_ONLINE" = true ]; then
            echo "$(date) - OFFLINE: Internet lost - switching to Variety-only" >> "$LOGFILE"
            IS_ONLINE=false
        fi
        
        echo "$(date) - [Offline] Using Variety" >> "$LOGFILE"
        
        if use_variety; then
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
