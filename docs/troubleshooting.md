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

---

## 5. El icono de AceStream desaparece de la bandeja del sistema

Si notas que el icono no está visible o desaparece repentinamente, se debe a una de estas dos razones:

### A. Windows lo tiene agrupado dentro del menú de iconos ocultos (`^`)
Windows 10 y Windows 11 por defecto esconden los iconos de la bandeja tras la flecha `^` (menú de desbordamiento):
1. **Método rápido:** Haz clic en la flecha `^` al lado del reloj, pincha con el botón izquierdo sobre el icono de AceStream y **arrástralo directamente a la barra de tareas**. Quedará siempre fijo y visible.
2. **Desde Configuración:**
   - **En Windows 11:** Ve a *Configuración > Personalización > Barra de tareas > Otros iconos de la bandeja del sistema*, busca *AceStream* y márcalo como **Activado**.
   - **En Windows 10:** Ve a *Configuración > Personalización > Barra de tareas > Área de notificación > Seleccionar qué iconos aparecen en la barra de tareas* y activa *AceStream* (o marca *"Mostrar siempre todos los iconos en el área de notificación"*).

### B. El proceso se cerraba al arrancar ("icono fantasma" que desaparece al pasar el ratón)
Si el icono salía pero desaparecía en cuanto pasabas el cursor sobre él, significa que `ace_engine.exe` se cerraba en segundo plano. Esto ocurría porque las peticiones internas de AceStream a `127.0.0.1:6878` se enviaban al proxy en vez de resolverse localmente.
- Los scripts actualizados ya incluyen **`NO_PROXY=localhost,127.0.0.1,::1`** y fijan el directorio de trabajo del motor.
- Para aplicar la solución en tu PC, vuelve a ejecutar el instalador:
  ```powershell
  .\windows\install-windows-autostart.ps1
  ```
  O ejecuta el acceso directo **`Reiniciar AceStream (WARP).bat`**.
