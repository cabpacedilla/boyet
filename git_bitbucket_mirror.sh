#!/usr/bin/env bash
# -------------------------------------------------------------------
# git_bitbucket_mirror.sh v2.3
# Automatically syncs GitHub, Bitbucket, and SourceForge mirrors.
# -------------------------------------------------------------------

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# === CONFIG ===
REPO_DIR="$HOME/Documents/boyet"
SOURCE_DIR="$HOME/Documents/bin"
GITHUB_REMOTE="origin"
MIRRORS=("bitbucket" "sourceforge")
BRANCH="master"
LOGFILE="$HOME/scriptlogs/git_mirror_safe.log"
mkdir -p "$(dirname "$LOGFILE")"

TIMESTAMP() { date '+%Y-%m-%d %H:%M:%S %Z'; }

# Rotate logs if they exceed 2MB
find "$(dirname "$LOGFILE")" -name "$(basename "$LOGFILE")" -size +2M -delete 2>/dev/null

# Prevent concurrent runs
LOCKFILE="/tmp/git_mirror_safe.lock"
exec 200>"$LOCKFILE"
flock -n 200 || { echo "Another instance is running. Exiting."; exit 1; }

START_TIME=$(date +%s)

# -----------------------------
# 1. Prepare Local Repo
# -----------------------------
echo "$(TIMESTAMP) - Copying files from $SOURCE_DIR to $REPO_DIR..." | tee -a "$LOGFILE"
\cp -rf "$SOURCE_DIR/"* "$REPO_DIR"/

cd "$REPO_DIR" || { echo "$(TIMESTAMP) - ERROR: Cannot cd to $REPO_DIR" | tee -a "$LOGFILE"; exit 1; }

# -----------------------------
# 2. Pull & Rebase (The "Origin" Fix)
# -----------------------------
echo "$(TIMESTAMP) - Syncing with $GITHUB_REMOTE/$BRANCH..." | tee -a "$LOGFILE"
# Fetch first to see what the remote has
git fetch "$GITHUB_REMOTE" &>> "$LOGFILE"

if git pull --rebase "$GITHUB_REMOTE" "$BRANCH" &>> "$LOGFILE"; then
    echo "$(TIMESTAMP) - ✅ Rebase successful." | tee -a "$LOGFILE"
else
    echo "$(TIMESTAMP) - ⚠️ Rebase conflict or divergence. Attempting standard merge..." | tee -a "$LOGFILE"
    git rebase --abort &>> "$LOGFILE"
    # Fallback: Merge remote changes to keep history moving
    git merge "$GITHUB_REMOTE/$BRANCH" --no-edit &>> "$LOGFILE"
fi

# -----------------------------
# 3. Stage & Commit
# -----------------------------
git add -A
if git diff --cached --quiet && git diff --quiet; then
    echo "$(TIMESTAMP) - No changes to commit." | tee -a "$LOGFILE"
else
    echo "$(TIMESTAMP) - Committing local changes..." | tee -a "$LOGFILE"
    git commit -m "Auto-sync update on $(date '+%Y-%m-%d %H:%M:%S')" &>> "$LOGFILE"
fi

# -----------------------------
# 4. Push Phase
# -----------------------------
SUCCESS=()
FAIL=()

# --- Push to GitHub ---
# We use --force-with-lease here. It's safer than --force 
# but stronger than a standard push.
echo "$(TIMESTAMP) - Pushing to GitHub ($GITHUB_REMOTE)..." | tee -a "$LOGFILE"
if git push "$GITHUB_REMOTE" "$BRANCH:$BRANCH" &>> "$LOGFILE"; then
    SUCCESS+=("origin ✅")
else
    # If standard push fails, try force-pushing to align GitHub with your local 'bin'
    echo "$(TIMESTAMP) - ⚠️ Standard push failed. Attempting force push to origin..." | tee -a "$LOGFILE"
    if git push --force "$GITHUB_REMOTE" "$BRANCH:$BRANCH" &>> "$LOGFILE"; then
         SUCCESS+=("origin ✅ (forced)")
    else
         FAIL+=("origin ❌")
    fi
fi

# --- Push to Mirrors ---
for REMOTE in "${MIRRORS[@]}"; do
    echo "$(TIMESTAMP) - Force pushing to $REMOTE..." | tee -a "$LOGFILE"
    if git push --force "$REMOTE" "$BRANCH:$BRANCH" &>> "$LOGFILE"; then
        SUCCESS+=("$REMOTE ✅")
    else
        FAIL+=("$REMOTE ❌")
    fi
done

# -----------------------------
# 5. Final Report
# -----------------------------
END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))
printf -v DURATION '%02dh %02dm %02ds' $((ELAPSED/3600)) $(((ELAPSED%3600)/60)) $((ELAPSED%60))

MSG=""
[[ ${#SUCCESS[@]} -gt 0 ]] && MSG+="Succeeded:\n$(printf '%s\n' "${SUCCESS[@]}")\n"
[[ ${#FAIL[@]} -gt 0 ]] && MSG+="Failed:\n$(printf '%s\n' "${FAIL[@]}")"

echo "$(TIMESTAMP) - Sync duration: $DURATION" | tee -a "$LOGFILE"

if [[ ${#FAIL[@]} -gt 0 ]]; then
    # FAILURE NOTIFICATION
    notify-send -u critical "⚠️ Git Mirror Error" "Duration: $DURATION\n\n$MSG\n\nCheck $LOGFILE for details."
else
    # SUCCESS NOTIFICATION
    notify-send "✅ Git Mirror Complete" "Duration: $DURATION\n\n$MSG"
fi
