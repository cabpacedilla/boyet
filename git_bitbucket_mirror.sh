#!/usr/bin/env bash
# git_mirror_safe.sh
# Safely sync GitHub master branch to multiple mirrors with auto force-push fallback
# Now also copies ~/Documents/bin/ into the repo before syncing
# Author: Claive Alvin P. Acedilla (modified)

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# -----------------------------
# Configuration
# -----------------------------
REPO_DIR="$HOME/Documents/boyet"
SOURCE_DIR="$HOME/Documents/bin"
GITHUB_REMOTE="origin"
MIRRORS=("bitbucket" "sourceforge")
BRANCH="master"
LOGFILE="$HOME/scriptlogs/git_mirror_safe.log"
mkdir -p "$(dirname "$LOGFILE")"

# Ensure only one instance is running
LOCKFILE="/tmp/git_mirror_safe.lock"
exec 200>"$LOCKFILE"
flock -n 200 || { echo "Another instance is running. Exiting."; exit 1; }

cd "$REPO_DIR" || { echo "$(date) - ERROR: Cannot cd to $REPO_DIR" | tee -a "$LOGFILE"; exit 1; }

# -----------------------------
# Copy latest scripts to repo
# -----------------------------
echo "$(date) - Copying files from $SOURCE_DIR to $REPO_DIR (overwrite enabled)..." | tee -a "$LOGFILE"
if ! yes | cp -rf "$SOURCE_DIR"/* "$REPO_DIR"/; then
    echo "$(date) - ERROR: Failed to copy files from $SOURCE_DIR" | tee -a "$LOGFILE"
    notify-send "⚠️ Git Mirror Failed" "Copying from $SOURCE_DIR failed. See log."
    exit 1
fi

# -----------------------------
# Fetch latest from GitHub
# -----------------------------
echo "$(date) - Fetching $BRANCH from $GITHUB_REMOTE..." | tee -a "$LOGFILE"
if ! git fetch "$GITHUB_REMOTE" "$BRANCH"; then
    echo "$(date) - ERROR: Failed to fetch from $GITHUB_REMOTE" | tee -a "$LOGFILE"
    notify-send "⚠️ Git Mirror Failed" "Fetching from $GITHUB_REMOTE failed. See log."
    exit 1
fi

# -----------------------------
# Reset local branch to GitHub
# -----------------------------
echo "$(date) - Resetting local $BRANCH to match $GITHUB_REMOTE/$BRANCH..." | tee -a "$LOGFILE"
if ! git reset --hard "$GITHUB_REMOTE/$BRANCH"; then
    echo "$(date) - ERROR: Failed to reset local branch" | tee -a "$LOGFILE"
    notify-send "⚠️ Git Mirror Failed" "Resetting local branch failed. See log."
    exit 1
fi

# -----------------------------
# Push to mirrors with fallback
# -----------------------------
SUCCESS=()
FAIL=()

for MIRROR in "${MIRRORS[@]}"; do
    echo "$(date) - Pushing to $MIRROR/$BRANCH..." | tee -a "$LOGFILE"
    if git push "$MIRROR" "$BRANCH" 2>&1 | tee /tmp/git_push_$MIRROR.log; then
        echo "$(date) - ✅ Successfully mirrored to $MIRROR" | tee -a "$LOGFILE"
        SUCCESS+=("$MIRROR ✅")
    else
        if grep -q "non-fast-forward" /tmp/git_push_$MIRROR.log; then
            echo "$(date) - ⚠️ Non-fast-forward detected for $MIRROR. Retrying with --force..." | tee -a "$LOGFILE"
            if git push --force "$MIRROR" "$BRANCH"; then
                echo "$(date) - ✅ Force push succeeded to $MIRROR" | tee -a "$LOGFILE"
                SUCCESS+=("$MIRROR ✅ (force)")
            else
                echo "$(date) - ❌ Force push failed to $MIRROR" | tee -a "$LOGFILE"
                FAIL+=("$MIRROR ❌")
            fi
        else
            echo "$(date) - ❌ Push to $MIRROR failed (not a non-fast-forward issue)" | tee -a "$LOGFILE"
            FAIL+=("$MIRROR ❌")
        fi
    fi
done

# -----------------------------
# Send combined notification
# -----------------------------
MSG=""
[[ ${#SUCCESS[@]} -gt 0 ]] && MSG+="Success:\n$(printf '%s\n' "${SUCCESS[@]}")\n"
[[ ${#FAIL[@]} -gt 0 ]] && MSG+="Failed:\n$(printf '%s\n' "${FAIL[@]}")"

if [[ ${#FAIL[@]} -gt 0 ]]; then
    notify-send "⚠️ Git Mirror Completed with Errors" "$MSG"
else
    notify-send "✅ Git Mirror Complete" "$MSG"
fi
