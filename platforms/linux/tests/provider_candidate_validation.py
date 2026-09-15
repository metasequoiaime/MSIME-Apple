#!/usr/bin/env python3
"""Keep Linux online candidates inside the shared Rust response contract."""
import importlib.machinery
import importlib.util
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
loader = importlib.machinery.SourceFileLoader(
    "candidate_online_provider", str(ROOT / "msime-client-online-provider"))
spec = importlib.util.spec_from_loader(loader.name, loader)
online = importlib.util.module_from_spec(spec)
loader.exec_module(online)


class ProviderCandidateValidation(unittest.TestCase):
    def test_unicode_candidates_preserve_text_source_and_byte_limit(self):
        self.assertEqual(online.candidate("  云端候选  ", 1),
                         {"text": "云端候选", "source": 1})
        self.assertIsNotNone(online.candidate("字" * 1365 + "a", 0))
        self.assertIsNone(online.candidate("字" * 1365 + "ab", 0))

    def test_every_c0_and_c1_control_is_rejected_inside_candidate_text(self):
        for codepoint in (*range(32), *range(127, 160)):
            with self.subTest(codepoint=codepoint):
                self.assertIsNone(online.candidate("left" + chr(codepoint) + "right", 0))


if __name__ == "__main__":
    unittest.main()
