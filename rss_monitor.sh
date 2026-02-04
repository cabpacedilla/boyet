#!/usr/bin/env bash

# File paths
HISTORY_FILE="/home/claiveapa/.cache/practical_science_history.log"
SIGNALS="Nutrition|Sleep|Exercise|Mental|Vaccine|Diet|Microbiome|Habit|Cognitive|Stress|Pollution|Climate|Plastic|Longevity|Health|Brain|Medicine|Aging|Cannabis|Mosquito|Virus|Bacteria|Ocean|Fruit|Plant|Genetic|DNA|Genome|AI|Deep Learning|Chemical|Origin|Space|Ice"
CRITICALS="Treatment|Cure|Toxin|Warning|Efficacy|Guidelines|FDA|Breakthrough|Prevention|Immunity|Sustainability|Discovery|Ancient|Himalayas|Darkwaves|Seafloor|Axion|Dangerous|Risk|Threat|Undetected|Record|Resurrect|Enzyme|Quantum|X-ray|Infection|Antibiotic"

FEEDS=(
    "https://www.nature.com/nature/research-articles.rss"
    "https://www.science.org/rss/news_current.xml"
    "https://www.sciencedaily.com/rss/top/health.xml"
    "https://www.sciencedaily.com/rss/top/environment.xml"
)

touch "$HISTORY_FILE"

while true; do
    for URL in "${FEEDS[@]}"; do
        # Fetch XML with User-Agent to bypass blocks
        RAW_XML=$(curl -sL -A "Mozilla/5.0" --connect-timeout 20 "$URL") || continue
        
        # Split items into lines for processing
        ITEMS=$(echo "$RAW_XML" | tr '\r\n\t' ' ' | sed 's/<item/\n<item/g' | grep '<item')

        while IFS= read -r ITEM || [[ -n "$ITEM" ]]; do
            [[ -z "$ITEM" ]] && continue

            # --- 1. ROBUST EXTRACTION ---
            # Remove CDATA and HTML entities, then grab Title and Link
            CLEAN_ITEM=$(echo "$ITEM" | sed -e 's/<!\[CDATA\[//g' -e 's/\]\]>//g' -e 's/&lt;[^&]*&gt;//g')
            
            TITLE=$(echo "$CLEAN_ITEM" | grep -oP '(?<=<title>).*?(?=</title>)' | xargs)
            
            # Extract standard <link> content
            LINK=$(echo "$CLEAN_ITEM" | grep -oP '(?<=<link>).*?(?=</link>)' | head -n1 | xargs)
            # Fallback for <link href="..."> style links
            [[ -z "$LINK" ]] && LINK=$(echo "$ITEM" | grep -oP '(?<=href=").*?(?=")' | head -n1)

            DESC=$(echo "$CLEAN_ITEM" | grep -oP '(?<=<description>).*?(?=</description>)' | xargs)

            # --- 2. VALIDATION ---
            [[ -z "$TITLE" || -z "$LINK" ]] && continue
            
            # --- 3. DUPLICATE CHECK ---
            grep -qF "$LINK" "$HISTORY_FILE" 2>/dev/null && continue

            # --- 4. FILTER CHECK ---
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

            # --- 5. LOGGING & NOTIFICATION ---
            if [[ "$SHOULD_PROCESS" == true ]]; then
                SOURCE="Discovery"
                [[ "$URL" == *"nature.com"* ]] && SOURCE="Nature"
                [[ "$URL" == *"science.org"* ]] && SOURCE="Science"
                [[ "$URL" == *"sciencedaily.com"* ]] && SOURCE="Practical News"

                TIMESTAMP=$(date "+%Y-%m-%d %H:%M")

                # Format for history log: ONE LINE per entry
                # This ensures awk deduplication doesn't separate titles from links
                ENTRY="[$TIMESTAMP][$TAG: $SOURCE] $TITLE | $LINK"
                
                echo "$ENTRY" >> "$HISTORY_FILE"
                
                # ASYNC NOTIFICATION
                (
                    RES=$(notify-send -u critical -a "ScienceMonitor" -t 0 \
                        --action="open=Read Article" \
                        "💡 $TAG" "$TITLE")
                    
                    [[ "$RES" == "open" ]] && xdg-open "$LINK"
                ) &
            fi
        done <<< "$ITEMS"
    done

    # Maintenance: Clean duplicate lines while preserving order
    # Because entries are now single-line, this works perfectly
    awk '!seen[$0]++' "$HISTORY_FILE" > "${HISTORY_FILE}.tmp" && mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"

    sleep 1200
done
