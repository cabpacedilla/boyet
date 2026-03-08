#!/usr/bin/env bash
# boyet-sync.sh - Force-mirror local bin to GitHub/Bitbucket/SF

SOURCE="$HOME/Documents/bin"
REPO="$HOME/Documents/boyet"
REMOTES=("origin" "bitbucket" "sourceforge")

# 1. Sync files to the repo folder
rsync -av --delete --exclude '.git/' "$SOURCE/" "$REPO/"

cd "$REPO" || exit 1

# 2. Commit everything
git add -A
git commit -m "Auto-sync: $(date '+%Y-%m-%d %H:%M')" || echo "No changes to commit"

# 3. The "Nuclear" Push (Parallel Force)
# This makes all remotes identical to your local master instantly.
for r in "${REMOTES[@]}"; do
    echo "Force pushing to $r..."
    git push --force-with-lease "$r" master
done

notify-send "✅ Boyet Mirrored" "All remotes updated from local bin."
