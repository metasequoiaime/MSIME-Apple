#!/usr/bin/env python3
"""Keep Linux cloud candidate timing aligned with Windows CloudCandidateWorker."""
import importlib.machinery
import importlib.util
from pathlib import Path
import sys
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
loader = importlib.machinery.SourceFileLoader(
    "cloud_timeout_provider", str(ROOT / "scripts" / "msime-client-online-provider"))
spec = importlib.util.spec_from_loader(loader.name, loader)
provider = importlib.util.module_from_spec(spec)
loader.exec_module(provider)


class CloudTimeoutParity(unittest.TestCase):
    def test_cloud_request_uses_two_second_total_budget(self):
        result = ["SUCCESS", [["nihao", ["你好"]]]]
        query = {"cloud_candidates": True, "cloud_eligible": True,
                 "query_text": "nihao", "scheme": 0}
        with mock.patch.object(provider, "fetch", return_value=result) as fetch:
            self.assertEqual(provider.cloud(query), {"text": "你好", "source": 0})
        self.assertEqual(fetch.call_args.args[1], 2.0)
        self.assertEqual(provider.CLOUD_REQUEST_TIMEOUT, 2.0)


if __name__ == "__main__":
    unittest.main()
