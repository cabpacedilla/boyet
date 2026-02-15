#!/usr/bin/env bash

# --- 1. CONFIGURATION ---
HISTORY_FILE="$HOME/.cache/practical_science_history.log"
LOGSEQ_JOURNAL="$HOME/Documents/Logseq/journals/$(date +%Y_%m_%d).md"
mkdir -p "$(dirname "$HISTORY_FILE")"

# --- 2. THE SIGNAL WEIGHTING ENGINE ---
CRITICALS="Treatment|Cure|Toxin|Warning|Efficacy|FDA|Zero-Day|Vulnerability|Exploit|Alert|Emergency|Crisis|Impossible|Overturned|Revolutionary|Milestone|Breakthrough|Discovered|Unlocks"

HYPER_BIO="Cure|Vaccine|Universal|Eradicated|Genome|Longevity|Birth|Contraception|Inhalable"
HYPER_TECH="Quantum|AGI|Superintelligence|Sentience|Encryption|Zero-Day|Exploit|Hardware|Semiconductor|Automated"
HYPER_SPACE="Exoplanet|Habitable|Aliens|Signals|James Webb|Mars|Lava|Moon|NASA|Planet"
HYPER_PHYS="Superconductor|Fusion|Quantum|Particle|Gravity|Atomic|Relativity|Einstein"
HYPER_EARTH="Extinction|Archaeological|Dinosaur|Climate|Evolution|Species|Fossil|Ancient"
HYPER_SOC="Policy|Crisis|Uprising|Election|Law|Reform|Pandemic|Education|Homelessness"

TECH_SIGNALS="AI|Deep Learning|LLM|Neural|NLP|GPU|Algorithm|Architecture|Transistor|Cybersecurity|Kernel|Compiler|Automation|Software|Hardware|CPU|NVME|Blockchain|Robot|Robotic|Chip|Circuit|Sensor|Computing|Digital|Network|System|Cyber|DDoS|Malicious|DevOps|Coding|Code"
BIO_SIGNALS="Nutrition|Sleep|Exercise|Mental|Vaccine|Diet|Microbiome|Habit|Cognitive|Health|Brain|Medicine|Aging|Virus|Bacteria|Genetic|DNA|Enzyme|Protein|Cell|Clinical|Therapy|Patient|Biotech|Biology|Alzheimer|Parkinson|Dementia|Synapse|Neurological|Psychology|Cancer|Microbe|Wellness|Reproduction|Uterus|Muscle|Obesity|Diabetes|Placenta"
SPACE_SIGNALS="Stars|Galaxy|Astronomy|Telescope|Cosmos|Jupiter|Universe|Orbit|Astronaut|Spacewalk|Observatory|Celestial|ISS|SpaceX|Satellite|Starship|Webb|Black Hole|Milky Way"
PHYS_SIGNALS="Physics|Axion|Superconductivity|Thermodynamics|Neutrino|Laser|Entangled|Qubit|Mechanics|Supercollider|Fusion|Relativity"
EARTH_SIGNALS="Fossil|Ocean|Plastic|Pollution|Biodiversity|Forest|Environment|Plant|Animal|Marine|Sealife|Fire|Arctic|Upcycling|Origin|Geology|Weather|Ecology|Seafloor|Storm|Flood|Antarctica|Glacier|Methane|Neanderthal|Paleolithic|Rocks|Metal|Stonehenge|Sailboat|Navy|Vessel"
SOCIAL_SIGNALS="Caregivers|Sociology|School|Primary|Demographic|Psychosocial|Community|Dating|Politics|Urban|Housing|Teens|Art|Faith|Race|Compassion"

SLOP_SIGNALS="TikTok|Trailer|Lamborghini|Supercar|Gaming|Switch 2|Steam Machine|Medicare|Scandal|Olympic|Vance|Trump|EPA|Stellantis"

# --- 3. THE PARSING ENGINE ---
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
    "https://www.technologyreview.com/feed/"
    "https://newatlas.com/index.rss"
    "https://news.ycombinator.com/rss"
    "https://hnrss.org/best"
    "http://feeds.arstechnica.com/arstechnica/index"
    "https://news.mit.edu/rss/topic/computer-science-and-technology"
    "https://thehackernews.com/feeds/posts/default"
)

# --- FUNCTION FOR NOTIFICATION HANDLING ---
handle_notification() {
    local LINK="$1"
    local TITLE="$2"
    local TAG="$3"
    local URGENCY="$4"

    echo "[DEBUG] Sending notification for: $TITLE" >&2
    RESPONSE=$(notify-send -u "$URGENCY" -a "ScienceMonitor" -t 15000 \
        --action="read_article=Read Article" \
        "💡 $TAG" "$TITLE")

    case "$RESPONSE" in
        "read_article")
            echo "[DEBUG] Opening link: $LINK" >&2
            xdg-open "$LINK" >/dev/null 2>&1 &
            ;;
        *)
            echo "[DEBUG] Notification action: $RESPONSE" >&2
            ;;
    esac
}

