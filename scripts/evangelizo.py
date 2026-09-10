#!/usr/bin/env python3

import argparse
import datetime
import html
import json
import os
import re
import ssl
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from html.parser import HTMLParser
from pathlib import Path

ALLOWED_LANGS = (
    "SP", "AM", "FR", "IT", "DE", "PT", "AR", "PL", "NL", "GR", "MG",
    "TRA", "TRS", "TRF", "TRD",
    "ARM", "BYA", "COA", "MAA", "SYA",
)
HOST = "feed.evangelizo.org"
READER_PATH = "/v2/reader.php"
TIMEOUT_SEC = 15
MAX_BYTES = 512 * 1024
MAX_LOOKBACK_DAYS = 30
PROVIDER = "evangelizo.org"
EXIT_OK = 0
EXIT_USAGE = 2
EXIT_NETWORK = 3
EXIT_PARSE = 4

READING_SLOTS = (
    ("reading_text1", "first"),
    ("reading_text2", "psalm"),
    ("reading_text3", "second"),
)


class Error(Exception):
    def __init__(self, message, code):
        super().__init__(message)
        self.code = code


class _HTMLText(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts = []

    def handle_data(self, data):
        self.parts.append(data)

    def handle_starttag(self, tag, attrs):
        if tag == "br":
            self.parts.append("\n")

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)


def normalize_lang(value):
    text = str(value or "").strip().upper()
    return text if text in ALLOWED_LANGS else ""


def parse_date(value):
    if value is None or str(value).strip() == "":
        return datetime.date.today()
    text = str(value).strip()
    if re.fullmatch(r"\d{8}", text):
        return datetime.date(int(text[0:4]), int(text[4:6]), int(text[6:8]))
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", text):
        return datetime.date.fromisoformat(text)
    raise Error("invalid date: %s" % text, EXIT_USAGE)


def assert_allowed_date(day, today=None):
    now = today or datetime.date.today()
    if day > now or (now - day).days > MAX_LOOKBACK_DAYS:
        raise Error("invalid date", EXIT_USAGE)
    return day


def compact_date(day):
    return day.strftime("%Y%m%d")


def iso_date(day):
    return day.isoformat()


def default_cache_dir():
    xdg = os.environ.get("XDG_CACHE_HOME")
    if xdg:
        return Path(xdg) / "gospel-of-the-day"
    return Path.home() / ".cache" / "gospel-of-the-day"


def cache_path(cache_dir, lang, day):
    return Path(cache_dir) / lang / ("%s.json" % iso_date(day))


def empty_reading(kind):
    return {"kind": kind, "title": "", "reference": "", "text": ""}


def empty_commentary():
    return {"available": False, "title": "", "author": "", "source": "", "text": ""}


