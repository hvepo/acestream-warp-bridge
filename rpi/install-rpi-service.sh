#!/usr/bin/env bash
# Script de instalación automatizada del Proxy Cloudflare WARP en Raspberry Pi
set -euo pipefail

echo "=== Instalador AceStream WARP Proxy para Raspberry Pi ==="

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
        echo "Arquitectura no soportada: $ARCH"
        exit 1
        ;;
esac

echo "[*] Arquitectura detectada: $ARCH ($SING_BOX_ARCH)"

# 1. Crear directorios
sudo mkdir -p /etc/warp-proxy /opt/warp-proxy /tmp/warp-setup
cd /tmp/warp-setup

# 2. Descargar e instalar sing-box
if [ ! -f /opt/warp-proxy/sing-box ]; then
    echo "[*] Descargando sing-box..."
    SING_BOX_URL=$(curl -fsSL https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep "browser_download_url.*${SING_BOX_ARCH}.tar.gz" | head -n 1 | cut -d '"' -f 4)
    curl -fsSL "$SING_BOX_URL" -o sing-box.tar.gz
    tar -xzf sing-box.tar.gz
    sudo mv sing-box-*/sing-box /opt/warp-proxy/sing-box
    sudo chmod +x /opt/warp-proxy/sing-box
fi

# 3. Registrar cuenta WARP y generar claves si no existe configuración
if [ ! -f /etc/warp-proxy/config.json ]; then
    echo "[*] Descargando wgcf para generar credenciales de Cloudflare WARP..."
    WGCF_URL=$(curl -fsSL https://api.github.com/repos/ViRb3/wgcf/releases/latest | grep "browser_download_url.*${WGCF_ARCH}" | head -n 1 | cut -d '"' -f 4)
    curl -fsSL "$WGCF_URL" -o wgcf
    chmod +x wgcf

    ./wgcf register --accept-tos
    ./wgcf generate

    PRIV_KEY=$(grep 'PrivateKey' wgcf-profile.conf | awk '{print $3}')
    PUB_KEY=$(grep 'PublicKey' wgcf-profile.conf | awk '{print $3}')
    ADDR4=$(grep 'Address' wgcf-profile.conf | cut -d '=' -f 2 | cut -d ',' -f 1 | xargs)
    ADDR6=$(grep 'Address' wgcf-profile.conf | cut -d '=' -f 2 | cut -d ',' -f 2 | xargs)

    echo "[*] Configurando /etc/warp-proxy/config.json..."
    sudo tee /etc/warp-proxy/config.json > /dev/null << EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "tag": "dns-remote",
        "type": "tls",
        "server": "1.1.1.1"
      }
    ]
  },
  "inbounds": [
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen": "::",
      "listen_port": 1080
    }
  ],
  "endpoints": [
    {
      "type": "wireguard",
      "tag": "warp-endpoint",
      "address": [
        "${ADDR4}",
        "${ADDR6}"
      ],
      "private_key": "${PRIV_KEY}",
      "peers": [
        {
          "address": "162.159.192.1",
          "port": 2408,
          "public_key": "${PUB_KEY}",
          "allowed_ips": ["0.0.0.0/0", "::/0"]
        }
      ],
      "mtu": 1280
    }
  ],
  "outbounds": [
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

# 4. Instalar y habilitar servicio systemd
echo "[*] Registrando servicio systemd..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sudo cp "$SCRIPT_DIR/warp-proxy.service" /etc/systemd/system/warp-proxy.service
sudo systemctl daemon-reload
sudo systemctl enable --now warp-proxy.service

# 5. Limpieza y comprobación
rm -rf /tmp/warp-setup
echo "[*] Verificando conectividad a traves de Cloudflare WARP..."
sleep 2
curl -s --max-time 5 -x socks5h://127.0.0.1:1080 https://cloudflare.com/cdn-cgi/trace | grep -E 'warp=|ip=|loc='

echo "=== Instalacion completada con exito. Proxy listo en puerto 1080 ==="
