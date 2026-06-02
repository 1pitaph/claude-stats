import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "update-appcast.py"


class UpdateAppcastTests(unittest.TestCase):
    def test_writes_apple_silicon_hardware_requirement(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            notes = root / "notes.html"
            out = root / "appcast.xml"
            notes.write_text("<ul><li>Apple Silicon only</li></ul>", encoding="utf-8")

            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--version",
                    "1.8.0",
                    "--build",
                    "80",
                    "--url",
                    "https://example.com/ClaudeStats-1.8.0.zip",
                    "--enclosure-attrs",
                    'sparkle:edSignature="abc" length="123"',
                    "--release-notes-file",
                    str(notes),
                    "--out",
                    str(out),
                ],
                text=True,
                capture_output=True,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            xml = out.read_text(encoding="utf-8")
            self.assertIn("<link>https://1pitaph.github.io/claude-stats/appcast.xml</link>", xml)
            self.assertNotIn("claude-stats-releases", xml)
            self.assertIn("<sparkle:minimumSystemVersion>14.0.0</sparkle:minimumSystemVersion>", xml)
            self.assertIn("<sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>", xml)

    def test_custom_hardware_requirement_is_supported(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            notes = root / "notes.html"
            out = root / "appcast.xml"
            notes.write_text("<p>custom</p>", encoding="utf-8")

            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--version",
                    "1.8.1",
                    "--build",
                    "81",
                    "--url",
                    "https://example.com/ClaudeStats-1.8.1.zip",
                    "--enclosure-attrs",
                    'sparkle:edSignature="abc" length="123"',
                    "--release-notes-file",
                    str(notes),
                    "--hardware-requirements",
                    "arm64",
                    "--out",
                    str(out),
                ],
                text=True,
                capture_output=True,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(
                "<sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>",
                out.read_text(encoding="utf-8"),
            )

    def test_custom_feed_metadata_is_supported(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            notes = root / "notes.html"
            out = root / "appcast-lite.xml"
            notes.write_text("<p>lite</p>", encoding="utf-8")

            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--version",
                    "1.8.1",
                    "--build",
                    "81",
                    "--url",
                    "https://example.com/ClaudeStatsLite-1.8.1.zip",
                    "--enclosure-attrs",
                    'sparkle:edSignature="abc" length="123"',
                    "--release-notes-file",
                    str(notes),
                    "--feed-url",
                    "https://1pitaph.github.io/claude-stats/appcast-lite.xml",
                    "--channel-title",
                    "Claude Stats Lite",
                    "--channel-description",
                    "Most recent updates to Claude Stats Lite.",
                    "--out",
                    str(out),
                ],
                text=True,
                capture_output=True,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            xml = out.read_text(encoding="utf-8")
            self.assertIn("<title>Claude Stats Lite</title>", xml)
            self.assertIn("<link>https://1pitaph.github.io/claude-stats/appcast-lite.xml</link>", xml)
            self.assertIn("<description>Most recent updates to Claude Stats Lite.</description>", xml)

    def test_writes_delta_enclosures_when_present(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            notes = root / "notes.html"
            deltas = root / "deltas.json"
            out = root / "appcast.xml"
            notes.write_text("<h2>本次更新</h2>\n<p>delta release</p>", encoding="utf-8")
            deltas.write_text(
                json.dumps(
                    [
                        {
                            "deltaFrom": "78",
                            "deltaFromDisplay": "1.8.0",
                            "url": "https://example.com/ClaudeStats-82-from-78.delta",
                            "enclosureAttrs": 'sparkle:edSignature="delta-a" length="456"',
                        },
                        {
                            "deltaFrom": "79",
                            "url": "https://example.com/ClaudeStats-82-from-79.delta",
                            "enclosureAttrs": 'sparkle:edSignature="delta-b" length="789"',
                        },
                    ]
                ),
                encoding="utf-8",
            )

            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--version",
                    "1.8.2",
                    "--build",
                    "82",
                    "--url",
                    "https://example.com/ClaudeStats-1.8.2.zip",
                    "--enclosure-attrs",
                    'sparkle:edSignature="full" length="123"',
                    "--release-notes-file",
                    str(notes),
                    "--deltas-file",
                    str(deltas),
                    "--out",
                    str(out),
                ],
                text=True,
                capture_output=True,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            xml = out.read_text(encoding="utf-8")
            self.assertIn("<sparkle:deltas>", xml)
            self.assertIn('sparkle:deltaFrom="78"', xml)
            self.assertIn('sparkle:deltaFrom="79"', xml)
            self.assertIn('sparkle:edSignature="delta-a" length="456"', xml)
            self.assertIn('sparkle:edSignature="delta-b" length="789"', xml)
            self.assertIn(
                '<enclosure url="https://example.com/ClaudeStats-1.8.2.zip" sparkle:edSignature="full" length="123" type="application/octet-stream"/>',
                xml,
            )
            self.assertIn("本次更新", xml)
            self.assertEqual(xml.count("本次更新"), 1)
            self.assertNotIn("cs-update-summary", xml)
            self.assertIn("cs-update-size-pill", xml)
            self.assertIn('data-sparkle-version="78"', xml)
            self.assertIn('data-sparkle-version="79"', xml)
            self.assertIn("456 bytes", xml)
            self.assertIn("789 bytes", xml)
            self.assertIn("123 bytes", xml)
            self.assertIn(".cs-update-size-delta.sparkle-installed-version", xml)
            self.assertIn(".cs-update-size-delta.sparkle-installed-version ~ .cs-update-size-full", xml)
            self.assertNotIn("下载大小", xml)
            self.assertNotIn("增量更新包", xml)
            self.assertNotIn("完整安装包", xml)
            self.assertIn("更新内容", xml)
            heading_start = xml.index("<h2>本次更新")
            heading_end = xml.index("</h2>", heading_start)
            self.assertLess(xml.index("cs-update-size-pill", heading_start), heading_end)
            self.assertLess(heading_end, xml.index("<p>delta release</p>"))

    def test_formats_download_sizes_in_release_notes(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            notes = root / "notes.html"
            deltas = root / "deltas.json"
            out = root / "appcast.xml"
            notes.write_text("<h2>本次更新</h2>\n<p>larger release</p>", encoding="utf-8")
            deltas.write_text(
                json.dumps(
                    [
                        {
                            "deltaFrom": "84",
                            "deltaFromDisplay": "1.8.4",
                            "url": "https://example.com/ClaudeStats-85-from-84.delta",
                            "enclosureAttrs": 'sparkle:edSignature="delta" length="2156350"',
                        }
                    ]
                ),
                encoding="utf-8",
            )

            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--version",
                    "1.8.5",
                    "--build",
                    "85",
                    "--url",
                    "https://example.com/ClaudeStats-1.8.5.zip",
                    "--enclosure-attrs",
                    'sparkle:edSignature="full" length="101037424"',
                    "--release-notes-file",
                    str(notes),
                    "--deltas-file",
                    str(deltas),
                    "--out",
                    str(out),
                ],
                text=True,
                capture_output=True,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            xml = out.read_text(encoding="utf-8")
            self.assertIn('data-sparkle-version="84"', xml)
            self.assertIn("2.2 MB", xml)
            self.assertIn("101 MB", xml)
            self.assertEqual(xml.count("本次更新"), 1)
            heading_start = xml.index("<h2>本次更新")
            heading_end = xml.index("</h2>", heading_start)
            self.assertLess(xml.index("cs-update-size-pill", heading_start), heading_end)
            self.assertLess(heading_end, xml.index("<p>larger release</p>"))

    def test_omits_delta_container_without_delta_file(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            notes = root / "notes.html"
            out = root / "appcast.xml"
            notes.write_text("<h2>本次更新</h2>\n<p>full only</p>", encoding="utf-8")

            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--version",
                    "1.8.3",
                    "--build",
                    "83",
                    "--url",
                    "https://example.com/ClaudeStats-1.8.3.zip",
                    "--enclosure-attrs",
                    'sparkle:edSignature="full" length="123"',
                    "--release-notes-file",
                    str(notes),
                    "--out",
                    str(out),
                ],
                text=True,
                capture_output=True,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            xml = out.read_text(encoding="utf-8")
            self.assertNotIn("<sparkle:deltas>", xml)
            self.assertIn("本次更新", xml)
            self.assertEqual(xml.count("本次更新"), 1)
            self.assertIn("123 bytes", xml)
            self.assertNotIn('class="cs-update-size-pill cs-update-size-delta"', xml)

    def test_existing_version_is_left_unchanged_even_with_deltas(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            notes = root / "notes.html"
            deltas = root / "deltas.json"
            appcast = root / "appcast.xml"
            notes.write_text("<p>new</p>", encoding="utf-8")
            deltas.write_text(
                json.dumps(
                    [
                        {
                            "deltaFrom": "80",
                            "url": "https://example.com/ClaudeStats-84-from-80.delta",
                            "enclosureAttrs": 'sparkle:edSignature="delta" length="456"',
                        }
                    ]
                ),
                encoding="utf-8",
            )
            original = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <item>
      <sparkle:shortVersionString>1.8.4</sparkle:shortVersionString>
      <enclosure url="https://example.com/original.zip" sparkle:edSignature="original" length="1" type="application/octet-stream"/>
    </item>
  </channel>
</rss>
"""
            appcast.write_text(original, encoding="utf-8")

            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--version",
                    "1.8.4",
                    "--build",
                    "84",
                    "--url",
                    "https://example.com/ClaudeStats-1.8.4.zip",
                    "--enclosure-attrs",
                    'sparkle:edSignature="full" length="123"',
                    "--release-notes-file",
                    str(notes),
                    "--deltas-file",
                    str(deltas),
                    "--in",
                    str(appcast),
                    "--out",
                    str(appcast),
                ],
                text=True,
                capture_output=True,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(appcast.read_text(encoding="utf-8"), original)


if __name__ == "__main__":
    unittest.main()
