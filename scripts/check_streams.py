#!/usr/bin/env python3
"""
Validador de catálogo y comprobador de disponibilidad para AceStream.
Valida sintaxis de IDs SHA-1 y comprueba en vivo el estado (ALIVE/DEAD),
latencia y flujo real de bytes a través de AceStream Engine.
"""

import json
import sys
import argparse
from datetime import datetime, timezone
from typing import Tuple, List, Dict
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed

try:
    from scripts.evaluate_and_update import (
        HEX_SHA1_PATTERN,
        check_engine_online,
        probe_single_stream,
    )
except ImportError:
    base_dir = Path(__file__).resolve().parent.parent
    if str(base_dir) not in sys.path:
        sys.path.insert(0, str(base_dir))
    from scripts.evaluate_and_update import (
        HEX_SHA1_PATTERN,
        check_engine_online,
        probe_single_stream,
    )


def load_channels(json_path: Path) -> dict:
    """Carga catálogo de canales desde un archivo JSON."""
    with open(json_path, "r", encoding="utf-8") as f:
        return json.load(f)


def check_engine_status(host: str = "127.0.0.1", port: int = 6878, timeout: float = 3.0) -> bool:
    """Verifica si AceStream Engine responde en la dirección y puerto indicados."""
    return check_engine_online(host=host, port=port, timeout=timeout)


def check_stream_alive(
    acestream_id: str,
    host: str = "127.0.0.1",
    port: int = 6878,
    timeout: float = 6.0
) -> Tuple[bool, float, str]:
    """
    Comprueba si un stream de AceStream está ACTIVO (ALIVE) o INACTIVO (DEAD).
    Conecta con AceStream Engine, solicita el stream e intenta leer el primer chunk de datos.
    """
    return probe_single_stream(acestream_id=acestream_id, host=host, port=port, timeout=timeout)


def check_streams_concurrent(
    channels: List[Dict],
    host: str = "127.0.0.1",
    port: int = 6878,
    timeout: float = 6.0,
    max_workers: int = 4
) -> List[Dict]:
    """
    Evalúa concurrentemente una lista de canales para comprobar cuáles están ALIVE.
    Retorna la lista en su orden original enriquecida con `is_alive`, `response_time` y `error_msg`.
    """
    total = len(channels)
    if total == 0:
        return []

    print(f"\n🔍 Comprobando estado en vivo de {total} streams (Timeout: {timeout}s, Hilos: {max_workers})...\n")

    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        future_map = {
            executor.submit(check_stream_alive, ch.get("acestream_id", ""), host, port, timeout): ch
            for ch in channels
        }

        completed = 0
        alive_count = 0

        for future in as_completed(future_map):
            ch = future_map[future]
            completed += 1
            name = ch.get("name", "Canal")
            cid = ch.get("acestream_id", "")

            try:
                is_alive, elapsed, err = future.result()
            except Exception as e:
                is_alive, elapsed, err = False, 0.0, str(e)

            ch["is_alive"] = is_alive
            ch["response_time"] = elapsed
            ch["error_msg"] = err

            if is_alive:
                alive_count += 1
                icon = "🟢 [ALIVE]"
                detail = f"{elapsed:.2f}s"
            else:
                icon = "🔴 [DEAD]"
                detail = err or "timeout"

            print(f"[{completed:02d}/{total:02d}] {icon} {name} ({cid[:10]}...) -> {detail}")

    print(f"\n📊 Resumen de comprobación: {alive_count} ALIVE / {total - alive_count} DEAD de {total} comprobados.")
    return channels


def validate_catalog(channels: list) -> list:
    """Valida la sintaxis de los hashes en el catálogo."""
    results = []
    seen_ids = set()

    for ch in channels:
        ch_id = ch.get("id", "sin-id")
        name = ch.get("name", "Desconocido")
        acestream_id = ch.get("acestream_id", "").strip()
        enabled = ch.get("enabled", True)

        errors = []
        if not acestream_id:
            errors.append("Falta acestream_id")
        elif len(acestream_id) != 40 or not HEX_SHA1_PATTERN.match(acestream_id):
            errors.append(f"Formato no válido (debe ser hash SHA-1 de 40 caracteres hexadecimales, longitud: {len(acestream_id)})")

        cid_lower = acestream_id.lower()
        if cid_lower and cid_lower in seen_ids:
            errors.append(f"acestream_id duplicado ({acestream_id})")
        elif cid_lower:
            seen_ids.add(cid_lower)

        results.append({
            "id": ch_id,
            "name": name,
            "acestream_id": acestream_id,
            "enabled": enabled,
            "valid_format": len(errors) == 0,
            "errors": errors,
        })

    return results


