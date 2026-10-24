#!/bin/sh
# NetBSD/SDF-aligned science RSS filter: POSIX sh only (no bash needed).
# Cron example (use full paths; cron has no profile):
#   */30 * * * * /bin/sh $HOME/practical_science_monitor_netbsd.sh >/dev/null 2>&1
set -u

# cron has a minimal PATH; pkgsrc installs under /usr/pkg.
PATH="$PATH:/usr/pkg/bin:/usr/pkg/sbin:/usr/local/bin"
export PATH
PYTHONIOENCODING=utf-8
export PYTHONIOENCODING

HISTORY_FILE="$HOME/practical_science_history.log"
LOGSEQ_JOURNAL="$HOME/science_journal_$(date +%Y_%m_%d).md"
ERROR_LOG="$HOME/practical_science_errors.log"
export HISTORY_FILE

# --- email ---
# Change ALERT_EMAIL to your address. Set MAILER="" to disable email.
#   msmtp : pkgin install msmtp ; configure ~/.msmtprc (chmod 600)
#   mail  : NetBSD base mail(1), needs a working local MTA / SMTP relay
ALERT_EMAIL="cabpacedilla@gmail.com"
MAILER="msmtp"
# 1 = send the digest even when no new items were found (so a quiet run is visible).
# 0 = only mail when there is at least one new item.
MAIL_ON_EMPTY=0

SLOP_PAT="tiktok|lamborghini|supercar|gaming|celebrity|gossip|rumor|entertainment|fashion|luxury|brand|influencer|scandal"
PRACTICAL="cured|eradicated|fda approved|fast-tracked|treatment|human trial|vaccine|sustainable|carbon-neutral"
THEORETICAL="breakthrough|revolutionary|milestone|first ever|world first|discovery|astonishing|self-replicate|high-efficiency|unprecedented|mystery solved|new class of|rethinking|paradigm shift"
export SLOP_PAT PRACTICAL THEORETICAL

# Skip items published more than this many days ago (0 = no limit). Items without a date are kept.
MAX_AGE_DAYS=14
export MAX_AGE_DAYS

# --- THE FEED LIST (one URL per line; add ' strict' to keep only BREAKTHROUGH/PRACTICAL matches) ---
# VERIFY each endpoint returns real RSS/Atom before relying on it.
FEEDS='
https://www.nature.com/nature/research-articles.rss
https://phys.org/rss-feed/
https://www.newscientist.com/section/news/feed/
https://www.newscientist.com/feed/home/
https://www.eurekalert.org/rss/breaking.xml
https://www.quantamagazine.org/feed/
https://www.sciencedaily.com/rss/top/science.xml
https://www.sciencedaily.com/rss/top/health.xml
https://www.sciencedaily.com/rss/top/environment.xml
https://www.sciencedaily.com/rss/top/technology.xml
https://www.sciencedaily.com/rss/mind_brain.xml
https://www.sciencedaily.com/rss/health_medicine/nutrition.xml
https://www.sciencedaily.com/rss/health_medicine/fitness.xml
https://www.sciencedaily.com/rss/mind_brain/sleep_disorders.xml
https://www.technologyreview.com/feed/
https://newatlas.com/index.rss
https://news.ycombinator.com/rss strict
https://hnrss.org/best strict
http://feeds.arstechnica.com/arstechnica/index strict
https://news.mit.edu/rss/research
https://thehackernews.com/feeds/posts/default strict
'

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$ERROR_LOG"; }

