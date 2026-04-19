#!/usr/bin/env bash

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

REPO_DIR="$HOME/Documents/boyet"
SOURCE_DIR="$HOME/Documents/bin"
GITHUB_REMOTE="origin"
MIRRORS=("bitbucket" "sourceforge")
BRANCH="master"
LOGFILE="$HOME/scriptlogs/git_sync_safe.log"
mkdir -p "$(dirname "$LOGFILE")"

TIMESTAMP() { date '+%Y-%m-%d %H:%M:%S %Z'; }

cd "$REPO_DIR" || exit 1

echo "$(TIMESTAMP) - Starting safe sync..." | tee -a "$LOGFILE"

# -----------------------------
# 1. SHOW what will be copied (without copying yet)
# -----------------------------
echo "=== Files in bin folder (to be copied) ===" | tee -a "$LOGFILE"
ls -la "$SOURCE_DIR" | tee -a "$LOGFILE"

echo "=== Current files in repo (before copy) ===" | tee -a "$LOGFILE"
ls -la "$REPO_DIR" | tee -a "$LOGFILE"

# -----------------------------
# 2. ASK before copying
# -----------------------------
read -p "Copy files from bin to repo? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "$(TIMESTAMP) - Copying files..." | tee -a "$LOGFILE"
    \cp -rf "$SOURCE_DIR/"* "$REPO_DIR"/ 2>/dev/null
    
    echo "=== Git changes after copy ===" | tee -a "$LOGFILE"
    git status -s | tee -a "$LOGFILE"
    echo "===============================" | tee -a "$LOGFILE"
    
    echo "=== Detailed changes ===" | tee -a "$LOGFILE"
    git diff --stat | tee -a "$LOGFILE"
fi

# -----------------------------
# 3. Check for ANY changes
# -----------------------------
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null || [ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ]; then
    echo "$(TIMESTAMP) - Auto-committing all changes..." | tee -a "$LOGFILE"
    git add -A
    git commit -m "Auto-sync update on $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOGFILE"
    echo "✅ Changes committed automatically" | tee -a "$LOGFILE"
else
    echo "No changes detected" | tee -a "$LOGFILE"
fi

# -----------------------------
# 4. SHOW what will be pushed
# -----------------------------
echo "=== Unpushed commits ===" | tee -a "$LOGFILE"
git log @{u}.. --oneline 2>/dev/null || echo "No unpushed commits" | tee -a "$LOGFILE"

# -----------------------------
# 5. ASK before pushing
# -----------------------------
read -p "Push to remotes? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Push cancelled" | tee -a "$LOGFILE"
    exit 0
fi

# -----------------------------
# 6. Push with proper error checking
# -----------------------------
SUCCESS=()
FAIL=()

# Push to GitHub
echo "$(TIMESTAMP) - Pushing to $GITHUB_REMOTE..." | tee -a "$LOGFILE"
git push "$GITHUB_REMOTE" "$BRANCH" 2>&1 | tee -a "$LOGFILE"
PUSH_EXIT=${PIPESTATUS[0]}

if [[ $PUSH_EXIT -eq 0 ]]; then
    SUCCESS+=("$GITHUB_REMOTE ✅")
else
    echo "⚠️  Normal push failed (exit code: $PUSH_EXIT). Try force push? (y/n): "
    read -n 1 -r FORCE
    echo
    if [[ $FORCE =~ ^[Yy]$ ]]; then
        git push --force "$GITHUB_REMOTE" "$BRANCH" 2>&1 | tee -a "$LOGFILE"
        FORCE_EXIT=${PIPESTATUS[0]}
        if [[ $FORCE_EXIT -eq 0 ]]; then
            SUCCESS+=("$GITHUB_REMOTE ✅ (forced)")
        else
            FAIL+=("$GITHUB_REMOTE ❌")
        fi
    else
        FAIL+=("$GITHUB_REMOTE ❌")
    fi
fi

# Push to mirrors
for REMOTE in "${MIRRORS[@]}"; do
    if git remote | grep -q "^$REMOTE$"; then
        read -p "Push to $REMOTE? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "$(TIMESTAMP) - Pushing to $REMOTE..." | tee -a "$LOGFILE"
            git push "$REMOTE" "$BRANCH" 2>&1 | tee -a "$LOGFILE"
            PUSH_EXIT=${PIPESTATUS[0]}
            
            if [[ $PUSH_EXIT -eq 0 ]]; then
                SUCCESS+=("$REMOTE ✅")
            else
                read -p "Force push to $REMOTE? (y/n): " -n 1 -r FORCE
                echo
                if [[ $FORCE =~ ^[Yy]$ ]]; then
                    git push --force "$REMOTE" "$BRANCH" 2>&1 | tee -a "$LOGFILE"
                    FORCE_EXIT=${PIPESTATUS[0]}
                    if [[ $FORCE_EXIT -eq 0 ]]; then
                        SUCCESS+=("$REMOTE ✅ (forced)")
                    else
                        FAIL+=("$REMOTE ❌")
                    fi
                else
                    FAIL+=("$REMOTE ❌")
                fi
            fi
        fi
    else
        echo "$REMOTE not configured, skipping" | tee -a "$LOGFILE"
    fi
done

# -----------------------------
# 7. Final report
# -----------------------------
echo ""
echo "=== Final Summary ===" | tee -a "$LOGFILE"
echo "Succeeded: ${#SUCCESS[@]}" | tee -a "$LOGFILE"
printf '  %s\n' "${SUCCESS[@]}" | tee -a "$LOGFILE"
echo "Failed: ${#FAIL[@]}" | tee -a "$LOGFILE"
printf '  %s\n' "${FAIL[@]}" | tee -a "$LOGFILE"

echo "$(TIMESTAMP) - Script completed safely" | tee -a "$LOGFILE"
