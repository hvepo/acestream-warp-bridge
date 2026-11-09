#!/usr/bin/env bash
# Setup Samba (Drive Z:) and Automatic Channel Updater on Raspberry Pi (WarpAcePi)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
PLAYLISTS_DIR="$REPO_DIR/playlists"

echo "=== WarpAcePi: Setup Samba & Channel Updater on Raspberry Pi ==="
echo "[*] Playlists directory: $PLAYLISTS_DIR"

# 1. Install dependencies
echo "[*] Installing Samba and Python dependencies..."
sudo apt-get update -y
sudo apt-get install -y samba python3 python3-pip python3-requests

# 2. Configure Samba share
SMB_CONF="/etc/samba/smb.conf"
SHARE_NAME="playlists"

if ! grep -q "\[$SHARE_NAME\]" "$SMB_CONF"; then
    echo "[*] Adding [$SHARE_NAME] share to $SMB_CONF..."
    sudo tee -a "$SMB_CONF" > /dev/null << EOF

[$SHARE_NAME]
   comment = WarpAcePi Playlists for VLC and AcePlayer
   path = $PLAYLISTS_DIR
   browseable = yes
   read only = no
   guest ok = yes
   create mask = 0775
   directory mask = 0775
   force user = $(whoami)
EOF
    echo "[*] Restarting Samba service (smbd)..."
    sudo systemctl restart smbd
    sudo systemctl enable smbd
else
    echo "[OK] Share [$SHARE_NAME] already configured in $SMB_CONF."
fi

# 3. Create systemd timer for automatic playlist updates
SERVICE_FILE="/etc/systemd/system/update-acestream-playlists.service"
TIMER_FILE="/etc/systemd/system/update-acestream-playlists.timer"

echo "[*] Creating systemd service for channel updates..."
sudo tee "$SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=WarpAcePi Automatic Channel Updater
After=network-online.target warp-proxy.service

[Service]
Type=oneshot
User=$(whoami)
WorkingDirectory=$REPO_DIR
ExecStart=/usr/bin/python3 $REPO_DIR/scripts/evaluate_and_update.py --mode vlc
StandardOutput=journal
StandardError=journal
EOF

echo "[*] Creating systemd timer (runs every 6 hours)..."
sudo tee "$TIMER_FILE" > /dev/null << EOF
[Unit]
Description=Timer for WarpAcePi Channel Updater

[Timer]
OnBootSec=5min
OnUnitActiveSec=6h
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now update-acestream-playlists.timer

echo ""
echo "=========================================================="
echo " [OK] RASPBERRY PI SETUP COMPLETED SUCCESSFULLY"
echo "=========================================================="
echo " 1. Samba share available on LAN: \\\\$(hostname -I | awk '{print $1}')\\$SHARE_NAME"
echo "    or via Tailscale: \\\\100.89.165.79\\$SHARE_NAME"
echo " 2. Playlists automatically updated every 6 hours."
echo " 3. On Windows, run: windows\\connect_z_drive_rpi.bat"
echo "=========================================================="
