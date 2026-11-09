#!/usr/bin/env bash
# Install systemd timer to update playlists every 6 hours on Raspberry Pi - WarpAcePi
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

SERVICE_FILE="/etc/systemd/system/update-acestream-playlists.service"
TIMER_FILE="/etc/systemd/system/update-acestream-playlists.timer"

echo "=== WarpAcePi: Install Systemd Timer for Automatic Channel Updates ==="

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

sudo tee "$TIMER_FILE" > /dev/null << EOF
[Unit]
Description=Timer for WarpAcePi Channel Updater (every 6 hours)

[Timer]
OnBootSec=5min
OnUnitActiveSec=6h
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now update-acestream-playlists.timer

echo "[OK] Timer enabled and started. Next run scheduled in 6 hours."
echo "[OK] Check status with: sudo systemctl status update-acestream-playlists.timer"
