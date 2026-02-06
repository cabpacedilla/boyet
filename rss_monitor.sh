#!/usr/bin/env bash

# ============================================================================
# Science News RSS Monitor & Notifier
# Filters science/tech/health news based on keywords and logs/notifies breakthroughs
# ============================================================================

HISTORY_FILE="$HOME/.cache/practical_science_history.log"
touch "$HISTORY_FILE" 2>/dev/null || { echo "Cannot create/write to $HISTORY_FILE"; exit 1; }

# ─────────────────────────────────────────────────────────────────────────────
# 1. KEYWORD GROUPS
# ─────────────────────────────────────────────────────────────────────────────

# High-impact / breakthrough indicators
CRITICALS="Treatment|Cure|Toxin|Warning|Efficacy|Guidelines|FDA|Breakthrough|Prevention|Immunity|Sustainability|Discovery|Ancient|Dangerous|Risk|Threat|Undetected|Record|Resurrect|Infection|Antibiotic|Zero-Day|Vulnerability|Benchmark|Protocol|Open-Source|Exploit|Framework|Breach|Hack"

# Tech, computing, engineering, infosec
TECH_SIGNALS="AI|Deep Learning|LLM|Neural|NLP|Multimodal|Inference|GPU|Algorithm|Architecture|Semiconductor|Transistor|Quantum|Encryption|Cybersecurity|Kernel|Compiler|Automation|Software|Hardware|Astronomy|CPU|NVME|Erase|Drive|Robotics|Security|Knox|Firewall|Patch|Firmware|Malware|Virtualization|Hypervisor"

# Health, biology, environment, life sciences
BIO_SIGNALS="Nutrition|Sleep|Exercise|Mental|Vaccine|Diet|Microbiome|Habit|Cognitive|Stress|Pollution|Climate|Plastic|Longevity|Health|Brain|Medicine|Aging|Virus|Bacteria|Ocean|Fruit|Plant|Genetic|DNA|Genome|Evolution|Puma|Penguin|Injuries|Pesticide|Biodiversity|Seed|Hormone|Animal|Movement|Gene|Fiber|CRISPR|Behavior|Psychology|Biology|Enzyme|Biocatalysis|Crystallography|Molecular|Protein"

# RSS / Atom feeds to monitor
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

# ─────────────────────────────────────────────────────────────────────────────
# Main loop
# ─────────────────────────────────────────────────────────────────────────────

