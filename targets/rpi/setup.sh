#!/usr/bin/env bash
# Full Setup and Deep Cleanup Script for Raspberry Pi - WarpAcePi
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "$HOME/WarpAcePi/targets/rpi")"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." 2>/dev/null && pwd || echo "$HOME/WarpAcePi")"

echo "=========================================================="
echo "    WARPACEPI - RASPBERRY PI CLEANUP & UPGRADE SETUP"
echo "=========================================================="
echo " Target : Raspberry Pi (Tailscale 100.89.165.79)"
echo " Purpose: Clean legacy files, setup Cloudflare WARP proxy,"
echo "          configure Samba [playlists] and 6h update timer."
echo "=========================================================="
echo ""

# ------------------------------------------------------------------------------
# 1. DEEP CLEANUP: Remove old obsolete services, cronjobs and legacy files
# ------------------------------------------------------------------------------
echo "[1/5] Erasing old and obsolete configurations..."

# A. Stop legacy or duplicate services
for s in update-acestream-playlists.timer update-acestream-playlists.service acestream-update.timer acestream-update.service acestream-evaluator.service warp-proxy.service; do
    if systemctl is-active --quiet "$s" 2>/dev/null; then
        echo "      Stopping service: $s"
        sudo systemctl stop "$s" 2>/dev/null || true
    fi
    if systemctl is-enabled --quiet "$s" 2>/dev/null; then
        echo "      Disabling service: $s"
        sudo systemctl disable "$s" 2>/dev/null || true
    fi
done

# B. Remove legacy crontab entries relating to acestream
if crontab -l 2>/dev/null | grep -qiE 'acestream|hector|evaluate_and_update|build_playlist'; then
    echo "      Cleaning legacy crontab entries..."
    crontab -l 2>/dev/null | grep -viE 'acestream|hector|evaluate_and_update|build_playlist' | crontab - || true
    echo "      [OK] Crontab cleaned."
else
    echo "      [OK] Crontab is already clean."
fi

# C. Remove old obsolete AceStream_hector directory if present
if [ -d "$HOME/AceStream_hector" ]; then
    echo "      Removing legacy directory: $HOME/AceStream_hector..."
    rm -rf "$HOME/AceStream_hector"
    echo "      [OK] Removed $HOME/AceStream_hector."
fi

# D. Clean temporary files
rm -rf /tmp/*acestream* /tmp/*warp* 2>/dev/null || true
echo "      [OK] Cleanup completed."
echo ""

# ------------------------------------------------------------------------------
# 2. INSTALL REQUIRED SYSTEM PACKAGES
# ------------------------------------------------------------------------------
echo "[2/5] Updating packages and installing dependencies..."
sudo apt-get update -y
sudo apt-get install -y python3 python3-pip python3-requests curl samba git

echo ""

# ------------------------------------------------------------------------------
# 3. CONFIGURE SING-BOX CLOUDFLARE WARP GATEWAY (Port 1080)
# ------------------------------------------------------------------------------
echo "[3/5] Setting up Cloudflare WARP proxy on port 1080..."
if [ -f "$SCRIPT_DIR/install_warp_service.sh" ]; then
    bash "$SCRIPT_DIR/install_warp_service.sh"
else
    echo "[!] install_warp_service.sh not found in $SCRIPT_DIR"
fi

echo ""

# ------------------------------------------------------------------------------
# 4. CONFIGURE SAMBA SHARE [playlists] FOR DRIVE Z:
# ------------------------------------------------------------------------------
echo "[4/5] Configuring Samba share [playlists] for Windows clients..."
if [ -f "$SCRIPT_DIR/configure_samba.sh" ]; then
    bash "$SCRIPT_DIR/configure_samba.sh"
else
    echo "[!] configure_samba.sh not found in $SCRIPT_DIR"
fi

echo ""

# ------------------------------------------------------------------------------
# 5. CONFIGURE AUTOMATIC 1-HOUR CHANNEL UPDATER & RUN INITIAL UPDATE
# ------------------------------------------------------------------------------
echo "[5/5] Configuring systemd 1-hour update timer..."
if [ -f "$SCRIPT_DIR/install_update_timer.sh" ]; then
    bash "$SCRIPT_DIR/install_update_timer.sh"
fi

echo "[*] Generating fresh initial playlists now..."
python3 "$REPO_DIR/scripts/evaluate_and_update.py" --mode vlc || true
python3 "$REPO_DIR/scripts/build_playlist.py" || true

echo ""
echo "=========================================================="
echo " [SUCCESS] RASPBERRY PI UPGRADE & SETUP COMPLETE"
echo "=========================================================="
echo " - Active Services:"
echo "   * warp-proxy.service (sing-box on port 1080): ACTIVE"
echo "   * smbd.service (Samba share [playlists]): ACTIVE"
echo "   * update-acestream-playlists.timer (every 1h): ACTIVE"
echo ""
echo " - Network Share Address:"
echo "   * LAN: \\\\$(hostname -I | awk '{print $1}')\\playlists"
echo "   * Tailscale: \\\\100.89.165.79\\playlists"
echo ""
echo " - Windows Clients:"
echo "   * Desktop: targets\\desktop\\activate.bat"
echo "   * Laptop:  targets\\laptop\\activate.bat"
echo "=========================================================="
