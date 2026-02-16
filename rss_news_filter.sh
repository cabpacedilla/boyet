#!/usr/bin/env bash

# --- 1. CONFIGURATION ---
HISTORY_FILE="$HOME/.cache/practical_science_history.log"
LOGSEQ_JOURNAL="$HOME/Documents/Logseq/journals/$(date +%Y_%m_%d).md"
mkdir -p "$(dirname "$HISTORY_FILE")"

# --- 2. THE SIGNAL WEIGHTING ENGINE ---
CRITICALS="Treatment|Cure|Toxin|Warning|Efficacy|FDA|Zero-Day|Vulnerability|Exploit|Alert|Emergency|Crisis|Impossible|Overturned|Revolutionary|Milestone|Breakthrough|Discovered|Unlocks"

# --- Updated keyword lists ---
HYPER_BIO="Cure|Vaccine|Universal|Eradicated|Genome|Longevity|Birth|Contraception|Inhalable|Neurodegenerative|Metabolic|Microbiome|Senses|Stethoscope|Achilles|Tennis Elbow|Kidney|Paralyzed|Consciousness|Hair Regrowth|Medicine|Pathogen|Bug|Brain|Enzyme|Protein|Disease|Virus|Bacteria|Gene|DNA|Neuro|Memory|Cancer|Immune|Wellness|Reproduction|Uterus|Muscle|Obesity|Diabetes|Placenta|Synapse|Neurological|Psychology|Alzheimer|Parkinson|Dementia"
HYPER_TECH="Quantum|AGI|Superintelligence|Sentience|Encryption|Hardware|Semiconductor|Automated|Cybersecurity|Kernel|Compiler|Deep Learning|LLM|Neural|NLP|GPU|Algorithm|Architecture|Transistor|Blockchain|Robot|Robotic|Chip|Circuit|Sensor|Computing|Digital|Network|System|Cyber|DDoS|Malicious|DevOps|Coding|Code|AI"
HYPER_SPACE="Exoplanet|Habitable|Aliens|Signals|James Webb|Mars|Lava|Moon|NASA|Planet|Satellite|SpaceX|ISS|Astronaut|Spacewalk|Observatory|Celestial|Starship|Webb|Black Hole|Milky Way|Nebula|Rover|Helix Nebula|Orbit|Universe|Cosmos|Telescope"
HYPER_PHYS="Superconductor|Fusion|Quantum|Particle|Gravity|Atomic|Relativity|Einstein|Laser|Entangled|Qubit|Spintronics|Quantum Time|Electric Fields|Water Chemistry|Thermodynamics|Neutrino|Mechanics|Supercollider"
HYPER_EARTH="Extinction|Archaeological|Dinosaur|Climate|Evolution|Species|Fossil|Ancient|Ocean|Plastic|Pollution|Biodiversity|Forest|Environment|Plant|Animal|Marine|Sealife|Fire|Arctic|Upcycling|Origin|Geology|Weather|Ecology|Seafloor|Storm|Flood|Antarctica|Glacier|Methane|Neanderthal|Paleolithic|Rocks|Metal|Stonehenge|Sailboat|Navy|Vessel|Forests|Deer|Carbon|Mineral|Dinosaur Footprint|Corals|Reefs|Glaciers|Volcano|Earthquake"
HYPER_SOC="Policy|Crisis|Uprising|Election|Law|Reform|Pandemic|Education|Homelessness|Sociology|Demographic|Psychosocial|Community|Dating|Politics|Urban|Housing|Teens|Art|Faith|Race|Compassion|Social|Inequality|Crime|Justice|Welfare|Immigration|Democracy|Economy|Poverty|Unemployment"

