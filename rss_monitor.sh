#!/usr/bin/env bash

# File paths
HISTORY_FILE="/home/claiveapa/.cache/practical_science_history.log"
touch "$HISTORY_FILE"

# --- 1. KEYWORD GROUPS (Balanced for Alignment) ---
# CRITICALS: Keywords that trigger the 🔥 BREAKTHROUGH tag and critical notifications.
CRITICALS="Treatment|Cure|Toxin|Warning|Efficacy|FDA|Breakthrough|Prevention|Immunity|Dangerous|Risk|Threat|Undetected|Resurrect|Infection|Antibiotic|Zero-Day|Vulnerability|Exploit|Alert|Emergency|Crisis|Impossible|Overturned|Overturns|Discovery|Discovers|Uncovers|Reveals|First-ever|Revolutionary|Milestone"

# TECH_SIGNALS: Keywords for Technology and Computing topics.
TECH_SIGNALS="AI|Deep Learning|LLM|Neural|NLP|GPU|Algorithm|Architecture|Semiconductor|Transistor|Encryption|Cybersecurity|Kernel|Compiler|Automation|Software|Hardware|CPU|NVME|Drive|Blockchain|Robot|Robotic|Chip|Circuit|Sensor|Computing|Digital|Network|System"

# BIO_SIGNALS: Keywords for Health, Biology, and Medical topics.
BIO_SIGNALS="Nutrition|Sleep|Exercise|Mental|Vaccine|Diet|Microbiome|Habit|Cognitive|Longevity|Health|Brain|Medicine|Aging|Virus|Bacteria|Genetic|DNA|Genome|Hormone|Enzyme|Protein|Cell|Clinical|Therapy|Patient|Biotech|Biology"

# SPACE_SIGNALS: Keywords for Astronomy and Space topics.
SPACE_SIGNALS="Stars|Galaxy|Astronomy|Space|NASA|Exoplanet|Telescope|Cosmos|Mars|Jupiter|Moon|Universe|Orbit|Astronaut|Spacewalk|Observatory|Celestial"

# PHYS_SIGNALS: Keywords for Physics and related fields.
PHYS_SIGNALS="Physics|Quantum|Axion|Superconductivity|Thermodynamics|Atomic|Particle|Gravity|Neutrino|Laser|Light|Magnetic|Matter|Entangled|Qubit|Mechanics|Relativity|Energy|Wave"

# EARTH_SIGNALS: Keywords for Earth Sciences, Environment, and Paleontology.
EARTH_SIGNALS="Dinosaur|Fossil|Evolution|Ocean|Climate|Plastic|Pollution|Biodiversity|Forest|Environment|Plant|Animal|Puma|Penguin|Marine|Sealife|Fire|Arctic|Upcycling|Life|Origin|Geology|Weather|Ecology|Seafloor"

# --- RSS FEED URLs ---
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

