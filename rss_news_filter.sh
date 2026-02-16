#!/usr/bin/env bash

# --- 1. CONFIGURATION ---
HISTORY_FILE="$HOME/.cache/practical_science_history.log"
LOGSEQ_JOURNAL="$HOME/Documents/Logseq/journals/$(date +%Y_%m_%d).md"
mkdir -p "$(dirname "$HISTORY_FILE")"
mkdir -p "$(dirname "$LOGSEQ_JOURNAL")"
ALERT_EMAIL="cabpacedilla@gmail.com"

# --- 2. COMPREHENSIVE KEYWORD ENGINE ---
ASTRONOMY_PAT="astronomy|exoplanet|james webb|black hole|nebula|starship|telescope|pulsar|quasar|dark matter|cosmology|spacex|nasa|esa|jaxa|supernova|moon|mars|orbit|gravitational wave"
ZOOLOGY_PAT="zoology|wildlife|species|puma|feline|canine|mammal|reptile|insect|fauna|migration|sealife|biodiversity|habitat|ecology|evolutionary|extinction"
# High-impact health and medical human progress
MEDICINE_PAT="medicine|oncology|virus|bacteria|vaccine|surgery|clinical trial|pharmacy|neuroscience|anatomy|pathogen|microbiome|longevity|wellness|obesity|diabetes|alzheimer|parkinson|dementia|nutrition|diet|fitness|sleep|fasting|statin|fda|inhalable|gene therapy|cancer|treatment|mammogram|cognitive training"
# Expanded Tech to catch specific AI labs and standard bodies
TECH_PAT="semiconductor|microchip|processor|automation|infrastructure|algorithm|software|ai|artificial intelligence|coding|cybersecurity|quantum computing|deep learning|llm|gpu|blockchain|robotics|android|pixel|verizon|windows|ios|sql|sqlite|javascript|chip|openai|anthropic|claude|unicode|ciso|spyware|zeroday"
PHYSICS_PAT="quantum physics|particle physics|superconductor|fusion|relativity|einstein|laser|entangled|qubit|neutrino|thermodynamics|cern|collider|antimatter|perovskite|energy-harvesting|nanotechnology|string theory|boson|photon"
# Earth/Nature includes archaeology to catch "unearthed" discoveries
EARTH_PAT="fossil|geology|paleontology|oceanography|climate change|global warming|seafloor|glacier|neanderthal|paleolithic|volcano|earthquake|mineral|botany|methane|pesticide|carbon|cement|sustainable|renewables|solar|unearthed|chronicle|archaeology"
SOCIAL_PAT="policy|reform|sociology|demographic|urban planning|housing crisis|inequality|immigration|democracy|economic|poverty|jurisprudence|kickstarter|surveillance|dhs|ice|censor|broadband"
SLOP_PAT="tiktok|lamborghini|supercar|gaming|celebrity|gossip|rumor|entertainment|fashion|luxury|brand|influencer|scandal"

# --- 3. CLASSIFICATION LOGIC (Order Matters!) ---
get_tag() {
    local text=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    if [[ "$text" =~ $SLOP_PAT ]]; then echo "SKIP"
    elif [[ "$text" =~ $MEDICINE_PAT ]]; then echo "Health/Bio"
    elif [[ "$text" =~ $EARTH_PAT ]]; then echo "Earth/Nature"
    elif [[ "$text" =~ $ASTRONOMY_PAT ]]; then echo "Astronomy"
    elif [[ "$text" =~ $TECH_PAT ]]; then echo "Tech/Comp"
    elif [[ "$text" =~ $PHYSICS_PAT ]]; then echo "Physics"
    elif [[ "$text" =~ $ZOOLOGY_PAT ]]; then echo "Zoology"
    elif [[ "$text" =~ $SOCIAL_PAT ]]; then echo "Social/Policy"
    else echo "Science (General)"; fi
}

# --- 4. THE 20-FEED LIST ---
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

# --- 5. HELPERS ---
decode_html_entities() {
    echo "$1" | sed -e 's/&#x27;/\'\''/g' -e 's/&amp;/\&/g' -e 's/&lt;/</g' -e 's/&gt;/>/g' -e 's/&quot;/"/g' -e "s/&#039;/'/g" -e 's/&#38;/\&/g'
}

