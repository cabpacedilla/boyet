#!/usr/bin/env bash

# File paths
HISTORY_FILE="/home/claiveapa/.cache/practical_science_history.log"
SIGNALS="Nutrition|Sleep|Exercise|Mental|Vaccine|Diet|Microbiome|Habit|Cognitive|Stress|Pollution|Climate|Plastic|Longevity|Health|Brain|Medicine|Aging|Cannabis|Mosquito|Virus|Bacteria|Ocean|Fruit|Plant|Genetic|DNA|Genome|AI|Deep Learning|Chemical|Origin|Space|Ice"
CRITICALS="Treatment|Cure|Toxin|Warning|Efficacy|Guidelines|FDA|Breakthrough|Prevention|Immunity|Sustainability|Discovery|Ancient|Himalayas|Darkwaves|Seafloor|Axion|Dangerous|Risk|Threat|Undetected|Record|Resurrect|Enzyme|Quantum|X-ray|Infection|Antibiotic"

# RSS Feeds
FEEDS=(
    "https://www.nature.com/nature/research-articles.rss"
    "https://www.science.org/rss/news_current.xml"
    "https://www.sciencedaily.com/rss/top/health.xml"
    "https://www.sciencedaily.com/rss/top/environment.xml"
)

touch "$HISTORY_FILE"

while true; do
    for URL in "${FEEDS[@]}"; do
        RAW_XML=$(curl -sL --connect-timeout 20 "$URL") || continue
        # Standardize XML to one item per line for easier processing
        ITEMS=$(echo "$RAW_XML" | tr '\r\n\t' ' ' | sed 's/<item/\n<item/g' | grep '<item')

        while IFS= read -r ITEM || [[ -n "$ITEM" ]]; do
            [[ -z "$ITEM" ]] && continue

            # 1. Extraction
            TITLE=$(echo "$ITEM" | grep -oP '<title[^>]*>\s*<!\[CDATA\[\K.*?(?=\]\]>)' || echo "$ITEM" | grep -oP '<title[^>]*>\K[^<]+')
            TITLE=$(echo "$TITLE" | sed 's/&amp;/&/g; s/&lt;/</g; s/&gt;/>/g' | xargs)
            
            LINK=$(echo "$ITEM" | grep -oP '<link>\K[^<]+' || echo "$ITEM" | grep -oP 'rdf:about="\K[^"]+')
            LINK=$(echo "$LINK" | cut -d'?' -f1 | xargs)

            DESC=$(echo "$ITEM" | grep -oP '<description[^>]*>\s*<!\[CDATA\[\K.*?(?=\]\]>)' || echo "$ITEM" | grep -oP '<description[^>]*>\K[^<]+')

            # 2. Basic Validation (Ignore empty titles or publisher links)
            [[ -z "$TITLE" || -z "$LINK" || "$LINK" == *"atypon.com"* ]] && continue
            
            # 3. Duplicate Check: Skip if already in history
            grep -qF "$LINK" "$HISTORY_FILE" 2>/dev/null && continue

            # 4. Filter Check: Scan for keywords
            CONTENT_TO_SCAN="$TITLE $DESC"
            TAG=""
            SHOULD_PROCESS=false
            
            if echo "$CONTENT_TO_SCAN" | grep -qiE "$CRITICALS"; then
                TAG="🔥 BREAKTHROUGH"
                SHOULD_PROCESS=true
            elif echo "$CONTENT_TO_SCAN" | grep -qiE "$SIGNALS"; then
                TAG="Health/Env"
                SHOULD_PROCESS=true
            fi

            # 5. Logging & Notification (Only for items that pass the filter)
            if [[ "$SHOULD_PROCESS" == true ]]; then
                SOURCE="Discovery"
                [[ "$URL" == *"nature.com"* ]] && SOURCE="Nature"
                [[ "$URL" == *"science.org"* ]] && SOURCE="Science"
                [[ "$URL" == *"sciencedaily.com"* ]] && SOURCE="Practical News"

                # TIMESTAMP for the log
                TIMESTAMP=$(date "+%Y-%m-%d %H:%M")

                # LOGGING: Write to the history file immediately
                printf '[%s][%s: %s] %s\n%s\n\n' "$TIMESTAMP" "$TAG" "$SOURCE" "$TITLE" "$LINK" >> "$HISTORY_FILE"
                
                # NOTIFICATION: Send critical alert
                (
                    RES=$(notify-send -u critical -a "ScienceMonitor" -t 0 \
                        --action="open=Read Article" \
                        "💡 $TAG" "$TITLE")
                    
                    [[ "$RES" == "open" ]] && xdg-open "$LINK"
                ) &
            fi
        done <<< "$ITEMS"
    done

    # Maintenance: Clean duplicate lines just in case
    awk '!seen[$0]++' "$HISTORY_FILE" > "${HISTORY_FILE}.tmp" && mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"

    # Check every 20 minutes
    sleep 1200
done
