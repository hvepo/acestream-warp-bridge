#!/usr/bin/env python3
"""
Evaluador de fuentes web y validador de streams AceStream.
Rastrea sitios web, portales, pastes y listas M3U remotas,
valida el estado en vivo de los canales mediante AceStream Engine,
actualiza el catálogo JSON y compila las listas M3U maestras.
"""

import sys
import re
import json
import time
import ssl
import argparse
from datetime import datetime, timezone
from functools import lru_cache
from pathlib import Path
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple, Set
from collections import Counter
import urllib.request
import urllib.error
import urllib.parse
from html.parser import HTMLParser
from concurrent.futures import ThreadPoolExecutor, as_completed

# Configurar codificación UTF-8 para salida estándar en Windows si es necesario
if sys.stdout and hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
if sys.stderr and hasattr(sys.stderr, "reconfigure"):
    try:
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

# Expresiones regulares precompiladas para detección de hashes y enlaces AceStream
HEX_SHA1_PATTERN = re.compile(r"^[a-fA-F0-9]{40}$")
ACESTREAM_SCHEME_REGEX = re.compile(r"acestream://([a-fA-F0-9]{40})", re.IGNORECASE)
HTTP_ACE_REGEX = re.compile(r"https?://[^/]+/ace/(?:getstream|manifest\.m3u8)\?id=([a-fA-F0-9]{40})", re.IGNORECASE)
GENERIC_ID_REGEX = re.compile(r"[?&]id=([a-fA-F0-9]{40})", re.IGNORECASE)
BARE_HASH_REGEX = re.compile(r"\b([a-fA-F0-9]{40})\b")
SLUG_CLEAN_REGEX = re.compile(r"[^a-zA-Z0-9]+")
WHITESPACE_REGEX = re.compile(r"\s+")
NATURAL_SORT_REGEX = re.compile(r"(\d+)")
WORD_TOKEN_REGEX = re.compile(r"[a-záéíóúñ]{3,}")

# Expresiones regulares precompiladas para extracción de M3U (#EXTINF)
EXTINF_TVG_NAME_REGEX = re.compile(r'tvg-name="([^"]+)"')
EXTINF_GROUP_REGEX = re.compile(r'group-title="([^"]+)"')
EXTINF_LOGO_REGEX = re.compile(r'tvg-logo="([^"]+)"')
EXTINF_TVG_ID_REGEX = re.compile(r'tvg-id="([^"]+)"')

# Expresiones regulares precompiladas para acestreamid.com
ACESTREAMID_LI_REGEX = re.compile(
    r'<li[^>]*class=["\'][^"\']*acestreamidID[^"\']*["\'][^>]*>(.*?)</li>',
    re.DOTALL | re.IGNORECASE
)
ACESTREAMID_TITLE_PATTERNS = (
    re.compile(r'title=["\']([^"\']+)["\'][^>]*href=["\']/channel/', re.IGNORECASE),
    re.compile(r'href=["\']/channel/[^"\']*["\'][^>]*title=["\']([^"\']+)["\']', re.IGNORECASE),
    re.compile(r'href=["\']/channel/[^"\']*["\']>([^<]+)</a>', re.IGNORECASE),
    re.compile(r'class=["\'][^"\']*col_title[^"\']*["\'][^>]*>.*?<a[^>]*>([^<]+)</a>', re.DOTALL | re.IGNORECASE),
)

# Expresiones regulares precompiladas para normalización y limpieza de nombres
NORM_SYMBOLS_REGEX = re.compile(r"[^\w\s\+\.\-]")
NORM_1080_REGEX = re.compile(r"\b1080\b")
NORM_720_REGEX = re.compile(r"\b720\b")
NORM_MOVISTAR_REGEX = re.compile(r"\bmovistar\+\b")
NORM_M_DOT_REGEX = re.compile(r"\bm\.\s*")
NORM_TRAILING_REGEX = re.compile(r"[\s*\-_]+$")

CLEAN_URL_REGEX = re.compile(r"https?://\S+")
CLEAN_ARROW_REGEX = re.compile(r"-->.*$")
CLEAN_SHICKAT_REGEX = re.compile(r"\|\s*shickat.*$", re.IGNORECASE)
CLEAN_DOMAINS_REGEX = re.compile(r"\b(elcano\.top|zeronet|ipfs|ipns)\b", re.IGNORECASE)
CLEAN_OPTION_PIPE_REGEX = re.compile(r"\|\s*option\s*\d+", re.IGNORECASE)
CLEAN_NUM_OPCION_REGEX = re.compile(r"\(?\b\d+\s*opci[oó]n\b\)?", re.IGNORECASE)
CLEAN_OPCION_NUM_REGEX = re.compile(r"\(?\b(?:opci[oó]n|option)\s*\d+\)?", re.IGNORECASE)
CLEAN_M_DOT_PREFIX_REGEX = re.compile(r"^M\.\s+", re.IGNORECASE)
CLEAN_1080P_REGEX = re.compile(r"\b1080[pP]?\b")
CLEAN_720P_REGEX = re.compile(r"\b720[pP]?\b")
CLEAN_TRAILING_DECOR_REGEX = re.compile(r"[\s*\-_|]+$")

# Contexto SSL compartido en memoria para evitar recrear certificados del sistema en cada petición
_SHARED_SSL_CTX = ssl.create_default_context()
_SHARED_SSL_CTX.check_hostname = False
_SHARED_SSL_CTX.verify_mode = ssl.CERT_NONE

# Cabecera HTTP estándar para evitar bloqueos por User-Agent genérico
DEFAULT_USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"


@dataclass
class SourceConfig:
    id: str
    name: str
    url: str
    type: str = "auto"
    enabled: bool = True
    category_fallback: str = "General"
    headers: Dict[str, str] = field(default_factory=dict)
    notes: str = ""


@dataclass
class ChannelItem:
    acestream_id: str
    name: str
    category: str = "General"
    logo: str = ""
    tvg_id: str = ""
    source: str = ""
    is_online: Optional[bool] = None
    response_time: float = 0.0
    error_msg: str = ""

    def get_slug(self) -> str:
        clean = SLUG_CLEAN_REGEX.sub("-", self.name.lower()).strip("-")
        return clean or "channel"


