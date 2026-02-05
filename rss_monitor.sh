#!/usr/bin/env bash

# File paths
HISTORY_FILE="/home/claiveapa/.cache/practical_science_history.log"

# --- 1. KEYWORD GROUPS ---
CRITICALS="Treatment|Cure|Toxin|Warning|Efficacy|Guidelines|FDA|Breakthrough|Prevention|Immunity|Sustainability|Discovery|Ancient|Himalayas|Darkwaves|Seafloor|Axion|Dangerous|Risk|Threat|Undetected|Record|Resurrect|Enzyme|Quantum|X-ray|Infection|Antibiotic|Zero-Day|Vulnerability|Benchmark|Standard|Protocol|Open-Source|Exploit|Framework|Study|Research"

TECH_SIGNALS="AI|Deep Learning|LLM|Neural|NLP|Multimodal|Inference|GPU|Algorithm|Architecture|Semiconductor|Transistor|Quantum|Encryption|Cybersecurity|Kernel|Compiler|Automation|Software|Hardware|Stars|Galaxy|Physics|Astronomy|CPU|NVME|Erase|Drive"

BIO_SIGNALS="Nutrition|Sleep|Exercise|Mental|Vaccine|Diet|Microbiome|Habit|Cognitive|Stress|Pollution|Climate|Plastic|Longevity|Health|Brain|Medicine|Aging|Cannabis|Mosquito|Virus|Bacteria|Ocean|Fruit|Plant|Genetic|DNA|Genome|Evolution|Puma|Penguin|Injuries|Pesticide|Biodiversity|Seed|Hormone|Animal"

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
    "https://phys.org/rss-feed/technology-news/consumer-gadgets/"
    "https://newatlas.com/index.rss"
    "https://news.ycombinator.com/rss"
    "https://hnrss.org/best"
    "http://feeds.arstechnica.com/arstechnica/index"
    "https://news.mit.edu/rss/topic/computer-science-and-technology"
    "https://thehackernews.com/feeds/posts/default"
)

touch "$HISTORY_FILE"

while true; do
    for URL in "${FEEDS[@]}"; do
        RAW_XML=$(curl -sL -A "Mozilla/5.0" --connect-timeout 20 "$URL") || continue
        ITEMS=$(echo "$RAW_XML" | tr '\r\n\t' ' ' | sed 's/<item/\n<item/g' | grep '<item')

        while IFS= read -r ITEM || [[ -n "$ITEM" ]]; do
            [[ -z "$ITEM" ]] && continue

            # --- 2. EXTRACTION ---
            CLEAN_ITEM=$(echo "$ITEM" | sed -e 's/<!\[CDATA\[//g' -e 's/\]\]>//g' -e 's/&lt;[^&]*&gt;//g')
            TITLE=$(echo "$CLEAN_ITEM" | grep -oP '(?<=<title>).*?(?=</title>)' | xargs)
            LINK=$(echo "$CLEAN_ITEM" | grep -oP '(?<=<link>).*?(?=</link>)' | head -n1 | xargs)
            [[ -z "$LINK" ]] && LINK=$(echo "$ITEM" | grep -oP '(?<=href=").*?(?=")' | head -n1)
            DESC=$(echo "$CLEAN_ITEM" | grep -oP '(?<=<description>).*?(?=</description>)' | xargs)

            [[ -z "$TITLE" || -z "$LINK" ]] && continue
            grep -qF "$LINK" "$HISTORY_FILE" 2>/dev/null && continue

            # --- 3. FIXED LOGIC: TOPIC ASSIGNMENT ---
            CONTENT_TO_SCAN="$TITLE $DESC"
            TOPIC_LABEL=""
            IS_BREAKTHROUGH=false
            SHOULD_PROCESS=false
            
            # Use \b to ensure whole word matches only
            # Priority 1: Health/Bio (Checks for mother plants, hormones, pesticides)
            if echo "$CONTENT_TO_SCAN" | grep -qiE "\b($BIO_SIGNALS)\b"; then
                TOPIC_LABEL="Health/Bio"
                SHOULD_PROCESS=true
            # Priority 2: Tech/Comp
            elif echo "$CONTENT_TO_SCAN" | grep -qiE "\b($TECH_SIGNALS)\b"; then
                TOPIC_LABEL="Tech/Comp"
                SHOULD_PROCESS=true
            fi

            # Step B: Check for Breakthrough status
            if echo "$CONTENT_TO_SCAN" | grep -qiE "\b($CRITICALS)\b"; then
                IS_BREAKTHROUGH=true
                SHOULD_PROCESS=true
            fi

            # Step C: Final Tag Construction
            if [[ "$IS_BREAKTHROUGH" == true ]]; then
                if [[ -n "$TOPIC_LABEL" ]]; then
                    TAG="🔥 BREAKTHROUGH ($TOPIC_LABEL)"
                else
                    TAG="🔥 BREAKTHROUGH"
                fi
            else
                TAG="$TOPIC_LABEL"
            fi

            # --- 4. SOURCE LABELING ---
            if [[ "$SHOULD_PROCESS" == true ]]; then
                SOURCE="Discovery"
                if [[ "$URL" == *"nature.com"* ]]; then SOURCE="Nature";
                elif [[ "$URL" == *"science.org"* ]]; then SOURCE="Science";
                elif [[ "$URL" == *"phys.org"* ]]; then SOURCE="Phys.org";
                elif [[ "$URL" == *"arstechnica.com"* ]]; then SOURCE="Ars Technica";
                elif [[ "$URL" == *"ycombinator.com"* || "$URL" == *"hnrss.org"* ]]; then SOURCE="Hacker News";
                elif [[ "$URL" == *"technologyreview.com"* ]]; then SOURCE="MIT Tech Review";
                elif [[ "$URL" == *"newatlas.com"* ]]; then SOURCE="New Atlas";
                elif [[ "$URL" == *"eurekalert.org"* ]]; then SOURCE="EurekAlert";
                elif [[ "$URL" == *"newscientist.com"* ]]; then SOURCE="New Scientist";
                elif [[ "$URL" == *"sciencedaily.com"* ]]; then
                    if [[ "$URL" == *"mind_brain"* ]]; then SOURCE="Brain/Habits";
                    elif [[ "$URL" == *"nutrition"* ]]; then SOURCE="Nutrition";
                    else SOURCE="Science Daily"; fi
                fi

                TIMESTAMP=$(date "+%Y-%m-%d %H:%M")
                ENTRY="[$TIMESTAMP][$TAG: $SOURCE] $TITLE | $LINK"
                echo "$ENTRY" >> "$HISTORY_FILE"
                
                # --- 5. NOTIFICATION ---
                (
                    URGENCY="normal"
                    [[ "$IS_BREAKTHROUGH" == true ]] && URGENCY="critical"

                    ACTION=$(notify-send -u "$URGENCY" -a "ScienceMonitor" -t 15000 \
                        --action="open=Read Article" \
                        "💡 $TAG ($SOURCE)" "$TITLE")
                    [[ "$ACTION" == "open" ]] && xdg-open "$LINK"
                ) &
            fi
        done <<< "$ITEMS"
    done
    awk '!seen[$0]++' "$HISTORY_FILE" > "${HISTORY_FILE}.tmp" && mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"
    sleep 1200
done