# --- Signal lists (for scoring) ---
TECH_SIGNALS="Deep Learning|LLM|Neural|NLP|GPU|Algorithm|Architecture|Transistor|Cybersecurity|Kernel|Compiler|Automation|Software|Hardware|CPU|NVME|Blockchain|Robot|Robotic|Chip|Circuit|Sensor|Computing|Digital|Network|System|Cyber|DDoS|Malicious|DevOps|Coding|Code|AI|Quantum Computing|Machine Learning|Data Science|Cloud|Server|Database|Encryption|Firewall|Malware|Ransomware|Phishing|Hacking|IoT|5G|WiFi|Bluetooth|VR|AR|Autonomous|Drone"
BIO_SIGNALS="Nutrition|Sleep|Exercise|Mental|Vaccine|Diet|Microbiome|Habit|Cognitive|Health|Brain|Medicine|Aging|Virus|Bacteria|Genetic|DNA|Enzyme|Protein|Cell|Clinical|Therapy|Patient|Biotech|Biology|Alzheimer|Parkinson|Dementia|Synapse|Neurological|Psychology|Cancer|Microbe|Wellness|Reproduction|Uterus|Muscle|Obesity|Diabetes|Placenta|Neurodegenerative|Metabolic|Senses|Stethoscope|Achilles|Tennis Elbow|Kidney|Paralyzed|Consciousness|Hair Regrowth|Pathogen|Bug|Immune System|Antibody|Neurotransmitter|Hormone|Tissue|Organ|Surgery|Pharma|Drug|Pill|Vaccination|Infection|Pandemic|Epidemic|Outbreak"
SPACE_SIGNALS="Stars|Galaxy|Astronomy|Telescope|Cosmos|Jupiter|Universe|Orbit|Astronaut|Spacewalk|Observatory|Celestial|ISS|SpaceX|Satellite|Starship|Webb|Black Hole|Milky Way|Nebula|Rover|Helix Nebula|Mars|Moon|Planet|Comet|Asteroid|Meteor|Solar System|Exoplanet|Habitable Zone|NASA|ESA|Space Mission|Launch|Rocket|Propulsion|Gravity|Atmosphere|Vacuum|Radiation|Cosmic|Interstellar|Light Year|Pulsar|Quasar|Dark Matter|Dark Energy"
PHYS_SIGNALS="Physics|Axion|Superconductivity|Thermodynamics|Neutrino|Laser|Entangled|Qubit|Mechanics|Supercollider|Fusion|Relativity|Spintronics|Quantum Time|Electric Fields|Water Chemistry|Particle|Gravity|Atomic|Nuclear|Plasma|Magnetism|Optics|Acoustics|Thermal|Fluid Dynamics|String Theory|Higgs Boson|CERN|Accelerator|Collider|Energy|Matter|Antimatter|Photon|Electron|Proton|Neutron|Ion|Phonon"
EARTH_SIGNALS="Fossil|Ocean|Plastic|Pollution|Biodiversity|Forest|Environment|Plant|Animal|Marine|Sealife|Fire|Arctic|Upcycling|Origin|Geology|Weather|Ecology|Seafloor|Storm|Flood|Antarctica|Glacier|Methane|Neanderthal|Paleolithic|Rocks|Metal|Stonehenge|Sailboat|Navy|Vessel|Forests|Deer|Carbon|Mineral|Dinosaur Footprint|Corals|Reefs|Glaciers|Volcano|Earthquake|Tsunami|Hurricane|Tornado|Drought|Erosion|Soil|Climate Change|Global Warming|Greenhouse Gas|CO2|Ozone|Atmosphere|Weather Pattern|El Niño|La Niña|Jet Stream|Polar Ice|Permafrost|Desert|Wetland|River|Lake|Mountain"
SOCIAL_SIGNALS="Caregivers|Sociology|School|Primary|Demographic|Psychosocial|Community|Dating|Politics|Urban|Housing|Teens|Art|Faith|Race|Compassion|Social|Inequality|Crime|Justice|Welfare|Immigration|Democracy|Economy|Poverty|Unemployment|Policy|Crisis|Uprising|Election|Law|Reform|Pandemic|Education|Homelessness|Gender|LGBTQ|Disability|Veteran|Refugee|Migration|Culture|Tradition|Heritage|Language|Ethnicity|Religion|Belief|Value|Norm|Stigma|Prejudice|Discrimination"

SLOP_SIGNALS="TikTok|Trailer|Lamborghini|Supercar|Gaming|Switch 2|Steam Machine|Medicare|Scandal|Olympic|Vance|Trump|EPA|Stellantis|Ferrari|KTM|Mazda|Porsche|Ducati|Celebrity|Influencer|Gossip|Rumor|Entertainment|Movie|Music|Concert|Fashion|Luxury|Brand|Product|Advertisement|Marketing|Sale|Discount|Deal|Promotion|Sponsor|Merchandise|Event|Festival|Award|Prize|Contest|Sports|Team|League|Tournament|Match|Game|Player|Coach|Fan|Supporter"

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

# --- Function to decode HTML entities ---
decode_html_entities() {
    echo "$1" | sed -e 's/&#x27;/\'\''/g' -e 's/&amp;/\&/g' -e 's/&lt;/</g' -e 's/&gt;/>/g' -e 's/&quot;/"/g' -e "s/&#039;/'/g"
}