# --- MAIN LOOP ---
while true; do
    for URL in "${FEEDS[@]}"; do
        # Fetch with a real User-Agent to avoid 403/404 errors
        RAW_XML=$(curl -sL -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" --connect-timeout 20 "$URL") || continue
        
        # Standardize XML format for parsing
        ITEMS=$(echo "$RAW_XML" | tr '\r\n\t' ' ' | sed 's/<item/\n<item/g' | grep '<item')

        while IFS= read -r ITEM || [[ -n "$ITEM" ]]; do
            [[ -z "$ITEM" ]] && continue

            # --- 2. EXTRACTION ---
            CLEAN_ITEM=$(echo "$ITEM" | sed -e 's/<!\[CDATA\[//g' -e 's/\]\]>//g' -e 's/&lt;[^&]*&gt;//g' -e 's/&amp;/&/g') # Added &amp; to & for cleaner titles
            TITLE=$(echo "$CLEAN_ITEM" | grep -oP '(?<=<title>).*?(?=</title>)' | head -n1 | xargs)
            LINK=$(echo "$CLEAN_ITEM" | grep -oP '(?<=<link>).*?(?=</link>)' | head -n1 | xargs)
            DESC=$(echo "$CLEAN_ITEM" | grep -oP '(?<=<description>).*?(?=</description>)' | head -n1 | xargs)

            # Skip if title or link is empty, or if link has been seen
            [[ -z "$TITLE" || -z "$LINK" ]] && continue
            grep -qF "$LINK" "$HISTORY_FILE" 2>/dev/null && continue

            # --- 3. SCORING LOGIC (The Alignment Fix) ---
            CONTENT=$(echo "$TITLE $DESC" | tr '[:upper:]' '[:lower:]') # Convert to lowercase for case-insensitive matching
            
            # Count matches for each category bucket
            B_SCORE=$(echo "$CONTENT" | grep -oiwE "($BIO_SIGNALS)" | wc -l)
            T_SCORE=$(echo "$CONTENT" | grep -oiwE "($TECH_SIGNALS)" | wc -l)
            S_SCORE=$(echo "$CONTENT" | grep -oiwE "($SPACE_SIGNALS)" | wc -l)
            P_SCORE=$(echo "$CONTENT" | grep -oiwE "($PHYS_SIGNALS)" | wc -l)
            E_SCORE=$(echo "$CONTENT" | grep -oiwE "($EARTH_SIGNALS)" | wc -l)

            # Determine Winning Category based on highest score
            TOPIC_LABEL="Science (General)" # Default label if no specific category wins
            MAX=0
            [[ $B_SCORE -gt $MAX ]] && { MAX=$B_SCORE; TOPIC_LABEL="Health/Bio"; }
            [[ $T_SCORE -gt $MAX ]] && { MAX=$T_SCORE; TOPIC_LABEL="Tech/Comp"; }
            [[ $S_SCORE -gt $MAX ]] && { MAX=$S_SCORE; TOPIC_LABEL="Space"; }
            [[ $P_SCORE -gt $MAX ]] && { MAX=$P_SCORE; TOPIC_LABEL="Physics"; }
            [[ $E_SCORE -gt $MAX ]] && { MAX=$E_SCORE; TOPIC_LABEL="Earth/Nature"; }

            # Breakthrough Detection
            IS_BREAKTHROUGH=false
            if echo "$CONTENT" | grep -qiE "\b($CRITICALS)\b"; then
                IS_BREAKTHROUGH=true
            fi

            # Construction of the Final Tag
            if [[ "$IS_BREAKTHROUGH" == true ]]; then
                TAG="🔥 BREAKTHROUGH ($TOPIC_LABEL)"
            else
                TAG="$TOPIC_LABEL"
            fi

            # --- 4. SOURCE LABELING ---
            SOURCE="Science News" # Default source if not explicitly matched
            if [[ "$URL" == *"nature.com"* ]]; then SOURCE="Nature";
            elif [[ "$URL" == *"science.org"* ]]; then SOURCE="Science"; # Assuming a science.org feed might be added later
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
                elif [[ "$URL" == *"fitness"* ]]; then SOURCE="Fitness"; # Added fitness source
                else SOURCE="Science Daily"; fi
            elif [[ "$URL" == *"news.mit.edu"* ]]; then SOURCE="MIT News"; # Specific MIT News
            elif [[ "$URL" == *"thehackernews.com"* ]]; then SOURCE="The Hacker News";
            fi

            # --- 5. LOGGING & NOTIFICATION ---
            TIMESTAMP=$(date "+%Y-%m-%d %H:%M")
            ENTRY="[$TIMESTAMP][$TAG: $SOURCE] $TITLE | $LINK"
            echo "$ENTRY" >> "$HISTORY_FILE"

            # NOTIFICATION LOGIC: Only send a notify-send for BREAKTHROUGH articles
            if [[ "$IS_BREAKTHROUGH" == true ]]; then
                (
                    URGENCY="critical" # Breakthroughs are always critical urgency
                    ACTION=$(notify-send -u "$URGENCY" -a "ScienceMonitor" -t 15000 \
                        --action="open=Read Article" \
                        "💡 $TAG ($SOURCE)" "$TITLE")
                    [[ "$ACTION" == "open" ]] && xdg-open "$LINK"
                ) &
            fi
            
        done <<< "$ITEMS"
    done
    
    # Final cleanup: Remove duplicate lines from history file and keep it tidy
    awk '!seen[$0]++' "$HISTORY_FILE" > "${HISTORY_FILE}.tmp" && mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"
    
    # Sleep for 20 minutes (1200 seconds) before the next fetch cycle
    sleep 1200 
done