class HTMLTableAndLinkParser(HTMLParser):
    """Parser HTML para extraer enlaces y pares (Nombre, Hash) en tablas o etiquetas de texto."""

    def __init__(self):
        super().__init__()
        self.extracted_items: List[Tuple[str, str]] = []  # List of (name, acestream_id)
        self.in_table = False
        self.current_row: List[str] = []
        self.current_cell: List[str] = []
        self.current_link_href: Optional[str] = None
        self.current_link_text: List[str] = []

    def handle_starttag(self, tag, attrs):
        if tag == "table":
            self.in_table = True
        elif tag == "tr" and self.in_table:
            self.current_row = []
        elif tag in ("td", "th") and self.in_table:
            self.current_cell = []
        elif tag == "a":
            for k, v in attrs:
                if v and k.lower() == "href":
                    href_lower = v.lower()
                    if "acestream://" in href_lower or "id=" in href_lower:
                        self.current_link_href = v
                        self.current_link_text = []
                    break

    def handle_data(self, data):
        text = data.strip()
        if not text:
            return
        if self.in_table and self.current_cell is not None:
            self.current_cell.append(text)
        if self.current_link_href is not None:
            self.current_link_text.append(text)

    def handle_endtag(self, tag):
        if tag in ("td", "th") and self.in_table:
            cell_content = " ".join(self.current_cell).strip()
            self.current_row.append(cell_content)
            self.current_cell = []
        elif tag == "tr" and self.in_table:
            if len(self.current_row) >= 2:
                row_hashes = []
                non_hash_texts = []
                for cell in self.current_row:
                    cell_s = cell.strip()
                    if len(cell_s) == 40 and HEX_SHA1_PATTERN.match(cell_s):
                        row_hashes.append(cell_s)
                    elif cell_s:
                        h_match = BARE_HASH_REGEX.search(cell_s)
                        if h_match and len(cell_s) == 40:
                            row_hashes.append(h_match.group(1))
                        else:
                            non_hash_texts.append(cell_s)

                if row_hashes and non_hash_texts:
                    ch_name = " - ".join(non_hash_texts)
                    self.extracted_items.append((ch_name, row_hashes[0]))
            self.current_row = []
        elif tag == "table":
            self.in_table = False
        elif tag == "a" and self.current_link_href is not None:
            href = self.current_link_href
            link_name = " ".join(self.current_link_text).strip()
            m_ace = ACESTREAM_SCHEME_REGEX.search(href)
            if m_ace:
                self.extracted_items.append((link_name or "AceStream Channel", m_ace.group(1)))
            else:
                m_id = GENERIC_ID_REGEX.search(href)
                if m_id:
                    self.extracted_items.append((link_name or "AceStream Channel", m_id.group(1)))
            self.current_link_href = None
            self.current_link_text = []


_LALIGA_KEYWORDS = ("laliga", "la liga", "smartbank", "hypermotion")
_CHAMPIONS_KEYWORDS = ("campeones", "champions")
_SPORTS_KEYWORDS = (
    "deportes", "sport", "eurosport", "golf", "f1", "formula 1",
    "motogp", "vamos", "tdp", "teledeporte", "nba", "tennis", "tenis",
    "futbol", "football", "bundesliga", "premier", "serie a", "ligue 1"
)
_CINEMA_KEYWORDS = ("cine", "pelicula", "hollywood", "action", "series", "estrenos")
_GENERAL_KEYWORDS = ("la 1", "la 2", "antena 3", "cuatro", "telecinco", "la sexta", "tve")


@lru_cache(maxsize=4096)
def deduce_category(name: str, fallback: str = "General") -> str:
    """Clasifica automáticamente un canal según palabras clave en su nombre."""
    name_lower = name.lower()
    if any(k in name_lower for k in _LALIGA_KEYWORDS):
        return "LaLiga"
    if any(k in name_lower for k in _CHAMPIONS_KEYWORDS):
        return "Champions"
    if "dazn" in name_lower:
        return "DAZN"
    if "nba" in name_lower:
        return "NBA"
    if any(k in name_lower for k in ("tennis", "tenis", "atp")):
        return "TENNIS"
    if any(k in name_lower for k in ("baloncesto", "basquet", "basket")):
        return "BALONCESTO"
    if any(k in name_lower for k in _SPORTS_KEYWORDS):
        return "Sports"
    if any(k in name_lower for k in _CINEMA_KEYWORDS):
        return "Cinema"
    if any(k in name_lower for k in _GENERAL_KEYWORDS):
        return "General"
    return fallback or "General"


def extract_channels_from_acestreamid(
    content: str,
    source_name: str = "acestreamid.com",
    category_fallback: str = "Sports"
) -> List[ChannelItem]:
    """
    Extrae canales desde el HTML de acestreamid.com (portada, resultados de búsqueda o fichas).
    Identifica elementos acestreamidID y extrae con precisión el título y el hash SHA-1.
    """
    channels: List[ChannelItem] = []
    for match in ACESTREAMID_LI_REGEX.finditer(content):
        it = match.group(1)
        ch_name = ""
        for pat in ACESTREAMID_TITLE_PATTERNS:
            title_m = pat.search(it)
            if title_m:
                ch_name = title_m.group(1).strip()
                break

        h_m = ACESTREAM_SCHEME_REGEX.search(it) or BARE_HASH_REGEX.search(it)
        if h_m:
            cid = h_m.group(1).lower()
            if HEX_SHA1_PATTERN.match(cid):
                display_name = clean_display_name(ch_name) if ch_name else f"Stream {cid[:8]}"
                channels.append(ChannelItem(
                    acestream_id=cid,
                    name=display_name,
                    category=deduce_category(display_name, category_fallback),
                    source=source_name
                ))

    return deduplicate_by_hash(channels)


def fetch_source_content(url: str, custom_headers: Optional[Dict[str, str]] = None, timeout: float = 12.0) -> str:
    """Descarga contenido de una URL web o lee un archivo local si es una ruta en disco."""
    if not url.startswith(("http://", "https://")):
        local_path = Path(url)
        downloads_dir = Path.home() / "Downloads"
        if not local_path.is_absolute() and (downloads_dir / local_path.name).exists():
            dl_file = downloads_dir / local_path.name
            if not local_path.exists() or dl_file.stat().st_mtime > local_path.stat().st_mtime:
                try:
                    local_path.parent.mkdir(parents=True, exist_ok=True)
                    local_path.write_bytes(dl_file.read_bytes())
                    print(f"   ℹ️ Detectado archivo descargado más reciente en Descargas: {dl_file} -> {local_path}")
                except Exception:
                    pass

        if local_path.exists() and local_path.is_file():
            return local_path.read_text(encoding="utf-8", errors="replace")

    headers = {"User-Agent": DEFAULT_USER_AGENT, "Accept": "*/*"}
    if custom_headers:
        headers.update(custom_headers)

    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=timeout, context=_SHARED_SSL_CTX) as resp:
        charset = resp.headers.get_content_charset() or "utf-8"
        raw_bytes = resp.read()
        try:
            return raw_bytes.decode(charset)
        except Exception:
            return raw_bytes.decode("utf-8", errors="replace")


