#!/usr/bin/env bash

# Nature & Science "Daily Life & Utility" Monitor
# Version: 3.0 (Focus: Practical News & Human Impact)

# --- PATHS ---
HISTORY_FILE="$HOME/.cache/practical_science_history.log"
LOGFILE="$HOME/scriptlogs/practical_science.log"
MUTE_FILE="$HOME/MUTE_SCIENCE"

# --- FEEDS (Added Practical/Life Science Feeds) ---
FEEDS=(
    "https://www.nature.com/nature/research-articles.rss"
    "https://www.science.org/rss/news_current.xml"
    "https://www.sciencedaily.com/rss/top/health.xml"       # Added for health utility
    "https://www.sciencedaily.com/rss/top/environment.xml" # Added for climate/nature
)

# --- KEYWORDS ---
# Signals: Practical daily life topics
SIGNALS="Nutrition|Sleep|Exercise|Mental|Vaccine|Diet|Microbiome|Habit|Cognitive|Stress|Pollution|Climate|Plastic|Longevity"

# Criticals: High-impact or immediate utility
CRITICALS="Treatment|Cure|Toxin|Warning|Efficacy|Guidelines|FDA|Breakthrough|Prevention|Immunity|Sustainability"

# --- CONFIG ---
TEST_MODE=false
BURST_LIMIT=5
SLEEP_TIME=1200 # 20 minutes

# --- PREP ---
mkdir -p "$(dirname "$LOGFILE")" "$(dirname "$HISTORY_FILE")"
touch "$HISTORY_FILE"

echo "$(date '+%Y-%m-%d %H:%M:%S') - Practical Monitor started." >> "$LOGFILE"

while true; do
    if [[ -f "$MUTE_FILE" ]]; then
        sleep 60
        continue
    fi

    CURRENT_BATCH_NOTIFS=0

    for URL in "${FEEDS[@]}"; do
        RAW_XML=$(curl -sL --connect-timeout 10 --max-time 30 "$URL") || continue
        NORMALIZED=$(echo "$RAW_XML" | tr '\r\n\t' ' ' | sed 's/>\s*</></g; s/\s\+/ /g')
        ITEMS=$(echo "$NORMALIZED" | grep -oP '<item[^>]*>.*?</item>' | sed 's/<\/item>/<\/item>\n/g')

        while IFS= read -r ITEM; do
            [[ -z "$ITEM" ]] && continue

            # --- EXTRACT DATA ---
            TITLE=$(echo "$ITEM" | grep -oP '<title[^>]*>.*?</title>' | \
                sed 's/.*<title[^>]*>//; s/<\/title>.*//; s/<!\[CDATA\[//; s/\]\]>//' | xargs)
            LINK=$(echo "$ITEM" | grep -oP '<link[^>]*>[^<]*</link>' | sed 's/.*<link[^>]*>//; s/<\/link>.*//' | head -n 1 | xargs)
            
            # Fallback for link in attributes
            if [[ -z "$LINK" ]]; then
                LINK=$(echo "$ITEM" | grep -oP 'rdf:about="[^"]*"' | cut -d'"' -f2 | head -n 1)
            fi

            [[ -z "$TITLE" || -z "$LINK" ]] && continue
            grep -qF "$LINK" "$HISTORY_FILE" 2>/dev/null && continue

            # --- CLASSIFY ---
            SHOULD_NOTIFY=false
            URGENCY="normal"
            ICON="appointment-soon"
            DISPLAY_SOURCE="Science Update"
            
            # Source Labeling
            [[ "$URL" == *"nature.com"* ]] && DISPLAY_SOURCE="Nature"
            [[ "$URL" == *"science.org"* ]] && DISPLAY_SOURCE="Science"
            [[ "$URL" == *"sciencedaily.com"* ]] && DISPLAY_SOURCE="Practical News"

            # Keyword Logic
            if [[ "$TEST_MODE" == true ]]; then
                SHOULD_NOTIFY=true
            elif echo "$TITLE" | grep -qiE "$CRITICALS"; then
                SHOULD_NOTIFY=true
                URGENCY="critical"
                ICON="emblem-important"
                DISPLAY_SOURCE="🚨 IMPORTANT: $DISPLAY_SOURCE"
            elif echo "$TITLE" | grep -qiE "$SIGNALS"; then
                SHOULD_NOTIFY=true
                ICON="media-record"
            fi

            [[ "$SHOULD_NOTIFY" != true ]] && continue

            # --- NOTIFY ---
            echo "$TITLE | $LINK | $DISPLAY_SOURCE" >> "$HISTORY_FILE"
            ((CURRENT_BATCH_NOTIFS++))

            if [[ $CURRENT_BATCH_NOTIFS -le $BURST_LIMIT ]]; then
                (
                    FINAL_BODY="$TITLE"
                    [[ "$URGENCY" == "critical" ]] && FINAL_BODY="<b>$TITLE</b>"
                    ACTION=$(notify-send -u "$URGENCY" -i "$ICON" -t 0 "💡 $DISPLAY_SOURCE" "$FINAL_BODY" --action="open=Read More")
                    [[ "$ACTION" == "open" ]] && xdg-open "$LINK"
                ) &
            fi
        done <<< "$ITEMS"
    done
    sleep $SLEEP_TIME
done
