#!/usr/bin/env python3
"""Windows-parity regressions for Linux AI candidate reuse."""
import importlib.machinery
import importlib.util
from pathlib import Path
from types import SimpleNamespace
import sys
import threading
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
loader = importlib.machinery.SourceFileLoader(
    "ai_cache_online_provider", str(ROOT / "scripts" / "msime-client-online-provider"))
spec = importlib.util.spec_from_loader(loader.name, loader)
provider = importlib.util.module_from_spec(spec)
loader.exec_module(provider)


def query(generation=1, context="", prompt="first", segments=None):
    return {
        "ai_eligible": True,
        "generation": generation,
        "session_id": generation,
        "ai_context": context,
        "pinyin_segments": segments or ["ni", "hao"],
        "ai_assistant": {
            "enabled": True,
            "provider": "synthetic",
            "endpoint": "https://ai.invalid/v1/chat/completions",
            "model": "synthetic-model",
            "prompt": prompt,
            "candidate_limit": 3,
        },
    }


class AiCandidateCache(unittest.TestCase):
    def setUp(self):
        self.state = SimpleNamespace(cache={}, lock=threading.Lock())
        self.config = {
            "provider": "synthetic",
            "endpoint": "https://ai.invalid/v1/chat/completions",
            "model": "synthetic-model",
            "token": "synthetic-token",
        }

    def configured(self, request):
        return provider.configured_ai(
            request, Path("/private/synthetic.json"), self.state.cache,
            self.state.lock)

    def test_success_is_reused_across_generation_context_and_prompt(self):
        rows = [{"text": "你好", "source": 1}]
        with mock.patch.object(provider, "load_ai_config",
                               return_value=self.config), \
                mock.patch.object(provider, "ai", return_value=rows) as ai:
            self.assertEqual(self.configured(query()), rows)
            self.assertEqual(
                self.configured(query(generation=9, context="private context",
                                      prompt="changed")), rows)
        self.assertEqual(ai.call_count, 1)

    def test_provider_identity_and_segments_partition_cache(self):
        rows = [{"text": "你好", "source": 1}]
        changed_model = query()
        changed_model["ai_assistant"]["model"] = "other-model"
        changed_segments = query(segments=["nin", "hao"])
        with mock.patch.object(provider, "load_ai_config",
                               return_value=self.config), \
                mock.patch.object(provider, "ai", return_value=rows) as ai:
            self.configured(query())
            self.configured(changed_model)
            self.configured(changed_segments)
        self.assertEqual(ai.call_count, 3)

    def test_empty_result_is_not_cached(self):
        with mock.patch.object(provider, "load_ai_config",
                               return_value=self.config), \
                mock.patch.object(provider, "ai",
                                  side_effect=[None, [{"text": "重试", "source": 1}]]) as ai:
            self.assertIsNone(self.configured(query()))
            self.assertEqual(self.configured(query()),
                             [{"text": "重试", "source": 1}])
        self.assertEqual(ai.call_count, 2)

    def test_cache_is_bounded_without_retaining_request_secrets(self):
        key = provider.ai_cache_key(query(context="sensitive", prompt="private"))
        self.assertNotIn("sensitive", key)
        self.assertNotIn("private", key)
        self.assertNotIn("synthetic-token", key)
        self.state.cache.update({str(index): [] for index in range(
            provider.MAX_AI_CACHE_ENTRIES)})
        rows = [{"text": "你好", "source": 1}]
        with mock.patch.object(provider, "load_ai_config",
                               return_value=self.config), \
                mock.patch.object(provider, "ai", return_value=rows):
            self.configured(query())
        self.assertEqual(len(self.state.cache), 1)


if __name__ == "__main__":
    unittest.main()