def extract_channels_from_content(content: str, source_meta: SourceConfig) -> List[ChannelItem]:
    """Extrae canales desde M3U, HTML, JSON o texto plano según formato detectado."""
    channels: List[ChannelItem] = []
    content_stripped = content.strip()
    if not content_stripped:
        return channels

    content_lower = content_stripped[:4096].lower()

    # 1. Detección de formato específico de tarjetas AceStreamID (acestreamid.com)
    if "acestreamidid" in content_lower or "acestreamid.com" in content_lower or "acestreamidID" in content:
        extracted_ace = extract_channels_from_acestreamid(
            content,
            source_name=source_meta.name,
            category_fallback=source_meta.category_fallback
        )
        if extracted_ace:
            return extracted_ace

    # 2. Detección de formato JSON
    if source_meta.type == "json" or (source_meta.type == "auto" and content_stripped[0] in ("{", "[")):
        try:
            parsed = json.loads(content_stripped)
            items = []
            if isinstance(parsed, dict):
                items = parsed.get("channels") or parsed.get("hashes") or []
            elif isinstance(parsed, list):
                items = parsed
            for item in items:
                if not isinstance(item, dict):
                    continue
                cid = item.get("acestream_id") or item.get("id") or item.get("hash") or ""
                if cid and len(cid) == 40 and HEX_SHA1_PATTERN.match(cid):
                    if item.get("name"):
                        name = item.get("name")
                    elif item.get("title"):
                        name = clean_display_name(item.get("title"))
                    else:
                        name = "AceStream Channel"
                    group = item.get("group") or ""
                    cat = item.get("category") or (deduce_category(group) if group else deduce_category(name, source_meta.category_fallback))
                    channels.append(ChannelItem(
                        acestream_id=cid.lower(),
                        name=name,
                        category=cat,
                        logo=item.get("logo", ""),
                        tvg_id=item.get("tvg_id", ""),
                        source=source_meta.name
                    ))
            if channels:
                return channels
        except Exception:
            pass

    # 3. Detección de formato M3U / M3U8
    if source_meta.type == "m3u" or (source_meta.type == "auto" and "#extm3u" in content_lower):
        curr_name = ""
        curr_group = source_meta.category_fallback
        curr_logo = ""
        curr_tvg_id = ""

        for raw_line in content.splitlines():
            line = raw_line.strip()
            if not line:
                continue
            if line.startswith("#EXTINF:"):
                m_group = EXTINF_GROUP_REGEX.search(line)
                curr_group = m_group.group(1) if m_group else source_meta.category_fallback
                m_logo = EXTINF_LOGO_REGEX.search(line)
                curr_logo = m_logo.group(1) if m_logo else ""
                m_tvg = EXTINF_TVG_ID_REGEX.search(line)
                curr_tvg_id = m_tvg.group(1) if m_tvg else ""

                if "," in line:
                    curr_name = line.split(",", 1)[-1].strip()
                else:
                    m_tvg_name = EXTINF_TVG_NAME_REGEX.search(line)
                    curr_name = m_tvg_name.group(1).strip() if m_tvg_name else "AceStream Channel"
            elif not line.startswith("#"):
                cid = None
                if len(line) == 40 and HEX_SHA1_PATTERN.match(line):
                    cid = line
                else:
                    m_ace = ACESTREAM_SCHEME_REGEX.search(line) or GENERIC_ID_REGEX.search(line)
                    if m_ace:
                        cid = m_ace.group(1)

                if cid and HEX_SHA1_PATTERN.match(cid):
                    name_val = curr_name or "AceStream Channel"
                    channels.append(ChannelItem(
                        acestream_id=cid.lower(),
                        name=name_val,
                        category=curr_group or deduce_category(name_val, source_meta.category_fallback),
                        logo=curr_logo,
                        tvg_id=curr_tvg_id,
                        source=source_meta.name
                    ))
                curr_name = ""
        if channels:
            return channels

    # 4. HTML parsing avanzado (Tablas y Enlaces)
    if "<html" in content_lower or "<table" in content_lower or "<a " in content_lower or "<a " in content:
        try:
            parser = HTMLTableAndLinkParser()
            parser.feed(content)
            for name, cid in parser.extracted_items:
                if HEX_SHA1_PATTERN.match(cid):
                    clean_name = WHITESPACE_REGEX.sub(" ", name).strip() or "AceStream Channel"
                    channels.append(ChannelItem(
                        acestream_id=cid.lower(),
                        name=clean_name,
                        category=deduce_category(clean_name, source_meta.category_fallback),
                        source=source_meta.name
                    ))
        except Exception:
            pass

    # 5. Extracción en una sola pasada por líneas para enlaces acestream:// y hashes SHA-1 en texto plano
    for raw_line in content.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue

        m_ace = ACESTREAM_SCHEME_REGEX.search(line)
        if m_ace:
            cid = m_ace.group(1).lower()
            cleaned = line.replace(m_ace.group(0), "").strip(" -:|,\t[]()")
            ch_name = cleaned if (cleaned and len(cleaned) < 50) else "AceStream Channel"
            channels.append(ChannelItem(
                acestream_id=cid,
                name=ch_name,
                category=deduce_category(ch_name, source_meta.category_fallback),
                source=source_meta.name
            ))
            continue

        h_match = BARE_HASH_REGEX.search(line)
        if h_match:
            cid = h_match.group(1).lower()
            remainder = line.replace(h_match.group(1), "").strip(" -:|,\t[]()")
            if remainder and len(remainder) < 50:
                channels.append(ChannelItem(
                    acestream_id=cid,
                    name=remainder,
                    category=deduce_category(remainder, source_meta.category_fallback),
                    source=source_meta.name
                ))

    return deduplicate_by_hash(channels)


GENERIC_KEYS = frozenset({
    "", "channel", "canal", "acestream", "acestream channel",
    "canal acestream", "stream", "live", "directo"
})


@lru_cache(maxsize=4096)
def normalize_channel_key(name: str) -> str:
    """
    Normaliza el nombre de un canal para identificar unívocamente canales idénticos
    procedentes de distintas fuentes o espejos (p. ej. 'DAZN 1 1080p **' vs 'DAZN 1 1080').
    """
    s = name.strip().lower()
    s = NORM_SYMBOLS_REGEX.sub("", s)
    s = NORM_1080_REGEX.sub("1080p", s)
    s = NORM_720_REGEX.sub("720p", s)
    s = NORM_MOVISTAR_REGEX.sub("m+", s)
    s = NORM_M_DOT_REGEX.sub("m+ ", s)
    s = NORM_TRAILING_REGEX.sub("", s)
    return WHITESPACE_REGEX.sub(" ", s).strip()


@lru_cache(maxsize=4096)
def clean_display_name(name: str) -> str:
    """
    Limpia el nombre para presentación final en M3U y catálogo,
    eliminando URLs, publicidad de proveedores, opciones previas y asteriscos.
    """
    s = name.strip()
    if "http" in s.lower():
        s = CLEAN_URL_REGEX.sub("", s)
    if "-->" in s:
        s = CLEAN_ARROW_REGEX.sub("", s)
    if "shickat" in s.lower():
        s = CLEAN_SHICKAT_REGEX.sub("", s)
    s = CLEAN_DOMAINS_REGEX.sub("", s)
    s = CLEAN_OPTION_PIPE_REGEX.sub("", s)
    s = CLEAN_NUM_OPCION_REGEX.sub("", s)
    s = CLEAN_OPCION_NUM_REGEX.sub("", s)
    if s[:2].lower() == "m.":
        s = CLEAN_M_DOT_PREFIX_REGEX.sub("M+ ", s)
    s = CLEAN_1080P_REGEX.sub("1080p", s)
    s = CLEAN_720P_REGEX.sub("720p", s)
    s = CLEAN_TRAILING_DECOR_REGEX.sub("", s).strip()
    return WHITESPACE_REGEX.sub(" ", s).strip()


@lru_cache(maxsize=4096)
def _natural_sort_tuple(s: str) -> tuple:
    return tuple(int(text) if text.isdigit() else text.lower() for text in NATURAL_SORT_REGEX.split(s))


