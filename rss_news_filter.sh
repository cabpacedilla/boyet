#!/usr/bin/env bash

# --- 1. CONFIGURATION & LOGGING ---
HISTORY_FILE="/home/claiveapa/.cache/practical_science_history.log"
touch "$HISTORY_FILE"

# --- 2. KEYWORD GROUPS (Balanced for Alignment) ---
# CRITICALS: High-impact triggers. Removed generic "Discovery" to prevent false alarms.
CRITICALS="Treatment|Cure|Toxin|Warning|Efficacy|FDA|Breakthrough|Zero-Day|Vulnerability|Exploit|Alert|Emergency|Crisis|Impossible|Overturned|Revolutionary|Milestone"

# TECH_SIGNALS: Technology and Computing.
TECH_SIGNALS="AI|Deep Learning|LLM|Neural|NLP|GPU|Algorithm|Architecture|Semiconductor|Transistor|Encryption|Cybersecurity|Kernel|Compiler|Automation|Software|Hardware|CPU|NVME|Blockchain|Robot|Robotic|Chip|Circuit|Sensor|Computing|Digital|Network|System"

# BIO_SIGNALS: Health, Biology, and Medical. (Expanded for Brain/Clinical/Microbe)
BIO_SIGNALS="Nutrition|Sleep|Exercise|Mental|Vaccine|Diet|Microbiome|Habit|Cognitive|Longevity|Health|Brain|Medicine|Aging|Virus|Bacteria|Genetic|DNA|Genome|Hormone|Enzyme|Protein|Cell|Clinical|Therapy|Patient|Biotech|Biology|Alzheimer|Parkinson|Dementia|Synapse|Neurological|Psychology|Cancer|Faecal|Microbe|Microbiology|Wellness|Microbes"

# SPACE_SIGNALS: Astronomy and Space topics.
SPACE_SIGNALS="Stars|Galaxy|Astronomy|Space|NASA|Exoplanet|Telescope|Cosmos|Mars|Jupiter|Moon|Universe|Orbit|Astronaut|Spacewalk|Observatory|Celestial|ISS|SpaceX|Satellite"

# PHYS_SIGNALS: Physics and related fields.
PHYS_SIGNALS="Physics|Quantum|Axion|Superconductivity|Thermodynamics|Atomic|Particle|Gravity|Neutrino|Laser|Light|Magnetic|Matter|Entangled|Qubit|Mechanics|Relativity|Energy|Wave|Superconductor|Photon"