while true; do
    for URL in "${FEEDS[@]}"; do
        # Fetch feed (timeout prevents hanging forever on bad servers)
        RAW_XML=$(curl -sL -A "Mozilla/5.0 (compatible; ScienceMonitor/1.0)" --connect-timeout 15 --max-time 30 "$URL") || continue

        # Handle both RSS <item> and Atom <entry>
        ITEMS=$(echo "$RAW_XML" | tr '\r\n\t' ' ' \
            | sed 's/</\n</g' \
            | grep -E '^<(item|entry)' \
            | sed 's/^<[^>]*>//' )

        while IFS= read -r ITEM || [[ -n "$ITEM" ]]; do
            [[ -z "$ITEM" ]] && continue

            # ─── Extraction ─────────────────────────────────────────────────────

            # Title (handle CDATA and plain text)
            TITLE=$(echo "$ITEM" | grep -oP '<title[^>]*>.*?</title>' \
                | sed -e 's/.*<title[^>]*>//' -e 's/<\/title>.*//' \
                | sed -e 's/<!\[CDATA\[//' -e 's/\]\]//' | xargs)

            # Link (RSS <link> or Atom href= fallback)
            LINK=$(echo "$ITEM" | grep -oP '<link[^>]*>.*?</link>' \
                | sed -e 's/.*<link[^>]*>//' -e 's/<\/link>.*//' \
                | sed -e 's/<!\[CDATA\[//' -e 's/\]\]//' | head -n1 | xargs)

            if [[ -z "$LINK" ]]; then
                LINK=$(echo "$ITEM" | grep -oP 'href="[^"]+"' | head -n1 | cut -d'"' -f2 | xargs)
            fi

            # Description / summary
            DESC=$(echo "$ITEM" | grep -oP '(<description>|<summary>|<content[^>]*>).*?(</description>|</summary>|</content>)' \
                | sed -e 's/.*>//' -e 's/<.*//' \
                | sed -e 's/<!\[CDATA\[//' -e 's/\]\]//' | xargs)

            [[ -z "$TITLE" || -z "$LINK" ]] && continue

            # Skip already seen articles
            grep -qF -- "$LINK" "$HISTORY_FILE" 2>/dev/null && continue

            # ─── Scoring ────────────────────────────────────────────────────────

            CONTENT_TO_SCAN="$TITLE $DESC"

            BIO_SCORE=$(echo "$CONTENT_TO_SCAN" | grep -oiwE "($BIO_SIGNALS)" | wc -l)
            TECH_SCORE=$(echo "$CONTENT_TO_SCAN" | grep -oiwE "($TECH_SIGNALS)" | wc -l)

            TOPIC_LABEL="General"
            SHOULD_PROCESS=false

            # Priority: Tech/Security > Health/Bio > mixed/default
            if (( TECH_SCORE > BIO_SCORE )); then
                TOPIC_LABEL="Tech/Security"
                SHOULD_PROCESS=true
            elif (( BIO_SCORE > TECH_SCORE )); then
                TOPIC_LABEL="Health/Bio"
                SHOULD_PROCESS=true
            elif (( BIO_SCORE > 0 || TECH_SCORE > 0 )); then
                # Tie / mixed — prefer Tech if security words are present
                if echo "$CONTENT_TO_SCAN" | grep -qiwE "(Vulnerability|Breach|Security|Knox|Exploit|Hack|Malware|Patch|Firmware)"; then
                    TOPIC_LABEL="Tech/Security"
                else
                    TOPIC_LABEL="Science"
                fi
                SHOULD_PROCESS=true
            fi

            # Independent breakthrough flag
            IS_BREAKTHROUGH=false
            if echo "$CONTENT_TO_SCAN" | grep -qiwE "($CRITICALS)"; then
                IS_BREAKTHROUGH=true
                SHOULD_PROCESS=true
            fi

            # ─── Tagging ────────────────────────────────────────────────────────

            if [[ "$IS_BREAKTHROUGH" == true ]]; then
                TAG="🔥 BREAKTHROUGH"
                [[ "$TOPIC_LABEL" != "General" ]] && TAG="🔥 BREAKTHROUGH ($TOPIC_LABEL)"
            else
                TAG="$TOPIC_LABEL"
            fi

            # ─── Logging & Notification ─────────────────────────────────────────

            if [[ "$SHOULD_PROCESS" == true ]]; then
                SOURCE="Discovery"
                [[ "$URL" == *"nature.com"*          ]] && SOURCE="Nature"
                [[ "$URL" == *"phys.org"*            ]] && SOURCE="Phys.org"
                [[ "$URL" == *"arstechnica.com"*     ]] && SOURCE="Ars Technica"
                [[ "$URL" == *"ycombinator.com"* || "$URL" == *"hnrss.org"* ]] && SOURCE="Hacker News"
                [[ "$URL" == *"technologyreview.com"*]] && SOURCE="MIT Tech Review"
                [[ "$URL" == *"sciencedaily.com"*    ]] && SOURCE="Science Daily"
                [[ "$URL" == *"thehackernews.com"*   ]] && SOURCE="The Hacker News"

                TIMESTAMP=$(date "+%Y-%m-%d %H:%M")
                ENTRY="[$TIMESTAMP][$TAG: $SOURCE] $TITLE | $LINK"

                printf '%s\n' "$ENTRY" >> "$HISTORY_FILE"

                # Background notification
                (
                    URGENCY="normal"
                    [[ "$IS_BREAKTHROUGH" == true ]] && URGENCY="critical"

                    RES=$(notify-send -u "$URGENCY" -a "ScienceMonitor" -t 15000 \
                        --action="open=Read Article" \
                        "💡 $TAG  ($SOURCE)" "$TITLE" 2>/dev/null)

                    [[ "$RES" == "open" ]] && xdg-open "$LINK" 2>/dev/null
                ) &>/dev/null &
            fi
        done <<< "$ITEMS"
    done

    # Deduplicate log (safe even if interrupted)
    if [[ -s "$HISTORY_FILE" ]]; then
        awk '!seen[$0]++' "$HISTORY_FILE" > "${HISTORY_FILE}.tmp" && \
            mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"
    fi

    sleep 1200   # 20 minutes
done