def natural_sort_key(s: str) -> list:
    """Clave para ordenación alfabética natural (ej: 'Canal 2' antes de 'Canal 10')."""
    return list(_natural_sort_tuple(s))


def merge_channel_metadata(target: ChannelItem, candidate: ChannelItem) -> None:
    """
    Enriquece un canal con los metadatos más completos encontrados en otra fuente.
    """
    if not target.logo and candidate.logo:
        target.logo = candidate.logo
    if not target.tvg_id and candidate.tvg_id:
        target.tvg_id = candidate.tvg_id
    if (not target.category or target.category.lower() in ("general", "sports")) and candidate.category and candidate.category.lower() not in ("general", "sports"):
        target.category = candidate.category
    if target.name.lower().startswith("acestream channel") and not candidate.name.lower().startswith("acestream channel"):
        target.name = clean_display_name(candidate.name)


def deduplicate_by_hash(channels: List[ChannelItem]) -> List[ChannelItem]:
    """
    Deduplicación de nivel 1: garantiza unicidad estricta por acestream_id (hash SHA-1),
    fusionando metadatos de múltiples fuentes que compartan el mismo hash.
    """
    hash_map: Dict[str, ChannelItem] = {}
    for ch in channels:
        cid = ch.acestream_id.lower()
        if len(cid) != 40 or not HEX_SHA1_PATTERN.match(cid):
            continue
        existing = hash_map.get(cid)
        if existing is None:
            ch.acestream_id = cid
            ch.name = clean_display_name(ch.name)
            hash_map[cid] = ch
        else:
            merge_channel_metadata(existing, ch)
    return list(hash_map.values())


def _stream_priority(ch: ChannelItem) -> tuple:
    online_score = 2 if ch.is_online is True else (1 if ch.is_online is None else 0)
    speed_score = -ch.response_time if (ch.is_online and ch.response_time > 0) else -999.0
    logo_score = 10 if (ch.logo and ch.logo.startswith("http")) else 0
    tvg_score = 5 if ch.tvg_id else 0
    name_score = 0 if ch.name.lower().startswith("acestream channel") else 5
    src_lower = ch.source.lower()
    src_score = 3 if "m3u" in src_lower else (2 if "portal" in src_lower else 1)
    return (online_score, speed_score, logo_score + tvg_score + name_score, src_score)


def deduplicate_by_channel_name(
    channels: List[ChannelItem],
    keep_mirrors: bool = True
) -> List[ChannelItem]:
    """
    Agrupa canales por nombre normalizado.
    Si keep_mirrors=True (por defecto): numera los streams múltiples como '| Option 1', '| Option 2', etc.
    ordenándolos internamente por calidad (online > offline, menor latencia). Si el canal tiene una sola opción,
    conserva su nombre limpio sin sufijo.
    Si keep_mirrors=False: colapsa en un único canal ganador seleccionando el mejor stream.
    Finalmente, ordena toda la lista de canales alfabéticamente (ordenación natural A-Z).
    """
    groups: Dict[str, List[ChannelItem]] = {}
    generic_counter = 0

    for ch in channels:
        clean_name = clean_display_name(ch.name)
        ch.name = clean_name
        key = normalize_channel_key(clean_name)
        if not key or key in GENERIC_KEYS:
            generic_counter += 1
            key = f"__generic_{generic_counter}__"
        groups.setdefault(key, []).append(ch)

    deduped: List[ChannelItem] = []
    for items in groups.values():
        if len(items) == 1:
            items[0].name = clean_display_name(items[0].name)
            deduped.append(items[0])
            continue

        # Ordenar streams por prioridad decreciente
        items.sort(key=_stream_priority, reverse=True)

        # Extraer en O(K) los mejores metadatos compartidos del grupo (evita bucle anidado O(K^2))
        best_logo = next((c.logo for c in items if c.logo), "")
        best_tvg_id = next((c.tvg_id for c in items if c.tvg_id), "")
        best_cat = next(
            (c.category for c in items if c.category and c.category.lower() not in ("general", "sports")),
            items[0].category or "General"
        )

        if keep_mirrors:
            base_name = clean_display_name(items[0].name)
            for idx, item in enumerate(items, 1):
                item.name = f"{base_name} | Option {idx}"
                if not item.logo and best_logo:
                    item.logo = best_logo
                if not item.tvg_id and best_tvg_id:
                    item.tvg_id = best_tvg_id
                if (not item.category or item.category.lower() in ("general", "sports")) and best_cat:
                    item.category = best_cat
                deduped.append(item)
        else:
            winner = items[0]
            winner.name = clean_display_name(winner.name)
            for candidate in items[1:]:
                merge_channel_metadata(winner, candidate)
            deduped.append(winner)

    # Ordenar alfabéticamente de forma natural (A-Z) usando tupla cacheada
    deduped.sort(key=lambda ch: _natural_sort_tuple(ch.name))
    return deduped


CORE_SPORTS_KEYWORDS = (
    "laliga", "dazn", "movistar", "campeones", "vamos", "deportes",
    "eurosport", "motogp", "f1", "formula 1", "hypermotion", "golf",
    "baloncesto", "basquet", "basket", "nba", "atp", "tenis", "tennis",
    "ufc", "smartbank", "premier", "champions", "teledeporte", "tdp",
    "futbol", "bein", "sky", "liga", "sport"
)

# Palabras clave esenciales que siempre se incorporan en las búsquedas de fuentes
PERSISTENT_SEARCH_KEYWORDS = (
    "atp", "tenis", "tennis", "basquet", "nba"
)

STOPWORDS_KEYWORD_EXTRACTION = frozenset({
    "1080p", "1080", "720p", "720", "fhd", "uhd", "4k", "hevc", "h265", "h264",
    "50fps", "fps", "hd", "sd", "sat", "channel", "canal", "acestream", "stream",
    "live", "directo", "españa", "spain", "esp", "por", "para", "con", "sin",
    "the", "and", "top", "zeronet", "ipfs", "http", "https", "com", "org", "net",
    "bar", "multi", "audio", "multiaudio", "plus", "new", "era", "code", "opcion"
})


def extract_search_keywords_from_channels(
    channels: List[ChannelItem],
    max_keywords: int = 30,
    extra_keywords: Optional[List[str]] = None
) -> List[str]:
    """
    Extrae palabras clave de alto interés a partir de los canales obtenidos de fuentes principales.
    Identifica entidades deportivas reconocidas (p. ej. 'laliga', 'dazn', 'movistar', 'f1')
    y términos frecuentes para consultar el buscador search-ace.stream como complemento.
    """
    if not channels and not extra_keywords:
        return []

    names_text = " ".join(ch.name for ch in channels).lower()

    # 1. Palabras clave esenciales presentes en los nombres de canales
    active_keywords: List[str] = [
        kw for kw in CORE_SPORTS_KEYWORDS if kw in names_text
    ]
    seen_kw = set(active_keywords)

    # 2. Palabras clave prioritarias persistentes para búsqueda e incorporación de fuentes
    for pkw in PERSISTENT_SEARCH_KEYWORDS:
        if pkw not in seen_kw:
            active_keywords.append(pkw)
            seen_kw.add(pkw)

    # 3. Palabras frecuentes adicionales con al menos 3 caracteres
    tokens = WORD_TOKEN_REGEX.findall(names_text)
    freq = Counter(t for t in tokens if t not in STOPWORDS_KEYWORD_EXTRACTION)

    for word, count in freq.most_common(30):
        if word not in seen_kw and count >= 3:
            active_keywords.append(word)
            seen_kw.add(word)

    # 3. Incorporar keywords extras si se proporcionan
    if extra_keywords:
        for ek in extra_keywords:
            cleaned = ek.strip().lower()
            if cleaned and cleaned not in seen_kw:
                active_keywords.append(cleaned)
                seen_kw.add(cleaned)

    return active_keywords[:max_keywords]