# EARTH_SIGNALS: Environment, Weather, and Paleontology. (Expanded for storms/archaeology)
EARTH_SIGNALS="Dinosaur|Fossil|Evolution|Ocean|Climate|Plastic|Pollution|Biodiversity|Forest|Environment|Plant|Animal|Marine|Sealife|Fire|Arctic|Upcycling|Origin|Geology|Weather|Ecology|Seafloor|Storm|Flood|Antarctica|Glacier|Methane|Species|Neanderthal|Archaeological|Paleolithic|Antarctic"

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

            # --- EXTRACTION ---
            CLEAN_ITEM=$(echo "$ITEM" | sed -e 's/<!\[CDATA\[//g' -e 's/\]\]>//g' -e 's/&lt;[^&]*&gt;//g' -e 's/&amp;/&/g')
            TITLE=$(echo "$CLEAN_ITEM" | grep -oP '(?<=<title>).*?(?=</title>)' | head -n1 | xargs)
            LINK=$(echo "$CLEAN_ITEM" | grep -oP '(?<=<link>).*?(?=</link>)' | head -n1 | xargs)
            DESC=$(echo "$CLEAN_ITEM" | grep -oP '(?<=<description>).*?(?=</description>)' | head -n1 | xargs)

            # Skip if title or link is empty
            [[ -z "$TITLE" || -z "$LINK" ]] && continue
            
            # CHECK HISTORY: Efficiency tweak for large log files
            tail -n 1000 "$HISTORY_FILE" | grep -qF "$LINK" 2>/dev/null && continue

            # --- SCORING LOGIC ---
            CONTENT=$(echo "$TITLE $DESC" | tr '[:upper:]' '[:lower:]')
            
            B_SCORE=$(echo "$CONTENT" | grep -oiwE "($BIO_SIGNALS)" | wc -l)
            T_SCORE=$(echo "$CONTENT" | grep -oiwE "($TECH_SIGNALS)" | wc -l)
            S_SCORE=$(echo "$CONTENT" | grep -oiwE "($SPACE_SIGNALS)" | wc -l)
            P_SCORE=$(echo "$CONTENT" | grep -oiwE "($PHYS_SIGNALS)" | wc -l)
            E_SCORE=$(echo "$CONTENT" | grep -oiwE "($EARTH_SIGNALS)" | wc -l)

            # Determine Winning Category
            TOPIC_LABEL="Science (General)"
            MAX=0
            
            # Order of preference: Bio/Earth/Tech usually have more specific keywords than Physics
            [[ $P_SCORE -gt $MAX ]] && { MAX=$P_SCORE; TOPIC_LABEL="Physics"; }
            [[ $S_SCORE -gt $MAX ]] && { MAX=$S_SCORE; TOPIC_LABEL="Space"; }
            [[ $T_SCORE -gt $MAX ]] && { MAX=$T_SCORE; TOPIC_LABEL="Tech/Comp"; }
            [[ $E_SCORE -gt $MAX ]] && { MAX=$E_SCORE; TOPIC_LABEL="Earth/Nature"; }
            [[ $B_SCORE -gt $MAX ]] && { MAX=$B_SCORE; TOPIC_LABEL="Health/Bio"; }

            # Breakthrough Detection
            IS_BREAKTHROUGH=false
            if echo "$CONTENT" | grep -qiE "\b($CRITICALS)\b"; then
                IS_BREAKTHROUGH=true
            fi

            # Tag construction
            if [[ "$IS_BREAKTHROUGH" == true ]]; then
                TAG="🔥 BREAKTHROUGH ($TOPIC_LABEL)"
            else
                TAG="$TOPIC_LABEL"
            fi

            # --- SOURCE LABELING ---
            SOURCE="Science News"
            if [[ "$URL" == *"nature.com"* ]]; then SOURCE="Nature";
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
                elif [[ "$URL" == *"fitness"* ]]; then SOURCE="Fitness";
                else SOURCE="Science Daily"; fi
            elif [[ "$URL" == *"news.mit.edu"* ]]; then SOURCE="MIT News";
            elif [[ "$URL" == *"thehackernews.com"* ]]; then SOURCE="The Hacker News";
            fi

            # --- LOGGING & NOTIFICATION ---
            TIMESTAMP=$(date "+%Y-%m-%d %H:%M")
            ENTRY="[$TIMESTAMP][$TAG: $SOURCE] $TITLE | $LINK"
            echo "$ENTRY" >> "$HISTORY_FILE"

            if [[ "$IS_BREAKTHROUGH" == true ]]; then
                (
                    notify-send -u "critical" -a "ScienceMonitor" -t 15000 \
                        --action="open=Read Article" \
                        "💡 $TAG ($SOURCE)" "$TITLE" | grep -q "open" && xdg-open "$LINK"
                ) &
            else
				(
				notify-send -u "normal" -a "ScienceMonitor" -t 15000 \
                        --action="open=Read Article" \
                        "💡 $TAG ($SOURCE)" "$TITLE" | grep -q "open" && xdg-open "$LINK"
                ) &
            fi
            
        done <<< "$ITEMS"
    done
    
    # Keep history file healthy (Remove duplicates, keep last 5000 lines)
    sort -u "$HISTORY_FILE" -o "$HISTORY_FILE"
    tail -n 5000 "$HISTORY_FILE" > "${HISTORY_FILE}.tmp" && mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"
    
    sleep 1200 
done