# --- Function for notification handling ---
handle_notification() {
    local LINK="$1"
    local TITLE="$2"
    local TAG="$3"
    local URGENCY="$4"

    RESPONSE=$(notify-send -u "$URGENCY" -a "ScienceMonitor" -t 15000 \
        --action="read_article=Read Article" \
        "💡 $TAG" "$TITLE")

    case "$RESPONSE" in
        "read_article")
            xdg-open "$LINK" >/dev/null 2>&1 &
            ;;
        *)
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

            # Decode HTML entities
            TITLE=$(decode_html_entities "$TITLE")
            DESC=$(decode_html_entities "$DESC")

            # Skip if title is empty, too short, or link is already in history
            [[ -z "$TITLE" || -z "$LINK" || ${#TITLE} -lt 5 ]] && continue
            grep -qF "$LINK" "$HISTORY_FILE" && continue

            # Skip if content matches slop signals
            CONTENT=$(echo "$TITLE $DESC" | tr '[:upper:]' '[:lower:]')
            [[ $(echo "$CONTENT" | grep -qiE "($SLOP_SIGNALS)") ]] && continue

            # --- 4. STRONG MANUAL OVERRIDES (PRIORITY) ---
            TITLE_LOWER=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]')
            DESC_LOWER=$(echo "$DESC" | tr '[:upper:]' '[:lower:]')

            # Health/Bio: Absolute priority for medical/biological terms
            if [[ "$TITLE_LOWER" =~ (brain|enzyme|protein|disease|virus|bacteria|gene|dna|neuro|memory|cancer|immune|metabolic|microbiome|aging|dementia|alzheimer|parkinson|synapse|neurological|psychology|wellness|reproduction|uterus|muscle|obesity|diabetes|placenta|neurodegenerative|senses|stethoscope|achilles|tennis elbow|kidney|paralyzed|consciousness|hair regrowth|pathogen|bug|immune system|antibody|neurotransmitter|hormone|tissue|organ|surgery|pharma|drug|pill|vaccination|infection|pandemic|epidemic|outbreak|heart|stroke|jet lag|spine|spinal|gut|bacteria|microbe|cell|clinical|therapy|patient|biotech|biology|medicine|vaccine) ]]; then
                TOPIC_LABEL="Health/Bio"

            # Space: Only for astronomy/spaceflight
            elif [[ "$TITLE_LOWER" =~ (mars|galaxy|astronomy|telescope|cosmos|jupiter|universe|orbit|astronaut|spacewalk|observatory|celestial|iss|spacex|satellite|starship|webb|black hole|milky way|nebula|rover|helix nebula|exoplanet|habitable|aliens|signals|james webb|nasa|planet|comet|asteroid|meteor|solar system|space mission|launch|rocket|propulsion|gravity|vacuum|radiation|cosmic|interstellar|light year|pulsar|quasar|dark matter|dark energy) ]]; then
                TOPIC_LABEL="Space"

            # Physics: Fundamental physics, quantum, etc.
            elif [[ "$TITLE_LOWER" =~ (physics|axion|superconductivity|thermodynamics|neutrino|laser|entangled|qubit|mechanics|supercollider|fusion|relativity|spintronics|quantum time|electric fields|water chemistry|particle|gravity|atomic|nuclear|plasma|magnetism|optics|acoustics|thermal|fluid dynamics|string theory|higgs boson|cern|accelerator|collider|energy|matter|antimatter|photon|electron|proton|neutron|ion|phonon) ]]; then
                TOPIC_LABEL="Physics"

            # Earth/Nature: Ecology, geology, environment
            elif [[ "$TITLE_LOWER" =~ (fossil|ocean|plastic|pollution|biodiversity|forest|environment|plant|animal|marine|sealife|fire|arctic|upcycling|origin|geology|weather|ecology|seafloor|storm|flood|antarctica|glacier|methane|neanderthal|paleolithic|rocks|metal|stonehenge|sailboat|navy|vessel|forests|deer|carbon|mineral|dinosaur footprint|corals|reefs|glaciers|volcano|earthquake|tsunami|hurricane|tornado|drought|erosion|soil|climate change|global warming|greenhouse gas|co2|ozone|atmosphere|weather pattern|el niño|la niña|jet stream|polar ice|permafrost|desert|wetland|river|lake|mountain) ]]; then
                TOPIC_LABEL="Earth/Nature"

            # Tech/Comp: Computing, AI, engineering
            elif [[ "$TITLE_LOWER" =~ (deep learning|llm|neural|nlp|gpu|algorithm|architecture|transistor|cybersecurity|kernel|compiler|automation|software|hardware|cpu|nvme|blockchain|robot|robotic|chip|circuit|sensor|computing|digital|network|system|cyber|ddos|malicious|devops|coding|code|ai|quantum computing|machine learning|data science|cloud|server|database|encryption|firewall|malware|ransomware|phishing|hacking|iot|5g|wifi|bluetooth|vr|ar|autonomous|drone) ]]; then
                TOPIC_LABEL="Tech/Comp"

            # Social/Policy: Sociology, politics, community
            elif [[ "$TITLE_LOWER" =~ (policy|crisis|uprising|election|law|reform|pandemic|education|homelessness|sociology|demographic|psychosocial|community|dating|politics|urban|housing|teens|art|faith|race|compassion|social|inequality|crime|justice|welfare|immigration|democracy|economy|poverty|unemployment) ]]; then
                TOPIC_LABEL="Social/Policy"

            else
                # --- 5. SCORING (FALLBACK) ---
                CONTENT_FOR_SCORING=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]')
                B_SCORE=$(echo "$CONTENT_FOR_SCORING" | grep -oiwE "($BIO_SIGNALS)" | wc -l)
                T_SCORE=$(echo "$CONTENT_FOR_SCORING" | grep -oiwE "($TECH_SIGNALS)" | wc -l)
                S_SCORE=$(echo "$CONTENT_FOR_SCORING" | grep -oiwE "($SPACE_SIGNALS)" | wc -l)
                P_SCORE=$(echo "$CONTENT_FOR_SCORING" | grep -oiwE "($PHYS_SIGNALS)" | wc -l)
                E_SCORE=$(echo "$CONTENT_FOR_SCORING" | grep -oiwE "($EARTH_SIGNALS)" | wc -l)
                SOC_SCORE=$(echo "$CONTENT_FOR_SCORING" | grep -oiwE "($SOCIAL_SIGNALS)" | wc -l)

                # Apply hyper signals
                echo "$CONTENT_FOR_SCORING" | grep -qiE "($HYPER_BIO)" && B_SCORE=$((B_SCORE + 5))
                echo "$CONTENT_FOR_SCORING" | grep -qiE "($HYPER_TECH)" && T_SCORE=$((T_SCORE + 5))
                echo "$CONTENT_FOR_SCORING" | grep -qiE "($HYPER_SPACE)" && S_SCORE=$((S_SCORE + 5))
                echo "$CONTENT_FOR_SCORING" | grep -qiE "($HYPER_PHYS)" && P_SCORE=$((P_SCORE + 5))
                echo "$CONTENT_FOR_SCORING" | grep -qiE "($HYPER_EARTH)" && E_SCORE=$((E_SCORE + 5))
                echo "$CONTENT_FOR_SCORING" | grep -qiE "($HYPER_SOC)" && SOC_SCORE=$((SOC_SCORE + 5))

                # --- 6. CATEGORY ASSIGNMENT (FALLBACK) ---
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
            fi

            # --- 7. BREAKTHROUGH TAGGING ---
            TAG="$TOPIC_LABEL"
            if echo "$CONTENT_FOR_SCORING" | grep -qiE "\b($CRITICALS|$HYPER_BIO|$HYPER_TECH|$HYPER_SPACE|$HYPER_PHYS|$HYPER_EARTH|$HYPER_SOC)\b"; then
                TAG="🔥 BREAKTHROUGH ($TOPIC_LABEL)"
            fi

            # --- 8. LOGGING ---
            TIMESTAMP=$(date "+%Y-%m-%d %H:%M")
            echo "[$TIMESTAMP][$TAG] $TITLE | $LINK" >> "$HISTORY_FILE"

            if [ -d "$(dirname "$LOGSEQ_JOURNAL")" ]; then
                echo "- #Breakthrough [$TAG] $TITLE [Link]($LINK)" >> "$LOGSEQ_JOURNAL"
            fi

            # --- 9. NOTIFICATION ---
            URGENCY="normal"
            [[ "$TAG" == *"BREAKTHROUGH"* ]] && URGENCY="critical"
            handle_notification "$LINK" "$TITLE" "$TAG" "$URGENCY" &
        done <<< "$ITEMS"
    done
    sleep 1200
done
