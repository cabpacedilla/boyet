#!/usr/bin/env bash
# Sync GitHub master branch to multiple mirrors
# Copies ~/Documents/bin/ into the repo before syncing
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

# -----------------------------
# Copy latest files to repo
# -----------------------------
echo "$(date) - Copying files from $SOURCE_DIR to $REPO_DIR..." | tee -a "$LOGFILE"
cp -rf "$SOURCE_DIR/"* "$REPO_DIR"/

cd "$REPO_DIR" || { echo "$(date) - ERROR: Cannot cd to $REPO_DIR" | tee -a "$LOGFILE"; exit 1; }

# -----------------------------
# Stage & commit local changes
# -----------------------------
git add -A
if git diff --cached --quiet && git diff --quiet; then
    echo "$(date) - No changes to commit." | tee -a "$LOGFILE"
else
    echo "$(date) - Committing new changes..." | tee -a "$LOGFILE"
    git commit -m "Auto-sync update on $(date '+%Y-%m-%d %H:%M:%S')"
fi

# -----------------------------
# Force push to all remotes
# -----------------------------
SUCCESS=()
FAIL=()

for REMOTE in "$GITHUB_REMOTE" "${MIRRORS[@]}"; do
    echo "$(date) - Force pushing to $REMOTE/$BRANCH..." | tee -a "$LOGFILE"
    if git push --force "$REMOTE" "$BRANCH:$BRANCH" &>> "$LOGFILE"; then
        echo "$(date) - ✅ Force push succeeded to $REMOTE" | tee -a "$LOGFILE"
        SUCCESS+=("$REMOTE ✅")
    else
        echo "$(date) - ❌ Force push failed to $REMOTE" | tee -a "$LOGFILE"
        FAIL+=("$REMOTE ❌")
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
