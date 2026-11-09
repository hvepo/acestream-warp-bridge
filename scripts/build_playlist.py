#!/usr/bin/env python3
"""
Generador de listas M3U a partir del catálogo JSON de canales AceStream.
Genera formatos directos (acestream://) y por proxy HTTP (http://127.0.0.1:6878/...).
"""

import json
import argparse
import sys
from pathlib import Path
from typing import Dict, List

# Importar funciones de normalización, ordenación y validación activa
try:
    from scripts.evaluate_and_update import (
        clean_display_name, normalize_channel_key, natural_sort_key,
        _natural_sort_tuple, GENERIC_KEYS,
        check_engine_online, validate_streams_concurrent, ChannelItem
    )
except ImportError:
    base_dir = Path(__file__).resolve().parent.parent
    if str(base_dir) not in sys.path:
        sys.path.insert(0, str(base_dir))
    from scripts.evaluate_and_update import (
        clean_display_name, normalize_channel_key, natural_sort_key,
        _natural_sort_tuple, GENERIC_KEYS,
        check_engine_online, validate_streams_concurrent, ChannelItem
    )


def load_channels(json_path: Path) -> dict:
    with open(json_path, "r", encoding="utf-8") as f:
        return json.load(f)


def prepare_channels_for_m3u(data: dict, only_enabled: bool = True) -> List[Dict]:
    """
    Filtra canales habilitados con hash válido, agrupa espejos numerando opciones
    (| Option 1, | Option 2, ...) y ordena alfabéticamente de forma natural (A-Z).
    """
    if data.get("_pre_sorted"):
        return data.get("channels", [])

    raw_channels = data.get("channels", [])
    groups: Dict[str, List[Dict]] = {}
    generic_counter = 0

    for ch in raw_channels:
        if only_enabled and not ch.get("enabled", True):
            continue
        cid = ch.get("acestream_id", "").strip()
        if not cid:
            continue

        clean_name = clean_display_name(ch.get("name", "Canal Desconocido"))
        key = normalize_channel_key(clean_name)
        if not key or key in GENERIC_KEYS:
            generic_counter += 1
            key = f"__generic_{generic_counter}__"

        entry = dict(ch)
        entry["_clean_name"] = clean_name
        groups.setdefault(key, []).append(entry)

    processed_channels: List[Dict] = []
    for items in groups.values():
        if len(items) == 1:
            item = items[0]
            item["name"] = item.pop("_clean_name")
            processed_channels.append(item)
        else:
            base_name = items[0]["_clean_name"]
            best_logo = next((c.get("logo") for c in items if c.get("logo")), "")
            best_tvg_id = next((c.get("tvg_id") for c in items if c.get("tvg_id")), "")
            best_cat = next(
                (c.get("category") for c in items if c.get("category") and c.get("category", "").lower() not in ("general", "sports")),
                items[0].get("category") or "General"
            )
            for idx, item in enumerate(items, 1):
                item.pop("_clean_name", None)
                item["name"] = f"{base_name} | Option {idx}"
                if not item.get("logo") and best_logo:
                    item["logo"] = best_logo
                if not item.get("tvg_id") and best_tvg_id:
                    item["tvg_id"] = best_tvg_id
                if (not item.get("category") or item.get("category", "").lower() in ("general", "sports")) and best_cat:
                    item["category"] = best_cat
                processed_channels.append(item)

    processed_channels.sort(key=lambda ch: _natural_sort_tuple(ch.get("name", "")))
    return processed_channels