def fetch_streams_for_single_keyword(keyword: str, timeout: float = 8.0) -> List[ChannelItem]:
    """Consulta la API de search-ace.stream para un término específico y extrae los canales devueltos."""
    encoded_query = urllib.parse.quote(keyword)
    url = f"https://search-ace.stream/search?query={encoded_query}"
    headers = {
        "User-Agent": DEFAULT_USER_AGENT,
        "Accept": "application/json"
    }
    channels: List[ChannelItem] = []
    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=timeout, context=_SHARED_SSL_CTX) as resp:
            data = resp.read().decode("utf-8", errors="replace")
            items = json.loads(data)
            if isinstance(items, list):
                for item in items:
                    if not isinstance(item, dict):
                        continue
                    cid = (item.get("content_id") or "").strip().lower()
                    if len(cid) == 40 and HEX_SHA1_PATTERN.match(cid):
                        raw_name = (item.get("name") or item.get("translated_name") or f"Stream {cid[:8]}").strip()
                        channels.append(ChannelItem(
                            acestream_id=cid,
                            name=raw_name,
                            category=deduce_category(raw_name, "Sports"),
                            source="search-ace.stream"
                        ))
    except Exception:
        pass
    return channels


def fetch_streams_from_acestreamid_keyword(keyword: str, timeout: float = 8.0) -> List[ChannelItem]:
    """Consulta el buscador de acestreamid.com para un término específico y extrae los canales devueltos."""
    encoded_query = urllib.parse.quote(keyword)
    url = f"https://acestreamid.com/search/?channel={encoded_query}"
    headers = {
        "User-Agent": DEFAULT_USER_AGENT,
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
    }
    channels: List[ChannelItem] = []
    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=timeout, context=_SHARED_SSL_CTX) as resp:
            charset = resp.headers.get_content_charset() or "utf-8"
            html = resp.read().decode(charset, errors="replace")
            channels = extract_channels_from_acestreamid(
                html,
                source_name="acestreamid.com",
                category_fallback="Sports"
            )
    except Exception:
        pass
    return channels


def fetch_streams_from_search_engines(
    keywords: List[str],
    engines: Optional[List[str]] = None,
    max_workers: int = 4,
    timeout: float = 8.0
) -> List[ChannelItem]:
    """
    Consulta en paralelo los motores de búsqueda configurados (search-ace.stream y/o acestreamid.com)
    para una lista de keywords de interés, devolviendo la lista deduplicada por hash de todos los canales encontrados.
    """
    if not keywords:
        return []

    if engines is None:
        engines = ["search-ace.stream", "acestreamid.com"]

    all_channels: List[ChannelItem] = []
    engines_str = ", ".join(engines)
    print(f"🔎 Consultando buscadores ({engines_str}) para {len(keywords)} keywords ({max_workers} hilos concurrentes)...")

    tasks: List[Tuple[str, str]] = [
        (kw, engine) for kw in keywords for engine in engines
    ]

    def _worker(kw: str, engine: str) -> Tuple[str, str, List[ChannelItem]]:
        if "acestreamid" in engine.lower():
            res = fetch_streams_from_acestreamid_keyword(kw, timeout=timeout)
        else:
            res = fetch_streams_for_single_keyword(kw, timeout=timeout)
        return kw, engine, res

    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        future_map = {
            executor.submit(_worker, kw, eng): (kw, eng)
            for kw, eng in tasks
        }
        for future in as_completed(future_map):
            kw, eng = future_map[future]
            try:
                _, _, results = future.result()
                if results:
                    all_channels.extend(results)
                    print(f"   • [{eng}] Keyword '{kw}': +{len(results)} streams encontrados")
                else:
                    print(f"   • [{eng}] Keyword '{kw}': 0 resultados")
            except Exception as e:
                print(f"   • [{eng}] Keyword '{kw}': error ({e})")

    deduped = deduplicate_by_hash(all_channels)
    print(f"   -> Total acumulado buscadores: {len(deduped)} streams únicos descubiertos.")
    return deduped


def fetch_streams_from_search_engine(
    keywords: List[str],
    max_workers: int = 4,
    timeout: float = 8.0
) -> List[ChannelItem]:
    """Compatibilidad con código anterior: consulta buscadores disponibles."""
    return fetch_streams_from_search_engines(
        keywords=keywords,
        engines=["search-ace.stream", "acestreamid.com"],
        max_workers=max_workers,
        timeout=timeout
    )


def check_engine_online(host: str = "127.0.0.1", port: int = 6878, timeout: float = 3.0) -> bool:
    """Verifica si AceStream Engine responde en la dirección local/remota indicada."""
    url = f"http://{host}:{port}/webui/api/service?method=get_version"
    headers = {"User-Agent": "AceStreamChecker/2.0", "Connection": "close"}
    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status == 200
    except Exception:
        fallback_url = f"http://{host}:{port}/"
        try:
            req = urllib.request.Request(fallback_url, headers=headers)
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return resp.status in (200, 403, 404)
        except Exception:
            return False


def probe_single_stream(acestream_id: str, host: str, port: int, timeout: float) -> Tuple[bool, float, str]:
    """
    Prueba si un stream tiene pares activos y emite datos en tiempo real.
    Devuelve (is_online, response_time_seconds, error_description).
    """
    clean_id = acestream_id.strip()
    if clean_id.lower().startswith("acestream://"):
        clean_id = clean_id[12:].strip()

    if len(clean_id) != 40 or not HEX_SHA1_PATTERN.match(clean_id):
        return False, 0.0, f"Hash no válido (esperados 40 caracteres hex, recibidos {len(clean_id)})"

    url = f"http://{host}:{port}/ace/getstream?id={clean_id}"
    req = urllib.request.Request(
        url,
        headers={"User-Agent": "VLC/3.0.18 LibVLC/3.0.18", "Connection": "close"}
    )
    start_time = time.perf_counter()

    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            if resp.status == 200:
                chunk = resp.read(1024)
                elapsed = time.perf_counter() - start_time
                if chunk:
                    return True, elapsed, ""
                return False, elapsed, "Respuesta vacía (0 bytes recibidos)"
            return False, time.perf_counter() - start_time, f"HTTP Status {resp.status}"
    except urllib.error.HTTPError as he:
        return False, time.perf_counter() - start_time, f"HTTP Error {he.code}"
    except (urllib.error.URLError, TimeoutError):
        return False, time.perf_counter() - start_time, "Timeout / Sin seeds activos"
    except Exception as e:
        return False, time.perf_counter() - start_time, str(e)


