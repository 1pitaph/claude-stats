#!/usr/bin/env python3
"""Prepend a release <item> to the Sparkle appcast.

The appcast is a small RSS file hosted on GitHub Pages
(https://1pitaph.github.io/claude-stats/appcast.xml). The release workflow
fetches the current copy, runs this script to add the new version's <item>,
and republishes it to the gh-pages branch.

Usage:
  update-appcast.py \
      --version 1.2.0 --build 42 \
      --url https://github.com/1pitaph/claude-stats/releases/download/v1.2.0/ClaudeStats-1.2.0.zip \
      --enclosure-attrs 'sparkle:edSignature="..." length="12345"' \
      --release-notes-file release_notes.html \
      --feed-url https://1pitaph.github.io/claude-stats/appcast.xml \
      --channel-title "Claude Stats" \
      --min-system-version 14.0.0 \
      --hardware-requirements arm64 \
      --deltas-file deltas.json \
      --in appcast.xml --out appcast.xml

The release-notes file should contain inline HTML (e.g. `<ul><li>…</li></ul>`).
It's embedded as CDATA inside the item's <description>, which Sparkle renders
inline — no webview fetch, no GitHub page chrome.

If --in does not exist (or is empty) a fresh appcast skeleton is created.
Re-running for a version that's already in the appcast is a no-op.
"""
import argparse
import email.utils
import html
import json
import os
import re
import sys
import time

DEFAULT_FEED_URL = "https://1pitaph.github.io/claude-stats/appcast.xml"
DEFAULT_CHANNEL_TITLE = "Claude Stats"
DEFAULT_CHANNEL_DESCRIPTION = "Most recent updates to Claude Stats."

SKELETON_TEMPLATE = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>{title}</title>
    <link>{feed}</link>
    <description>{description}</description>
    <language>en</language>
  </channel>
</rss>
"""

ITEM_TEMPLATE = """    <item>
      <title>Version {version}</title>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{min_sys}</sparkle:minimumSystemVersion>
      <sparkle:hardwareRequirements>{hardware_requirements}</sparkle:hardwareRequirements>
      <description><![CDATA[
{notes_html}
]]></description>
      <pubDate>{pub_date}</pubDate>
      <enclosure url="{url}" {enclosure_attrs} type="application/octet-stream"/>
{deltas_xml}\
    </item>
