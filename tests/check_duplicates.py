#!/usr/bin/env python3
import json
import sys
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from scripts.evaluate_and_update import normalize_channel_key


def main() -> None:
    catalog_path = ROOT_DIR / "data" / "channels.json"
    with open(catalog_path, encoding="utf-8") as f:
        data = json.load(f)

    channels = data.get("channels", [])
    names = {}
    duplicates = []

    for ch in channels:
        raw_name = ch.get("name", "").strip()
        norm = normalize_channel_key(raw_name)
        if norm in names:
            duplicates.append((raw_name, ch["acestream_id"], names[norm]["name"], names[norm]["acestream_id"]))
        else:
            names[norm] = ch

    print("Total channels:", len(channels))
    print("Unique normalized names:", len(names))
    print("Duplicate names count:", len(duplicates))
    for d in duplicates:
        print(f"  Duplicado: '{d[0]}' ({d[1][:8]}...) vs '{d[2]}' ({d[3][:8]}...)")


if __name__ == "__main__":
    main()