def validate_streams_concurrent(
    channels: List[ChannelItem],
    host: str,
    port: int,
    timeout: float,
    max_workers: int
) -> List[ChannelItem]:
    """Valida concurrentemente la lista de canales mediante ThreadPoolExecutor."""
    total = len(channels)
    if total == 0:
        return channels

    print(f"\n🔍 Iniciando validación activa de {total} streams en AceStream Engine (Timeout: {timeout}s, Hilos: {max_workers})...\n")

    completed = 0
    online_count = 0

    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        future_map = {
            executor.submit(probe_single_stream, ch.acestream_id, host, port, timeout): ch
            for ch in channels
        }

        for future in as_completed(future_map):
            ch = future_map[future]
            completed += 1
            try:
                is_online, elapsed, err = future.result()
            except Exception as exc:
                is_online, elapsed, err = False, 0.0, str(exc)

            ch.is_online = is_online
            ch.response_time = elapsed
            ch.error_msg = err

            if is_online:
                online_count += 1
                icon = "🟢 [ONLINE]"
                detail = f"{elapsed:.2f}s"
            else:
                icon = "🔴 [OFFLINE]"
                detail = err or "timeout"

            print(f"[{completed:02d}/{total:02d}] {icon} {ch.name} ({ch.acestream_id[:8]}...) -> {detail}")

    print(f"\n📊 Resultado de la comprobación: {online_count} online / {total - online_count} offline de {total} totales.")
    return channels


def render_m3u_content(
    channels: List[ChannelItem],
    mode: str = "direct",
    host: str = "127.0.0.1",
    port: int = 6878,
    network_caching: int = 3000
) -> str:
    """Construye en memoria el contenido M3U ordenado alfabéticamente de forma natural."""
    sorted_channels = sorted(channels, key=lambda ch: _natural_sort_tuple(ch.name or ""))
    lines = ['#EXTM3U x-tvg-url=""']

    is_vlc = mode == "vlc"
    is_direct = mode == "direct"
    is_hls = mode == "hls"
    vlc_opt_cache = f"#EXTVLCOPT:network-caching={network_caching}"
    vlc_opt_reconn = "#EXTVLCOPT:http-reconnect=true"
    base_getstream = f"http://{host}:{port}/ace/getstream?id="
    base_hls = f"http://{host}:{port}/ace/manifest.m3u8?id="

    for ch in sorted_channels:
        tvg_id = ch.tvg_id or ""
        logo = ch.logo or ""
        category = ch.category or "General"
        name = ch.name or "AceStream Channel"

        if logo:
            lines.append(f'#EXTINF:-1 tvg-id="{tvg_id}" tvg-name="{name}" tvg-logo="{logo}" group-title="{category}",{name}')
        else:
            lines.append(f'#EXTINF:-1 tvg-id="{tvg_id}" tvg-name="{name}" group-title="{category}",{name}')

        if is_vlc:
            lines.append(vlc_opt_cache)
            lines.append(vlc_opt_reconn)
            lines.append(f"{base_getstream}{ch.acestream_id}")
        elif is_direct:
            lines.append(f"acestream://{ch.acestream_id}")
        elif is_hls:
            lines.append(f"{base_hls}{ch.acestream_id}")
        else:
            lines.append(f"{base_getstream}{ch.acestream_id}")

    return "\n".join(lines) + "\n"


def generate_m3u_file(
    channels: List[ChannelItem],
    output_path: Path,
    mode: str = "direct",
    host: str = "127.0.0.1",
    port: int = 6878,
    network_caching: int = 3000
) -> None:
    """Genera un archivo M3U con formato estándar IPTV o compatible con VLC, ordenado alfabéticamente."""
    content = render_m3u_content(channels, mode=mode, host=host, port=port, network_caching=network_caching)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(content, encoding="utf-8")
    print(f"📁 Lista generada ({mode}): {output_path} ({len(channels)} canales)")


def _write_m3u_targets(
    channels: List[ChannelItem],
    output_paths: List[Path],
    mode: str = "direct",
    host: str = "127.0.0.1",
    port: int = 6878,
    network_caching: int = 3000
) -> None:
    """Renderiza una única vez el contenido M3U y lo escribe en múltiples destinos equivalentes."""
    content = render_m3u_content(channels, mode=mode, host=host, port=port, network_caching=network_caching)
    count = len(channels)
    for out_path in output_paths:
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(content, encoding="utf-8")
        print(f"📁 Lista generada ({mode}): {out_path} ({count} canales)")


def sync_with_catalog_json(
    channels: List[ChannelItem],
    catalog_path: Path,
    only_working: bool = False
) -> None:
    """Sincroniza y actualiza el archivo data/channels.json respetando su estructura y evitando duplicados de dirección acestream."""
    existing_data = {"metadata": {}, "channels": []}
    if catalog_path.exists():
        try:
            with open(catalog_path, "r", encoding="utf-8") as f:
                existing_data = json.load(f)
        except Exception as e:
            print(f"⚠️ Aviso al leer {catalog_path}: {e}")

    existing_channels_map = {
        ch.get("acestream_id", "").lower(): ch
        for ch in existing_data.get("channels", [])
        if "acestream_id" in ch and HEX_SHA1_PATTERN.match(ch.get("acestream_id", ""))
    }

    updated_channels_list = []
    seen_ids = set()

    for ch in channels:
        cid = ch.acestream_id.lower()
        if len(cid) != 40 or not HEX_SHA1_PATTERN.match(cid) or cid in seen_ids:
            continue
        seen_ids.add(cid)

        if cid in existing_channels_map:
            prev = existing_channels_map[cid]
            prev_name = clean_display_name(prev.get("name", ""))
            name = prev_name if prev_name and not prev_name.lower().startswith("acestream channel") else clean_display_name(ch.name)
            prev_cat = prev.get("category", "")
            cat = prev_cat if prev_cat and prev_cat.lower() not in ("general", "sports") else (ch.category or prev_cat or "General")
            logo = prev.get("logo") or ch.logo
            tvg_id = prev.get("tvg_id") or ch.tvg_id
            slug = prev.get("id") or ch.get_slug()
            notes = prev.get("notes", "")
        else:
            name = clean_display_name(ch.name)
            cat = ch.category
            logo = ch.logo
            tvg_id = ch.tvg_id
            slug = f"{ch.get_slug()}-{len(updated_channels_list) + 1}"
            notes = f"Descubierto desde fuente: {ch.source}"

        if ch.is_online is not None:
            enabled = ch.is_online
            if not enabled and ch.error_msg:
                notes = f"Inactivo: {ch.error_msg}"
        else:
            enabled = existing_channels_map.get(cid, {}).get("enabled", True)

        if only_working and not enabled:
            continue

        updated_channels_list.append({
            "id": slug,
            "name": name,
            "category": cat,
            "acestream_id": cid,
            "logo": logo,
            "tvg_id": tvg_id,
            "enabled": enabled,
            "notes": notes
        })

    # Conservar streams previos que no vinieron en la recolección actual si no están ya incluidos
    for cid, prev in existing_channels_map.items():
        if cid not in seen_ids:
            if only_working and not prev.get("enabled", True):
                continue
            seen_ids.add(cid)
            prev["name"] = clean_display_name(prev.get("name", ""))
            updated_channels_list.append(prev)

    # Ordenar la lista del catálogo alfabéticamente de forma natural
    updated_channels_list.sort(key=lambda ch: _natural_sort_tuple(ch.get("name", "")))

    existing_data["metadata"] = {
        "title": "AceStream Channel Catalog",
        "description": "Catálogo sincronizado y validado automáticamente (sin duplicados de streams Acestrem)",
        "updated_at": datetime.now(timezone.utc).isoformat(),
        "total_channels": len(updated_channels_list),
        "working_channels": sum(1 for c in updated_channels_list if c.get("enabled", True)),
        "version": "1.2.0"
    }
    existing_data["channels"] = updated_channels_list

    catalog_path.parent.mkdir(parents=True, exist_ok=True)
    with open(catalog_path, "w", encoding="utf-8") as f:
        json.dump(existing_data, f, indent=2, ensure_ascii=False)

    print(f"💾 Catálogo sincronizado en {catalog_path}: {len(updated_channels_list)} streams únicos registrados.")


