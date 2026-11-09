#!/usr/bin/env bash
# Configurar Samba (Unidad Z:) y Actualizador Automático de Listas en Raspberry Pi
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
PLAYLISTS_DIR="$REPO_DIR/playlists"

echo "=== Configuración de Samba y Actualizador de Canales en Raspberry Pi ==="
echo "[*] Carpeta de listas detectada: $PLAYLISTS_DIR"

# 1. Instalar dependencias necesarias
echo "[*] Instalando Samba y dependencias de Python..."
sudo apt-get update -y
sudo apt-get install -y samba python3 python3-pip python3-requests

# 2. Configurar Samba para compartir la carpeta playlists
SMB_CONF="/etc/samba/smb.conf"
SHARE_NAME="playlists"

if ! grep -q "\[$SHARE_NAME\]" "$SMB_CONF"; then
    echo "[*] Añadiendo recurso compartido [$SHARE_NAME] a $SMB_CONF..."
    sudo tee -a "$SMB_CONF" > /dev/null << EOF

[$SHARE_NAME]
   comment = Listas AceStream para VLC y AcePlayer
   path = $PLAYLISTS_DIR
   browseable = yes
   read only = no
   guest ok = yes
   create mask = 0775
   directory mask = 0775
   force user = $(whoami)
EOF
    echo "[*] Reiniciando servicio Samba (smbd)..."
    sudo systemctl restart smbd
    sudo systemctl enable smbd
else
    echo "[OK] El recurso [$SHARE_NAME] ya existe en $SMB_CONF."
fi

# 3. Crear servicio systemd para la actualización automática de canales
SERVICE_FILE="/etc/systemd/system/update-acestream-playlists.service"
TIMER_FILE="/etc/systemd/system/update-acestream-playlists.timer"

echo "[*] Creando servicio systemd para actualizar canales..."
sudo tee "$SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=Actualizador Automatico de Canales AceStream
After=network-online.target warp-proxy.service

[Service]
Type=oneshot
User=$(whoami)
WorkingDirectory=$REPO_DIR
ExecStart=/usr/bin/python3 $REPO_DIR/scripts/evaluate_and_update.py --mode vlc
StandardOutput=journal
StandardError=journal
EOF

echo "[*] Creando temporizador systemd (ejecución cada 6 horas)..."
sudo tee "$TIMER_FILE" > /dev/null << EOF
[Unit]
Description=Temporizador para actualizador de listas AceStream

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
echo " [OK] CONFIGURACION DE RASPBERRY PI COMPLETADA CON EXITO"
echo "=========================================================="
echo " 1. Recurso Samba disponible en red como: \\\\$(hostname -I | awk '{print $1}')\\$SHARE_NAME"
echo "    o via Tailscale: \\\\100.89.165.79\\$SHARE_NAME"
echo " 2. Listas actualizadas automaticamente cada 6 horas."
echo " 3. En Windows, ejecuta: windows\\Conectar Unidad Z (Raspberry Pi).bat"
echo "=========================================================="
