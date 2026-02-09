#!/usr/bin/env bash

# --- 1. CONFIGURATION & LOGGING ---
HISTORY_FILE="/home/claiveapa/.cache/practical_science_history.log"
mkdir -p "$(dirname "$HISTORY_FILE")"
touch "$HISTORY_FILE"

# --- 2. REFINED KEYWORD GROUPS (Context-Aware) ---
# CRITICALS: High-impact triggers only. (Removed generic "Breakthrough" to avoid spam)
CRITICALS="Treatment|Cure|Toxin|Warning|Efficacy|FDA|Zero-Day|Vulnerability|Exploit|Alert|Emergency|Crisis|Impossible|Overturned|Revolutionary|Milestone"

# TECH_SIGNALS: Focused on computing and engineering.
TECH_SIGNALS="AI|Deep Learning|LLM|Neural|NLP|GPU|Algorithm|Architecture|Semiconductor|Transistor|Encryption|Cybersecurity|Kernel|Compiler|Automation|Software|Hardware|CPU|NVME|Blockchain|Robot|Robotic|Chip|Circuit|Sensor|Computing|Digital|Network|System|Cyber|DDoS|Malicious|Exchange|Hackers|DevOps|Coding|Code"

# BIO_SIGNALS: Health, Biology, and Medical.
BIO_SIGNALS="Nutrition|Sleep|Exercise|Mental|Vaccine|Diet|Microbiome|Habit|Cognitive|Longevity|Health|Brain|Medicine|Aging|Virus|Bacteria|Genetic|DNA|Genome|Hormone|Enzyme|Protein|Cell|Clinical|Therapy|Patient|Biotech|Biology|Alzheimer|Parkinson|Dementia|Synapse|Neurological|Psychology|Cancer|Faecal|Microbe|Microbiology|Wellness|Microbes|Reproduction|Uterus|Muscle|Obesity|Diabetes"

# SPACE_SIGNALS: Astronomy and Space topics.
SPACE_SIGNALS="Stars|Galaxy|Astronomy|Space|NASA|Exoplanet|Telescope|Cosmos|Mars|Jupiter|Moon|Universe|Orbit|Astronaut|Spacewalk|Observatory|Celestial|ISS|SpaceX|Satellite|Starship|Webb"

# PHYS_SIGNALS: Physical sciences (More specific to avoid generic overlaps).
PHYS_SIGNALS="Physics|Quantum|Axion|Superconductivity|Thermodynamics|Atomic|Particle|Gravity|Neutrino|Laser|Entangled|Qubit|Mechanics|Relativity|Superconductor|Photon|CERN|Supercollider|Fusion"

