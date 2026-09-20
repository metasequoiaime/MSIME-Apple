#!/usr/bin/env python3
"""The packaged provider's model listing and polish test. Synthetic responses only.

Neither request may take an endpoint or a token from the settings page: the page
names a provider, the private owner-only file holds the credential, and the two
have to agree first. That is the whole point of keeping AI credentials out of the
shell on this platform, so it is what these cases check.
"""
import importlib.machinery
import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))


def load(name, filename):
    loader = importlib.machinery.SourceFileLoader(name, str(ROOT / "scripts" / filename))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


online = load("ai_service_online_provider", "msime-client-online-provider")

PRIVATE = {
    "provider": "synthetic",
    "endpoint": "https://service.example.invalid/openai/v1/chat/completions",
    "model": "synthetic-model",
    "token": "synthetic-token",
}


class AiServiceContract(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="msime-ai-service-")
        self.addCleanup(self.directory.cleanup)
        path = Path(self.directory.name) / "ai-provider.json"
        path.write_text(json.dumps(PRIVATE))
        path.chmod(0o600)
        self.server = SimpleNamespace(ai_config_path=str(path))
        self.requests = []
        self.original_fetch = online.fetch
        self.addCleanup(setattr, online, "fetch", self.original_fetch)

    def respond(self, document):
        def fetch(url, timeout, body=None, token=None, extra_headers=None):
            self.requests.append({"url": url, "body": body, "token": token})
            return document

        online.fetch = fetch

    def test_model_catalogue_sits_beside_the_configured_endpoint(self):
        # The endpoint's own API prefix is reused rather than assumed, which is
        # what the desktop shell's ai_models_url does for the hosts that hold the
        # token themselves.
        self.assertEqual(
            online.ai_models_url(PRIVATE["endpoint"]),
            "https://service.example.invalid/openai/v1/models",
        )
        self.assertEqual(
            online.ai_models_url("https://service.example.invalid/chat/completions"),
            "https://service.example.invalid/v1/models",
        )

    def test_models_are_listed_with_the_private_token_and_bounded(self):
        self.respond(
            {
                "data": [
                    {"id": "alpha"},
                    {"id": "alpha"},
                    {"id": ""},
                    {"id": "bad\nname"},
                    {"id": "beta"},
                    "not an object",
                ]
            }
        )
        result = online.ai_models(
            {"provider": "synthetic", "endpoint": PRIVATE["endpoint"]}, self.server
        )
        # Duplicates, empties and control characters are dropped; order is kept.
        self.assertEqual(result, {"models": ["alpha", "beta"]})
        self.assertEqual(self.requests[0]["url"], "https://service.example.invalid/openai/v1/models")
        self.assertEqual(self.requests[0]["token"], PRIVATE["token"])
        self.assertIsNone(self.requests[0]["body"])

    def test_models_refuse_a_provider_or_endpoint_the_private_file_disagrees_with(self):
        self.respond({"data": [{"id": "alpha"}]})
        for query in (
            {"provider": "other", "endpoint": PRIVATE["endpoint"]},
            {"provider": "synthetic", "endpoint": "https://elsewhere.example.invalid/v1/chat"},
            {"provider": "synthetic"},
            {},
        ):
            self.assertEqual(online.ai_models(query, self.server), {"models": []})
        # Nothing left the process for any of them.
        self.assertEqual(self.requests, [])

    def test_polish_sends_the_page_text_under_the_private_credential(self):
        self.respond({"choices": [{"message": {"content": "  polished  "}}]})
        result = online.ai_polish_test(
            {
                "provider": "synthetic",
                "endpoint": PRIVATE["endpoint"],
                "model": PRIVATE["model"],
                "prompt": "synthetic prompt",
                "text": "synthetic input",
            },
            self.server,
        )
        self.assertEqual(result, {"text": "polished"})
        sent = self.requests[0]
        self.assertEqual(sent["url"], PRIVATE["endpoint"])
        self.assertEqual(sent["token"], PRIVATE["token"])
        self.assertEqual(sent["body"]["model"], PRIVATE["model"])
        self.assertEqual(
            [message["content"] for message in sent["body"]["messages"]],
            ["synthetic prompt", "synthetic input"],
        )

    def test_polish_requires_the_model_to_match_and_real_text(self):
        self.respond({"choices": [{"message": {"content": "polished"}}]})
        base = {
            "provider": "synthetic",
            "endpoint": PRIVATE["endpoint"],
            "model": PRIVATE["model"],
            "prompt": "synthetic prompt",
            "text": "synthetic input",
        }
        # The model is compared here, unlike the listing: a polish request runs on
        # one specific model and the settings page must be naming the configured
        # one.
        for override in (
            {"model": "another-model"},
            {"text": "   "},
            {"text": ""},
            {"text": None},
            {"text": "x" * 8193},
            {"prompt": "p" * 8193},
        ):
            self.assertEqual(
                online.ai_polish_test({**base, **override}, self.server), {"text": ""}
            )
        self.assertEqual(self.requests, [])

    def test_polish_and_models_survive_a_service_answering_nonsense(self):
        for document in ({}, {"choices": []}, {"choices": [{}]}, [], "text", None):
            self.respond(document)
            self.assertEqual(
                online.ai_polish_test(
                    {
                        "provider": "synthetic",
                        "endpoint": PRIVATE["endpoint"],
                        "model": PRIVATE["model"],
                        "prompt": "p",
                        "text": "t",
                    },
                    self.server,
                ),
                {"text": ""},
            )
            self.assertEqual(
                online.ai_models(
                    {"provider": "synthetic", "endpoint": PRIVATE["endpoint"]}, self.server
                ),
                {"models": []},
            )

    def test_thinking_is_disabled_for_the_providers_that_need_it_said(self):
        for provider, key in (("deepseek", "thinking"), ("siliconflow", "enable_thinking")):
            path = Path(self.directory.name) / f"{provider}.json"
            path.write_text(json.dumps({**PRIVATE, "provider": provider}))
            path.chmod(0o600)
            server = SimpleNamespace(ai_config_path=str(path))
            self.requests.clear()
            self.respond({"choices": [{"message": {"content": "polished"}}]})
            online.ai_polish_test(
                {
                    "provider": provider,
                    "endpoint": PRIVATE["endpoint"],
                    "model": PRIVATE["model"],
                    "prompt": "p",
                    "text": "t",
                },
                server,
            )
            self.assertIn(key, self.requests[0]["body"])


if __name__ == "__main__":
    unittest.main()
