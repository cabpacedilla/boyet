#!/usr/bin/env bash
export PATH="$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"

# =============================================================================
# yt-dlp Interactive Downloader
# =============================================================================
#
# Usage:
#   ./yt-dl.sh
#   ./yt-dl.sh "https://www.youtube.com/watch?v=..."
#
# Features:
#   1. Single video or full playlist
#   2. Audio-only selector (M4A preferred; falls back to any audio-only format)
#   3. Best video + audio (requires ffmpeg for merging)
#   4. Manual format selection using yt-dlp -F
#   5. URL supplied as an argument or entered interactively
#   6. Dependency validation (yt-dlp required; ffmpeg optional but warned)
#   7. Preflight format resolution check before actual download
#   8. Download success/failure reporting
#
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# COLORS
# -----------------------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# -----------------------------------------------------------------------------
# HELPERS
# -----------------------------------------------------------------------------

info() {
    printf '%b\n' "${GREEN}$1${NC}"
}

warning() {
    printf '%b\n' "${YELLOW}$1${NC}"
}

error() {
    printf '%b\n' "${RED}Error: $1${NC}" >&2
}

# -----------------------------------------------------------------------------
# HEADER
# -----------------------------------------------------------------------------

echo
printf '%b\n' "${GREEN}=== yt-dlp Interactive Downloader ===${NC}"
echo

# -----------------------------------------------------------------------------
# DEPENDENCY CHECK
# -----------------------------------------------------------------------------

if ! command -v yt-dlp >/dev/null 2>&1; then
    error "yt-dlp is not installed or is not in PATH."
    echo
    echo "Install it using your preferred package manager."
    exit 1
fi

# ffmpeg is required when yt-dlp needs to merge separate streams.
if ! command -v ffmpeg >/dev/null 2>&1; then
    warning "ffmpeg was not found."
    warning "Video + audio merging may not work correctly."
    echo
fi

# -----------------------------------------------------------------------------
# 1. GET URL
# -----------------------------------------------------------------------------

if [[ -n "${1:-}" ]]; then
    URL="$1"
else
    read -r -p "Enter YouTube URL: " URL
fi

if [[ -z "$URL" ]]; then
    error "No URL provided."
    exit 1
fi

echo

# -----------------------------------------------------------------------------
# 2. SINGLE VIDEO OR PLAYLIST?
# -----------------------------------------------------------------------------

read -r -p "Download only this single video? (y/n, default y): " SINGLE_ONLY
SINGLE_ONLY="${SINGLE_ONLY:-y}"

case "$SINGLE_ONLY" in
    y|Y)
        NO_PLAYLIST=(--no-playlist)
        info "Mode: Single video only"
        ;;

    n|N)
        NO_PLAYLIST=()
        info "Mode: Full playlist"
        ;;

    *)
        error "Please answer y or n."
        exit 1
        ;;
esac

echo

# -----------------------------------------------------------------------------
# 3. FORMAT SELECTION
# -----------------------------------------------------------------------------

echo "What would you like to do?"
echo
echo "  1) Best audio-only format — M4A preferred (falls back to any audio-only format)"
echo
echo "  2) Best Video + Audio (merged)"
echo
echo "  3) Show the full format list and select manually"
echo

read -r -p "Choose (1/2/3, default 3): " CHOICE
CHOICE="${CHOICE:-3}"

case "$CHOICE" in

    # -------------------------------------------------------------------------
    # OPTION 1: AUDIO-ONLY SELECTOR (M4A PREFERRED)
    # -------------------------------------------------------------------------

    1)
        info "Selected: Best audio-only format (M4A preferred)"
        echo
        warning "Checking available audio formats..."

        # Prefer the best-ranked audio-only M4A format.
        # If no M4A audio-only format exists, fall back to the best-ranked
        # audio-only format available.
        # Never fall back to /best, which could select video.
        FORMAT='bestaudio[ext=m4a]/bestaudio'

        # Preflight resolution check. This verifies that yt-dlp can resolve
        # the selector against the current URL, but does not guarantee the
        # actual download will succeed later (network conditions may change).
        if ! yt-dlp \
            --simulate \
            -f "$FORMAT" \
            "${NO_PLAYLIST[@]}" \
            "$URL" >/dev/null 2>&1
        then
            error "No compatible audio format could be resolved."
            exit 1
        fi

        info "Audio format resolved successfully."

        # Show the user which format yt-dlp selected. Note: %(abr)s may be
        # blank for some formats or extractors; this is informational only.
        SELECTED_AUDIO=$(
            yt-dlp \
                --simulate \
                --print "%(format_id)s | %(ext)s | %(acodec)s | %(abr)s kbps" \
                -f "$FORMAT" \
                "${NO_PLAYLIST[@]}" \
                "$URL" 2>/dev/null \
            | head -n 1 || true
        )

        if [[ -n "$SELECTED_AUDIO" ]]; then
            if [[ ${#NO_PLAYLIST[@]} -eq 0 ]]; then
                info "Selected audio format (first playlist item): $SELECTED_AUDIO"
            else
                info "Selected audio format: $SELECTED_AUDIO"
            fi
        else
            warning "Audio was resolved, but format details could not be displayed."
        fi
        ;;

    # -------------------------------------------------------------------------
    # OPTION 2: BEST VIDEO + AUDIO
    # -------------------------------------------------------------------------

    2)
        FORMAT='bestvideo+bestaudio/best'

        info "Selected: Best Video + Audio (merged)"

        echo
        warning "Checking available video/audio formats..."

        if ! yt-dlp \
            --simulate \
            -f "$FORMAT" \
            "${NO_PLAYLIST[@]}" \
            "$URL" >/dev/null 2>&1
        then
            error "No compatible video/audio combination could be resolved."
            exit 1
        fi

        info "Video/audio combination resolved successfully."
        ;;

    # -------------------------------------------------------------------------
    # OPTION 3: MANUAL FORMAT SELECTION (also preflight-checked)
    # -------------------------------------------------------------------------

    3)
        echo
        warning "Fetching available formats..."
        echo

        if ! yt-dlp \
            -F \
            "${NO_PLAYLIST[@]}" \
            "$URL"
        then
            error "Could not retrieve available formats."
            exit 1
        fi

        echo
        read -r -p "Enter format ID(s) (e.g. 140, 251, or 137+140): " FORMAT

        if [[ -z "$FORMAT" ]]; then
            error "No format selected."
            exit 1
        fi

        info "Selected format: $FORMAT"

        # Validate that the user-entered format can actually be resolved.
        echo
        warning "Checking if the selected format is available..."

        if ! yt-dlp \
            --simulate \
            -f "$FORMAT" \
            "${NO_PLAYLIST[@]}" \
            "$URL" >/dev/null 2>&1
        then
            error "The selected format could not be resolved."
            exit 1
        fi

        info "Selected format is available."
        ;;

    *)
        error "Invalid choice. Please select 1, 2, or 3."
        exit 1
        ;;

esac

# -----------------------------------------------------------------------------
# 4. DOWNLOAD
# -----------------------------------------------------------------------------

echo
info "Starting download..."
echo

if yt-dlp \
    -f "$FORMAT" \
    "${NO_PLAYLIST[@]}" \
    "$URL"
then
    echo
    info "Download completed successfully."
else
    echo
    error "Download failed."
    exit 1
fi

echo
info "Done."
