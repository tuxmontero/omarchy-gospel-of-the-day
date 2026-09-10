#!/usr/bin/env python3

import datetime
import io
import json
import sys
import tempfile
import unittest
import urllib.error
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import evangelizo as ev

FIXTURES = Path(__file__).resolve().parent / "fixtures"


def fixture(name):
    return (FIXTURES / name).read_text(encoding="utf-8")


class FakeResponse:
    def __init__(self, body, url):
        self._body = body if isinstance(body, bytes) else body.encode("utf-8")
        self._url = url
        self._offset = 0

    def geturl(self):
        return self._url

    def read(self, size=-1):
        if self._offset >= len(self._body):
            return b""
        if size is None or size < 0:
            chunk = self._body[self._offset:]
            self._offset = len(self._body)
            return chunk
        chunk = self._body[self._offset:self._offset + size]
        self._offset += len(chunk)
        return chunk

    def close(self):
        return None


class ParseTests(unittest.TestCase):
    def test_spanish_full(self):
        data = ev.parse_xml(fixture("sp-full.xml"), "SP", datetime.date(2026, 8, 15))
        self.assertEqual(data["date"], "2026-08-15")
        self.assertEqual(data["language"], "SP")
        self.assertEqual(data["liturgicalTitle"], "Solemnidad de prueba")
        self.assertEqual(data["saint"], "Santa Prueba")
        self.assertEqual(data["provider"], "evangelizo.org")
        self.assertEqual([item["kind"] for item in data["readings"]], ["first", "psalm", "second"])
        self.assertEqual(data["readings"][0]["reference"], "1_Pr 1,1-3.")
        self.assertEqual(data["readings"][0]["title"], "Libro primero 1,1-3.")
        self.assertEqual(data["readings"][0]["text"], "Primera lectura de prueba.")
        self.assertEqual(data["gospel"]["kind"], "gospel")
        self.assertEqual(data["gospel"]["text"], "Evangelio de prueba.")
        self.assertTrue(data["commentary"]["available"])
        self.assertEqual(data["commentary"]["author"], "Autor de prueba")
        self.assertEqual(data["commentary"]["source"], "Fuente de prueba")
        self.assertEqual(data["commentary"]["title"], "Título del comentario")

    def test_english_full(self):
        data = ev.parse_xml(fixture("am-full.xml"), "AM", datetime.date(2026, 8, 15))
        self.assertEqual(data["language"], "AM")
        self.assertEqual(data["liturgicalTitle"], "Test solemnity")
        self.assertEqual(data["saint"], "Test Saint")
        self.assertEqual([item["kind"] for item in data["readings"]], ["first", "psalm", "second"])
        self.assertEqual(data["readings"][0]["text"], "First reading sample.")
        self.assertEqual(data["gospel"]["text"], "Gospel sample.")
        self.assertEqual(data["commentary"]["author"], "Sample author")
        self.assertTrue(data["commentary"]["available"])

    def test_optional_reading_and_commentary(self):
        data = ev.parse_xml(fixture("sp-optional.xml"), "SP", datetime.date(2026, 8, 17))
        self.assertEqual([item["kind"] for item in data["readings"]], ["first", "psalm"])
        self.assertEqual(data["gospel"]["text"], "Solo evangelio.")
        self.assertEqual(data["saint"], "")
        self.assertFalse(data["commentary"]["available"])
        self.assertEqual(data["commentary"]["text"], "")

    def test_unicode(self):
        data = ev.parse_xml(fixture("unicode.xml"), "SP", datetime.date(2026, 1, 1))
        self.assertIn("Año", data["liturgicalTitle"])
        self.assertIn("niño", data["readings"][0]["text"])
        self.assertEqual(data["gospel"]["text"], "¡feliz!")
        self.assertEqual(data["commentary"]["author"], "José")

    def test_bad_xml(self):
        with self.assertRaises(ev.Error) as raised:
            ev.parse_xml(fixture("bad.xml"), "SP", datetime.date(2026, 8, 15))
        self.assertEqual(raised.exception.code, ev.EXIT_PARSE)

    def test_empty_response(self):
        with self.assertRaises(ev.Error) as raised:
            ev.parse_xml(fixture("empty.xml"), "SP", datetime.date(2026, 8, 15))
        self.assertEqual(raised.exception.code, ev.EXIT_PARSE)

    def test_arabic_rtl_metadata(self):
        data = ev.parse_xml(fixture("ar-full.xml"), "AR", datetime.date(2026, 8, 15))
        self.assertEqual(data["language"], "AR")
        self.assertEqual(data["liturgicalTitle"], "عيد تجريبي")
        self.assertEqual(data["gospel"]["text"], "نص إنجيل تجريبي.")
        self.assertEqual(data["commentary"]["author"], "كاتب")
        self.assertTrue(data["commentary"]["available"])
        text = ev.html_to_text('<font dir="rtl">كاتب تجريبي<br />مصدر</font>')
        self.assertEqual(text, "كاتب تجريبي\nمصدر")

    def test_greek_unicode(self):
        data = ev.parse_xml(fixture("gr-full.xml"), "GR", datetime.date(2026, 8, 15))
        self.assertEqual(data["language"], "GR")
        self.assertEqual(data["liturgicalTitle"], "Δοκιμαστική εορτή")
        self.assertEqual(data["gospel"]["text"], "Δείγμα ευαγγελίου.")
        self.assertEqual(data["commentary"]["author"], "Συγγραφέας")
        self.assertEqual(len(data["readings"]), 2)

    def test_html_to_text(self):
        text = ev.html_to_text('<font dir="ltr">Beato <b>Columba</b><br />Abad</font>')
        self.assertEqual(text, "Beato Columba\nAbad")


