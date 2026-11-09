#!/usr/bin/env bash
# Configure Samba share [playlists] on Raspberry Pi - WarpAcePi
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PLAYLISTS_DIR="$REPO_DIR/playlists"
SMB_CONF="/etc/samba/smb.conf"
SHARE_NAME="playlists"

echo "=== WarpAcePi: Configure Samba Share [$SHARE_NAME] ==="
echo "[*] Exposing playlists directory: $PLAYLISTS_DIR"

if ! command -v smbd &> /dev/null; then
    echo "[*] Installing Samba..."
    sudo apt-get update -y
    sudo apt-get install -y samba
fi

if ! grep -q "\[$SHARE_NAME\]" "$SMB_CONF"; then
    echo "[*] Appending [$SHARE_NAME] configuration to $SMB_CONF..."
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
    echo "[*] Enabling and restarting Samba daemon..."
    sudo systemctl enable smbd
    sudo systemctl restart smbd
    echo "[OK] Share [$SHARE_NAME] created."
else
    echo "[OK] Share [$SHARE_NAME] already exists in $SMB_CONF. Restarting smbd..."
    sudo systemctl restart smbd
fi

echo "[OK] Samba share is accessible at \\\\$(hostname -I | awk '{print $1}')\\$SHARE_NAME"