"""

DELTA_ENCLOSURE_TEMPLATE = """        <enclosure url="{url}" sparkle:deltaFrom="{delta_from}" {enclosure_attrs} type="application/octet-stream"/>
"""

LENGTH_ATTRIBUTE_RE = re.compile(r'(?:^|\s)length="(?P<length>\d+)"')
UPDATE_HEADING_RE = re.compile(r"(<h([1-6])[^>]*>\s*本次更新\s*)(</h\2>)", re.IGNORECASE)


def enclosure_length(enclosure_attrs: str) -> int | None:
    match = LENGTH_ATTRIBUTE_RE.search(enclosure_attrs)
    if match is None:
        return None
    return int(match.group("length"))


def format_byte_count(byte_count: int) -> str:
    if byte_count == 1:
        return "1 byte"
    if byte_count < 1000:
        return f"{byte_count} bytes"

    value = float(byte_count)
    for unit in ("KB", "MB", "GB", "TB"):
        value /= 1000.0
        if value < 1000.0 or unit == "TB":
            places = 0 if value >= 100 else 1
            text = f"{value:.{places}f}".rstrip("0").rstrip(".")
            return f"{text} {unit}"

    return f"{byte_count} bytes"


def render_size_pill(size: str, class_name: str, version: str | None = None) -> str:
    attrs = f'class="cs-update-size-pill {html.escape(class_name, quote=True)}"'
    if version is not None:
        attrs += f' data-sparkle-version="{html.escape(version, quote=True)}"'
    return f"<span {attrs}>{html.escape(size)}</span>"


def render_update_size_pills(enclosure_attrs: str, deltas: list[dict[str, str]]) -> str:
    full_length = enclosure_length(enclosure_attrs)
    if full_length is None:
        raise ValueError("full enclosureAttrs must include length")

    pills: list[str] = []
    for delta in deltas:
        delta_length = enclosure_length(delta["enclosureAttrs"])
        if delta_length is None:
            continue
        size = format_byte_count(delta_length)
        pills.append(render_size_pill(size, "cs-update-size-delta", delta["deltaFrom"]))

    full_size = format_byte_count(full_length)
    pills.append(render_size_pill(full_size, "cs-update-size-full"))

    return f'<span class="cs-update-size-pills">{"".join(pills)}</span>'


def inject_update_size_pills(notes_html: str, enclosure_attrs: str, deltas: list[dict[str, str]]) -> str:
    pills = render_update_size_pills(enclosure_attrs, deltas)

    def add_pills(match: re.Match[str]) -> str:
        return f"{match.group(1)}{pills}{match.group(3)}"

    updated_notes, count = UPDATE_HEADING_RE.subn(add_pills, notes_html, count=1)
    if count:
        return updated_notes
    return "\n".join(
        [
            '<div class="cs-update-size-fallback">',
            pills,
            "</div>",
            notes_html,
        ]
    )


def render_release_notes_section(notes_html: str) -> str:
    if not notes_html:
        return ""
    return "\n".join(
        [
            '<div style="margin: 0; color: #1f2937; font-size: 13px; line-height: 1.55;">',
            (
                '  <p style="margin: 0 0 10px; color: #172033; font-size: 15px; '
                'font-weight: 700;">更新内容</p>'
            ),
            '  <div style="margin: 0; padding: 0;">',
            notes_html,
            "  </div>",
            "</div>",
        ]
    )


def render_appcast_notes_html(
    notes_html: str,
    enclosure_attrs: str,
    deltas: list[dict[str, str]],
) -> str:
    notes_html = inject_update_size_pills(notes_html, enclosure_attrs, deltas)
    release_notes = render_release_notes_section(notes_html)
    return "\n".join(
        [
            (
                '<div class="cs-appcast-notes" style="font-family: -apple-system, BlinkMacSystemFont, '
                'Helvetica, Arial, sans-serif; color: #1f2937;">'
            ),
            "  <style>",
            (
                "    .cs-update-size-fallback { margin: 0 0 14px; }"
            ),
            (
                "    .cs-update-size-pills { display: inline-flex; align-items: center; "
                "margin-left: 10px; min-width: 0; vertical-align: middle; }"
            ),
            (
                "    .cs-update-size-pill { display: inline-block; padding: 4px 10px; "
                "border: 0; border-radius: 999px; background: #eaf1ff; color: #172033; "
                "font-size: 12px; font-weight: 700; line-height: 1.2; white-space: nowrap; }"
            ),
            "    .cs-update-size-delta { display: none; }",
            "    .cs-update-size-delta.sparkle-installed-version { display: inline-block; }",
            "    .cs-update-size-delta.sparkle-installed-version ~ .cs-update-size-full { display: none; }",
            "  </style>",
            release_notes,
            "</div>",
        ]
    )


def load_deltas(path: str | None) -> list[dict[str, str]]:
    if not path:
        return []
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    if not isinstance(data, list):
        raise ValueError("deltas file must contain a JSON array")

    deltas: list[dict[str, str]] = []
    for index, entry in enumerate(data):
        if not isinstance(entry, dict):
            raise ValueError(f"delta entry {index} must be an object")
        normalized: dict[str, str] = {}
        for key in ("deltaFrom", "url", "enclosureAttrs"):
            value = entry.get(key)
            if not isinstance(value, str) or not value.strip():
                raise ValueError(f"delta entry {index} is missing non-empty {key}")
            normalized[key] = value.strip()
        display = entry.get("deltaFromDisplay")
        if isinstance(display, str) and display.strip():
            normalized["deltaFromDisplay"] = display.strip()
        attrs = normalized["enclosureAttrs"]
        if "sparkle:edSignature" not in attrs or "length=" not in attrs:
            raise ValueError(f"delta entry {index} enclosureAttrs must include signature and length")
        deltas.append(normalized)
    return deltas


def render_deltas(deltas: list[dict[str, str]]) -> str:
    if not deltas:
        return ""
    enclosures = "".join(
        DELTA_ENCLOSURE_TEMPLATE.format(
            url=delta["url"],
            delta_from=delta["deltaFrom"],
            enclosure_attrs=delta["enclosureAttrs"],
        )
        for delta in deltas
    )
    return "      <sparkle:deltas>\n{}      </sparkle:deltas>\n".format(enclosures)


def appcast_skeleton(feed_url: str, channel_title: str, channel_description: str) -> str:
    return SKELETON_TEMPLATE.format(
        feed=html.escape(feed_url, quote=False),
        title=html.escape(channel_title, quote=False),
        description=html.escape(channel_description, quote=False),
    )


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--version", required=True)
    p.add_argument("--build", required=True)
    p.add_argument("--url", required=True)
    p.add_argument("--enclosure-attrs", required=True,
                   help='the `sparkle:edSignature="..." length="..."` string from sign_update')
    p.add_argument("--release-notes-file", required=True,
                   help="path to an HTML fragment with this release's notes; embedded in CDATA")
    p.add_argument("--feed-url", default=DEFAULT_FEED_URL,
                   help="absolute URL where this appcast is hosted")
    p.add_argument("--channel-title", default=DEFAULT_CHANNEL_TITLE,
                   help="RSS channel title for newly-created appcasts")
    p.add_argument("--channel-description", default=DEFAULT_CHANNEL_DESCRIPTION,
                   help="RSS channel description for newly-created appcasts")
    p.add_argument("--min-system-version", default="14.0.0")
    p.add_argument("--hardware-requirements", default="arm64")
    p.add_argument("--deltas-file",
                   help="optional JSON array of delta enclosure metadata to embed under sparkle:deltas")
    p.add_argument("--in", dest="infile", default="appcast.xml")
    p.add_argument("--out", dest="outfile", default="appcast.xml")
    args = p.parse_args()

    if os.path.exists(args.infile) and os.path.getsize(args.infile) > 0:
        with open(args.infile, encoding="utf-8") as fh:
            xml = fh.read()
    else:
        xml = appcast_skeleton(args.feed_url, args.channel_title, args.channel_description)

    version_tag = "<sparkle:shortVersionString>{}</sparkle:shortVersionString>".format(args.version)
    if version_tag in xml:
        print("appcast already contains version {} — leaving it unchanged".format(args.version))
        with open(args.outfile, "w", encoding="utf-8") as fh:
            fh.write(xml)
        return 0

    with open(args.release_notes_file, encoding="utf-8") as fh:
        notes_html = fh.read().strip()
    if "]]>" in notes_html:
        print("error: release notes contain ']]>' which would break CDATA", file=sys.stderr)
        return 1
    try:
        deltas = load_deltas(args.deltas_file)
        notes_html = render_appcast_notes_html(notes_html, args.enclosure_attrs.strip(), deltas)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print("error: invalid appcast metadata: {}".format(error), file=sys.stderr)
        return 1
    if "]]>" in notes_html:
        print("error: release notes contain ']]>' which would break CDATA", file=sys.stderr)
        return 1

    item = ITEM_TEMPLATE.format(
        version=args.version,
        build=args.build,
        min_sys=args.min_system_version,
        hardware_requirements=args.hardware_requirements,
        notes_html=notes_html,
        pub_date=email.utils.formatdate(time.time(), localtime=False, usegmt=True),
        url=args.url,
        enclosure_attrs=args.enclosure_attrs.strip(),
        deltas_xml=render_deltas(deltas),
    )

    if "<item>" in xml:
        xml = xml.replace("    <item>", item + "    <item>", 1)
    elif "</channel>" in xml:
        xml = xml.replace("  </channel>", item + "  </channel>", 1)
    else:
        print("error: malformed appcast — no <item> or </channel> found", file=sys.stderr)
        return 1

    with open(args.outfile, "w", encoding="utf-8") as fh:
        fh.write(xml)
    print("added Version {} (build {}) to {}".format(args.version, args.build, args.outfile))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
