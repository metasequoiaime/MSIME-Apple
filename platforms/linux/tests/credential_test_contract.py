#!/usr/bin/env python3
"""Synthetic credential-test dispatch; no real credentials or network calls."""
import importlib.machinery
import importlib.util
from pathlib import Path
from types import SimpleNamespace
import sys
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


def load(name, filename):
    loader = importlib.machinery.SourceFileLoader(name, str(ROOT / filename))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


online = load("credential_online_provider", "msime-client-online-provider")
voice = load("credential_voice_provider", "msime-client-voice-provider")


class OnlineCredentialTest(unittest.TestCase):
    def setUp(self):
        self.server = SimpleNamespace(ai_config_path=Path("/private/ai.json"),
                                      tencent_config_path=Path("/private/tencent.json"))

    def test_ai_uses_private_credential_bound_to_current_options(self):
        private = {"provider": "deepseek", "endpoint": "https://fixture.invalid/chat",
                   "model": "fixture-model", "token": "fixture-private-token"}
        query = {"service": "ai.assistant", "config": {
            "provider": "deepseek", "endpoint": private["endpoint"], "model": private["model"]}}
        with mock.patch.object(online, "load_ai_config", return_value=private), \
                mock.patch.object(online, "fetch", return_value={"choices": [{}]}) as fetch:
            result = online.credential_test(query, self.server)
        self.assertTrue(result["ok"])
        self.assertEqual(fetch.call_args.args[3], "fixture-private-token")
        query["config"]["model"] = "other-model"
        with mock.patch.object(online, "load_ai_config", return_value=private), \
                mock.patch.object(online, "fetch") as fetch:
            result = online.credential_test(query, self.server)
        self.assertFalse(result["ok"])
        fetch.assert_not_called()

    def test_translation_services_return_only_bounded_status(self):
        with mock.patch.object(online, "load_tencent_config", return_value={
                "secret_id": "fixture", "secret_key": "fixture", "region": "fixture"}), \
                mock.patch.object(online, "tencent_translation", return_value=["合成结果"]):
            result = online.credential_test(
                {"service": "translation.tencent", "config": {}}, self.server)
        self.assertEqual(result, {"ok": True, "message": "连接成功，当前配置有效。"})
        with mock.patch.object(online, "custom_translation", side_effect=RuntimeError("private detail")):
            result = online.credential_test({"service": "translation.custom", "config": {
                "endpoint": "https://fixture.invalid/translate", "api_key": "fixture"}}, self.server)
        self.assertFalse(result["ok"])
        self.assertNotIn("private detail", result["message"])


class VoiceCredentialTest(unittest.TestCase):
    def setUp(self):
        self.server = SimpleNamespace(config_path=Path("/private/voice.json"))

    def test_asr_and_polish_select_matching_private_profiles(self):
        configuration = {
            "asr": {"provider": "openai", "model": "whisper-1", "token": "private",
                    "endpoint": "https://fixture.invalid/asr"},
            "polish": {"provider": "deepseek", "model": "fixture-chat", "token": "private",
                       "endpoint": "https://fixture.invalid/chat"},
            "asr_profiles": {}, "polish_profiles": {},
        }
        with mock.patch.object(voice, "load_config", return_value=configuration), \
                mock.patch.object(voice, "batch_asr_credential_test", return_value=True) as batch:
            result = voice.credential_test({"service": "voice.asr", "config": {
                "asr_provider": "openai", "asr_model": "whisper-1"}}, self.server)
        self.assertTrue(result["ok"])
        batch.assert_called_once_with(configuration["asr"])
        with mock.patch.object(voice, "load_config", return_value=configuration), \
                mock.patch.object(voice, "polish_credential_test", return_value=True) as polish:
            result = voice.credential_test({"service": "voice.polish", "config": {
                "polish_provider": "deepseek", "polish_model": "fixture-chat"}}, self.server)
        self.assertTrue(result["ok"])
        polish.assert_called_once_with(configuration["polish"])

    def test_invalid_or_failed_requests_do_not_expose_details(self):
        result = voice.credential_test({"service": "voice.asr", "config": {"bad": 1}}, self.server)
        self.assertEqual(result, {"ok": False, "message": "当前语音选项无效。"})
        with mock.patch.object(voice, "load_config", side_effect=RuntimeError("private detail")):
            result = voice.credential_test(
                {"service": "voice.asr", "config": {"asr_provider": "openai"}}, self.server)
        self.assertFalse(result["ok"])
        self.assertNotIn("private detail", result["message"])


if __name__ == "__main__":
    unittest.main()
