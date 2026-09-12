#!/usr/bin/env python3
"""Exercise installed-provider config discovery with local synthetic responses."""
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
HARNESS = r'''
import importlib.machinery, importlib.util, json, sys
path = sys.argv.pop(1)
loader = importlib.machinery.SourceFileLoader("provider", path)
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)
def local_fetch(url, *args, **kwargs):
    if url == "https://tmt.tencentcloudapi.com/":
        return {"Response": {"TargetTextList": ["synthetic translation"]}}
    if url == "https://provider.example.invalid/":
        return {"choices": [{"message": {"content": json.dumps({"candidates": [{"text": "synthetic candidate"}]})}}]}
    raise AssertionError("unexpected endpoint")
module.fetch = local_fetch
module.main()
'''


class ConfigDiscovery(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="msime-config-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.config = self.root / "config"
        self.address = self.root / "provider.sock"
        self.env = {**os.environ, "PYTHONPATH": str(ROOT)}

    def start(self, *args):
        process = subprocess.Popen(
            [sys.executable, "-c", HARNESS, str(ROOT / "msime-client-online-provider"),
             str(self.address), *map(str, args)], env=self.env,
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        self.addCleanup(self.stop, process)
        return process

    @staticmethod
    def stop(process):
        if process.poll() is None:
            process.terminate()
        process.communicate(timeout=5)

    def request(self, kind, query):
        with socket.socket(socket.AF_UNIX) as client:
            client.settimeout(3)
            client.connect(str(self.address))
            client.sendall(json.dumps({"version": 1, "kind": kind, "query": query}).encode() + b"\n")
            with client.makefile("rb") as reader:
                return json.loads(reader.readline(16385))

    def test_launcher_tracks_directory_before_files_exist(self):
        loader = importlib.machinery.SourceFileLoader("launcher", str(ROOT / "msime-client-provider-session"))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        module = importlib.util.module_from_spec(spec)
        loader.exec_module(module)
        class Launched(Exception):
            pass
        with mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": str(self.root), "XDG_CONFIG_HOME": str(self.config)}), \
             mock.patch.object(sys, "argv", ["provider-session", "online"]), \
             mock.patch.object(module.os, "execv", side_effect=Launched) as execute:
            with self.assertRaises(Launched):
                module.main()
        command = execute.call_args.args[1]
        self.assertEqual(command[-2:], ["--config-directory", str(self.config / "msime-client")])
        self.assertFalse(self.config.exists())

    def test_late_creation_permissions_removal_and_repair(self):
        process = self.start("--config-directory", self.config)
        deadline = time.monotonic() + 3
        while not self.address.exists() and process.poll() is None and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertIsNone(process.poll(), "provider did not start without optional config files")
        self.assertTrue(self.address.exists())
        ai = {"cloud_candidates": False, "cloud_eligible": False, "ai_eligible": True,
              "pinyin_segments": ["ni", "hao"], "ai_assistant": {
                  "enabled": True, "provider": "synthetic", "endpoint": "https://provider.example.invalid/",
                  "model": "synthetic", "prompt": "synthetic prompt"}}
        translation = {"candidates": ["你好"], "target_language": "en"}
        def check(enabled):
            self.assertEqual(bool(self.request("online", ai)["candidates"]), enabled)
            self.assertEqual(bool(self.request("translation", translation)["translations"]), enabled)
        check(False)
        self.config.mkdir(mode=0o700)
        files = [(self.config / "ai-provider.json", {
            "provider": "synthetic", "endpoint": "https://provider.example.invalid/",
            "model": "synthetic", "token": "synthetic-local-token"}),
            (self.config / "tencent-provider.json", {
                "secret_id": "synthetic-local-id", "secret_key": "synthetic-local-key"})]
        def save():
            for path, value in files:
                temporary = path.with_suffix(".tmp")
                temporary.write_text(json.dumps(value))
                temporary.chmod(0o600)
                temporary.replace(path)
        save()
        check(True)
        for path, _ in files:
            path.chmod(0o644)
        check(False)
        save()
        check(True)
        for path, _ in files:
            path.unlink()
        check(False)
        for path, _ in files:
            path.write_text("{")
            path.chmod(0o600)
        check(False)
        save()
        check(True)
        self.assertIsNone(process.poll())

    def test_explicit_invalid_files_still_fail_at_startup(self):
        for option in ("--ai-config", "--tencent-config"):
            with self.subTest(option=option):
                process = self.start(option, self.root / "absent.json")
                process.communicate(timeout=3)
                self.assertEqual(process.returncode, 2)

    def test_relative_directory_is_rejected(self):
        process = self.start("--config-directory", "relative")
        process.communicate(timeout=3)
        self.assertEqual(process.returncode, 2)


if __name__ == "__main__":
    unittest.main()
