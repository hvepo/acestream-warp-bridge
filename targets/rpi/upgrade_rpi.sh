#!/usr/bin/env bash
# 1-Line Remote Upgrade & Cleanup Script for Raspberry Pi - WarpAcePi
set -euo pipefail

echo "=========================================================="
echo "      WARPACEPI - 1-LINE RASPBERRY PI UPGRADER"
echo "=========================================================="

REPO_URL="https://github.com/hvepo/WarpAcePi.git"
TARGET_DIR=""

if [ -d "$HOME/WarpAcePi/.git" ]; then
    TARGET_DIR="$HOME/WarpAcePi"
elif [ -d "$HOME/acestream-warp-bridge/.git" ]; then
    TARGET_DIR="$HOME/acestream-warp-bridge"
else
    TARGET_DIR="$HOME/WarpAcePi"
    echo "[*] Cloning repository to $TARGET_DIR..."
    git clone "$REPO_URL" "$TARGET_DIR"
fi

echo "[*] Updating repository at $TARGET_DIR..."
cd "$TARGET_DIR"
git fetch origin main
git reset --hard origin/main

echo "[*] Making scripts executable..."
chmod +x targets/rpi/*.sh

echo "[*] Executing setup and deep cleanup..."
bash targets/rpi/setup.sh