handle_notification() {
    local LINK="$1" TITLE="$2" TAG="$3" URGENCY="$4"
    (
        RESPONSE=$(notify-send -u "$URGENCY" -a "ScienceMonitor" -t 15000 \
            --print-id \
            --action="default=Open Article" \
            --action="read_article=Read Article" \
            --wait \
            "💡 $TAG" "$TITLE" 2>/dev/null)

        if [[ "$RESPONSE" == *"read_article"* ]] || [[ "$RESPONSE" == *"default"* ]]; then
            xdg-open "$LINK" >/dev/null 2>&1 &
        fi
    ) &
}

# --- 6. MAIN LOOP ---
while true; do
    for URL in "${FEEDS[@]}"; do
        RAW_XML=$(curl -sL -A "Mozilla/5.0" --connect-timeout 15 "$URL") || continue
        ITEMS=$(echo "$RAW_XML" | sed -e 's/<\/item>/<\/item>\n/g' -e 's/<\/entry>/<\/entry>\n/g' | grep -E '<item|<entry')

        while IFS= read -r ITEM; do
            [[ -z "$ITEM" ]] && continue
            TITLE=$(echo "$ITEM" | sed -n 's/.*<title[^>]*>\(.*\)<\/title>.*/\1/p' | sed 's/<!\[CDATA\[//g;s/\]\]>//g' | head -n1 | xargs)
            LINK=$(echo "$ITEM" | sed -n 's/.*<link>\([^<]*\)<\/link>.*/\1/p' | head -n1)
            [[ -z "$LINK" ]] && LINK=$(echo "$ITEM" | sed -n 's/.*href="\([^"]*\)".*/\1/p' | head -n1)
            DESC=$(echo "$ITEM" | sed -n 's/.*<description[^>]*>\(.*\)<\/description>.*/\1/p' | sed 's/<!\[CDATA\[//g;s/\]\]>//g' | head -n1 | xargs)

            TITLE=$(decode_html_entities "$TITLE")
            DESC=$(decode_html_entities "$DESC")

            # FILTER: Quality guard
            [[ ${#TITLE} -lt 15 || -z "$LINK" ]] && continue
            grep -qF "$LINK" "$HISTORY_FILE" && continue

            TOPIC_LABEL=$(get_tag "$TITLE $DESC")
            [[ "$TOPIC_LABEL" == "SKIP" ]] && continue

            # UNIVERSAL BREAKTHROUGH CHECK
            FINAL_TAG="$TOPIC_LABEL"
            PRACTICAL="cured|eradicated|fda approved|fast-tracked|treatment|human trial|vaccine|sustainable|carbon-neutral"
            THEORETICAL="breakthrough|revolutionary|milestone|first ever|world first|discovery|astonishing|self-replicate|high-efficiency|unprecedented|mystery solved|new class of|rethinking|paradigm shift"
            
            if echo "$TITLE $DESC" | grep -qiE "$PRACTICAL|$THEORETICAL"; then
                FINAL_TAG="🔥 BREAKTHROUGH ($TOPIC_LABEL)"
                handle_notification "$LINK" "$TITLE" "$FINAL_TAG" "critical"
                
                # --- EMAIL PART (Category and Title in Subject) ---
                echo -e "Subject: $TOPIC_LABEL: $TITLE\n\n$(date '+%Y-%m-%d %H:%M')  $TITLE\n$TOPIC_LABEL\n$LINK" | msmtp -t "$ALERT_EMAIL"
            else
                handle_notification "$LINK" "$TITLE" "$TOPIC_LABEL" "normal"
            fi

            # LOGGING
            echo "$(date '+%Y-%m-%d %H:%M') | $FINAL_TAG | $TITLE | $LINK" >> "$HISTORY_FILE"
            # Format for Logseq using #[[Tag]] for easier navigation
            echo "- #[[${TOPIC_LABEL}]] ${TITLE} [Link](${LINK})" >> "$LOGSEQ_JOURNAL"
        done <<< "$ITEMS"
    done
    sleep 1800
done