def generate_m3u(
    data: dict,
    mode: str = "vlc",
    host: str = "127.0.0.1",
    port: int = 6878,
    only_enabled: bool = True,
    network_caching: int = 3000
) -> str:
    processed_channels = prepare_channels_for_m3u(data, only_enabled=only_enabled)
    lines = ['#EXTM3U x-tvg-url=""']

    is_vlc = mode == "vlc"
    is_direct = mode == "direct"
    is_hls = mode == "hls"
    vlc_opt_cache = f"#EXTVLCOPT:network-caching={network_caching}"
    vlc_opt_reconn = "#EXTVLCOPT:http-reconnect=true"
    base_getstream = f"http://{host}:{port}/ace/getstream?id="
    base_hls = f"http://{host}:{port}/ace/manifest.m3u8?id="

    for ch in processed_channels:
        cid = ch.get("acestream_id", "").strip()
        name = ch.get("name", "Canal Desconocido")
        category = ch.get("category", "General")
        tvg_id = ch.get("tvg_id", "")
        logo = ch.get("logo", "")

        if logo:
            lines.append(f'#EXTINF:-1 tvg-id="{tvg_id}" tvg-name="{name}" tvg-logo="{logo}" group-title="{category}",{name}')
        else:
            lines.append(f'#EXTINF:-1 tvg-id="{tvg_id}" tvg-name="{name}" group-title="{category}",{name}')

        if is_vlc:
            lines.append(vlc_opt_cache)
            lines.append(vlc_opt_reconn)
            lines.append(f"{base_getstream}{cid}")
        elif is_direct:
            lines.append(f"acestream://{cid}")
        elif is_hls:
            lines.append(f"{base_hls}{cid}")
        else:  # http stream (TS stream default)
            lines.append(f"{base_getstream}{cid}")

    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description="Construir listas M3U desde catálogo de canales AceStream.")
    parser.add_argument("--input", default="data/channels.json", help="Ruta al archivo JSON de canales.")
    parser.add_argument("--output", default=None, help="Ruta del archivo M3U de salida.")
    parser.add_argument(
        "--mode",
        choices=["vlc", "http", "direct", "hls", "all"],
        default="all",
        help="Modo de generación de URL (vlc=proxy HTTP optimizado para VLC, http=proxy HTTP TS estándar, direct=acestream://, hls=manifest.m3u8, all=generar todas las listas).",
    )
    parser.add_argument("--host", default="127.0.0.1", help="Host del AceStream Engine (default: 127.0.0.1).")
    parser.add_argument("--port", type=int, default=6878, help="Puerto HTTP del AceStream Engine (default: 6878).")
    parser.add_argument("--network-caching", type=int, default=3000, help="Milisegundos de caché de red para VLC (default: 3000).")
    parser.add_argument("--include-disabled", action="store_true", help="Incluir canales marcados como deshabilitados.")
    parser.add_argument(
        "--now",
        action="store_true",
        help="Probar emisiones en tiempo real contra Ace Stream Engine y generar listas M3U con sufijo NOW con únicamente los canales que están emitiendo señal en el momento (formatos VLC y Ace Player)."
    )
    parser.add_argument("--timeout", type=float, default=3.5, help="Timeout por stream en segundos al verificar señal (default: 3.5).")
    parser.add_argument("--workers", type=int, default=10, help="Hilos concurrentes para validación activa (default: 10).")

    args = parser.parse_args()

    base_dir = Path(__file__).resolve().parent.parent
    input_file = base_dir / args.input
    playlists_dir = base_dir / "playlists"
    playlists_dir.mkdir(parents=True, exist_ok=True)

    if not input_file.exists():
        print(f"[ERROR] No se encontró el archivo de entrada: {input_file}")
        return

    data = load_channels(input_file)
    only_enabled = not args.include_disabled

    if args.output:
        chosen_mode = "vlc" if args.mode == "all" else args.mode
        out_path = Path(args.output)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        content = generate_m3u(
            data,
            mode=chosen_mode,
            host=args.host,
            port=args.port,
            only_enabled=only_enabled,
            network_caching=args.network_caching
        )
        out_path.write_text(content, encoding="utf-8")
        print(f"[OK] Generada lista M3U ({chosen_mode}): {out_path}")
    elif args.mode == "all":
        # Pre-procesar y ordenar una única vez para todos los formatos
        prepared_data = {
            "channels": prepare_channels_for_m3u(data, only_enabled=only_enabled),
            "_pre_sorted": True
        }

        # 1. Genera lista Maestra y VLC compatible
        vlc_content = generate_m3u(
            prepared_data, mode="vlc", host=args.host, port=args.port,
            only_enabled=only_enabled, network_caching=args.network_caching
        )
        out_master = playlists_dir / "playlist.m3u"
        out_master.write_text(vlc_content, encoding="utf-8")
        out_vlc = playlists_dir / "playlist_vlc.m3u"
        out_vlc.write_text(vlc_content, encoding="utf-8")
        print(f"[OK] Generada lista maestra VLC: {out_master}")
        print(f"[OK] Generada lista optimizada VLC: {out_vlc}")

        # 2. Genera lista HTTP estándar
        http_content = generate_m3u(prepared_data, mode="http", host=args.host, port=args.port, only_enabled=only_enabled)
        out_http = playlists_dir / "playlist_http.m3u"
        out_http.write_text(http_content, encoding="utf-8")
        print(f"[OK] Generada lista HTTP proxy: {out_http}")

        # 3. Genera lista Directa
        direct_content = generate_m3u(prepared_data, mode="direct", only_enabled=only_enabled)
        out_direct = playlists_dir / "playlist_direct.m3u"
        out_direct.write_text(direct_content, encoding="utf-8")
        print(f"[OK] Generada lista Directa (acestream://): {out_direct}")
    else:
        out_path = playlists_dir / f"playlist_{args.mode}.m3u"
        content = generate_m3u(
            data,
            mode=args.mode,
            host=args.host,
            port=args.port,
            only_enabled=only_enabled,
            network_caching=args.network_caching
        )
        out_path.write_text(content, encoding="utf-8")
        print(f"[OK] Generada lista M3U ({args.mode}): {out_path}")

    # Generar listas NOW si se especificó la bandera --now
    if args.now:
        print("\n🔍 Validando canales activos para listas en directo (NOW)...")
        raw_channels = data.get("channels", [])
        candidates = []
        for ch in raw_channels:
            if only_enabled and not ch.get("enabled", True):
                continue
            cid = ch.get("acestream_id", "").strip()
            if not cid:
                continue
            candidates.append(ChannelItem(
                acestream_id=cid,
                name=ch.get("name", "Canal Desconocido"),
                category=ch.get("category", "General"),
                logo=ch.get("logo", ""),
                tvg_id=ch.get("tvg_id", "")
            ))
        probed = validate_streams_concurrent(
            candidates, host=args.host, port=args.port, timeout=args.timeout, max_workers=args.workers
        )
        online_items = [
            {
                "name": ch.name,
                "category": ch.category,
                "acestream_id": ch.acestream_id,
                "logo": ch.logo,
                "tvg_id": ch.tvg_id,
                "enabled": True
            }
            for ch in probed if ch.is_online
        ]
        now_prepared = {
            "channels": prepare_channels_for_m3u({"channels": online_items}, only_enabled=True),
            "_pre_sorted": True
        }
        print(f"✨ Canales streameando señal en el momento (NOW): {len(online_items)}")

        # 1. Formato VLC con sufijo NOW
        now_vlc_content = generate_m3u(
            now_prepared, mode="vlc", host=args.host, port=args.port,
            only_enabled=True, network_caching=args.network_caching
        )
        for vlc_now_name in ("working_streams_NOW.m3u", "working_streams_vlc_NOW.m3u", "playlist_vlc_NOW.m3u", "playlist_NOW.m3u"):
            (playlists_dir / vlc_now_name).write_text(now_vlc_content, encoding="utf-8")
        print(f"[OK] Generada lista VLC en directo (NOW): {playlists_dir / 'working_streams_NOW.m3u'}")

        # 2. Formato Ace Player directo (acestream://) con sufijo NOW
        now_direct_content = generate_m3u(now_prepared, mode="direct", only_enabled=True)
        for direct_now_name in ("working_streams_direct_NOW.m3u", "playlist_direct_NOW.m3u"):
            (playlists_dir / direct_now_name).write_text(now_direct_content, encoding="utf-8")
        print(f"[OK] Generada lista Ace Player en directo (NOW): {playlists_dir / 'working_streams_direct_NOW.m3u'}")


if __name__ == "__main__":
    main()