def clean_text(value):
    text = str(value or "").replace("\r\n", "\n").replace("\r", "\n")
    text = re.sub(r"[ \t]+\n", "\n", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def html_to_text(value):
    raw = str(value or "")
    parser = _HTMLText()
    try:
        parser.feed(raw)
        parser.close()
        text = "".join(parser.parts)
    except Exception:
        text = re.sub(r"<[^>]+>", "", raw)
        text = html.unescape(text)
    return clean_text(text)


def child_text(parent, name):
    if parent is None:
        return ""
    node = parent.find(name)
    if node is None or node.text is None:
        return ""
    return clean_text(node.text)


def reading_from_prefix(parent, prefix, kind):
    text = child_text(parent, prefix)
    title = child_text(parent, prefix + "_lt")
    reference = child_text(parent, prefix + "_st")
    if text == "" and title == "" and reference == "":
        return None
    if text == "":
        return None
    return {
        "kind": kind,
        "title": title,
        "reference": reference,
        "text": text,
    }


def parse_xml(raw, lang, day):
    payload = raw if isinstance(raw, str) else raw.decode("utf-8", errors="replace")
    if clean_text(payload) == "":
        raise Error("empty response", EXIT_PARSE)
    try:
        root = ET.fromstring(payload)
    except ET.ParseError as exc:
        raise Error("bad xml: %s" % exc, EXIT_PARSE) from exc

    ev = root.find("evangelizo")
    if ev is None:
        ev = root if root.tag == "evangelizo" else None
    if ev is None:
        raise Error("missing evangelizo node", EXIT_PARSE)

    title = child_text(ev, "litugic_t") or child_text(ev, "liturgic_t")
    saint = html_to_text(child_text(ev, "saint"))
    xml_date = child_text(ev, "date")
    if xml_date:
        try:
            day = parse_date(xml_date)
        except Error:
            pass

    readings = []
    for prefix, kind in READING_SLOTS:
        item = reading_from_prefix(ev, prefix, kind)
        if item is not None:
            readings.append(item)

    gospel = reading_from_prefix(ev, "reading_gospel", "gospel")
    if gospel is None:
        gospel = empty_reading("gospel")

    comment_text = child_text(ev, "comment")
    commentary = {
        "available": comment_text != "",
        "title": child_text(ev, "comment_t"),
        "author": child_text(ev, "comment_a"),
        "source": child_text(ev, "comment_s"),
        "text": comment_text,
    }

    return {
        "date": iso_date(day),
        "language": lang,
        "liturgicalTitle": title,
        "saint": saint,
        "readings": readings,
        "gospel": gospel,
        "commentary": commentary,
        "provider": PROVIDER,
        "fetchedAt": datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat(),
    }


def reader_url(lang, day, type_name):
    query = urllib.parse.urlencode({
        "date": compact_date(day),
        "type": type_name,
        "lang": lang,
    })
    return "https://%s%s?%s" % (HOST, READER_PATH, query)


def assert_allowed_url(url):
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme != "https" or parsed.hostname != HOST or parsed.path != READER_PATH:
        raise Error("blocked url", EXIT_NETWORK)


def http_get(url, opener=None):
    assert_allowed_url(url)
    request = urllib.request.Request(
        url,
        method="GET",
        headers={"Accept": "application/xml, text/xml, text/plain, text/html;q=0.9"},
    )
    context = ssl.create_default_context()
    try:
        if opener is not None:
            response = opener(request)
        else:
            response = urllib.request.urlopen(request, timeout=TIMEOUT_SEC, context=context)
    except (urllib.error.URLError, TimeoutError, ssl.SSLError, OSError) as exc:
        raise Error("network failure: %s" % exc, EXIT_NETWORK) from exc

    try:
        final = getattr(response, "geturl", lambda: url)()
        assert_allowed_url(final)
        chunks = []
        total = 0
        while True:
            chunk = response.read(8192)
            if not chunk:
                break
            total += len(chunk)
            if total > MAX_BYTES:
                raise Error("response too large", EXIT_NETWORK)
            chunks.append(chunk)
        return b"".join(chunks)
    finally:
        close = getattr(response, "close", None)
        if close:
            close()


def fetch_type(lang, day, type_name, opener=None):
    raw = http_get(reader_url(lang, day, type_name), opener=opener)
    return raw.decode("utf-8", errors="replace")


def apply_fallbacks(data, lang, day, opener=None):
    if data["liturgicalTitle"] == "":
        data["liturgicalTitle"] = html_to_text(fetch_type(lang, day, "liturgic_t", opener=opener))
    if data["saint"] == "":
        try:
            data["saint"] = html_to_text(fetch_type(lang, day, "saint", opener=opener))
        except Error:
            pass

    commentary = data["commentary"]
    if commentary["available"]:
        if commentary["author"] == "":
            commentary["author"] = html_to_text(fetch_type(lang, day, "comment_a", opener=opener))
        if commentary["source"] == "":
            commentary["source"] = html_to_text(fetch_type(lang, day, "comment_s", opener=opener))
        if commentary["title"] == "":
            commentary["title"] = html_to_text(fetch_type(lang, day, "comment_t", opener=opener))
    return data


def read_cache(path, lang=None, day=None):
    path = Path(path)
    try:
        if path.is_symlink() or not path.is_file():
            return None
        size = path.stat().st_size
        if size <= 0 or size > MAX_BYTES:
            return None
        text = path.read_text(encoding="utf-8")
        data = json.loads(text)
    except (OSError, json.JSONDecodeError, UnicodeError):
        return None
    if not isinstance(data, dict):
        return None
    for key in ("date", "language", "liturgicalTitle", "saint", "readings", "gospel", "commentary", "provider", "fetchedAt"):
        if key not in data:
            return None
    if lang and normalize_lang(data.get("language")) != lang:
        return None
    if day and str(data.get("date") or "") != iso_date(day):
        return None
    return data


def write_cache(path, data):
    path = Path(path)
    parent = path.parent
    parent.mkdir(parents=True, exist_ok=True)
    if parent.is_symlink() or path.is_symlink():
        raise Error("cache path rejected", EXIT_PARSE)
    fd, tmp_name = tempfile.mkstemp(prefix=".g.", suffix=".tmp", dir=str(parent))
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(data, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
        os.replace(tmp_name, path)
        os.chmod(path, 0o600)
    except Exception:
        try:
            os.unlink(tmp_name)
        except OSError:
            pass
        raise


def load_day(lang, day, cache_dir, refresh=False, opener=None):
    lang = normalize_lang(lang)
    if lang == "":
        raise Error("invalid language", EXIT_USAGE)

    path = cache_path(cache_dir, lang, day)
    cached = read_cache(path, lang, day)
    if cached is not None and not refresh:
        return cached

    try:
        raw = fetch_type(lang, day, "xml", opener=opener)
        data = parse_xml(raw, lang, day)
        data = apply_fallbacks(data, lang, day, opener=opener)
    except Error as exc:
        if cached is not None:
            return cached
        raise exc

    write_cache(path, data)
    return data


def build_parser():
    parser = argparse.ArgumentParser(prog="evangelizo.py")
    parser.add_argument("--lang", required=True)
    parser.add_argument("--date")
    parser.add_argument("--refresh", action="store_true")
    parser.add_argument("--cache-dir")
    return parser


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)
    lang = normalize_lang(args.lang)
    if lang == "":
        print("invalid language: %s" % args.lang, file=sys.stderr)
        return EXIT_USAGE
    try:
        day = assert_allowed_date(parse_date(args.date))
        cache_dir = Path(args.cache_dir) if args.cache_dir else default_cache_dir()
        data = load_day(lang, day, cache_dir, refresh=args.refresh)
    except Error as exc:
        print(str(exc), file=sys.stderr)
        return exc.code
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return EXIT_USAGE
    json.dump(data, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
