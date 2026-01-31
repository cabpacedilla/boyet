#!/usr/bin/env bash

# Nature & Science "Major Discovery" Monitor
# Version: 2.0 (Criticality & Keyword Logic)

# --- PATHS ---
HISTORY_FILE="$HOME/.cache/discovery_mega_history.log"
LOGFILE="$HOME/scriptlogs/discovery_mega.log"
MUTE_FILE="$HOME/MUTE_SCIENCE"

# --- FEEDS ---
FEEDS=(
    "https://www.nature.com/nature/research-articles.rss"
    "https://www.science.org/rss/news_current.xml"
)

# --- KEYWORDS ---
# Signals: General keywords to trigger a normal notification
SIGNALS="Discovery|Breakthrough|Universal|Mechanism|Solved|Observation|First|Novel|Paradigm|CRISPR|Spotted|Signals|Detected"

# Criticals: High-value keywords that trigger "Critical" urgency and unique icons
CRITICALS="Superconductor|Fusion|AGI|Quantum|Room-temperature|Exoplanet|Earth-size|Cataclysm"

# --- CONFIG ---
TEST_MODE=false           # Set to true to notify about EVERY new article
BURST_LIMIT=5             # Max immediate notifications before batch summary
SLEEP_TIME=1200           # 20 minutes between checks

# --- PREP ---
mkdir -p "$(dirname "$LOGFILE")" "$(dirname "$HISTORY_FILE")"
touch "$HISTORY_FILE"

echo "$(date '+%Y-%m-%d %H:%M:%S') - Monitor started. Mute with: touch $MUTE_FILE" >> "$LOGFILE"

while true; do
    if [[ -f "$MUTE_FILE" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Muted. Sleeping 60s..." >> "$LOGFILE"
        sleep 60
        continue
    fi

    START_COUNT=$(wc -l < "$HISTORY_FILE" 2>/dev/null || echo 0)
    CURRENT_BATCH_NOTIFS=0

    for URL in "${FEEDS[@]}"; do
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Checking: $URL" >> "$LOGFILE"

        RAW_XML=$(curl -sL --connect-timeout 10 --max-time 30 "$URL") || {
            echo "$(date '+%Y-%m-%d %H:%M:%S') - curl failed: $URL" >> "$LOGFILE"
            continue
        }

        # Normalize XML to a single line to make Regex parsing easier
        NORMALIZED=$(echo "$RAW_XML" | tr '\r\n\t' ' ' | sed 's/>\s*</></g; s/\s\+/ /g')

        # Extract items
        ITEMS=$(echo "$NORMALIZED" | grep -oP '<item[^>]*>.*?</item>' | sed 's/<\/item>/<\/item>\n/g')

        while IFS= read -r ITEM; do
            [[ -z "$ITEM" ]] && continue

            # --- EXTRACT TITLE ---
            TITLE=$(echo "$ITEM" | grep -oP '<title[^>]*>.*?</title>' | \
                sed 's/.*<title[^>]*>//; s/<\/title>.*//; s/<!\[CDATA\[//; s/\]\]>//' | xargs)

            # --- EXTRACT LINK ---
            LINK=$(echo "$ITEM" | grep -oP '<link[^>]*>[^<]*</link>' | sed 's/.*<link[^>]*>//; s/<\/link>.*//' | head -n 1 | xargs)
            
            # Fallback for link in attributes
            if [[ -z "$LINK" ]]; then
                LINK=$(echo "$ITEM" | grep -oP 'rdf:about="[^"]*"' | cut -d'"' -f2 | head -n 1)
            fi

            [[ -z "$TITLE" || -z "$LINK" ]] && continue

            # --- DEDUPLICATION ---
            grep -qF "$LINK" "$HISTORY_FILE" 2>/dev/null && continue

            # --- DECIDE NOTIFICATION TYPE ---
            SHOULD_NOTIFY=false
            URGENCY="normal"
            ICON="utilities-terminal"
            DISPLAY_SOURCE="Journal Update"

            [[ "$URL" == *"nature.com"* ]] && DISPLAY_SOURCE="Nature"
            [[ "$URL" == *"science.org"* ]] && DISPLAY_SOURCE="Science"

            if [[ "$TEST_MODE" == true ]]; then
                SHOULD_NOTIFY=true
            elif echo "$TITLE" | grep -qiE "$CRITICALS"; then
                SHOULD_NOTIFY=true
                URGENCY="critical"
                ICON="emblem-important"
                DISPLAY_SOURCE="🔥 BREAKTHROUGH: $DISPLAY_SOURCE"
            elif echo "$TITLE" | grep -qiE "$SIGNALS"; then
                SHOULD_NOTIFY=true
            fi

            [[ "$SHOULD_NOTIFY" != true ]] && continue

            # --- RECORD ---
            echo "$TITLE | $LINK | $DISPLAY_SOURCE" >> "$HISTORY_FILE"
            ((CURRENT_BATCH_NOTIFS++))

            # --- SEND NOTIFICATION ---
            if [[ $CURRENT_BATCH_NOTIFS -le $BURST_LIMIT ]]; then
                (
                    ACTION=$(notify-send -u "$URGENCY" -i "$ICON" -t 0 "💎 $DISPLAY_SOURCE" "$TITLE" \
                        --action="open=Read Article" 2>/dev/null)
                    [[ "$ACTION" == "open" ]] && xdg-open "$LINK" 2>/dev/null
                ) &
            fi

            echo "$(date '+%Y-%m-%d %H:%M:%S') - [NEW] [$DISPLAY_SOURCE] $TITLE" >> "$LOGFILE"

        done <<< "$ITEMS"
    done

    # --- SUMMARY FOR BURSTS ---
    if [[ $CURRENT_BATCH_NOTIFS -gt $BURST_LIMIT ]]; then
        notify-send -u normal "📦 Journal Batch" "Found $CURRENT_BATCH_NOTIFS articles. Checked logs for full list."
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') - Cycle done. Sleeping 20m..." >> "$LOGFILE"
    sleep $SLEEP_TIME
done