# Cleanup on any exit. Only remove the lock if THIS run acquired it.
HAVE_LOCK=0
TMPD=""
LOCKDIR="$HOME/.science-rss.lock.d"
cleanup() {
    [ -n "$TMPD" ] && rm -rf "$TMPD"
    [ "$HAVE_LOCK" -eq 1 ] && rm -rf "$LOCKDIR"
    return 0
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

# Serialize overlapping runs with a mkdir lock (NetBSD has no flock(1)).
if mkdir "$LOCKDIR" 2>/dev/null; then
    HAVE_LOCK=1
else
    oldpid=$(cat "$LOCKDIR/pid" 2>/dev/null)
    if [ -z "$oldpid" ]; then sleep 1; oldpid=$(cat "$LOCKDIR/pid" 2>/dev/null); fi
    if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then
        exit 0                          # a live run holds the lock
    fi
    rm -rf "$LOCKDIR"                   # stale lock from a crashed run
    mkdir "$LOCKDIR" 2>/dev/null || exit 1
    HAVE_LOCK=1
fi
echo $$ > "$LOCKDIR/pid"

TMPD=$(mktemp -d "${TMPDIR:-/tmp}/scirss.XXXXXX") || exit 1
DIGEST="$TMPD/digest.md"
: > "$DIGEST"

# Find a Python 3 (pkgsrc often installs only versioned names).
PY=""
for c in python3 python3.13 python3.12 python3.11 python3.10 python3.9 python3.8 python; do
    if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import sys; sys.exit(sys.version_info[0] < 3)' 2>/dev/null; then
        PY=$c; break
    fi
done
if [ -z "$PY" ]; then log "NO PYTHON 3 FOUND (try: pkgin install python312)"; exit 1; fi
command -v curl >/dev/null 2>&1 || { log "curl not found (try: pkgin install curl)"; exit 1; }
if [ -n "$MAILER" ] && ! command -v "$MAILER" >/dev/null 2>&1; then
    log "MAILER '$MAILER' not found in PATH; email disabled for this run"
    MAILER=""
fi

# Only use --compressed if this curl was built with zlib.
COMP=""
if curl --version 2>/dev/null | grep -qiE 'libz|zlib'; then COMP="--compressed"; fi

cat > "$TMPD/parse.py" <<'PY'
import os, re, sys
from datetime import datetime, timezone, timedelta
from email.utils import parsedate_to_datetime
import xml.etree.ElementTree as ET
from urllib.parse import urljoin, urlsplit, quote

def local(tag):
    return tag.rsplit("}", 1)[-1] if isinstance(tag, str) else ""

slop_re = re.compile(r"\b(?:%s)" % os.environ["SLOP_PAT"], re.I)
prac_re = re.compile(r"\b(?:%s)" % os.environ["PRACTICAL"], re.I)
theo_re = re.compile(r"\b(?:%s)" % os.environ["THEORETICAL"], re.I)
base = os.environ.get("FEED_URL", "")
strict = os.environ.get("STRICT") == "1"

try:
    max_age = float(os.environ.get("MAX_AGE_DAYS", "0"))
except ValueError:
    max_age = 0
cutoff = datetime.now(timezone.utc) - timedelta(days=max_age) if max_age > 0 else None

def parse_date(txt):
    txt = txt.strip()
    try:
        d = parsedate_to_datetime(txt)            # RSS: "Sat, 18 Oct 2026 10:00:00 GMT"
    except (TypeError, ValueError):
        d = None
    if d is None:
        try:
            d = datetime.fromisoformat(txt.replace("Z", "+00:00"))   # Atom / dc:date
        except ValueError:
            return None
    if d.tzinfo is None:
        d = d.replace(tzinfo=timezone.utc)
    return d

seen = set()
try:
    with open(os.environ["HISTORY_FILE"], encoding="utf-8", errors="replace") as fh:
        for line in fh:
            seen.add(line.rstrip("\n").rsplit(" | ", 1)[-1])
except FileNotFoundError:
    pass

try:
    root = ET.fromstring(sys.stdin.buffer.read())
except ET.ParseError as e:
    print(f"XML parse error: {e}", file=sys.stderr)
    sys.exit(2)

count = 0
old = 0
for item in (e for e in root.iter() if local(e.tag) in ("item", "entry")):
    title = link = ""
    dates = {}
    for ch in item:
        name = local(ch.tag)
        if name == "title" and not title:
            title = " ".join((ch.text or "").split())
        elif name == "link" and not link:
            if ch.get("href"):
                if ch.get("rel", "alternate") == "alternate":
                    link = ch.get("href").strip()
            elif ch.text:
                link = ch.text.strip()
        elif name in ("published", "pubDate", "date", "updated") and ch.text and name not in dates:
            dates[name] = ch.text
    if len(title) < 15 or not link or slop_re.search(title):
        continue
    if cutoff is not None:
        d = None
        for k in ("published", "pubDate", "date", "updated"):
            if k in dates:
                d = parse_date(dates[k])
                if d:
                    break
        if d and d < cutoff:
            old += 1
            continue
    link = urljoin(base, link)
    if urlsplit(link).scheme not in ("http", "https"):
        continue
    link = quote(link, safe=":/?#[]@!$&'*+,;=%-._~")  # encodes ( ) and spaces
    if theo_re.search(title):
        tag = "BREAKTHROUGH"
    elif prac_re.search(title):
        tag = "PRACTICAL"
    else:
        tag = "GENERAL"
    if strict and tag == "GENERAL":
        continue            # strict feeds: keep only keyword matches
    if link in seen:
        continue
    seen.add(link)
    md_title = re.sub(r"([\\\[\]])", r"\\\1", title)
    print(f"{tag}\t{title}\t{md_title}\t{link}")
    count += 1
print(f"{count} new from {base} ({old} older than {max_age:g}d skipped)", file=sys.stderr)
PY

UA="Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0"
ACCEPT="application/rss+xml, application/atom+xml, application/xml;q=0.9, text/xml;q=0.8, */*;q=0.5"
TAB=$(printf '\t')

# Keep the error log from growing forever (~1 MB cap).
if [ -f "$ERROR_LOG" ]; then
    set -- $(wc -c < "$ERROR_LOG")
    if [ "$1" -gt 1000000 ]; then
        tail -n 2000 "$ERROR_LOG" > "$TMPD/log.trim" && cat "$TMPD/log.trim" > "$ERROR_LOG"
    fi
fi

# send_mail SUBJECT BODYFILE -> 0 on success
send_mail() {
    _subj=$1
    _body=$2
    case "$MAILER" in
        msmtp)
            {
                printf 'To: %s\n' "$ALERT_EMAIL"
                printf 'Subject: %s\n' "$_subj"
                printf 'Content-Type: text/plain; charset=utf-8\n\n'
                cat "$_body"
            } | msmtp "$ALERT_EMAIL"
            ;;
        mail)
            # NetBSD mail(1): body on stdin, recipient as argument, NO -t.
            mail -s "$_subj" "$ALERT_EMAIL" < "$_body"
            ;;
        *)
            return 1
            ;;
    esac
}