# EARTH_SIGNALS: Environment, Nature, and Archaeology.
EARTH_SIGNALS="Dinosaur|Fossil|Evolution|Ocean|Climate|Plastic|Pollution|Biodiversity|Forest|Environment|Plant|Animal|Marine|Sealife|Fire|Arctic|Upcycling|Origin|Geology|Weather|Ecology|Seafloor|Storm|Flood|Antarctica|Glacier|Methane|Species|Neanderthal|Archaeological|Paleolithic|Antarctic|Rocks|Metal|Stonehenge"

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
        # Fetch RSS
        RAW_XML=$(curl -sL -A "Mozilla/5.0" --connect-timeout 15 "$URL") || continue
        
        # Parse items
        ITEMS=$(echo "$RAW_XML" | tr '\r\n\t' ' ' | sed 's/<item/\n<item/g' | grep '<item')

        while IFS= read -r ITEM || [[ -n "$ITEM" ]]; do
            [[ -z "$ITEM" ]] && continue

            # --- EXTRACTION ---
            CLEAN_ITEM=$(echo "$ITEM" | sed -e 's/<!\[CDATA\[//g' -e 's/\]\]>//g' -e 's/&lt;[^&]*&gt;//g' -e 's/&amp;/&/g')
            TITLE=$(echo "$CLEAN_ITEM" | grep -oP '(?<=<title>).*?(?=</title>)' | head -n1 | xargs)
            LINK=$(echo "$CLEAN_ITEM" | grep -oP '(?<=<link>).*?(?=</link>)' | head -n1 | xargs)
            DESC=$(echo "$CLEAN_ITEM" | grep -oP '(?<=<description>).*?(?=</description>)' | head -n1 | xargs)

            [[ -z "$TITLE" || -z "$LINK" ]] && continue
            
            # History check
            grep -qF "$LINK" "$HISTORY_FILE" && continue

            # --- SCORING ENGINE ---
            CONTENT=$(echo "$TITLE $DESC" | tr '[:upper:]' '[:lower:]')
            
            # Count matches
            B_SCORE=$(echo "$CONTENT" | grep -oiwE "($BIO_SIGNALS)" | wc -l)
            T_SCORE=$(echo "$CONTENT" | grep -oiwE "($TECH_SIGNALS)" | wc -l)
            S_SCORE=$(echo "$CONTENT" | grep -oiwE "($SPACE_SIGNALS)" | wc -l)
            P_SCORE=$(echo "$CONTENT" | grep -oiwE "($PHYS_SIGNALS)" | wc -l)
            E_SCORE=$(echo "$CONTENT" | grep -oiwE "($EARTH_SIGNALS)" | wc -l)

            # SOURCE BIAS (Improves accuracy for specialized sites)
            [[ "$URL" == *"thehackernews"* || "$URL" == *"ycombinator"* ]] && T_SCORE=$((T_SCORE + 2))
            [[ "$URL" == *"phys.org"* ]] && P_SCORE=$((P_SCORE + 1))

            # --- WINNER DETERMINATION (Weighted Priority) ---
            TOPIC_LABEL="Science (General)"
            MAX_SCORE=0

            # Priority Order: Bio > Earth > Tech > Space > Physics
            # We check in reverse order of specificity
            [[ $P_SCORE -gt $MAX_SCORE ]] && { MAX_SCORE=$P_SCORE; TOPIC_LABEL="Physics"; }
            [[ $S_SCORE -gt $MAX_SCORE ]] && { MAX_SCORE=$S_SCORE; TOPIC_LABEL="Space"; }
            [[ $T_SCORE -gt $MAX_SCORE ]] && { MAX_SCORE=$T_SCORE; TOPIC_LABEL="Tech/Comp"; }
            [[ $E_SCORE -gt $MAX_SCORE ]] && { MAX_SCORE=$E_SCORE; TOPIC_LABEL="Earth/Nature"; }
            [[ $B_SCORE -gt $MAX_SCORE ]] && { MAX_SCORE=$B_SCORE; TOPIC_LABEL="Health/Bio"; }

            # Breakthrough check
            TAG="$TOPIC_LABEL"
            if echo "$CONTENT" | grep -qiE "\b($CRITICALS)\b"; then
                TAG="🔥 BREAKTHROUGH ($TOPIC_LABEL)"
            fi

            # --- SOURCE LABELING ---
            SOURCE="Science News"
            case "$URL" in
                *nature.com*) SOURCE="Nature" ;;
                *phys.org*) SOURCE="Phys.org" ;;
                *arstechnica.com*) SOURCE="Ars Technica" ;;
                *ycombinator.com*|*hnrss.org*) SOURCE="Hacker News" ;;
                *technologyreview.com*) SOURCE="MIT Tech Review" ;;
                *newatlas.com*) SOURCE="New Atlas" ;;
                *eurekalert.org*) SOURCE="EurekAlert" ;;
                *newscientist.com*) SOURCE="New Scientist" ;;
                *news.mit.edu*) SOURCE="MIT News" ;;
                *thehackernews.com*) SOURCE="The Hacker News" ;;
                *sciencedaily.com*)
                    if [[ "$URL" == *"mind_brain"* ]]; then SOURCE="Brain/Habits"
                    elif [[ "$URL" == *"nutrition"* ]]; then SOURCE="Nutrition"
                    elif [[ "$URL" == *"fitness"* ]]; then SOURCE="Fitness"
                    else SOURCE="Science Daily"; fi ;;
            esac

            # --- OUTPUT & NOTIFY ---
            TIMESTAMP=$(date "+%Y-%m-%d %H:%M")
            echo "[$TIMESTAMP][$TAG: $SOURCE] $TITLE | $LINK" >> "$HISTORY_FILE"

            URGENCY="normal"
            [[ "$TAG" == *"BREAKTHROUGH"* ]] && URGENCY="critical"

            (
                notify-send -u "$URGENCY" -a "ScienceMonitor" -t 15000 \
                    --action="open=Read Article" \
                    "💡 $TAG ($SOURCE)" "$TITLE" | grep -q "open" && xdg-open "$LINK"
            ) &
            
        done <<< "$ITEMS"
    done
    
    # Maintenance: Clean up history but keep it unique
    tail -n 3000 "$HISTORY_FILE" | sort -u > "${HISTORY_FILE}.tmp" && mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"
    
    sleep 1200 # 20 Minute interval
done
