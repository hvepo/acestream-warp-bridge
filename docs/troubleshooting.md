# Guía de Diagnóstico y Resolución de Problemas (Troubleshooting)

## 1. Comprobar el servicio en la Raspberry Pi

Conéctate por SSH a la Raspberry Pi:
```bash
ssh rpi
```

Verificar el estado del servicio:
```bash
sudo systemctl status warp-proxy.service
```

Reiniciar el servicio si fuera necesario:
```bash
sudo systemctl restart warp-proxy.service
```

Comprobar que Cloudflare WARP responde correctamente en el puerto local:
```bash
curl -s -x socks5h://127.0.0.1:1080 https://cloudflare.com/cdn-cgi/trace | grep warp=
# Debe devolver: warp=on
```

---

## 2. Comprobar la conexión desde el PC o portátil

Desde tu terminal (PowerShell o bash):
```bash
# Probar conexión vía Tailscale:
curl -s -x socks5h://100.89.165.79:1080 https://cloudflare.com/cdn-cgi/trace | grep warp=

# Probar conexión vía red local:
curl -s -x socks5h://192.168.1.139:1080 https://cloudflare.com/cdn-cgi/trace | grep warp=
```

Si devuelve `warp=on` y `loc=ES`, el túnel está al 100% operativo.

---

## 3. ¿Qué ocurre si la Raspberry Pi está apagada?

El script de arranque (`launch_acestream.bat`) y el acceso directo del escritorio (`Reiniciar AceStream (WARP).bat`) comprueban automáticamente si la RPi responde en un plazo de **600 milisegundos**:
- **Si la RPi no responde:** AceStream se inicia en modo directo normal (sin proxy).
- Nunca te quedarás bloqueado ni con AceStream sin abrir.
- Cuando enciendas la Raspberry Pi, simplemente ejecuta el acceso directo **`Reiniciar AceStream (WARP).bat`** de tu Escritorio para aplicar el escudo sin reiniciar el ordenador.

---

## 4. ¿Afecta al resto de programas del PC?

**No.** El proxy se inyecta única y exclusivamente como variables de entorno locales al proceso de `ace_engine.exe`. Navegadores (Chrome, Edge), juegos (Steam) y descargas siguen saliendo por tu conexión normal de fibra al máximo ancho de banda.
