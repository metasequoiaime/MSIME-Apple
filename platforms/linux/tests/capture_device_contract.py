#!/usr/bin/env python3
"""Synthetic capture-device validation tests; no real audio or private data."""
import importlib.util
from importlib.machinery import SourceFileLoader
from pathlib import Path
import sys
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
loader = SourceFileLoader("msime_capture_provider", str(ROOT / "msime-client-voice-provider"))
spec = importlib.util.spec_from_loader(loader.name, loader)
provider = importlib.util.module_from_spec(spec)
spec.loader.exec_module(provider)


class CaptureDeviceContract(unittest.TestCase):
    def test_command_line_and_request_paths_share_limits(self):
        valid = "node-" + "a" * 123
        with mock.patch.object(provider.shutil, "which", return_value="/usr/bin/parec"):
            command = provider.capture_command("pulse", valid)
            request = provider.request_capture_command(
                {"capture_backend": "pulse", "capture_device": valid}, "auto", None)
        self.assertIn("--device=" + valid, command)
        self.assertIn("--device=" + valid, request)

        for invalid in ("a" * 129, "é" * 257, "node\x1f", "node\x7f", "node\x80"):
            with self.subTest(invalid=repr(invalid)):
                with self.assertRaises(ValueError):
                    provider.capture_command("pulse", invalid)
                with self.assertRaises(ValueError):
                    provider.request_capture_command(
                        {"capture_backend": "pulse", "capture_device": invalid}, "auto", None)

    def test_empty_request_inherits_service_device(self):
        with mock.patch.object(provider.shutil, "which", return_value="/usr/bin/parec"):
            command = provider.request_capture_command(
                {"capture_backend": "", "capture_device": ""}, "pulse", "fixture-source")
        self.assertIn("--device=fixture-source", command)

    def test_empty_explicit_command_line_device_is_rejected(self):
        with self.assertRaises(ValueError):
            provider.capture_command("pulse", "")


if __name__ == "__main__":
    unittest.main()
