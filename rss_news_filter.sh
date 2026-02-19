#!/usr/bin/env bash

LOCK_FILE="/tmp/rss_news_filter_$(whoami).lock"
exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
    exit 1
fi

# Store our PID
echo $$ > "$LOCK_FILE"

# Enhanced cleanup that only removes our PID file
cleanup() {
    # Only remove if it's our PID (prevents removing another process's lock)
    if [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$$" ]]; then
        rm -f "$LOCK_FILE"
    fi
    flock -u 9
    exec 9>&-
}

trap cleanup EXIT

# --- CONFIGURATION ---
LOG_FILE="$HOME/.cache/practical_science_history.log"
CACHE_DIR="/tmp/sciencemonitor_cache"
mkdir -p "$(dirname "$LOG_FILE")" "$CACHE_DIR"
ALERT_EMAIL="cabpacedilla@gmail.com"

# 1. MUST declare associative array BEFORE assigning values
declare -A KEYWORD_WEIGHTS

FEEDS=(
    "https://www.nature.com/nature/research-articles.rss"
    "https://phys.org/rss-feed/"
    "https://www.newscientist.com/section/news/feed/"
    "https://www.eurekalert.org/rss/breaking.xml"
    "https://www.quantamagazine.org/feed/"
    "https://www.sciencedaily.com/rss/top/science.xml"
    "https://www.sciencedaily.com/rss/top/health.xml"
    "https://www.sciencedaily.com/rss/top/environment.xml"
    "https://www.sciencedaily.com/rss/top/technology.xml"
    "https://www.sciencedaily.com/rss/mind_brain.xml"
    "https://www.sciencedaily.com/rss/health_medicine/nutrition.xml"
    "https://www.sciencedaily.com/rss/health_medicine/fitness.xml"
    "https://www.sciencedaily.com/rss/mind_brain/sleep.xml"
    "https://www.technologyreview.com/feed/"
    "https://newatlas.com/index.rss"
    "https://news.ycombinator.com/rss"
    "https://hnrss.org/best"
    "http://feeds.arstechnica.com/arstechnica/index"
    "https://news.mit.edu/rss/topic/computer-science-and-technology"
    "https://thehackernews.com/feeds/posts/default"
)

KEYWORD_WEIGHTS=(
    ["fda approved"]=12 ["human trial"]=10 ["phase 3"]=10 
    ["cured"]=12 ["breakthrough"]=7 ["world first"]=8 
    ["quantum"]=5 ["battery"]=4 ["superconductor"]=6
)

echo "🔭 Science Monitor Started. Checking ${#FEEDS[@]} feeds..."

# --- HELPER: HTML DECODER ---
decode() {
    echo "$1" | sed "s/&quot;/\"/g; s/&amp;/\&/g; s/&lt;/</g; s/&gt;/>/g; s/&#039;/'/g; s/&#x27;/'/g"
}

# --- MAIN ENGINE ---
fetch_and_process() {
    for URL in "${FEEDS[@]}"; do
        RAW_XML=$(curl -sL -A "Mozilla/5.0" --connect-timeout 10 "$URL")
        [[ -z "$RAW_XML" ]] && continue

        # Split items into new lines
        ITEMS=$(echo "$RAW_XML" | sed -e 's/<\/item>/<\/item>\n/g' -e 's/<\/entry>/<\/entry>\n/g' | grep -E '<item|<entry')

        while IFS= read -r ITEM; do
            [[ -z "$ITEM" ]] && continue

            TITLE=$(echo "$ITEM" | sed -n 's/.*<title[^>]*>\(.*\)<\/title>.*/\1/p' | sed 's/<!\[CDATA\[//g;s/\]\]>//g' | head -n1 | xargs)
            TITLE=$(decode "$TITLE")
            
            LINK=$(echo "$ITEM" | sed -n 's/.*<link>\([^<]*\)<\/link>.*/\1/p' | head -n1)
            [[ -z "$LINK" ]] && LINK=$(echo "$ITEM" | sed -n 's/.*href="\([^"]*\)".*/\1/p' | head -n1)
            
            [[ -z "$TITLE" || -z "$LINK" ]] && continue

            CONTENT_HASH=$(echo "$TITLE" | md5sum | cut -d' ' -f1)
            if grep -q "$CONTENT_HASH" "$LOG_FILE"; then continue; fi

            # Scoring logic
            SCORE=1
            LOWER_TITLE=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]')
            for kw in "${!KEYWORD_WEIGHTS[@]}"; do
                [[ "$LOWER_TITLE" == *"$kw"* ]] && SCORE=$((SCORE + KEYWORD_WEIGHTS[$kw]))
            done

            SOURCE=$(echo "$LINK" | awk -F[/:] '{print $4}' | sed 's/^www\.//')
            DATE=$(date '+%Y-%m-%d %H:%M')

            # LOGGING: Matches your new() function
            echo "$DATE | $SCORE | $SOURCE | $TITLE | $LINK | $CONTENT_HASH" >> "$LOG_FILE"

            # NOTIFICATION
            (
                RESPONSE=$(notify-send -u normal -t 10000 \
                    --print-id --action="read=Read Article" \
                    "💎 $SOURCE [$SCORE]" "$TITLE" 2>/dev/null)
                
                if [[ "$RESPONSE" == "read" ]]; then
                    xdg-open "$LINK" >/dev/null 2>&1 &
                fi

                echo -e "Subject: $TITLE\n\nDate: $DATE\nScore: $SCORE\nSource: $SOURCE\nTitle: $TITLE\nLink: $LINK" | msmtp -t "$ALERT_EMAIL"
            ) &

        done <<< "$ITEMS"
    done
}

# --- LOOP ---
while true; do
    fetch_and_process
    sleep 1200
done
