#!/usr/bin/env python3
"""Exercise Doubao authentication header selection with synthetic credentials."""
import importlib.util
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("msime_voice_doubao", ROOT / "scripts" / "msime_voice_doubao.py")
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


class DoubaoAuthMode(unittest.TestCase):
    def setUp(self):
        self.config = {"app_key": "synthetic-app-id", "token": "synthetic-token"}

    def test_api_key_mode_ignores_stale_app_id(self):
        self.assertEqual(
            MODULE.doubao_auth_headers(self.config, {"doubao_auth_mode": "api_key"}),
            {"X-Api-Key": "synthetic-token"},
        )

    def test_legacy_mode_uses_app_id_and_access_token(self):
        self.assertEqual(
            MODULE.doubao_auth_headers(self.config, {"doubao_auth_mode": "legacy"}),
            {"X-Api-App-Key": "synthetic-app-id", "X-Api-Access-Key": "synthetic-token"},
        )

    def test_missing_mode_preserves_legacy_config(self):
        self.assertEqual(
            MODULE.doubao_auth_headers(self.config, {}),
            {"X-Api-App-Key": "synthetic-app-id", "X-Api-Access-Key": "synthetic-token"},
        )

    def test_missing_mode_without_app_id_uses_api_key(self):
        config = {"app_key": "", "token": "synthetic-token"}
        self.assertEqual(
            MODULE.doubao_auth_headers(config, {}),
            {"X-Api-Key": "synthetic-token"},
        )

    def test_legacy_mode_without_app_id_is_rejected(self):
        with self.assertRaises(ValueError):
            MODULE.doubao_auth_headers(
                {"app_key": "", "token": "synthetic-token"},
                {"doubao_auth_mode": "legacy"},
            )

    def test_unknown_mode_keeps_old_inference(self):
        self.assertEqual(
            MODULE.doubao_auth_headers(self.config, {"doubao_auth_mode": "old-console"}),
            {"X-Api-App-Key": "synthetic-app-id", "X-Api-Access-Key": "synthetic-token"},
        )

    def test_placeholder_app_id_is_not_inferred_as_legacy(self):
        config = {"app_key": "<not-a-credential>", "token": "synthetic-token"}
        self.assertEqual(
            MODULE.doubao_auth_headers(config, {}),
            {"X-Api-Key": "synthetic-token"},
        )


if __name__ == "__main__":
    unittest.main()
