#!/usr/bin/env python3
"""Keep Linux voice transcripts inside the provider's text contract."""
import importlib.machinery
import importlib.util
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
loader = importlib.machinery.SourceFileLoader(
    "voice_text_provider", str(ROOT / "msime-client-voice-provider"))
spec = importlib.util.spec_from_loader(loader.name, loader)
voice = importlib.util.module_from_spec(spec)
loader.exec_module(voice)


class ProviderVoiceTextValidation(unittest.TestCase):
    def test_unicode_text_whitespace_and_byte_limit_are_preserved(self):
        self.assertEqual(voice.bounded_text(" \u00a0水杉输入\u00a0 "), "水杉输入")
        self.assertEqual(voice.bounded_text("第一行\n第二行\t注释"), "第一行\n第二行\t注释")
        boundary = "字" * 1365 + "a"
        self.assertEqual(len(boundary.encode()), 4096)
        self.assertEqual(voice.bounded_text(boundary + "字"), boundary)

    def test_non_text_controls_are_rejected_at_every_position(self):
        controls = (*[value for value in range(32) if value not in (9, 10)],
                    *range(127, 160))
        for codepoint in controls:
            for text in (chr(codepoint) + "right", "left" + chr(codepoint) + "right",
                         "left" + chr(codepoint)):
                with self.subTest(codepoint=codepoint, text=text):
                    self.assertEqual(voice.bounded_text(text), "")


if __name__ == "__main__":
    unittest.main()
