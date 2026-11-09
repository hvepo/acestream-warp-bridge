#!/usr/bin/env bash
# Install sing-box Cloudflare WARP proxy service on Raspberry Pi - WarpAcePi
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="warp-proxy"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
CONFIG_DIR="/etc/sing-box"
CONFIG_FILE="${CONFIG_DIR}/config.json"
TEMPLATE_FILE="${SCRIPT_DIR}/config.json.template"

echo "=== WarpAcePi: Install Cloudflare WARP Proxy Service (Port 1080) ==="

# 1. Install sing-box if missing
if ! command -v sing-box &> /dev/null; then
    echo "[*] sing-box not found. Installing sing-box..."
    sudo mkdir -p /etc/apt/keyrings
    sudo curl -fsSL https://sing-box.app/gpg.key -o /etc/apt/keyrings/sagernet.asc
    sudo chmod a+r /etc/apt/keyrings/sagernet.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/sagernet.asc] https://deb.sagernet.org/ * *" | \
        sudo tee /etc/apt/sources.list.d/sagernet.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y sing-box
fi

# 2. Deploy sing-box config
sudo mkdir -p "$CONFIG_DIR"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "[*] Generating WARP WireGuard keys via sing-box..."
    WARP_KEYS=$(sing-box generate warp-account)
    
    PRIVATE_KEY=$(echo "$WARP_KEYS" | grep -oP '"private_key":\s*"\K[^"]+')
    PEER_PUBKEY=$(echo "$WARP_KEYS" | grep -oP '"peer_public_key":\s*"\K[^"]+')
    IPV4_ADDR=$(echo "$WARP_KEYS" | grep -oP '"local_address_ipv4":\s*"\K[^"]+')
    IPV6_ADDR=$(echo "$WARP_KEYS" | grep -oP '"local_address_ipv6":\s*"\K[^"]+')
    RESERVED=$(echo "$WARP_KEYS" | grep -oP '"reserved":\s*\[\K[^\]]+')
    
    sed -e "s|__PRIVATE_KEY__|${PRIVATE_KEY}|g" \
        -e "s|__PEER_PUBLIC_KEY__|${PEER_PUBKEY}|g" \
        -e "s|__LOCAL_IPV4__|${IPV4_ADDR}|g" \
        -e "s|__LOCAL_IPV6__|${IPV6_ADDR}|g" \
        -e "s|__RESERVED__|${RESERVED}|g" \
        "$TEMPLATE_FILE" | sudo tee "$CONFIG_FILE" > /dev/null
    echo "[OK] Configuration written to $CONFIG_FILE"
else
    echo "[OK] $CONFIG_FILE already exists. Keeping current configuration."
fi

# 3. Install systemd service
sudo cp "${SCRIPT_DIR}/warp-proxy.service" "$SERVICE_FILE"
sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl restart "$SERVICE_NAME"

echo "[OK] ${SERVICE_NAME} running on port 1080 (Mixed SOCKS5 + HTTP)."
