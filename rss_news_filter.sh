#!/usr/bin/env bash

# --- 1. CONFIGURATION ---
ALERT_EMAIL="cabpacedilla@gmail.com"
HISTORY_FILE="$HOME/.cache/practical_science_history.log"
LOGSEQ_JOURNAL="$HOME/Documents/Logseq/journals/$(date +%Y_%m_%d).md"
mkdir -p "$(dirname "$HISTORY_FILE")"
mkdir -p "$(dirname "$LOGSEQ_JOURNAL")"

# --- 2. THE FILTER ENGINE ---
SLOP_PAT="tiktok|lamborghini|supercar|gaming|celebrity|gossip|rumor|entertainment|fashion|luxury|brand|influencer|scandal"

# Breakthrough keywords
PRACTICAL="cured|eradicated|fda approved|fast-tracked|treatment|human trial|vaccine|sustainable|carbon-neutral"
THEORETICAL="breakthrough|revolutionary|milestone|first ever|world first|discovery|astonishing|self-replicate|high-efficiency|unprecedented|mystery solved|new class of|rethinking|paradigm shift"

# --- 3. THE FEED LIST ---
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

# --- 4. HELPERS ---
decode_html_entities() {
    echo "$1" | python3 -c "import sys, html, urllib.parse; print(html.unescape(urllib.parse.unquote(sys.stdin.read().strip())))"
}

# --- 5. MAIN LOOP ---
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

            [[ ${#TITLE} -lt 15 || -z "$LINK" ]] && continue
            grep -qF "$LINK" "$HISTORY_FILE" && continue

            if echo "$TITLE $DESC" | tr '[:upper:]' '[:lower:]' | grep -qiE "$SLOP_PAT"; then
                continue
            fi

            # --- LOGIC: BREAKTHROUGH OR NOTHING ---
            FINAL_TAG=""
            URGENCY="normal"

            if echo "$TITLE $DESC" | grep -qiE "$PRACTICAL|$THEORETICAL"; then
                FINAL_TAG="🔥 BREAKTHROUGH "
                URGENCY="critical"
            fi

            # --- NOTIFICATIONS ---
            (
                ACTION=$(notify-send -u "$URGENCY" -a "News Alert" \
                    -t 0 \
                    --hint=int:transient:0 \
                    --action="open=Read Article" \
                    "💡 $FINAL_TAG" "$TITLE")

                if [[ "$ACTION" == "open" ]]; then
                    xdg-open "$LINK" >/dev/null 2>&1
                fi
            ) &

            # --- EMAIL ---
            (
                # If no tag, the subject starts directly with the Title
                echo -e "Subject: ${FINAL_TAG}${TITLE}\n\nDate: $(date)\nLink: $LINK\n\nDescription: $DESC" | msmtp -t "$ALERT_EMAIL"
            ) &

            # --- LOGGING ---
            # Using empty string for tag column if it's not a breakthrough
            echo "$(date '+%Y-%m-%d %H:%M') | $FINAL_TAG | Feed | $TITLE | $LINK" >> "$HISTORY_FILE"
            echo "- ${TITLE} [Link](${LINK})" >> "$LOGSEQ_JOURNAL"

        done <<< "$ITEMS"
    done
    sleep 1800 
done
