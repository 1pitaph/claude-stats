import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SIDECAR = ROOT / "MemorySidecar"


class MemoryClassifierTests(unittest.TestCase):
    def setUp(self):
        import sys

        sys.path.insert(0, str(SIDECAR))
        self.addCleanup(lambda: sys.path.remove(str(SIDECAR)) if str(SIDECAR) in sys.path else None)

    def test_detects_xcodegen_modules_and_paths(self):
        from memoryd.classifier import classify_path, detect_modules

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "ClaudeStats").mkdir()
            (root / "project.yml").write_text(
                """
name: Demo
targets:
  ClaudeStats:
    type: application
  HelperTool:
    type: tool
""".strip(),
                encoding="utf-8",
            )

            modules = detect_modules(root)
            names = {module.name for module in modules}
            self.assertIn("ClaudeStats", names)
            self.assertIn("HelperTool", names)

            classified = classify_path(root, "ClaudeStats/App.swift")
            self.assertEqual(classified["kind"], "file")
            self.assertEqual(classified["path"], "ClaudeStats/App.swift")


if __name__ == "__main__":
    unittest.main()