def apply_live_results_to_catalog(data: dict, probed_channels: List[Dict]) -> None:
    """
    Actualiza el campo `enabled` de los canales evaluados según `is_alive`
    y limpia los atributos transitorios antes de persistir el JSON.
    """
    for ch in probed_channels:
        if "is_alive" in ch:
            ch["enabled"] = bool(ch.pop("is_alive"))
        ch.pop("response_time", None)
        err = ch.pop("error_msg", None)
        if not ch.get("enabled", True) and err:
            ch["notes"] = f"Inactivo: {err}"

    all_channels = data.get("channels", [])
    if "metadata" not in data or not isinstance(data["metadata"], dict):
        data["metadata"] = {}
    data["metadata"]["updated_at"] = datetime.now(timezone.utc).isoformat()
    data["metadata"]["total_channels"] = len(all_channels)
    data["metadata"]["working_channels"] = sum(1 for c in all_channels if c.get("enabled", True))


def main():
    parser = argparse.ArgumentParser(
        description="Comprobar estado de canales AceStream (sintaxis y comprobación en vivo ALIVE/DEAD)."
    )
    parser.add_argument("--input", default="data/channels.json", help="Ruta al catálogo JSON de canales.")
    parser.add_argument("--id", help="Probar un hash o enlace acestream:// individual directamente.")
    parser.add_argument("--live", action="store_true", help="Comprobar en vivo el estado (ALIVE/DEAD) con AceStream Engine.")
    parser.add_argument("--timeout", type=float, default=6.0, help="Timeout en segundos por stream (default: 6.0s).")
    parser.add_argument("--workers", type=int, default=4, help="Hilos concurrentes para la prueba en vivo (default: 4).")
    parser.add_argument("--limit", type=int, default=None, help="Limitar número de canales a comprobar.")
    parser.add_argument("--host", default="127.0.0.1", help="Host del AceStream Engine (default: 127.0.0.1).")
    parser.add_argument("--port", type=int, default=6878, help="Puerto HTTP del AceStream Engine (default: 6878).")
    parser.add_argument("--update-catalog", action="store_true", help="Actualizar enabled=True/False en channels.json según el resultado.")
    args = parser.parse_args()

    # Comprobación de un único ID si se pasó por CLI
    if args.id:
        print(f"Probando stream individual: {args.id} en {args.host}:{args.port} (Timeout: {args.timeout}s)...")
        alive, elapsed, err = check_stream_alive(args.id, host=args.host, port=args.port, timeout=args.timeout)
        if alive:
            print(f"🟢 [ALIVE] El stream responde correctamente y emite datos en {elapsed:.2f} segundos.")
        else:
            print(f"🔴 [DEAD] El stream no está disponible: {err} ({elapsed:.2f}s).")
        return

    base_dir = Path(__file__).resolve().parent.parent
    input_file = base_dir / args.input

    if not input_file.exists():
        print(f"[ERROR] No se encontró: {input_file}")
        return

    data = load_channels(input_file)
    channels = data.get("channels", [])

    print("=" * 65)
    print(" 📡 COMPROBADOR DE ESTADO DE STREAMS ACESTREAM")
    print("=" * 65)

    engine_online = check_engine_status(args.host, args.port)
    engine_status_str = f"🟢 ACTIVO ({args.host}:{args.port})" if engine_online else f"🔴 INACTIVO ({args.host}:{args.port})"
    print(f"Estado AceStream Engine: {engine_status_str}")
    print("-" * 65)

    if args.limit and args.limit > 0:
        channels = channels[:args.limit]
        print(f"🔬 Filtro --limit activo: comprobando los primeros {len(channels)} canales.")

    # 1. Validación de formato
    results = validate_catalog(channels)
    invalid = [r for r in results if not r["valid_format"]]
    print(f"Total canales analizados en catálogo: {len(results)}")
    if invalid:
        print(f"⚠️ {len(invalid)} canales con formato incorrecto o duplicados.")
    else:
        print("✅ Todos los canales analizados tienen sintaxis SHA-1 correcta.")

    # 2. Comprobación en vivo si se especificó --live
    if args.live:
        if not engine_online:
            print("\n❌ AceStream Engine no está activo. Inicia Ace Stream para realizar la comprobación en vivo.")
            return

        live_results = check_streams_concurrent(
            channels,
            host=args.host,
            port=args.port,
            timeout=args.timeout,
            max_workers=args.workers
        )

        if args.update_catalog:
            apply_live_results_to_catalog(data, live_results)
            with open(input_file, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2, ensure_ascii=False)
            print(f"\n💾 Catálogo actualizado en {input_file}.")

    print("=" * 65)


if __name__ == "__main__":
    main()