def main():
    parser = argparse.ArgumentParser(
        description="Evaluar fuentes web de canales AceStream, validar funcionamiento y generar listas M3U."
    )
    parser.add_argument(
        "--sources",
        default="data/sources.json",
        help="Ruta al archivo JSON de fuentes configuradas (default: data/sources.json)"
    )
    parser.add_argument(
        "--url",
        action="append",
        dest="extra_urls",
        help="URL web adicional directa a evaluar (puede repetirse: --url URL1 --url URL2)"
    )
    parser.add_argument(
        "--probe",
        action="store_true",
        default=None,
        help="Forzar comprobación activa de streams en AceStream Engine"
    )
    parser.add_argument(
        "--skip-probe",
        action="store_true",
        help="Omitir comprobación activa en AceStream Engine (solo validar sintaxis SHA-1)"
    )
    parser.add_argument(
        "--host",
        default="127.0.0.1",
        help="Host del motor AceStream Engine (default: 127.0.0.1)"
    )
    parser.add_argument(
        "--port",
        type=int,
        default=6878,
        help="Puerto HTTP del motor AceStream Engine (default: 6878)"
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=6.0,
        help="Timeout en segundos por stream durante la prueba (default: 6.0s)"
    )
    parser.add_argument(
        "--workers",
        type=int,
        default=4,
        help="Hilos concurrentes para la prueba de streams (default: 4)"
    )
    parser.add_argument(
        "--sync-catalog",
        action="store_true",
        default=True,
        help="Sincronizar el catálogo data/channels.json (activado por defecto)"
    )
    parser.add_argument(
        "--no-sync-catalog",
        dest="sync_catalog",
        action="store_false",
        help="No modificar data/channels.json"
    )
    parser.add_argument(
        "--only-working",
        action="store_true",
        default=False,
        help="Filtrar todas las listas M3U para incluir únicamente canales verificados online (por defecto solo working_streams.m3u se filtra)"
    )
    parser.add_argument(
        "--dedupe-by-name",
        action="store_true",
        default=False,
        help="Colapsar streams de un mismo canal en uno solo (por defecto desactivado para mantener todos los streams/emisiones de cada canal)"
    )
    parser.add_argument(
        "--output-dir",
        default="playlists",
        help="Directorio donde se guardarán los archivos M3U (default: playlists)"
    )
    parser.add_argument(
        "--skip-search",
        action="store_true",
        help="Omitir búsqueda complementaria de streams en buscadores (search-ace.stream, acestreamid.com)"
    )
    parser.add_argument(
        "--search-engine",
        choices=["all", "acestreamid", "search-ace"],
        default="all",
        help="Motor de búsqueda a utilizar (default: all - consulta search-ace.stream y acestreamid.com)"
    )
    parser.add_argument(
        "--search-keywords",
        help="Keywords adicionales personalizadas separadas por coma para el buscador (ej: 'dazn,f1,movistar')"
    )
    parser.add_argument(
        "--max-keywords",
        type=int,
        default=30,
        help="Máximo número de keywords a consultar en search-ace.stream (default: 30)"
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Limitar el número de canales a procesar/probar (útil para pruebas rápidas)"
    )
    args = parser.parse_args()

    base_dir = Path(__file__).resolve().parent.parent
    sources_path = base_dir / args.sources
    output_dir = base_dir / args.output_dir
    catalog_path = base_dir / "data" / "channels.json"

    print("=" * 70)
    print(" 📡 EVALUADOR Y VALIDADOR DE CANALES ACESTREAM")
    print("=" * 70)

    # 1. Cargar fuentes
    sources: List[SourceConfig] = []
    if sources_path.exists():
        try:
            with open(sources_path, "r", encoding="utf-8") as f:
                data = json.load(f)
                for s in data.get("sources", []):
                    if s.get("enabled", True):
                        sources.append(SourceConfig(
                            id=s.get("id", f"source-{len(sources)+1}"),
                            name=s.get("name", "Fuente"),
                            url=s.get("url", ""),
                            type=s.get("type", "auto"),
                            enabled=s.get("enabled", True),
                            category_fallback=s.get("category_fallback", "General"),
                            headers=s.get("headers", {}),
                            notes=s.get("notes", "")
                        ))
        except Exception as e:
            print(f"[ERROR] Error al leer {sources_path}: {e}")

    # Añadir URLs pasadas por CLI
    if args.extra_urls:
        for idx, extra_url in enumerate(args.extra_urls, 1):
            sources.append(SourceConfig(
                id=f"cli-url-{idx}",
                name=f"URL CLI ({extra_url[:30]}...)",
                url=extra_url,
                type="auto",
                enabled=True,
                category_fallback="General"
            ))

    if not sources:
        print("[AVISO] No se han especificado fuentes habilitadas en data/sources.json ni mediante --url.")
        print("Ejemplo de uso: python scripts/evaluate_and_update.py --url https://miweb.com/canales")
        return

    print(f"Fuentes a evaluar ({len(sources)}):")
    for s in sources:
        print(f"  • {s.name} -> {s.url}")
    print("-" * 70)

    # 2. Extraer canales de cada fuente primaria concurrentemente manteniendo el orden determinista
    primary_sources = [s for s in sources if s.type != "search_engine"]
    all_extracted_channels: List[ChannelItem] = []

    def _fetch_and_extract_source(src: SourceConfig) -> List[ChannelItem]:
        target_url = src.url
        if not target_url.startswith(("http://", "https://")):
            target_url = str(base_dir / target_url)
        content = fetch_source_content(target_url, custom_headers=src.headers)
        return extract_channels_from_content(content, src)

    if primary_sources:
        max_src_workers = min(len(primary_sources), max(args.workers, 4))
        with ThreadPoolExecutor(max_workers=max_src_workers) as executor:
            future_by_idx = {
                idx: executor.submit(_fetch_and_extract_source, s)
                for idx, s in enumerate(primary_sources)
            }
            for idx, s in enumerate(primary_sources):
                print(f"\n🌐 Rastreador: procesando fuente '{s.name}'...")
                try:
                    extracted = future_by_idx[idx].result()
                    print(f"   -> Encontrados {len(extracted)} canales en esta fuente.")
                    all_extracted_channels.extend(extracted)
                except Exception as e:
                    print(f"   ⚠️ Error extrayendo de '{s.name}': {e}")

    # Deduplicación por dirección Acestrem (hash SHA-1)
    base_channels = deduplicate_by_hash(all_extracted_channels)
    print(f"\nCanales base con dirección única identificados: {len(base_channels)} (de {len(all_extracted_channels)} extraídos de fuentes primarias)")

    # 3. Buscadores complementarios (search-ace.stream y/o acestreamid.com) por keywords derivadas
    if not args.skip_search:
        engine_sources = [s for s in sources if s.type == "search_engine" and s.enabled]
        active_engines: List[str] = []

        if args.search_engine in ("all", "search-ace"):
            if not engine_sources or any("search-ace" in s.id.lower() or "search-ace" in s.url.lower() for s in engine_sources):
                active_engines.append("search-ace.stream")
        if args.search_engine in ("all", "acestreamid"):
            if not engine_sources or any("acestreamid" in s.id.lower() or "acestreamid" in s.url.lower() for s in engine_sources):
                active_engines.append("acestreamid.com")

        if not active_engines and engine_sources:
            active_engines = [s.name for s in engine_sources]

        extra_kws = [k.strip() for k in args.search_keywords.split(",") if k.strip()] if args.search_keywords else None
        keywords = extract_search_keywords_from_channels(
            base_channels,
            max_keywords=args.max_keywords,
            extra_keywords=extra_kws
        )
        if keywords and active_engines:
            print(f"\n🔎 Buscadores complementarios ({', '.join(active_engines)}):")
            print(f"   Keywords de interés derivadas ({len(keywords)}): {', '.join(keywords)}")
            search_streams = fetch_streams_from_search_engines(
                keywords,
                engines=active_engines,
                max_workers=min(args.workers, 4),
                timeout=min(args.timeout, 8.0)
            )
            if search_streams:
                all_extracted_channels.extend(search_streams)
                hash_unique_channels = deduplicate_by_hash(all_extracted_channels)
                print(f"   -> Catálogo total unificado con buscadores: {len(hash_unique_channels)} streams únicos")
            else:
                hash_unique_channels = base_channels
        else:
            hash_unique_channels = base_channels
    else:
        print("\n⏭️ Búsqueda complementaria en motores de búsqueda omitida por bandera --skip-search.")
        hash_unique_channels = base_channels

    if not hash_unique_channels:
        print("⚠️ No se encontraron canales con hashes válidos para procesar.")
        return

    if args.limit and args.limit > 0:
        hash_unique_channels = hash_unique_channels[:args.limit]
        print(f"🔬 Filtro --limit activo: evaluando los primeros {len(hash_unique_channels)} canales.")

    # 4. Comprobar disponibilidad de AceStream Engine
    engine_online = check_engine_online(args.host, args.port)
    engine_status_str = f"🟢 ONLINE ({args.host}:{args.port})" if engine_online else f"🔴 OFFLINE ({args.host}:{args.port})"
    print(f"Estado de AceStream Engine: {engine_status_str}")

    should_probe = False
    if args.skip_probe:
        print("⏭️ Comprobación activa de streams omitida por bandera --skip-probe.")
        should_probe = False
    elif args.probe is True:
        should_probe = True
    elif engine_online:
        should_probe = True
    else:
        print("⚠️ AceStream Engine no detectado en ejecución. Se omitirá el probing activo.")
        print("   (Para probar en vivo, asegúrate de que Ace Stream esté abierto en tu equipo).")
        should_probe = False

    if should_probe:
        probed_channels = validate_streams_concurrent(
            hash_unique_channels,
            host=args.host,
            port=args.port,
            timeout=args.timeout,
            max_workers=args.workers
        )
    else:
        probed_channels = hash_unique_channels

    # 5. Formatear canales con opciones (| Option 1, | Option 2, ...) y ordenación alfabética natural
    if args.dedupe_by_name:
        unique_channels = deduplicate_by_channel_name(probed_channels, keep_mirrors=False)
        removed_dups = len(probed_channels) - len(unique_channels)
        print(f"\n🧹 Deduplicación por nombre completada: {len(probed_channels)} streams consolidados en {len(unique_channels)} canales únicos ({removed_dups} emisiones espejo fusionadas).")
    else:
        unique_channels = deduplicate_by_channel_name(probed_channels, keep_mirrors=True)
        multi_count = sum(1 for ch in unique_channels if " | Option " in ch.name)
        print(f"\n✨ Canales formateados y ordenados alfabéticamente: {len(unique_channels)} streams organizados ({multi_count} opciones de canales alternativos numeradas).")

    working_channels = [ch for ch in unique_channels if ch.is_online] if should_probe else unique_channels
    if should_probe and not args.dedupe_by_name:
        working_channels = deduplicate_by_channel_name(working_channels, keep_mirrors=True)

    target_channels = working_channels if (args.only_working and should_probe) else unique_channels

    print("\n" + "=" * 70)
    print(" 📄 GENERACIÓN DE ARCHIVOS M3U (DEDUPLICADOS POR DIRECCIÓN ACESTREAM)")
    print("=" * 70)

    output_dir.mkdir(parents=True, exist_ok=True)

    # A & B) Listas maestras VLC (playlist.m3u y playlist_vlc.m3u) - renderizado único
    _write_m3u_targets(
        target_channels,
        [output_dir / "playlist.m3u", output_dir / "playlist_vlc.m3u"],
        mode="vlc",
        host=args.host,
        port=args.port
    )

    # C) Lista Proxy HTTP estándar IPTV
    generate_m3u_file(target_channels, output_dir / "playlist_http.m3u", mode="http", host=args.host, port=args.port)

    # D) Lista Directa (acestream://)
    generate_m3u_file(target_channels, output_dir / "playlist_direct.m3u", mode="direct")

    # E & G.1) Listas de canales activos/NOW en formato VLC - renderizado único
    _write_m3u_targets(
        working_channels,
        [
            output_dir / "working_streams.m3u",
            output_dir / "working_streams_NOW.m3u",
            output_dir / "working_streams_vlc_NOW.m3u",
            output_dir / "playlist_NOW.m3u",
        ],
        mode="vlc",
        host=args.host,
        port=args.port
    )

    # F & G.2) Listas de canales activos/NOW en formato directo (acestream://) - renderizado único
    _write_m3u_targets(
        working_channels,
        [
            output_dir / "working_streams_direct.m3u",
            output_dir / "working_streams_direct_NOW.m3u",
            output_dir / "playlist_direct_NOW.m3u",
        ],
        mode="direct"
    )

    # 6. Sincronizar catálogo data/channels.json
    if args.sync_catalog:
        print("-" * 70)
        sync_with_catalog_json(unique_channels, catalog_path, only_working=(args.only_working and should_probe))

    print("=" * 70)
    print("🎉 Proceso finalizado con éxito.")
    print("=" * 70)


if __name__ == "__main__":
    main()

