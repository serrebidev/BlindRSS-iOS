#!/usr/bin/env python3
"""Convert the desktop BlindRSS gettext catalogs (.po) into an Apple
String Catalog (Localizable.xcstrings) for the iOS app.

Why this works: gettext keys strings by their English source text
(msgid), and SwiftUI resolves literal Text/Button titles through the
string catalog by the same source text. Converting the desktop
catalogs therefore localizes every iOS interface literal whose text
matches a desktop string, with no code changes. Strings built in code
(accessibilityLabel values, announcements) are plain Swift Strings and
do not pass through the catalog; they stay English (see AUDIT.md,
research round 0.1.13).

Usage: po2xcstrings.py <po-dir> <output.xcstrings>
The .po files are the desktop repo's locale/<lang>/LC_MESSAGES/
blindrss.po files, saved in <po-dir> as <lang>.po.
"""
import json
import re
import sys
from pathlib import Path

# gettext language -> Apple locale identifier used in catalogs/regions.
LOCALES = {
    "de": "de", "es": "es", "fr": "fr", "hi": "hi", "it": "it",
    "ja": "ja", "nl": "nl", "nl_BE": "nl-BE", "pl": "pl",
    "pt_BR": "pt-BR", "pt_PT": "pt-PT", "ru": "ru", "sv": "sv",
    "zh_CN": "zh-Hans", "zh_TW": "zh-Hant",
}


def parse_po(text):
    """Yields (msgid, msgstr) pairs; plural entries yield msgstr[0]."""
    entries = []
    msgid = msgstr = None
    state = None
    fuzzy = False
    buf = []

    def flush():
        nonlocal msgid, msgstr, fuzzy
        if msgid:
            entries.append((msgid, msgstr or "", fuzzy))
        msgid = msgstr = None
        fuzzy = False

    for raw in text.splitlines():
        line = raw.strip()
        if line.startswith("#,"):
            fuzzy = "fuzzy" in line
            continue
        if line.startswith("#"):
            continue
        if line.startswith("msgid_plural"):
            state = "plural"
            continue
        if line.startswith("msgid "):
            flush()
            state = "id"
            buf = [line[6:]]
            msgid = _join(buf)
            continue
        if line.startswith("msgstr["):
            # Plural translation: keep the first form only.
            if msgstr is None:
                state = "str"
                buf = [line.split(" ", 1)[1] if " " in line else '""']
                msgstr = _join(buf)
            else:
                state = "skip"
            continue
        if line.startswith("msgstr "):
            state = "str"
            buf = [line[7:]]
            msgstr = _join(buf)
            continue
        if line.startswith('"'):
            if state == "id":
                msgid = _join([_quote(msgid or "")] + [line]) if False else _append(msgid, line)
            elif state == "str":
                msgstr = _append(msgstr, line)
            continue
        if line == "":
            state = None
    flush()
    return entries


def _quote(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _join(parts):
    out = ""
    for part in parts:
        out += _unquote(part.strip())
    return out


def _append(current, quoted_line):
    return (current or "") + _unquote(quoted_line.strip())


def _unquote(token):
    token = token.strip()
    if len(token) >= 2 and token.startswith('"') and token.endswith('"'):
        body = token[1:-1]
        return (body.replace("\\n", "\n").replace("\\t", "\t")
                .replace('\\"', '"').replace("\\\\", "\\"))
    return ""


def swift_format(text):
    """gettext placeholders -> String Catalog format specifiers."""
    text = re.sub(r"%\(\w+\)[#0\- +]*\d*(?:\.\d+)?[diouxXeEfFgGcrs]", "%@", text)
    text = re.sub(r"%[#0\- +]*\d*(?:\.\d+)?d", "%lld", text)
    text = re.sub(r"%[#0\- +]*\d*(?:\.\d+)?[srs]", "%@", text)
    return text


def main():
    po_dir, out_path = Path(sys.argv[1]), Path(sys.argv[2])
    strings = {}
    stats = {}
    for lang, locale in LOCALES.items():
        po_file = po_dir / f"{lang}.po"
        if not po_file.exists():
            print(f"missing {po_file}, skipped")
            continue
        count = 0
        for msgid, msgstr, fuzzy in parse_po(po_file.read_text(encoding="utf-8")):
            if fuzzy or not msgstr or msgid == msgstr:
                continue
            key = swift_format(msgid)
            entry = strings.setdefault(key, {"localizations": {}})
            entry["localizations"][locale] = {
                "stringUnit": {"state": "translated", "value": swift_format(msgstr)}
            }
            count += 1
        stats[locale] = count
    catalog = {"sourceLanguage": "en", "strings": strings, "version": "1.0"}
    out_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{len(strings)} keys -> {out_path}")
    for locale, count in sorted(stats.items()):
        print(f"  {locale}: {count} translations")


if __name__ == "__main__":
    main()
