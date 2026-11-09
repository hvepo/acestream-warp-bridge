#!/usr/bin/env bash
# Automated Cloudflare WARP Proxy Installer for Raspberry Pi (WarpAcePi)
set -euo pipefail

echo "=== WarpAcePi: Cloudflare WARP Proxy Installer for Raspberry Pi ==="

ARCH=$(uname -m)
case "$ARCH" in
    armv7l|armhf)
        SING_BOX_ARCH="linux-armv7"
        WGCF_ARCH="linux_armv7"
        ;;
    aarch64|arm64)
        SING_BOX_ARCH="linux-arm64"
        WGCF_ARCH="linux_arm64"
        ;;
    x86_64)
        SING_BOX_ARCH="linux-amd64"
        WGCF_ARCH="linux_amd64"
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

echo "[*] Architecture detected: $ARCH ($SING_BOX_ARCH)"

# 1. Create directories
sudo mkdir -p /etc/warp-proxy /opt/warp-proxy /tmp/warp-setup
cd /tmp/warp-setup

# 2. Download and install sing-box
if [ ! -f /opt/warp-proxy/sing-box ]; then
    echo "[*] Downloading sing-box..."
    SING_BOX_URL=$(curl -fsSL https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep "browser_download_url.*${SING_BOX_ARCH}.tar.gz" | head -n 1 | cut -d '"' -f 4)
    curl -fsSL "$SING_BOX_URL" -o sing-box.tar.gz
    tar -xzf sing-box.tar.gz
    sudo mv sing-box-*/sing-box /opt/warp-proxy/sing-box
    sudo chmod +x /opt/warp-proxy/sing-box
fi

# 3. Register WARP account and generate keys if configuration does not exist
if [ ! -f /etc/warp-proxy/config.json ]; then
    echo "[*] Downloading wgcf to generate Cloudflare WARP credentials..."
    WGCF_URL=$(curl -fsSL https://api.github.com/repos/ViRb3/wgcf/releases/latest | grep "browser_download_url.*${WGCF_ARCH}" | head -n 1 | cut -d '"' -f 4)
    curl -fsSL "$WGCF_URL" -o wgcf
    chmod +x wgcf

    ./wgcf register --accept-tos
    ./wgcf generate

    PRIV_KEY=$(grep 'PrivateKey' wgcf-profile.conf | awk '{print $3}')
    PUB_KEY=$(grep 'PublicKey' wgcf-profile.conf | awk '{print $3}')
    ADDR4=$(grep 'Address' wgcf-profile.conf | cut -d '=' -f 2 | cut -d ',' -f 1 | xargs)
    ADDR6=$(grep 'Address' wgcf-profile.conf | cut -d '=' -f 2 | cut -d ',' -f 2 | xargs)

    echo "[*] Writing /etc/warp-proxy/config.json..."
    sudo tee /etc/warp-proxy/config.json > /dev/null << EOF
{
  "log": {
    "level": "warn",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen": "::",
      "listen_port": 1080
    }
  ],
  "outbounds": [
    {
      "type": "wireguard",
      "tag": "warp-endpoint",
      "server": "162.159.192.1",
      "server_port": 2408,
      "local_address": [
        "${ADDR4}",
        "${ADDR6}"
      ],
      "private_key": "${PRIV_KEY}",
      "peer_public_key": "${PUB_KEY}",
      "reserved": [0, 0, 0],
      "mtu": 1280
    },
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "rules": [
      {
        "inbound": "mixed-in",
        "outbound": "warp-endpoint"
      }
    ]
  }
}
EOF
fi

# 4. Install and enable systemd service
echo "[*] Registering systemd service..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sudo cp "$SCRIPT_DIR/warp-proxy.service" /etc/systemd/system/warp-proxy.service
sudo systemctl daemon-reload
sudo systemctl enable --now warp-proxy.service

# 5. Cleanup and verify
rm -rf /tmp/warp-setup
echo "[*] Verifying connectivity through Cloudflare WARP..."
sleep 2
curl -s --max-time 5 -x socks5h://127.0.0.1:1080 https://cloudflare.com/cdn-cgi/trace | grep -E 'warp=|ip=|loc='

echo "=== Installation completed successfully. Proxy active on port 1080 ==="
