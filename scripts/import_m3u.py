#!/usr/bin/env python3
"""
Importa una lista M3U existente y la convierte al formato estructurado channels.json.
"""

import sys
import re
import json
from datetime import datetime, timezone
from pathlib import Path

try:
    from scripts.evaluate_and_update import (
        HEX_SHA1_PATTERN,
        EXTINF_GROUP_REGEX,
        EXTINF_TVG_ID_REGEX,
        EXTINF_LOGO_REGEX,
        EXTINF_TVG_NAME_REGEX,
        SLUG_CLEAN_REGEX,
        clean_display_name,
        deduce_category,
        _natural_sort_tuple,
    )
except ImportError:
    base_dir = Path(__file__).resolve().parent.parent
    if str(base_dir) not in sys.path:
        sys.path.insert(0, str(base_dir))
    from scripts.evaluate_and_update import (
        HEX_SHA1_PATTERN,
        EXTINF_GROUP_REGEX,
        EXTINF_TVG_ID_REGEX,
        EXTINF_LOGO_REGEX,
        EXTINF_TVG_NAME_REGEX,
        SLUG_CLEAN_REGEX,
        clean_display_name,
        deduce_category,
        _natural_sort_tuple,
    )

STREAM_ID_PARAM_REGEX = re.compile(r"id=([a-fA-F0-9]{40})", re.IGNORECASE)


def import_m3u(m3u_text: str, output_path: Path):
    channels = []
    seen_hashes = set()
    curr_name = ""
    curr_group = "General"
    curr_tvg_id = ""
    curr_logo = ""

    for raw_line in m3u_text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#EXTM3U"):
            continue

        if line.startswith("#EXTINF:"):
            m_group = EXTINF_GROUP_REGEX.search(line)
            curr_group = m_group.group(1) if m_group else "General"

            m_tvg = EXTINF_TVG_ID_REGEX.search(line)
            curr_tvg_id = m_tvg.group(1) if m_tvg else ""

            m_logo = EXTINF_LOGO_REGEX.search(line)
            curr_logo = m_logo.group(1) if m_logo else ""

            if "," in line:
                curr_name = line.split(",", 1)[-1].strip()
            else:
                m_tvg_name = EXTINF_TVG_NAME_REGEX.search(line)
                curr_name = m_tvg_name.group(1).strip() if m_tvg_name else "Canal Desconocido"
            continue

        if line.startswith("#"):
            continue

        cid = ""
        if line.lower().startswith("acestream://"):
            cid = line[12:].strip().lower()
        elif "id=" in line:
            m_id = STREAM_ID_PARAM_REGEX.search(line)
            if m_id:
                cid = m_id.group(1).lower()
        elif len(line) == 40 and HEX_SHA1_PATTERN.match(line):
            cid = line.lower()

        if cid and len(cid) == 40 and HEX_SHA1_PATTERN.match(cid) and cid not in seen_hashes:
            seen_hashes.add(cid)
            clean_name = clean_display_name(curr_name or "Canal Desconocido")
            slug = SLUG_CLEAN_REGEX.sub("-", clean_name.lower()).strip("-") or "channel"
            category = curr_group if curr_group and curr_group != "General" else deduce_category(clean_name, "General")
            channels.append({
                "id": f"{slug}-{len(channels) + 1}",
                "name": clean_name,
                "category": category,
                "acestream_id": cid,
                "logo": curr_logo,
                "tvg_id": curr_tvg_id,
                "enabled": True,
                "notes": ""
            })
            curr_name = ""

    channels.sort(key=lambda ch: _natural_sort_tuple(ch.get("name", "")))

    out_data = {
        "metadata": {
            "title": "AceStream Channel Catalog",
            "description": "Catálogo importado y organizado de AceStream_hector",
            "updated_at": datetime.now(timezone.utc).isoformat(),
            "total_channels": len(channels),
            "working_channels": len(channels),
            "version": "1.2.0"
        },
        "channels": channels
    }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(out_data, f, indent=2, ensure_ascii=False)

    print(f"[OK] Importados {len(channels)} canales únicos en {output_path}")


if __name__ == "__main__":
    base_dir = Path(__file__).resolve().parent.parent
    if len(sys.argv) > 1:
        m3u_file = Path(sys.argv[1])
        text = m3u_file.read_text(encoding="utf-8")
    else:
        text = sys.stdin.read()

    output_json = base_dir / "data" / "channels.json"
    import_m3u(text, output_json)

