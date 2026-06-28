#!/bin/bash
# ================================================================
# Job Fetcher – Smart Ranked Adzuna Monitor (debug‑ready)
# ================================================================

set -euo pipefail

DEBUG="${DEBUG:-0}"

log() {
    [[ "$DEBUG" -ge 1 ]] && echo "[DEBUG] $*" >&2
}
verbose_run() {
    [[ "$DEBUG" -ge 2 ]] && echo "[VERBOSE] $*" >&2
    "$@"
}

# ---------- Dependencies ----------
for cmd in curl jq msmtp flock notify-send; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "Missing dependency: $cmd" >&2
        exit 1
    }
done

# ---------- Lock ----------
LOCKFILE="/tmp/job_fetcher.lock"
exec 200>"$LOCKFILE"
flock -n 200 || {
    echo "Another instance is running." >&2
    exit 1
}

# ---------- Environment ----------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

[[ -f "$ENV_FILE" ]] || { echo ".env missing" >&2; exit 1; }

set -a
source "$ENV_FILE"
set +a

# ---------- Config ----------
COUNTRIES=("au" "nz" "ca")
KEYWORDS="software tester|QA|test automation|quality assurance"
DAYS_OLD=3
RESULTS_PER_PAGE=20

RECIPIENT="cabpacedilla@gmail.com"
EMAIL_SUBJECT="🔍 Smart Ranked QA Jobs"

CACHE_FILE="${HOME}/.cache/job_fetcher_seen.txt"
MAX_CACHE_LINES=5000

mkdir -p "$(dirname "$CACHE_FILE")"
touch "$CACHE_FILE"

TMPFILE=$(mktemp)
BODY_FILE=$(mktemp)

cleanup() {
    rm -f "$TMPFILE" "$BODY_FILE"
}
trap cleanup EXIT

# ---------- Heuristics (unchanged) ----------
country_boost() {
    case "$1" in
        au) echo 30 ;;
        nz) echo 10 ;;
        ca) echo 15 ;;
        *) echo 0 ;;
    esac
}

company_boost() {
    case "$1" in
        "Google"|"Microsoft"|"Atlassian"|"Amazon") echo 25 ;;
        *) echo 0 ;;
    esac
}

rank_job() {
    local country="$1"
    local company="$2"
    local salary="$3"
    local score=0
    score=$((score + $(country_boost "$country")))
    score=$((score + $(company_boost "$company")))
    if [[ "$salary" =~ [0-9]+ ]]; then
        if (( salary > 90000 )); then score=$((score + 40))
        elif (( salary > 60000 )); then score=$((score + 20))
        fi
    fi
    echo "$score"
}

tier_from_score() {
    local s=$1
    if (( s >= 70 )); then echo "A"
    elif (( s >= 40 )); then echo "B"
    else echo "C"
    fi
}

# ---------- Cache ----------
declare -A SEEN
while read -r id; do
    SEEN["$id"]=1
done < "$CACHE_FILE"

# ---------- Email ----------
{
    echo "To: $RECIPIENT"
    echo "Subject: $EMAIL_SUBJECT"
    echo "Content-Type: text/plain; charset=UTF-8"
    echo
    echo "Smart ranked job results (Tier A = best matches)"
    echo
} > "$TMPFILE"

NEW_IDS=()
NEW_COUNT=0

# ---------- Fetch loop ----------
for COUNTRY in "${COUNTRIES[@]}"; do

    log "Fetching $COUNTRY"

    # Build the curl command (without --retry-5xx for compatibility)
    CURL_CMD=(
        curl -sS
        --retry 3
        --retry-delay 2
        -o "$BODY_FILE"
        -w "%{http_code}"
        -G "https://api.adzuna.com/v1/api/jobs/$COUNTRY/search/1"
        --data-urlencode "app_id=$ADZUNA_APP_ID"
        --data-urlencode "app_key=$ADZUNA_API_KEY"
        --data-urlencode "what=$KEYWORDS"
        --data-urlencode "max_days=$DAYS_OLD"
        --data-urlencode "results_per_page=$RESULTS_PER_PAGE"
    )

    log "Running: ${CURL_CMD[*]}"

    # Execute with error capture
    if ! HTTP_CODE=$( "${CURL_CMD[@]}" 2> >(tee /tmp/curl_err.log >&2) ); then
        ERR_MSG=$(< /tmp/curl_err.log)
        echo "⚠️  Network error for $COUNTRY: $ERR_MSG" >> "$TMPFILE"
        rm -f /tmp/curl_err.log
        continue
    fi
    rm -f /tmp/curl_err.log

    BODY=$(<"$BODY_FILE")

    [[ "$HTTP_CODE" =~ ^[0-9]{3}$ ]] || {
        echo "Bad HTTP code: $COUNTRY ($HTTP_CODE)" >> "$TMPFILE"
        continue
    }
    [[ "$HTTP_CODE" -eq 200 ]] || {
        echo "API error: $COUNTRY HTTP $HTTP_CODE" >> "$TMPFILE"
        continue
    }

    # Parse results
    while read -r job; do
        JOB_ID=$(jq -r '.id // empty' <<< "$job")
        [[ -z "$JOB_ID" ]] && continue

        [[ -v SEEN["$JOB_ID"] ]] && continue
        SEEN["$JOB_ID"]=1

        TITLE=$(jq -r '.title // "N/A"' <<< "$job")
        COMPANY=$(jq -r '.company.display_name // "Unknown"' <<< "$job")
        URL=$(jq -r '.redirect_url // ""' <<< "$job")
        SALARY_RAW=$(jq -r '.salary_max // 0' <<< "$job" 2>/dev/null || echo 0)

        SCORE=$(rank_job "$COUNTRY" "$COMPANY" "$SALARY_RAW")
        TIER=$(tier_from_score "$SCORE")

        if (( SCORE < 15 )); then
            log "Skipping low score job $TITLE ($SCORE)"
            continue
        fi

        printf "[%s | %s pts]\n📍 %s @ %s (%s)\n🔗 %s\n\n" \
            "$TIER" "$SCORE" "$TITLE" "$COMPANY" "$COUNTRY" "$URL" >> "$TMPFILE"

        ((++NEW_COUNT))
        NEW_IDS+=("$JOB_ID")

        if [[ "$TIER" == "A" && -n "${DISPLAY:-}" ]]; then
            notify-send "🔥 Tier A Job" "$TITLE @ $COMPANY ($COUNTRY)"
        fi
    done < <(jq -c '.results[]?' <<< "$BODY")

done

# ---------- Exit if nothing new ----------
((NEW_COUNT == 0)) && {
    echo "No new jobs"
    exit 0
}

# ---------- Send email ----------
if msmtp "$RECIPIENT" < "$TMPFILE"; then
    tmp_cache=$(mktemp)
    cat "$CACHE_FILE" > "$tmp_cache"
    printf "%s\n" "${NEW_IDS[@]}" >> "$tmp_cache"
    mv "$tmp_cache" "$CACHE_FILE"
    tail -n "$MAX_CACHE_LINES" "$CACHE_FILE" > "$CACHE_FILE.tmp"
    mv "$CACHE_FILE.tmp" "$CACHE_FILE"
    echo "Sent + cached"
else
    echo "Email failed" >&2
    exit 1
fi
