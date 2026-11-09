#!/usr/bin/env python3
"""
Suite de pruebas unitarias para el script de evaluación, extracción y validación de canales AceStream.
"""

import unittest
import json
import tempfile
import sys
from pathlib import Path

# Añadir directorio raíz al sys.path para importar scripts
ROOT_DIR = Path(__file__).resolve().parent.parent
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from scripts.evaluate_and_update import (
    deduce_category,
    extract_channels_from_content,
    extract_channels_from_acestreamid,
    generate_m3u_file,
    sync_with_catalog_json,
    normalize_channel_key,
    clean_display_name,
    merge_channel_metadata,
    deduplicate_by_hash,
    deduplicate_by_channel_name,
    extract_search_keywords_from_channels,
    fetch_streams_for_single_keyword,
    fetch_streams_from_acestreamid_keyword,
    fetch_streams_from_search_engines,
    HEX_SHA1_PATTERN,
    ChannelItem,
    SourceConfig
)


class TestAceStreamEvaluator(unittest.TestCase):

    def test_hex_sha1_pattern(self):
        valid_hash = "94d34491106e00394835c8cb68aa94481339b53f"
        invalid_short = "94d34491106e00394835c8cb68aa94481339b5"
        invalid_chars = "94d34491106e00394835c8cb68aa94481339b5zz"

        self.assertTrue(bool(HEX_SHA1_PATTERN.match(valid_hash)))
        self.assertFalse(bool(HEX_SHA1_PATTERN.match(invalid_short)))
        self.assertFalse(bool(HEX_SHA1_PATTERN.match(invalid_chars)))

    def test_deduce_category(self):
        self.assertEqual(deduce_category("M. LaLiga 1080P"), "LaLiga")
        self.assertEqual(deduce_category("DAZN 1 1080"), "DAZN")
        self.assertEqual(deduce_category("NBA ESPN 720p"), "NBA")
        self.assertEqual(deduce_category("ATP Tour 1080p"), "TENNIS")
        self.assertEqual(deduce_category("Sky Sport Tennis"), "TENNIS")
        self.assertEqual(deduce_category("Basquet Girona 720p"), "BALONCESTO")
        self.assertEqual(deduce_category("M.L. Campeones HD"), "Champions")
        self.assertEqual(deduce_category("Eurosport 1 1080"), "Sports")
        self.assertEqual(deduce_category("M. Deportes 2"), "Sports")
        self.assertEqual(deduce_category("Cine Acción"), "Cinema")
        self.assertEqual(deduce_category("La 1 TVE"), "General")
        self.assertEqual(deduce_category("Canal Desconocido", fallback="Otros"), "Otros")

    def test_extract_from_html_links(self):
        html = """
        <html>
        <body>
            <h1>Canales AceStream</h1>
            <a href="acestream://94d34491106e00394835c8cb68aa94481339b53f">M. LaLiga 1080P</a>
            <a href="http://127.0.0.1:6878/ace/getstream?id=7cf0086fa7d478f51dbba952865c79e66cb9add5">DAZN 1</a>
        </body>
        </html>
        """
        source = SourceConfig(id="test-html", name="Test HTML", url="test.html", type="html")
        channels = extract_channels_from_content(html, source)

        self.assertEqual(len(channels), 2)
        hashes = [c.acestream_id for c in channels]
        names = [c.name for c in channels]

        self.assertIn("94d34491106e00394835c8cb68aa94481339b53f", hashes)
        self.assertIn("7cf0086fa7d478f51dbba952865c79e66cb9add5", hashes)
        self.assertIn("M+ LaLiga 1080p", names)
        self.assertIn("DAZN 1", names)

    def test_extract_from_html_tables(self):
        html_table = """
        <table>
            <thead><tr><th>Canal</th><th>AceStream ID</th></tr></thead>
            <tbody>
                <tr><td>Eurosport 1</td><td>16ffa1713f42aa27317ee039a2bd0cdbc89a1580</td></tr>
                <tr><td>M. Deportes</td><td>55d4602cb22b0d8a33c10c2c2f42dae64a9e8895</td></tr>
            </tbody>
        </table>
        """
        source = SourceConfig(id="test-table", name="Test Table", url="table.html", type="auto")
        channels = extract_channels_from_content(html_table, source)

        self.assertGreaterEqual(len(channels), 2)
        hashes = [c.acestream_id for c in channels]
        self.assertIn("16ffa1713f42aa27317ee039a2bd0cdbc89a1580", hashes)
        self.assertIn("55d4602cb22b0d8a33c10c2c2f42dae64a9e8895", hashes)

    def test_extract_from_m3u(self):
        m3u = """#EXTM3U
#EXTINF:-1 tvg-id="laliga-1" tvg-name="M. LaLiga" group-title="LaLiga",M. LaLiga HD
acestream://94d34491106e00394835c8cb68aa94481339b53f
#EXTINF:-1 group-title="DAZN",DAZN F1 1080
http://127.0.0.1:6878/ace/getstream?id=71eef80158aa8b37f3dc59f6793c6696df9a2dfa
"""
        source = SourceConfig(id="test-m3u", name="Test M3U", url="test.m3u", type="m3u")
        channels = extract_channels_from_content(m3u, source)

        self.assertEqual(len(channels), 2)
        self.assertEqual(channels[0].name, "M. LaLiga HD")
        self.assertEqual(channels[0].category, "LaLiga")
        self.assertEqual(channels[0].acestream_id, "94d34491106e00394835c8cb68aa94481339b53f")
        self.assertEqual(channels[0].tvg_id, "laliga-1")

        self.assertEqual(channels[1].name, "DAZN F1 1080")
        self.assertEqual(channels[1].category, "DAZN")
        self.assertEqual(channels[1].acestream_id, "71eef80158aa8b37f3dc59f6793c6696df9a2dfa")

    def test_extract_from_plain_text(self):
        text = """
        Lista de canales de prueba:
        Partidazo: acestream://0a26e20f39845e928411e09a124374fccb6e1478
        EuroSport HD - 98784fa0714190de289f42eb5b84e405df7e685a
        """
        source = SourceConfig(id="test-text", name="Test Text", url="test.txt", type="text")
        channels = extract_channels_from_content(text, source)

        hashes = [c.acestream_id for c in channels]
        self.assertIn("0a26e20f39845e928411e09a124374fccb6e1478", hashes)
        self.assertIn("98784fa0714190de289f42eb5b84e405df7e685a", hashes)

    def test_extract_from_json(self):
        json_str = json.dumps({
            "channels": [
                {
                    "name": "M. LaLiga",
                    "category": "LaLiga",
                    "acestream_id": "94d34491106e00394835c8cb68aa94481339b53f"
                }
            ]
        })
        source = SourceConfig(id="test-json", name="Test JSON", url="test.json", type="json")
        channels = extract_channels_from_content(json_str, source)

        self.assertEqual(len(channels), 1)
        self.assertEqual(channels[0].name, "M. LaLiga")
        self.assertEqual(channels[0].acestream_id, "94d34491106e00394835c8cb68aa94481339b53f")

    def test_generate_m3u_file(self):
        channels = [
            ChannelItem(
                acestream_id="94d34491106e00394835c8cb68aa94481339b53f",
                name="M. LaLiga 1080P",
                category="LaLiga",
                tvg_id="laliga-1"
            )
        ]

        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            out_direct = tmp_path / "test_direct.m3u"
            out_http = tmp_path / "test_http.m3u"
            out_vlc = tmp_path / "test_vlc.m3u"

            generate_m3u_file(channels, out_direct, mode="direct")
            generate_m3u_file(channels, out_http, mode="http", host="127.0.0.1", port=6878)
            generate_m3u_file(channels, out_vlc, mode="vlc", host="127.0.0.1", port=6878)

            content_direct = out_direct.read_text(encoding="utf-8")
            content_http = out_http.read_text(encoding="utf-8")
            content_vlc = out_vlc.read_text(encoding="utf-8")

            self.assertIn("#EXTM3U", content_direct)
            self.assertIn("acestream://94d34491106e00394835c8cb68aa94481339b53f", content_direct)
            self.assertIn("group-title=\"LaLiga\"", content_direct)

            self.assertIn("#EXTM3U", content_http)
            self.assertIn("http://127.0.0.1:6878/ace/getstream?id=94d34491106e00394835c8cb68aa94481339b53f", content_http)

            self.assertIn("#EXTM3U", content_vlc)
            self.assertIn("#EXTVLCOPT:network-caching=3000", content_vlc)
            self.assertIn("#EXTVLCOPT:http-reconnect=true", content_vlc)
            self.assertIn("http://127.0.0.1:6878/ace/getstream?id=94d34491106e00394835c8cb68aa94481339b53f", content_vlc)

    def test_sync_with_catalog_json(self):
        channels = [
            ChannelItem(
                acestream_id="94d34491106e00394835c8cb68aa94481339b53f",
                name="M. LaLiga 1080P",
                category="LaLiga",
                is_online=True
            ),
            ChannelItem(
                acestream_id="1111111111111111111111111111111111111111",
                name="Canal Nuevo Online",
                category="General",
                is_online=True
            )
        ]

        with tempfile.TemporaryDirectory() as tmpdir:
            cat_file = Path(tmpdir) / "channels.json"
            # Crear catálogo base inicial
            init_data = {
                "metadata": {"title": "Test"},
                "channels": [
                    {
                        "id": "m-laliga-1",
                        "name": "M. LaLiga 1080P",
                        "category": "LaLiga",
                        "acestream_id": "94d34491106e00394835c8cb68aa94481339b53f",
                        "enabled": False,
                        "notes": "Anteriormente deshabilitado"
                    }
                ]
            }
            cat_file.write_text(json.dumps(init_data), encoding="utf-8")

            sync_with_catalog_json(channels, cat_file, only_working=False)

            with open(cat_file, "r", encoding="utf-8") as f:
                saved = json.load(f)

            self.assertIn("metadata", saved)
            self.assertEqual(len(saved["channels"]), 2)
            # El canal que estaba deshabilitado ahora debe estar enabled=True porque is_online=True
            ch_map = {c["acestream_id"]: c for c in saved["channels"]}
            self.assertTrue(ch_map["94d34491106e00394835c8cb68aa94481339b53f"]["enabled"])
            self.assertIn("1111111111111111111111111111111111111111", ch_map)

    def test_normalize_channel_key(self):
        # Múltiples formatos y espejos deben dar la misma clave normalizada
        self.assertEqual(normalize_channel_key("DAZN 1 1080p **"), "dazn 1 1080p")
        self.assertEqual(normalize_channel_key("DAZN 1 1080p *"), "dazn 1 1080p")
        self.assertEqual(normalize_channel_key("DAZN 1 1080"), "dazn 1 1080p")
        self.assertEqual(normalize_channel_key("M. LaLiga 1080P"), "m+ laliga 1080p")
        self.assertEqual(normalize_channel_key("M+ LaLiga 1080p **"), "m+ laliga 1080p")
        self.assertEqual(normalize_channel_key("UFC FIGHT PASS *"), "ufc fight pass")
        self.assertEqual(normalize_channel_key("Dazn MotoGP 1080p **"), "dazn motogp 1080p")

    def test_clean_display_name(self):
        self.assertEqual(clean_display_name("DAZN 1 1080p **"), "DAZN 1 1080p")
        self.assertEqual(clean_display_name("DAZN 1 1080p *"), "DAZN 1 1080p")
        self.assertEqual(clean_display_name("DAZN 1 1080"), "DAZN 1 1080p")
        self.assertEqual(clean_display_name("M. LaLiga 1080P"), "M+ LaLiga 1080p")
        self.assertEqual(clean_display_name("UFC FIGHT PASS *"), "UFC FIGHT PASS")

    def test_merge_channel_metadata(self):
        target = ChannelItem(
            acestream_id="94d34491106e00394835c8cb68aa94481339b53f",
            name="AceStream Channel",
            category="General",
            logo="",
            tvg_id=""
        )
        candidate = ChannelItem(
            acestream_id="94d34491106e00394835c8cb68aa94481339b53f",
            name="M+ LaLiga 1080p",
            category="LaLiga",
            logo="https://example.com/logo.png",
            tvg_id="laliga-1"
        )
        merge_channel_metadata(target, candidate)

        self.assertEqual(target.name, "M+ LaLiga 1080p")
        self.assertEqual(target.category, "LaLiga")
        self.assertEqual(target.logo, "https://example.com/logo.png")
        self.assertEqual(target.tvg_id, "laliga-1")

    def test_deduplicate_by_hash(self):
        # Dos fuentes con el mismo hash deben unificarse en 1 solo canal
        channels = [
            ChannelItem(
                acestream_id="94d34491106e00394835c8cb68aa94481339b53f",
                name="Canal Fuente 1",
                source="Fuente A"
            ),
            ChannelItem(
                acestream_id="94d34491106e00394835c8cb68aa94481339b53f",
                name="Canal Fuente 2",
                logo="http://logo.com/pic.png",
                source="Fuente B"
            )
        ]
        result = deduplicate_by_hash(channels)
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0].logo, "http://logo.com/pic.png")

    def test_deduplicate_by_channel_name_collapsing(self):
        # Dos emisiones del mismo canal con hashes distintos: debe prevalecer el que está online
        ch_offline = ChannelItem(
            acestream_id="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            name="DAZN 1 1080p *",
            is_online=False,
            source="Fuente Offline"
        )
        ch_online = ChannelItem(
            acestream_id="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            name="DAZN 1 1080p **",
            is_online=True,
            response_time=1.5,
            logo="http://dazn.com/logo.png",
            source="Fuente Online"
        )
        result = deduplicate_by_channel_name([ch_offline, ch_online], keep_mirrors=False)

        self.assertEqual(len(result), 1)
        # El stream online debe ser el ganador
        self.assertEqual(result[0].acestream_id, "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
        self.assertEqual(result[0].name, "DAZN 1 1080p")
        self.assertEqual(result[0].logo, "http://dazn.com/logo.png")
        self.assertTrue(result[0].is_online)

    def test_deduplicate_by_channel_name_keep_mirrors(self):
        ch1 = ChannelItem(
            acestream_id="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            name="DAZN 1 1080p *",
            source="Fuente 1"
        )
        ch2 = ChannelItem(
            acestream_id="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            name="DAZN 1 1080p **",
            source="Fuente 2"
        )
        ch_single = ChannelItem(
            acestream_id="cccccccccccccccccccccccccccccccccccccccc",
            name="DAZN 4",
            source="Fuente 3"
        )
        result = deduplicate_by_channel_name([ch1, ch2, ch_single], keep_mirrors=True)

        self.assertEqual(len(result), 3)
        # Múltiples opciones numeradas con '| Option X'
        self.assertEqual(result[0].name, "DAZN 1 1080p | Option 1")
        self.assertEqual(result[1].name, "DAZN 1 1080p | Option 2")
        # Canal individual sin número de opción
        self.assertEqual(result[2].name, "DAZN 4")

    def test_natural_alphabetical_sorting(self):
        ch_b = ChannelItem(acestream_id="1111111111111111111111111111111111111111", name="LaLiga TV 10")
        ch_a = ChannelItem(acestream_id="2222222222222222222222222222222222222222", name="LaLiga TV 2")
        ch_c = ChannelItem(acestream_id="3333333333333333333333333333333333333333", name="Canal Panda")

        sorted_res = deduplicate_by_channel_name([ch_b, ch_a, ch_c], keep_mirrors=True)
        names = [c.name for c in sorted_res]
        # Orden natural: Canal Panda -> LaLiga TV 2 -> LaLiga TV 10
        self.assertEqual(names, ["Canal Panda", "LaLiga TV 2", "LaLiga TV 10"])

    def test_sync_with_catalog_json_purges_duplicates(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            cat_file = Path(tmpdir) / "channels.json"
            init_data = {
                "metadata": {"title": "Test"},
                "channels": [
                    {
                        "id": "dazn-1-stream1",
                        "name": "DAZN 1 1080p *",
                        "category": "DAZN",
                        "acestream_id": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                        "enabled": True
                    },
                    {
                        "id": "dazn-1-stream2",
                        "name": "DAZN 1 1080p **",
                        "category": "DAZN",
                        "acestream_id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                        "enabled": True
                    },
                    {
                        "id": "invalid-hash",
                        "name": "Canal Invalido",
                        "acestream_id": "short-hash-123",
                        "enabled": False
                    }
                ]
            }
            cat_file.write_text(json.dumps(init_data), encoding="utf-8")

            # Entrada: re-enviamos el stream 1 (duplicado por hash) y un stream nuevo (distinto hash)
            new_channels = [
                ChannelItem(
                    acestream_id="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                    name="DAZN 1 1080p * (Actualizado)",
                    category="DAZN",
                    is_online=True
                ),
                ChannelItem(
                    acestream_id="cccccccccccccccccccccccccccccccccccccccc",
                    name="DAZN 1 1080p (Tercer Stream)",
                    category="DAZN",
                    is_online=True
                )
            ]

            sync_with_catalog_json(new_channels, cat_file)

            with open(cat_file, "r", encoding="utf-8") as f:
                saved = json.load(f)

            # Deben mantenerse los 3 streams distintos de DAZN 1 y eliminarse el hash duplicado y el inválido
            self.assertEqual(len(saved["channels"]), 3)
            ids = [c["acestream_id"] for c in saved["channels"]]
            self.assertIn("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", ids)
            self.assertIn("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", ids)
            self.assertIn("cccccccccccccccccccccccccccccccccccccccc", ids)
            self.assertNotIn("short-hash-123", ids)

    def test_extract_search_keywords_from_channels(self):
        channels = [
            ChannelItem(acestream_id="1" * 40, name="DAZN 1 1080p FHD"),
            ChannelItem(acestream_id="2" * 40, name="DAZN 2 1080p"),
            ChannelItem(acestream_id="3" * 40, name="Movistar LaLiga HD"),
            ChannelItem(acestream_id="4" * 40, name="#Vamos 1080p"),
            ChannelItem(acestream_id="5" * 40, name="Eurosport 1 Bar"),
            ChannelItem(acestream_id="6" * 40, name="Eurosport 2 Bar"),
            ChannelItem(acestream_id="7" * 40, name="NBA ESPN 720p"),
        ]
        kws = extract_search_keywords_from_channels(channels, max_keywords=15, extra_keywords=["motogp", "f1"])
        self.assertIn("dazn", kws)
        self.assertIn("laliga", kws)
        self.assertIn("vamos", kws)
        self.assertIn("eurosport", kws)
        self.assertIn("nba", kws)
        self.assertIn("atp", kws)
        self.assertIn("tenis", kws)
        self.assertIn("tennis", kws)
        self.assertIn("basquet", kws)
        self.assertIn("motogp", kws)
        self.assertIn("f1", kws)
        # Asegurar que se excluyeron stopwords como '1080p', 'fhd', 'bar'
        self.assertNotIn("1080p", kws)
        self.assertNotIn("fhd", kws)
        self.assertNotIn("bar", kws)

    def test_fetch_streams_for_single_keyword_mocked(self):
        from unittest.mock import patch, MagicMock
        fake_json = json.dumps([
            {
                "name": "DAZN 1 Bar FHD",
                "content_id": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                "pid": 1234
            },
            {
                "name": "Canal Invalido",
                "content_id": "short-hash",
                "pid": 5678
            }
        ]).encode("utf-8")

        mock_resp = MagicMock()
        mock_resp.read.return_value = fake_json
        mock_resp.__enter__.return_value = mock_resp

        with patch("urllib.request.urlopen", return_value=mock_resp):
            items = fetch_streams_for_single_keyword("dazn")
            self.assertEqual(len(items), 1)
            self.assertEqual(items[0].acestream_id, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
            self.assertEqual(items[0].source, "search-ace.stream")

    def test_extract_channels_from_acestreamid(self):
        sample_html = """
        <ul id="acestreamids" class="collection with-header">
            <li class="collection-item acestreamidID">
                <div class="row">
                    <div class="col m3 s12 col_title">
                        <a class="font-small grey-text truncate content" title="Movistar LaLiga 1 HD" href="/channel/movistar-laliga-1-hd">
                            Movistar LaLiga 1 HD
                        </a>
                    </div>
                    <div class="col m7 s12 col_id">
                        <div class="content wrap">
                            <a href="acestream://1111111111111111111111111111111111111111">
                                <i class="fa fa-dot-circle-o grey-text"></i>
                            </a>
                            1111111111111111111111111111111111111111
                        </div>
                    </div>
                </div>
            </li>
            <li class="collection-item acestreamidID">
                <div class="row">
                    <div class="col m3 s12 col_title">
                        <a class="font-small grey-text truncate content" title="Sky Sports F1" href="/channel/sky-sports-f1">
                            Sky Sports F1
                        </a>
                    </div>
                    <div class="col m7 s12 col_id">
                        <div class="content wrap">
                            <a href="acestream://2222222222222222222222222222222222222222"></a>
                        </div>
                    </div>
                </div>
            </li>
        </ul>
        """
        channels = extract_channels_from_acestreamid(sample_html, source_name="acestreamid.com")
        self.assertEqual(len(channels), 2)
        c1, c2 = channels[0], channels[1]
        self.assertEqual(c1.acestream_id, "1111111111111111111111111111111111111111")
        self.assertEqual(c1.name, "Movistar LaLiga 1 HD")
        self.assertEqual(c1.category, "LaLiga")
        self.assertEqual(c2.acestream_id, "2222222222222222222222222222222222222222")
        self.assertEqual(c2.name, "Sky Sports F1")
        self.assertEqual(c2.category, "Sports")

    def test_extract_channels_from_content_acestreamid(self):
        source = SourceConfig(
            id="acestreamid-test",
            name="acestreamid.com",
            url="https://acestreamid.com/",
            type="html"
        )
        sample_html = """
        <html><body>
            <li class="collection-item acestreamidID">
                <a href="/channel/dazn-f1" title="DAZN F1">DAZN F1</a>
                <a href="acestream://3333333333333333333333333333333333333333"></a>
            </li>
        </body></html>
        """
        extracted = extract_channels_from_content(sample_html, source)
        self.assertEqual(len(extracted), 1)
        self.assertEqual(extracted[0].name, "DAZN F1")
        self.assertEqual(extracted[0].category, "DAZN")
        self.assertEqual(extracted[0].acestream_id, "3333333333333333333333333333333333333333")

    def test_fetch_streams_from_acestreamid_keyword_mocked(self):
        from unittest.mock import patch, MagicMock
        fake_html = """
        <li class="collection-item acestreamidID">
            <a href="/channel/laliga-tv" title="LaLiga TV">LaLiga TV</a>
            <a href="acestream://4444444444444444444444444444444444444444"></a>
        </li>
        """.encode("utf-8")

        mock_resp = MagicMock()
        mock_resp.read.return_value = fake_html
        mock_resp.headers.get_content_charset.return_value = "utf-8"
        mock_resp.__enter__.return_value = mock_resp

        with patch("urllib.request.urlopen", return_value=mock_resp):
            items = fetch_streams_from_acestreamid_keyword("laliga")
            self.assertEqual(len(items), 1)
            self.assertEqual(items[0].acestream_id, "4444444444444444444444444444444444444444")
            self.assertEqual(items[0].source, "acestreamid.com")

    def test_fetch_streams_from_search_engines_mocked(self):
        from unittest.mock import patch
        item_ace = [ChannelItem(acestream_id="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", name="SearchAce Stream", category="Sports", source="search-ace.stream")]
        item_id = [ChannelItem(acestream_id="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", name="AceStreamID Stream", category="Sports", source="acestreamid.com")]

        with patch("scripts.evaluate_and_update.fetch_streams_for_single_keyword", return_value=item_ace), \
             patch("scripts.evaluate_and_update.fetch_streams_from_acestreamid_keyword", return_value=item_id):
            res = fetch_streams_from_search_engines(["f1"], engines=["search-ace.stream", "acestreamid.com"], max_workers=2)
            self.assertEqual(len(res), 2)
            ids = [ch.acestream_id for ch in res]
    def test_now_playlists_generation(self):
        online_channels = [
            ChannelItem(
                acestream_id="1111111111111111111111111111111111111111",
                name="DAZN F1 1080p",
                category="Sports",
                is_online=True
            ),
            ChannelItem(
                acestream_id="2222222222222222222222222222222222222222",
                name="M+ LaLiga 1080p",
                category="Sports",
                is_online=True
            )
        ]

        with tempfile.TemporaryDirectory() as tmpdir:
            out_dir = Path(tmpdir)
            out_vlc_now = out_dir / "working_streams_NOW.m3u"
            out_direct_now = out_dir / "working_streams_direct_NOW.m3u"

            generate_m3u_file(online_channels, out_vlc_now, mode="vlc", host="127.0.0.1", port=6878)
            generate_m3u_file(online_channels, out_direct_now, mode="direct")

            content_vlc = out_vlc_now.read_text(encoding="utf-8")
            content_direct = out_direct_now.read_text(encoding="utf-8")

            # Formato VLC con sufijo NOW
            self.assertIn("#EXTM3U", content_vlc)
            self.assertIn("#EXTVLCOPT:network-caching=3000", content_vlc)
            self.assertIn("#EXTVLCOPT:http-reconnect=true", content_vlc)
            self.assertIn("http://127.0.0.1:6878/ace/getstream?id=1111111111111111111111111111111111111111", content_vlc)

            # Formato Ace Player con sufijo NOW
            self.assertIn("#EXTM3U", content_direct)
            self.assertIn("acestream://1111111111111111111111111111111111111111", content_direct)
            self.assertIn("acestream://2222222222222222222222222222222222222222", content_direct)

    def test_check_streams_apply_live_results_to_catalog(self):
        from scripts.check_streams import apply_live_results_to_catalog, validate_catalog
        catalog_data = {
            "metadata": {"title": "Test"},
            "channels": [
                {
                    "id": "ch-1",
                    "name": "DAZN 1",
                    "acestream_id": "1111111111111111111111111111111111111111",
                    "enabled": True,
                    "is_alive": False,
                    "response_time": 6.0,
                    "error_msg": "Timeout"
                },
                {
                    "id": "ch-2",
                    "name": "DAZN 2",
                    "acestream_id": "2222222222222222222222222222222222222222",
                    "enabled": False,
                    "is_alive": True,
                    "response_time": 0.45,
                    "error_msg": ""
                }
            ]
        }
        val_res = validate_catalog(catalog_data["channels"])
        self.assertTrue(all(r["valid_format"] for r in val_res))

        apply_live_results_to_catalog(catalog_data, catalog_data["channels"])
        self.assertFalse(catalog_data["channels"][0]["enabled"])
        self.assertTrue(catalog_data["channels"][1]["enabled"])
        self.assertNotIn("is_alive", catalog_data["channels"][0])
        self.assertNotIn("response_time", catalog_data["channels"][0])
        self.assertEqual(catalog_data["metadata"]["working_channels"], 1)

    def test_build_playlist_pre_sorted_reuse(self):
        from scripts.build_playlist import prepare_channels_for_m3u, generate_m3u
        raw_data = {
            "channels": [
                {"name": "M. LaLiga 1080P *", "acestream_id": "1" * 40, "category": "LaLiga", "enabled": True},
                {"name": "M+ LaLiga 1080p **", "acestream_id": "2" * 40, "category": "LaLiga", "enabled": True},
                {"name": "Canal Deshabilitado", "acestream_id": "3" * 40, "category": "General", "enabled": False},
            ]
        }
        prepared = {
            "channels": prepare_channels_for_m3u(raw_data, only_enabled=True),
            "_pre_sorted": True
        }
        self.assertEqual(len(prepared["channels"]), 2)
        self.assertEqual(prepared["channels"][0]["name"], "M+ LaLiga 1080p | Option 1")
        self.assertEqual(prepared["channels"][1]["name"], "M+ LaLiga 1080p | Option 2")

        m3u_vlc = generate_m3u(prepared, mode="vlc")
        m3u_direct = generate_m3u(prepared, mode="direct")
        self.assertIn("#EXTVLCOPT:network-caching=3000", m3u_vlc)
        self.assertIn("acestream://" + ("1" * 40), m3u_direct)

    def test_import_m3u_deduplication_and_cleaning(self):
        from scripts.import_m3u import import_m3u
        sample_m3u = """#EXTM3U
#EXTINF:-1 tvg-id="dazn1" group-title="DAZN",DAZN 1 1080P **
acestream://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
#EXTINF:-1 tvg-id="dazn1" group-title="DAZN",DAZN 1 Duplicado
http://127.0.0.1:6878/ace/getstream?id=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
#EXTINF:-1 group-title="General",M. Deportes 1
acestream://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
"""
        with tempfile.TemporaryDirectory() as tmpdir:
            out_json = Path(tmpdir) / "channels.json"
            import_m3u(sample_m3u, out_json)
            saved = json.loads(out_json.read_text(encoding="utf-8"))
            self.assertEqual(len(saved["channels"]), 2)
            self.assertEqual(saved["channels"][0]["name"], "DAZN 1 1080p")
            self.assertEqual(saved["channels"][1]["name"], "M+ Deportes 1")
            self.assertEqual(saved["channels"][1]["category"], "Sports")


if __name__ == "__main__":
    unittest.main()
