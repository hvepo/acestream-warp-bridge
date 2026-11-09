#!/usr/bin/env bash
# Full Setup Script for Raspberry Pi - WarpAcePi
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=========================================================="
echo "        WARPACEPI - RASPBERRY PI TARGET SETUP"
echo "=========================================================="
echo " 1. Install Cloudflare WARP proxy on port 1080"
echo " 2. Configure Samba share [playlists] for drive Z:"
echo " 3. Setup systemd timer for automatic channel updates"
echo "=========================================================="
echo ""

echo "[*] Updating package repositories..."
sudo apt-get update -y
sudo apt-get install -y python3 python3-pip python3-requests curl samba

echo ""
echo "[*] Step 1: Installing WARP Proxy Service..."
bash "$SCRIPT_DIR/install_warp_service.sh"

echo ""
echo "[*] Step 2: Configuring Samba Share for Drive Z:..."
bash "$SCRIPT_DIR/configure_samba.sh"

echo ""
echo "[*] Step 3: Installing 6-hour Update Timer..."
bash "$SCRIPT_DIR/install_update_timer.sh"

echo ""
echo "=========================================================="
echo " [SUCCESS] RASPBERRY PI FULLY CONFIGURED"
echo "=========================================================="
echo " - WARP Proxy: $(hostname -I | awk '{print $1}'):1080 (Tailscale: 100.89.165.79:1080)"
echo " - Samba Share: \\\\$(hostname -I | awk '{print $1}')\\playlists (Drive Z: for Windows)"
echo " - Playlist Refresh: active every 6 hours via systemd timer"
echo "=========================================================="
