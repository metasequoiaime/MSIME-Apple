import importlib.util
from importlib.machinery import SourceFileLoader
import json
import pathlib
import sys
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
loader = SourceFileLoader("msime_voice_provider", str(ROOT / "msime-client-voice-provider"))
spec = importlib.util.spec_from_loader(loader.name, loader)
provider = importlib.util.module_from_spec(spec)
spec.loader.exec_module(provider)
from msime_voice_doubao import doubao_headers, normalize_doubao_auth_mode


class DoubaoAuthentication(unittest.TestCase):
    def test_explicit_modes_override_legacy_inference(self):
        self.assertEqual(normalize_doubao_auth_mode("api_key", "fixture-app"), "api_key")
        self.assertEqual(normalize_doubao_auth_mode("legacy", ""), "legacy")
        self.assertEqual(normalize_doubao_auth_mode("unknown", "fixture-app"), "legacy")
        self.assertEqual(normalize_doubao_auth_mode("unknown", ""), "api_key")

        common = {"resource_id": "fixture-resource", "token": "fixture-token",
                  "app_key": "fixture-app", "doubao_auth_mode": "api_key"}
        headers = doubao_headers(common, "fixture-request")
        self.assertEqual(headers["X-Api-Key"], "fixture-token")
        self.assertNotIn("X-Api-App-Key", headers)
        self.assertNotIn("X-Api-Access-Key", headers)
        common["doubao_auth_mode"] = "legacy"
        headers = doubao_headers(common, "fixture-request")
        self.assertEqual(headers["X-Api-App-Key"], "fixture-app")
        self.assertEqual(headers["X-Api-Access-Key"], "fixture-token")
        self.assertNotIn("X-Api-Key", headers)

    def test_private_config_normalizes_and_validates_modes(self):
        def read_config(asr):
            with tempfile.TemporaryDirectory() as directory:
                path = pathlib.Path(directory) / "voice.json"
                path.write_text(json.dumps({"asr": asr}), encoding="utf-8")
                path.chmod(0o600)
                return provider.load_config(path)["asr"]

        api = read_config({"provider": "doubao", "token": "fixture-token"})
        self.assertEqual(api["doubao_auth_mode"], "api_key")
        legacy = read_config({"provider": "doubao", "token": "fixture-token",
                              "app_key": "fixture-app"})
        self.assertEqual(legacy["doubao_auth_mode"], "legacy")
        explicit = read_config({"provider": "doubao", "token": "fixture-token",
                                "app_key": "stale-app", "doubao_auth_mode": "api_key"})
        self.assertEqual(explicit["doubao_auth_mode"], "api_key")
        with self.assertRaises(ValueError):
            read_config({"provider": "doubao", "token": "fixture-token",
                         "doubao_auth_mode": "legacy"})


if __name__ == "__main__":
    unittest.main()