while true; do
    for URL in "${FEEDS[@]}"; do
        RAW_XML=$(curl -sL -A "Mozilla/5.0" --connect-timeout 15 "$URL") || continue
        ITEMS=$(echo "$RAW_XML" | tr '\r\n\t' ' ' | sed 's/<item/\n<item/g' | grep '<item')

        while IFS= read -r ITEM || [[ -n "$ITEM" ]]; do
            [[ -z "$ITEM" ]] && continue
            CLEAN_ITEM=$(echo "$ITEM" | sed -e 's/<!\[CDATA\[//g' -e 's/\]\]>//g' -e 's/&lt;[^&]*&gt;//g' -e 's/&amp;/&/g')
            TITLE=$(echo "$CLEAN_ITEM" | grep -oP '(?<=<title>).*?(?=</title>)' | head -n1 | xargs)
            LINK=$(echo "$CLEAN_ITEM" | grep -oP '(?<=<link>).*?(?=</link>)' | head -n1 | xargs)
            DESC=$(echo "$CLEAN_ITEM" | grep -oP '(?<=<description>).*?(?=</description>)' | head -n1 | xargs)

            [[ -z "$TITLE" || -z "$LINK" ]] && continue
            grep -qF "$LINK" "$HISTORY_FILE" && continue

            CONTENT=$(echo "$TITLE $DESC" | tr '[:upper:]' '[:lower:]')
            [[ $(echo "$CONTENT" | grep -qiE "($SLOP_SIGNALS)") ]] && continue

            # --- 4. SCORING ---
            B_SCORE=$(echo "$CONTENT" | grep -oiwE "($BIO_SIGNALS)" | wc -l)
            T_SCORE=$(echo "$CONTENT" | grep -oiwE "($TECH_SIGNALS)" | wc -l)
            S_SCORE=$(echo "$CONTENT" | grep -oiwE "($SPACE_SIGNALS)" | wc -l)
            P_SCORE=$(echo "$CONTENT" | grep -oiwE "($PHYS_SIGNALS)" | wc -l)
            E_SCORE=$(echo "$CONTENT" | grep -oiwE "($EARTH_SIGNALS)" | wc -l)
            SOC_SCORE=$(echo "$CONTENT" | grep -oiwE "($SOCIAL_SIGNALS)" | wc -l)

            echo "$CONTENT" | grep -qiE "($HYPER_BIO)" && B_SCORE=$((B_SCORE + 5))
            echo "$CONTENT" | grep -qiE "($HYPER_TECH)" && T_SCORE=$((T_SCORE + 5))
            echo "$CONTENT" | grep -qiE "($HYPER_SPACE)" && S_SCORE=$((S_SCORE + 5))
            echo "$CONTENT" | grep -qiE "($HYPER_PHYS)" && P_SCORE=$((P_SCORE + 5))
            echo "$CONTENT" | grep -qiE "($HYPER_EARTH)" && E_SCORE=$((E_SCORE + 5))
            echo "$CONTENT" | grep -qiE "($HYPER_SOC)" && SOC_SCORE=$((SOC_SCORE + 5))

            if echo "$CONTENT" | grep -qiE "planet"; then S_SCORE=$((S_SCORE + 3)); fi

            TOPIC_LABEL="Science (General)"
            MAX_SCORE=0
            for s in "$P_SCORE:Physics" "$S_SCORE:Space" "$E_SCORE:Earth/Nature" "$B_SCORE:Health/Bio" "$T_SCORE:Tech/Comp" "$SOC_SCORE:Social/Policy"; do
                curr_score=${s%%:*}
                curr_label=${s#*:}
                if [ "$curr_score" -gt "$MAX_SCORE" ]; then
                    MAX_SCORE=$curr_score
                    TOPIC_LABEL=$curr_label
                fi
            done

            TAG="$TOPIC_LABEL"
            if echo "$CONTENT" | grep -qiE "\b($CRITICALS|$HYPER_BIO|$HYPER_TECH|$HYPER_SPACE|$HYPER_PHYS|$HYPER_EARTH|$HYPER_SOC)\b"; then
                TAG="🔥 BREAKTHROUGH ($TOPIC_LABEL)"
            fi

            # --- 5. NOTIFICATION & LOGGING ---
            TIMESTAMP=$(date "+%Y-%m-%d %H:%M")
            echo "[$TIMESTAMP][$TAG] $TITLE | $LINK" >> "$HISTORY_FILE"

            if [ -d "$(dirname "$LOGSEQ_JOURNAL")" ]; then
                echo "- #Breakthrough [$TAG] $TITLE [Link]($LINK)" >> "$LOGSEQ_JOURNAL"
            fi

            URGENCY="normal"
            [[ "$TAG" == *"BREAKTHROUGH"* ]] && URGENCY="critical"

            # Call the notification handler in the background
            handle_notification "$LINK" "$TITLE" "$TAG" "$URGENCY" &
        done <<< "$ITEMS"
    done
    sleep 1200
done