class SecurityTests(unittest.TestCase):
    def test_invalid_language(self):
        self.assertEqual(ev.normalize_lang("TRA"), "TRA")
        self.assertEqual(ev.normalize_lang("xx"), "")
        self.assertEqual(ev.normalize_lang("sp"), "SP")
        for lang in ev.ALLOWED_LANGS:
            self.assertEqual(ev.normalize_lang(lang), lang)
            self.assertEqual(ev.normalize_lang(lang.lower()), lang)
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(ev.Error) as raised:
                ev.load_day("XX", datetime.date(2026, 8, 15), tmp)
            self.assertEqual(raised.exception.code, ev.EXIT_USAGE)

    def test_blocks_non_https_and_other_hosts(self):
        with self.assertRaises(ev.Error):
            ev.assert_allowed_url("http://feed.evangelizo.org/v2/reader.php")
        with self.assertRaises(ev.Error):
            ev.assert_allowed_url("https://evil.example/v2/reader.php")
        with self.assertRaises(ev.Error):
            ev.assert_allowed_url("https://feed.evangelizo.org/other.php")

    def test_cli_invalid_language_no_stdout_json(self):
        stdout = io.StringIO()
        stderr = io.StringIO()
        with mock.patch("sys.stdout", stdout), mock.patch("sys.stderr", stderr):
            code = ev.main(["--lang", "ZZ"])
        self.assertEqual(code, ev.EXIT_USAGE)
        self.assertEqual(stdout.getvalue(), "")
        self.assertIn("invalid language", stderr.getvalue())

    def test_cli_rejects_out_of_range_date(self):
        stdout = io.StringIO()
        stderr = io.StringIO()
        with mock.patch("sys.stdout", stdout), mock.patch("sys.stderr", stderr):
            code = ev.main(["--lang", "SP", "--date", "1999-01-01"])
        self.assertEqual(code, ev.EXIT_USAGE)
        self.assertEqual(stdout.getvalue(), "")
        self.assertIn("invalid date", stderr.getvalue())

    def test_cache_rejects_symlink_oversize_and_mismatch(self):
        day = datetime.date(2026, 8, 15)
        with tempfile.TemporaryDirectory() as tmp:
            good = ev.parse_xml(fixture("sp-full.xml"), "SP", day)
            path = ev.cache_path(tmp, "SP", day)
            ev.write_cache(path, good)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertIsNotNone(ev.read_cache(path, "SP", day))

            wrong = dict(good)
            wrong["language"] = "AM"
            ev.write_cache(path, wrong)
            self.assertIsNone(ev.read_cache(path, "SP", day))

            ev.write_cache(path, good)
            link = Path(tmp) / "SP" / "link.json"
            link.symlink_to(path)
            self.assertIsNone(ev.read_cache(link, "SP", day))

            huge = path.parent / "huge.json"
            huge.write_bytes(b"{" + (b"a" * (ev.MAX_BYTES + 8)) + b"}")
            self.assertIsNone(ev.read_cache(huge, "SP", day))


