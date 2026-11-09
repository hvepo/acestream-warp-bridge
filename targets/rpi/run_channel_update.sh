#!/usr/bin/env bash
# Manually run channel evaluation and playlist generation immediately - WarpAcePi
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=== WarpAcePi: Running Channel Evaluation and Playlist Build ==="
cd "$REPO_DIR"

python3 "$REPO_DIR/scripts/evaluate_and_update.py" --mode vlc
python3 "$REPO_DIR/scripts/build_playlist.py"

echo "[OK] Playlists updated in $REPO_DIR/playlists"
