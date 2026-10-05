#!/usr/bin/env bash
set -euo pipefail

src="$HOME/Documents/bin/prune-old-kernels.sh"
dst="/usr/local/sbin/prune-old-kernels.sh"

[[ -f "$src" ]] || { echo "ERROR: source not found: $src" >&2; exit 1; }

# Syntax-check before installing, so we never publish a broken script
# to a root-owned path that runs unattended.
bash -n "$src" || { echo "ERROR: syntax check failed for $src" >&2; exit 1; }

sudo install -o root -g root -m 0755 "$src" "$dst"
echo "Published: $dst"
ls -l "$dst"
