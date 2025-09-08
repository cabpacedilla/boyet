#!/usr/bin/env bash
# git_mirror_safe.sh
# Safely sync GitHub master branch to Bitbucket mirror without force-push
# Author: Claive Alvin P. Acedilla (modified)

# Configuration
REPO_DIR="$HOME/Documents/boyet"
GITHUB_REMOTE="origin"
BITBUCKET_REMOTE="bitbucket"
BRANCH="master"
LOGFILE="$HOME/scriptlogs/git_mirror_safe.log"
mkdir -p "$(dirname "$LOGFILE")"

# Ensure only one instance is running
LOCKFILE="/tmp/git_mirror_safe.lock"
exec 200>"$LOCKFILE"
flock -n 200 || { echo "Another instance is running. Exiting."; exit 1; }

cd "$REPO_DIR" || { echo "$(date) - ERROR: Cannot cd to $REPO_DIR" | tee -a "$LOGFILE"; exit 1; }

# Fetch latest from GitHub
echo "$(date) - Fetching $BRANCH from $GITHUB_REMOTE..." | tee -a "$LOGFILE"
if ! git fetch "$GITHUB_REMOTE" "$BRANCH"; then
    echo "$(date) - ERROR: Failed to fetch from $GITHUB_REMOTE" | tee -a "$LOGFILE"
    notify-send "⚠️ Git Mirror Failed" "Fetching from $GITHUB_REMOTE failed. See log."
    exit 1
fi

# Reset local branch to GitHub
echo "$(date) - Resetting local $BRANCH to match $GITHUB_REMOTE/$BRANCH..." | tee -a "$LOGFILE"
if ! git reset --hard "$GITHUB_REMOTE/$BRANCH"; then
    echo "$(date) - ERROR: Failed to reset local branch" | tee -a "$LOGFILE"
    notify-send "⚠️ Git Mirror Failed" "Resetting local branch failed. See log."
    exit 1
fi

# Push safely to Bitbucket (non-destructive)
echo "$(date) - Pushing to $BITBUCKET_REMOTE/$BRANCH..." | tee -a "$LOGFILE"
if git push "$BITBUCKET_REMOTE" "$BRANCH"; then
    echo "$(date) - ✅ Successfully mirrored GitHub to Bitbucket" | tee -a "$LOGFILE"
    notify-send "✅ Git Mirror Complete" "Bitbucket now matches GitHub."
else
    echo "$(date) - ⚠️ Push to $BITBUCKET_REMOTE failed" | tee -a "$LOGFILE"
    notify-send "⚠️ Git Mirror Failed" "Push to $BITBUCKET_REMOTE failed. See log."
    exit 1
fi
