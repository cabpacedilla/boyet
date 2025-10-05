#!/usr/bin/env bash
set -euo pipefail
SERVER="127.0.0.1"
NUM_DOMAINS=10
LOGDIR="$HOME/scriptlogs/unbound-tests"
mkdir -p "$LOGDIR"
chmod 0755 "$LOGDIR"
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
LOGFILE="$LOGDIR/unbound_test_$TIMESTAMP.log"
CSVFILE="$LOGDIR/unbound_test_$TIMESTAMP.csv"
timestamp_human=$(date -u '+%Y-%m-%d %H:%M:%SZ (UTC)')
GREEN='\033[1;32m'
RED='\033[1;31m'
NC='\033[0m'

# Pool of uncommon/random domains - EXPANDED
POOL=(
    # Alternative OS & Tech
    templeos.org skyos.org visopsys.org redox-os.org

    # Research / Academic
    arxiv.org journals.plos.org mit.edu csail.mit.edu

    # Retro Computing & Gaming
    cpcwiki.eu retrocomputing.stackexchange.com amiga.resource.cx

    # Embedded / IoT
    zephyrproject.org tinkerforge.com mbed.org adafruit.com

    # Rare Distros
    dragora.org parrotsec.org antiXlinux.com taildisk.org

    # Programming Languages & Tools
    factorcode.org nim-lang.org gleam.run elixir-lang.org

    # Security / Privacy
    pryv.com privacymonitor.com protonmail.com searx.org

    # Networking & Protocols
    quicwg.org bgp.tools netdevconf.org

    # Esoteric Languages
    brainfuck.org unlambda.com false-lang.org pyth-lang.org

    # Retro Web & Media
    textfiles.com oldversion.com abandonia.com classicdosgames.com

    # Minimalist / Experimental Web
    minimalistweb.design motherfuckingwebsite.com hackernews.com

    # Old School BBS & Retro Protocols
    telnetbbsguide.com bbs.archivist.org nntp.org

    # Alternative Social & P2P
    scuttlebutt.nz mastodon.social retroshare.net

    # IRC Networks
    libera.chat oftc.net ircnet.org

    # Old File Formats
    groff.gnu.org dvi2pdf.org troff.org nroff.org

    # Audio / DSP
    csound.com faust.grame.fr supercollider.github.io

    # Graphics / Rendering
    blender.org openscad.org povray.org luxcorerender.org

    # CAD / Engineering
    librecad.org qcad.org freecadweb.org bricsys.com

    # Scientific & Engineering
    octave.org maxima.sourceforge.io sagecell.sagemath.org scilab.org

    # Theorem Provers
    coq.inria.fr isabelle.in.tum.de agda.org

    # Constraint Programming
    minizinc.org gecode.org choco-solver.org

    # Logic Programming
    swi-prolog.org gnu.org/software/prolog

    # Concatenative Languages
    joy-lang.org cat-language.org

    # Array Languages
    dyalog.com aplwiki.com arrayfire.com

    # Miscellaneous
    glitch.com cyberciti.biz wikitech.wikimedia.org neocities.org
)

# Pick random domains
readarray -t DOMAINS < <(shuf -e "${POOL[@]}" | head -n "$NUM_DOMAINS")

echo "Unbound Cache Test — $timestamp_human"
echo "Server: $SERVER"
echo "Domains: ${DOMAINS[*]}"
echo "Text Log: $LOGFILE"
echo "CSV Log:  $CSVFILE"
echo "------------------------------------------------------------" | tee "$LOGFILE"
echo "domain,round1_ms,round2_ms" > "$CSVFILE"

command -v unbound-control >/dev/null 2>&1 || { echo "unbound-control not found"; exit 1; }

echo "Flushing Unbound cache..." | tee -a "$LOGFILE"
if ! sudo unbound-control flush_zone .; then
    echo "(flush skipped — no socket access)" | tee -a "$LOGFILE"
fi

declare -A ROUND1 ROUND2

function testround() {
    local label="$1"
    local -n result="$2"
    echo -e "\n$label" | tee -a "$LOGFILE"
    printf -- "----------------------------------------\n" | tee -a "$LOGFILE"
    for d in "${DOMAINS[@]}"; do
        local t
        t=$(dig @"$SERVER" +noall +stats "$d" 2>/dev/null | awk '/Query time:/ {print $4}' || echo 0)
        result["$d"]=$t
        printf "  %-25s → %s ms\n" "$d" "$t" | tee -a "$LOGFILE"
    done
}

testround "🌐 Round 1: Uncached (cold cache)" ROUND1
sleep 2
testround "⚡ Round 2: Cached (warm cache)" ROUND2

printf "\n📊 Cache Efficiency Summary\n" | tee -a "$LOGFILE"
printf -- "----------------------------------------\n" | tee -a "$LOGFILE"
for d in "${DOMAINS[@]}"; do
    printf "%-25s → %s ms / %s ms\n" "$d" "${ROUND1[$d]}" "${ROUND2[$d]}" | tee -a "$LOGFILE"
    echo "$d,${ROUND1[$d]},${ROUND2[$d]}" >> "$CSVFILE"
done