class CacheAndNetworkTests(unittest.TestCase):
    def opener_for(self, bodies):
        def opener(request):
            url = request.full_url
            query = urllib_parse_qs(url)
            type_name = query.get("type", [""])[0]
            if type_name not in bodies:
                raise urllib.error.URLError("missing %s" % type_name)
            return FakeResponse(bodies[type_name], url)
        return opener

    def test_cache_hit_skips_network(self):
        day = datetime.date(2026, 8, 15)
        with tempfile.TemporaryDirectory() as tmp:
            data = ev.parse_xml(fixture("sp-full.xml"), "SP", day)
            ev.write_cache(ev.cache_path(tmp, "SP", day), data)

            def fail(_request):
                raise AssertionError("network should not run")

            loaded = ev.load_day("SP", day, tmp, refresh=False, opener=fail)
            self.assertEqual(loaded["gospel"]["text"], "Evangelio de prueba.")

    def test_english_uses_am_cache_and_query(self):
        day = datetime.date(2026, 8, 15)
        seen = []

        def opener(request):
            seen.append(request.full_url)
            return FakeResponse(fixture("am-full.xml"), request.full_url)

        with tempfile.TemporaryDirectory() as tmp:
            loaded = ev.load_day("AM", day, tmp, opener=opener)
            self.assertEqual(loaded["language"], "AM")
            self.assertEqual(loaded["gospel"]["text"], "Gospel sample.")
            self.assertTrue(ev.cache_path(tmp, "AM", day).exists())
            self.assertFalse(ev.cache_path(tmp, "SP", day).exists())
            self.assertTrue(any("lang=AM" in url and "type=xml" in url for url in seen))

    def test_all_allowed_languages_cache_apart(self):
        day = datetime.date(2026, 8, 15)
        remaining = ("FR", "IT", "DE", "PT", "AR", "PL", "NL", "GR", "MG")
        with tempfile.TemporaryDirectory() as tmp:
            for lang in remaining:
                seen = []

                def opener(request, current=lang, bucket=seen):
                    bucket.append(request.full_url)
                    return FakeResponse(fixture("am-full.xml"), request.full_url)

                loaded = ev.load_day(lang, day, tmp, opener=opener)
                self.assertEqual(loaded["language"], lang)
                self.assertTrue(ev.cache_path(tmp, lang, day).exists())
                self.assertTrue(any(("lang=" + lang) in url for url in seen))

    def test_refresh_writes_new_cache(self):
        day = datetime.date(2026, 8, 15)
        with tempfile.TemporaryDirectory() as tmp:
            old = ev.parse_xml(fixture("sp-optional.xml"), "SP", day)
            ev.write_cache(ev.cache_path(tmp, "SP", day), old)
            loaded = ev.load_day(
                "SP",
                day,
                tmp,
                refresh=True,
                opener=self.opener_for({"xml": fixture("sp-full.xml")}),
            )
            self.assertEqual(loaded["liturgicalTitle"], "Solemnidad de prueba")
            cached = ev.read_cache(ev.cache_path(tmp, "SP", day))
            self.assertEqual(cached["gospel"]["text"], "Evangelio de prueba.")

    def test_network_failure_uses_cache(self):
        day = datetime.date(2026, 8, 15)
        with tempfile.TemporaryDirectory() as tmp:
            data = ev.parse_xml(fixture("sp-full.xml"), "SP", day)
            ev.write_cache(ev.cache_path(tmp, "SP", day), data)

            def boom(_request):
                raise urllib.error.URLError("down")

            loaded = ev.load_day("SP", day, tmp, refresh=True, opener=boom)
            self.assertEqual(loaded["provider"], "evangelizo.org")

    def test_network_failure_without_cache(self):
        day = datetime.date(2026, 8, 15)

        def boom(_request):
            raise urllib.error.URLError("down")

        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(ev.Error) as raised:
                ev.load_day("SP", day, tmp, opener=boom)
            self.assertEqual(raised.exception.code, ev.EXIT_NETWORK)

    def test_comment_and_title_fallback(self):
        day = datetime.date(2026, 8, 16)
        bodies = {
            "xml": fixture("sp-comment-fallback.xml"),
            "liturgic_t": "<font>Título vía endpoint</font>",
            "comment_a": "<font>Autor vía endpoint</font>",
            "comment_s": "<font>Fuente vía endpoint</font>",
            "comment_t": "<font>Tema vía endpoint</font>",
        }
        with tempfile.TemporaryDirectory() as tmp:
            loaded = ev.load_day("SP", day, tmp, opener=self.opener_for(bodies))
            self.assertEqual(loaded["liturgicalTitle"], "Título vía endpoint")
            self.assertEqual(loaded["commentary"]["author"], "Autor vía endpoint")
            self.assertEqual(loaded["commentary"]["source"], "Fuente vía endpoint")
            self.assertEqual(loaded["commentary"]["title"], "Tema vía endpoint")
            self.assertEqual(loaded["saint"], "")
            self.assertTrue(loaded["commentary"]["available"])

    def test_saint_fallback(self):
        day = datetime.date(2026, 8, 16)
        bodies = {
            "xml": fixture("sp-comment-fallback.xml"),
            "liturgic_t": "<font>Título vía endpoint</font>",
            "comment_a": "<font>Autor vía endpoint</font>",
            "comment_s": "<font>Fuente vía endpoint</font>",
            "comment_t": "<font>Tema vía endpoint</font>",
            "saint": '<font dir="ltr">San Agustín<br />obispo y doctor</font>',
        }
        with tempfile.TemporaryDirectory() as tmp:
            loaded = ev.load_day("SP", day, tmp, opener=self.opener_for(bodies))
            self.assertEqual(loaded["saint"], "San Agustín\nobispo y doctor")


def urllib_parse_qs(url):
    from urllib.parse import parse_qs, urlparse
    return parse_qs(urlparse(url).query)


if __name__ == "__main__":
    unittest.main()
