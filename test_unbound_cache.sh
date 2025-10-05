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
    # Obscure OS Projects
    reactos.org syllable-os.org aros.org amigaos.net
    morphos-team.net risc-os.org menuetos.net visopsys.org
    
    # Research/Academic
    singularity-os.orgBareMetal-OS.com exokernel.org
    microkernel.info capsicum-project.org
    
    # Retro Computing
    atari.org commodore.ca zx-spectrum.net
    amstrad-cpc.net sinclair.org
    
    # Embedded RTOS
    freertos.org rt-thread.io threadx.io
    nuttx.apache.org mynewt.apache.org
    
    # Rare Distros
    nixos.org guix.gnu.org gobolinux.org
    lunar-linux.org sourcemage.org crux.nu
    
    # Plan 9 Family
    9front.org plan9.io 9p.io cat-v.org
    
    # Lisp Machines
    lispm.org common-lisp.net sbcl.org
    
    # Forth/Stack Languages
    forth.org gforth.org ficl.org
    
    # Alternative Browsers
    dillo.org netsurf-browser.org links.twibright.com
    lynx.invisible-island.net w3m.org
    
    # Gopher/Gemini
    gopher.floodgap.com gemini.circumlunar.space
    
    # Old Protocols
    finger.org archie.org veronica.org
    
    # Text Processing
    groff.gnu.org troff.org nroff.org
    
    # Audio/DSP
    supercollider.github.io csound.com puredata.info
    chuck.stanford.edu faust.grame.fr
    
    # Graphics/Rendering
    povray.org blender.org openscad.org
    
    # CAD/Engineering
    freecad.org librecad.org qcad.org
    
    # Scientific Computing
    octave.org scilab.org maxima.sourceforge.io
    sagemath.org gap-system.org
    
    # Theorem Provers
    coq.inria.fr isabelle.in.tum.de agda.org
    lean-lang.org idris-lang.org
    
    # Constraint Programming
    minizinc.org gecode.org choco-solver.org
    
    # Logic Programming
    swi-prolog.org gnu.org/software/prolog
    
    # Concatenative Languages
    factor-lang.org joy-lang.org cat-language.org
    
    # Array Languages
    jsoftware.com dyalog.com aplwiki.com
    kx.com arrayfire.com
    
    # Esoteric Languages
    esolangs.org brainfuck.org befunge.org
    
    # Retro Games Preservation
    abandonia.com dosgamesarchive.com
    
    # Demoscene
    pouet.net scene.org
    
    # Alternative Search
    marginalia.nu wiby.me teclis.com
    
    # Minimal Web
    motherfuckingwebsite.com brutalist-web.design
    
    # Old School BBS
    bbs.io telnetbbsguide.com
    
    # Retro Protocols
    nntp.org usenet.org
    
    # Alternative Social
    scuttlebutt.nz mastodon.social diasporafoundation.org
    
    # P2P Networks
    gnutella.org soulseek.net bittorrent.org
    
    # IRC Networks
    libera.chat oftc.net freenode.net
    
    # Old File Formats
    ps2pdf.com dvi2pdf.org
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
