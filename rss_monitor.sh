#!/usr/bin/env bash

# File paths
HISTORY_FILE="/home/claiveapa/.cache/practical_science_history.log"
SIGNALS="Nutrition|Sleep|Exercise|Mental|Vaccine|Diet|Microbiome|Habit|Cognitive|Stress|Pollution|Climate|Plastic|Longevity|Health|Brain|Medicine|Aging|Cannabis|Mosquito|Virus|Bacteria|Ocean|Fruit|Plant|Genetic|DNA|Genome|AI|Deep Learning|Chemical|Origin|Space|Ice|Quantum|Encryption|Cybersecurity|Kernel|Compiler|LLM|Neural|Architecture|Semiconductor|Transistor|Algorithm"
CRITICALS="Treatment|Cure|Toxin|Warning|Efficacy|Guidelines|FDA|Breakthrough|Prevention|Immunity|Sustainability|Discovery|Ancient|Himalayas|Darkwaves|Seafloor|Axion|Dangerous|Risk|Threat|Undetected|Record|Resurrect|Enzyme|Quantum|X-ray|Infection|Antibiotic|Zero-Day|Vulnerability|Benchmark|Standard|Protocol|Open-Source|Exploit|Hardware|Framework|Zero-Day|Vulnerability|Benchmark|Standard|Protocol|Open-Source|Exploit|Hardware|Framework"

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
	"https://hnrss.org/best"
    "http://feeds.arstechnica.com/arstechnica/index"
    "https://news.mit.edu/rss/topic/computer-science-and-technology"
    "https://thehackernews.com/feeds/posts/default"
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

            # --- 4. TAG ALIGNMENT (PRIORITY RE-ORDERED) ---
            CONTENT_TO_SCAN="$TITLE $DESC"
            TAG=""
            SHOULD_PROCESS=false
            
            # Breakthroughs always come first
            if echo "$CONTENT_TO_SCAN" | grep -qiE "$CRITICALS"; then
                TAG="🔥 BREAKTHROUGH"
                SHOULD_PROCESS=true
            # TECH checked BEFORE BIO to avoid mislabeling "AI Learning"
            elif echo "$CONTENT_TO_SCAN" | grep -qiE "$TECH_SIGNALS"; then
                TAG="Tech/Comp"
                SHOULD_PROCESS=true
            elif echo "$CONTENT_TO_SCAN" | grep -qiE "$BIO_SIGNALS"; then
                TAG="Health/Bio"
                SHOULD_PROCESS=true
            fi

            # --- 5. SOURCE CONTEXTUALIZATION (CONTEXT-AWARE) ---
            if [[ "$SHOULD_PROCESS" == true ]]; then
                SOURCE="Discovery"
                
                # Identify exact source by URL patterns
                if [[ "$URL" == *"nature.com"* ]]; then SOURCE="Nature";
                elif [[ "$URL" == *"science.org"* ]]; then SOURCE="Science";
                elif [[ "$URL" == *"arstechnica.com"* ]]; then SOURCE="Ars Technica";
                elif [[ "$URL" == *"technologyreview.com"* ]]; then SOURCE="MIT Tech Review";
                elif [[ "$URL" == *"newatlas.com"* ]]; then SOURCE="New Atlas";
                elif [[ "$URL" == *"ycombinator.com"* || "$URL" == *"hnrss.org"* ]]; then SOURCE="Hacker News";
                elif [[ "$URL" == *"thehackernews.com"* ]]; then SOURCE="CyberSecurity";
                elif [[ "$URL" == *"mit.edu"* ]]; then SOURCE="MIT News";
                elif [[ "$URL" == *"phys.org"* ]]; then SOURCE="Phys.org";
                elif [[ "$URL" == *"eurekalert.org"* ]]; then SOURCE="EurekAlert";
                elif [[ "$URL" == *"newscientist.com"* ]]; then SOURCE="New Scientist";
                elif [[ "$URL" == *"quantamagazine.org"* ]]; then SOURCE="Quanta Mag";
                elif [[ "$URL" == *"sciencedaily.com"* ]]; then
                    if [[ "$URL" == *"mind_brain"* ]]; then SOURCE="Brain/Habits";
                    elif [[ "$URL" == *"nutrition"* ]]; then SOURCE="Nutrition";
                    elif [[ "$URL" == *"technology"* ]]; then SOURCE="Tech Daily";
                    else SOURCE="Science Daily"; fi
                fi

                TIMESTAMP=$(date "+%Y-%m-%d %H:%M")

                # Format for history log: ONE LINE per entry
                # This ensures awk deduplication doesn't separate titles from links
                ENTRY="[$TIMESTAMP][$TAG: $SOURCE] $TITLE | $LINK"
                
                echo "$ENTRY" >> "$HISTORY_FILE"
                
                # ASYNC NOTIFICATION
				(
					# This sends the notification and waits for the 'open' action
					ACTION=$(notify-send -u critical -a "ScienceMonitor" -t 0 \
						--action="open=Read Article" \
						"💡 $TAG ($SOURCE)" "$TITLE")
					
					if [[ "$ACTION" == "open" ]]; then
						xdg-open "$LINK"
					fi
				) &
            fi
        done <<< "$ITEMS"
    done

    # Maintenance: Clean duplicate lines while preserving order
    # Because entries are now single-line, this works perfectly
    awk '!seen[$0]++' "$HISTORY_FILE" > "${HISTORY_FILE}.tmp" && mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"

    sleep 1200
done
