# WarpAcePi Troubleshooting Guide 🛠️

## 1. Checking the Raspberry Pi Services

Connect via SSH to your Raspberry Pi:
```bash
ssh rpi
# Or via Tailscale: ssh hvepo@100.89.165.79
```

### Check WARP Proxy status:
```bash
sudo systemctl status warp-proxy.service
```

Restart the service if needed:
```bash
sudo systemctl restart warp-proxy.service
```

Verify that Cloudflare WARP is responding locally on port 1080:
```bash
curl -s -x socks5h://127.0.0.1:1080 https://cloudflare.com/cdn-cgi/trace | grep -E 'warp=|ip=|loc='
# Expected output: warp=on, loc=ES
```

### Check Samba (Drive Z:) and Playlist Updater:
```bash
sudo systemctl status smbd
sudo systemctl status update-acestream-playlists.timer
```

---

## 2. Checking Connectivity from Windows (Desktop or Laptop)

Open PowerShell or Command Prompt on your Windows computer:
```powershell
# Test connection via Tailscale:
curl -s -x http://100.89.165.79:1080 https://cloudflare.com/cdn-cgi/trace | Select-String "warp="

# Test connection via Local LAN:
curl -s -x http://192.168.1.139:1080 https://cloudflare.com/cdn-cgi/trace | Select-String "warp="
```

Or run the target-specific connection tester:
- On Desktop: `targets\desktop\test_connection.bat`
- On Laptop: `targets\laptop\test_connection.bat`

If it returns `warp=on` and `loc=ES`, the proxy tunnel is 100% operational.

---

## 3. What Happens if the Raspberry Pi is Offline?

The startup scripts (`launch_acestream.bat`, `restart_acestream_warp.bat`) automatically probe if the RPi responds within **2.5 seconds** (Tailscale) or **1.5 seconds** (LAN):
- **If the RPi does not respond:** AceStream falls back gracefully to direct mode (without proxy).
- You will never be locked out or unable to launch AceStream.
- Once you turn on the Raspberry Pi, run `targets\<target>\restart_acestream_warp.bat` to re-engage the WARP shield without rebooting your computer.

---

## 4. Does This Affect Other PC Applications?

**No.** The proxy settings (`HTTP_PROXY`, `HTTPS_PROXY`) are injected locally only to the `ace_engine.exe` process environment. Web browsers (Chrome, Edge), online gaming (Steam), torrents, and general downloads continue using your full fiber bandwidth directly.

---

## 5. Multi-Device Port Conflicts on Home Routers

If you stream on both a Desktop PC and a Laptop behind the same router:
- **Desktop PC:** Uses P2P port `48621` (configured via `targets\desktop\activate.bat`).
- **Laptop:** Uses P2P port `48622` (configured via `targets\laptop\activate.bat`).
- **Why?** Two computers behind the same public IP cannot share the same external UPnP port.
- Both devices continue using standard local port `6878` for VLC playback.

---

## 6. VLC "Unable to Open MRL" / "Failed to Load Content"

If VLC reports `VLC is unable to open the MRL 'http://127.0.0.1:6878/...`:
1. **AceStream is not running or listening on port 6878:**
   Run `targets\<target>\restart_acestream_warp.bat` to force-bind the engine to port 6878.
2. **ISP Censorship Block:**
   If entering `http://127.0.0.1:6878/ace/getstream?id=<ID>` in your browser shows `failed to load content`, AceStream is attempting direct connections that your ISP is null-routing. Ensure Tailscale is active and run `targets\<target>\restart_acestream_warp.bat`.
3. **Router DoS Protection:**
   Disable "DoS Protection" in your router settings (or set level to "Low") to prevent the router from dropping burst P2P packets.

---

## 7. Network Drive Z: Disconnected or Not Found

Run:
- On Desktop: `targets\desktop\mount_z_drive.bat`
- On Laptop: `targets\laptop\mount_z_drive.bat`

This utility automatically detects the active Raspberry Pi IP (LAN or Tailscale), verifies SMB port 445, prompts to switch Windows network profile from Public to Private if blocked, and persistently maps the `playlists` share to `Z:`.

---

## 8. Laptop-Specific Diagnostics & Repair

On the Laptop, run:
```cmd
targets\laptop\diagnose_and_repair.bat
```
This utility:
- Tests and reconnects Network Drive `Z:`.
- Optimizes USB Dock network adapters by disabling Green Ethernet / Energy Efficient Ethernet.
- Checks local AceStream Engine and port `48622`.
- Validates the Raspberry Pi WARP tunnel on port `1080`.
- Ensures zero files or shortcuts exist on your Desktop.
