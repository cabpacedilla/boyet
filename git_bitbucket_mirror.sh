#!/usr/bin/env bash
# -------------------------------------------------------------------
# git_bitbucket_mirror.sh
# Automatically syncs GitHub master branch to Bitbucket and SourceForge mirrors.
# Copies ~/Documents/bin/ into the repo before syncing.
# Author: Claive Alvin P. Acedilla (modified)
# -------------------------------------------------------------------

# === Setup Instructions ===
# 1. Generate SSH key: ssh-keygen -t ed25519 -C "your_email@example.com"
# 2. Start ssh-agent: eval "$(ssh-agent -s)" && ssh-add ~/.ssh/id_ed25519
# 3. Add public key to GitHub, Bitbucket, SourceForge.
# 4. Test SSH: ssh -T git@github.com | ssh -T git@bitbucket.org | ssh -T cabpacedilla@git.code.sf.net
# 5. Configure remotes:
#    git remote set-url origin git@github.com:cabpacedilla/boyet.git
#    git remote set-url bitbucket git@bitbucket.org:cabpa/boyet.git
#    git remote set-url sourceforge ssh://cabpacedilla@git.code.sf.net/p/boyet/code
# -------------------------------------------------------------------

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

REPO_DIR="$HOME/Documents/boyet"
SOURCE_DIR="$HOME/Documents/bin"
GITHUB_REMOTE="origin"
MIRRORS=("bitbucket" "sourceforge")
BRANCH="master"
LOGFILE="$HOME/scriptlogs/git_mirror_safe.log"
mkdir -p "$(dirname "$LOGFILE")"

TIMESTAMP() { date '+%Y-%m-%d %H:%M:%S %Z'; }
find "$(dirname "$LOGFILE")" -name "$(basename "$LOGFILE")" -size +2M -delete 2>/dev/null

LOCKFILE="/tmp/git_mirror_safe.lock"
exec 200>"$LOCKFILE"
flock -n 200 || { echo "Another instance is running. Exiting."; exit 1; }

START_TIME=$(date +%s)

# -----------------------------
# Copy latest files to repo
# -----------------------------
echo "$(TIMESTAMP) - Copying files from $SOURCE_DIR to $REPO_DIR..." | tee -a "$LOGFILE"
\cp -rf "$SOURCE_DIR/"* "$REPO_DIR"/

cd "$REPO_DIR" || { echo "$(TIMESTAMP) - ERROR: Cannot cd to $REPO_DIR" | tee -a "$LOGFILE"; exit 1; }

# -----------------------------
# Pull latest from GitHub (prevent divergence)
# -----------------------------
echo "$(TIMESTAMP) - Pulling latest changes from $GITHUB_REMOTE/$BRANCH with rebase..." | tee -a "$LOGFILE"
if git pull --rebase "$GITHUB_REMOTE" "$BRANCH" &>> "$LOGFILE"; then
    echo "$(TIMESTAMP) - ✅ Rebase successful." | tee -a "$LOGFILE"
else
    echo "$(TIMESTAMP) - ⚠️ Rebase conflict detected. Aborting rebase..." | tee -a "$LOGFILE"
    git rebase --abort &>> "$LOGFILE"
fi

# -----------------------------
# Stage & commit local changes
# -----------------------------
git add -A
if git diff --cached --quiet && git diff --quiet; then
    echo "$(TIMESTAMP) - No changes to commit." | tee -a "$LOGFILE"
else
    echo "$(TIMESTAMP) - Committing new changes..." | tee -a "$LOGFILE"
    git commit -m "Auto-sync update on $(date '+%Y-%m-%d %H:%M:%S')"
fi

# -----------------------------
# Push updates safely (no force)
# -----------------------------
SUCCESS=()
FAIL=()

echo "$(TIMESTAMP) - Pushing to GitHub ($GITHUB_REMOTE/$BRANCH)..." | tee -a "$LOGFILE"
if git push "$GITHUB_REMOTE" "$BRANCH:$BRANCH" &>> "$LOGFILE"; then
    SUCCESS+=("$GITHUB_REMOTE ✅")
else
    FAIL+=("$GITHUB_REMOTE ❌")
fi

# -----------------------------
# Mirror push (still force for mirrors)
# -----------------------------
for REMOTE in "${MIRRORS[@]}"; do
    echo "$(TIMESTAMP) - Force pushing to $REMOTE/$BRANCH..." | tee -a "$LOGFILE"
    if git push --force "$REMOTE" "$BRANCH:$BRANCH" &>> "$LOGFILE"; then
        SUCCESS+=("$REMOTE ✅")
    else
        FAIL+=("$REMOTE ❌")
    fi
done

# -----------------------------
# Report duration
# -----------------------------
END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))
printf -v DURATION '%02dh %02dm %02ds' $((ELAPSED/3600)) $(((ELAPSED%3600)/60)) $((ELAPSED%60))
echo "$(TIMESTAMP) - Total sync duration: $DURATION" | tee -a "$LOGFILE"

MSG=""
[[ ${#SUCCESS[@]} -gt 0 ]] && MSG+="Succeeded:\n$(printf '%s\n' "${SUCCESS[@]}")\n"
[[ ${#FAIL[@]} -gt 0 ]] && MSG+="Failed:\n$(printf '%s\n' "${FAIL[@]}")"

if [[ ${#FAIL[@]} -gt 0 ]]; then
    notify-send "⚠️ Git Mirror Completed with Errors" "Duration: $DURATION\n$MSG"
else
    notify-send "✅ Git Mirror Complete" "Duration: $DURATION\n$MSG"
fi
