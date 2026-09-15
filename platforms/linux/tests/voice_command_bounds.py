#!/usr/bin/env python3
"""Synthetic voice helper process tests; no audio, credentials, or private data."""
import importlib.util
from importlib.machinery import SourceFileLoader
from pathlib import Path
import subprocess
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
loader = SourceFileLoader("msime_voice_command_provider", str(ROOT / "msime-client-voice-provider"))
spec = importlib.util.spec_from_loader(loader.name, loader)
provider = importlib.util.module_from_spec(spec)
spec.loader.exec_module(provider)


class VoiceCommandBounds(unittest.TestCase):
    def test_output_is_discarded_when_the_caller_does_not_need_it(self):
        self.assertEqual(provider.command(["/bin/sh", "-c", "printf fixture"], timeout=1), b"")

    def test_captured_output_is_bounded_and_processes_time_out(self):
        self.assertEqual(
            provider.command(["/bin/sh", "-c", "printf abc"], timeout=1, max_output=3), b"abc")
        with self.assertRaises(ValueError):
            provider.command(["/bin/sh", "-c", "printf abcd"], timeout=1, max_output=3)
        with self.assertRaises(subprocess.TimeoutExpired):
            provider.command(["/bin/sh", "-c", "sleep 1"], timeout=0.02, max_output=3)

    def test_capture_and_input_are_not_combined(self):
        with self.assertRaises(ValueError):
            provider.command(["/bin/sh", "-c", "exit 0"], data=b"fixture", max_output=1)


if __name__ == "__main__":
    unittest.main()