# curl_get URL ACCEPT -> sets $meta ("code|content-type") and $rc; body in $TMPD/body
curl_get() {
    meta=$(curl -sSL $COMP \
        --retry 2 --retry-delay 2 \
        --connect-timeout 10 --max-time 30 --max-filesize 5000000 \
        -A "$UA" \
        -H 'Accept-Language: en-US,en;q=0.9' \
        -H "Accept: $2" \
        -o "$TMPD/body" -w '%{http_code}|%{content_type}' "$1" \
        </dev/null 2>"$TMPD/curl.err")
    rc=$?
}

# fetch_feed URL -> body in $TMPD/body ; returns 0 only for a usable 2xx non-HTML response.
fetch_feed() {
    curl_get "$1" "$ACCEPT"
    # Some sites answer 406 to a specific Accept list; retry once accepting anything.
    case "$meta" in
        "406|"*) curl_get "$1" "*/*" ;;
    esac
    if [ "$rc" -ne 0 ]; then
        log "FETCH FAILED (curl rc=$rc): $1 :: $(tr '\n' ' ' < "$TMPD/curl.err")"
        return 1
    fi
    code=${meta%%|*}; ctype=${meta#*|}
    case "$code" in
        2??) ;;
        *) log "FETCH FAILED (HTTP $code): $1"; return 1 ;;
    esac
    if dd if="$TMPD/body" bs=512 count=1 2>/dev/null | tr -d '\000' \
        | grep -qiE '^[[:space:]]*(<!doctype html|<html)'; then
        log "NOT A FEED (HTML returned, content-type=$ctype; blocked or wrong URL?): $1"
        return 1
    fi
    return 0
}

ok=0; fail=0; wfail=0
printf '%s\n' "$FEEDS" > "$TMPD/feeds"
while read -r URL MODE; do
    [ -z "$URL" ] && continue
    STRICT=0
    [ "$MODE" = "strict" ] && STRICT=1
    if ! fetch_feed "$URL"; then fail=$((fail+1)); continue; fi

    FEED_URL="$URL" STRICT="$STRICT" "$PY" "$TMPD/parse.py" < "$TMPD/body" > "$TMPD/parsed" 2>"$TMPD/py.err"
    prc=$?
    if [ "$prc" -ne 0 ]; then
        log "PARSE FAILED: $URL :: $(tr '\n' ' ' < "$TMPD/py.err")"
        fail=$((fail+1)); continue
    fi
    ok=$((ok+1))
    log "OK $URL :: $(tail -n 1 "$TMPD/py.err")"
    [ -s "$TMPD/parsed" ] || continue

    while IFS="$TAB" read -r TAG TITLE MD_TITLE LINK; do
        [ -z "$LINK" ] && continue
        case "$TAG" in
            BREAKTHROUGH) LABEL="🔥 BREAKTHROUGH " ;;
            PRACTICAL)    LABEL="🛠 PRACTICAL " ;;
            *)            LABEL="" ;;
        esac
        # Journal first: if it fails, the article is NOT marked seen and is retried next run.
        if printf '%s\n' "- ${LABEL}${MD_TITLE} [Link](${LINK})" >> "$LOGSEQ_JOURNAL"; then
            if printf '%s | %s | %s | %s\n' "$(date '+%Y-%m-%d %H:%M')" "$TAG" "$TITLE" "$LINK" \
                    >> "$HISTORY_FILE"; then
                # Only queue for email after both journal and history succeeded.
                printf -- '- %s%s [Link](%s)\n' "$LABEL" "$TITLE" "$LINK" >> "$DIGEST"
            else
                log "HISTORY WRITE FAILED: $LINK"; wfail=$((wfail+1))
            fi
        else
            log "JOURNAL WRITE FAILED: $LINK"; wfail=$((wfail+1))
        fi
    done < "$TMPD/parsed"
done < "$TMPD/feeds"

log "RUN DONE: $ok feeds ok, $fail feed failures, $wfail write failures"

# --- email digest ---
if [ -n "$MAILER" ] && [ -n "$ALERT_EMAIL" ]; then
    n=0
    if [ -s "$DIGEST" ]; then
        n=$(grep -c '^- ' "$DIGEST" 2>/dev/null) || true
        [ -z "$n" ] && n=0
    fi
    if [ "$n" -gt 0 ] || [ "$MAIL_ON_EMPTY" -eq 1 ]; then
        {
            if [ "$n" -gt 0 ]; then
                cat "$DIGEST"
            else
                printf 'No new items this run.\n'
            fi
            printf '\n---\nRUN DONE: %s feeds ok, %s feed failures, %s write failures\n' \
                "$ok" "$fail" "$wfail"
        } > "$TMPD/mailbody"
        if send_mail "Science RSS: $n new item(s) $(date '+%Y-%m-%d %H:%M')" "$TMPD/mailbody"; then
            log "EMAIL SENT: $n item(s) to $ALERT_EMAIL via $MAILER"
        else
            log "EMAIL FAILED (rc=$?, mailer=$MAILER)"
        fi
    fi
fi

# Non-zero only if no feed worked or a write failed; single-feed failures are logged, not cron-mailed.
if [ "$ok" -eq 0 ] || [ "$wfail" -gt 0 ]; then exit 1; fi
exit 0
