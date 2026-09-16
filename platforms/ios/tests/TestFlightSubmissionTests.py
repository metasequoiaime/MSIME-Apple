#!/usr/bin/env python3
"""提交 TestFlight 外部审核那段逻辑的测试。

这段代码只在发布当天跑,而且跑在拿得到 App Store Connect 凭据的作业里 —— 想靠"下次发版看看对不对"
来验证它,代价是一次失败的发布。所以真正会出错的几处都在这里用桩走一遍:找不到 build、build 处理
失败、处理超时、找不到测试组、以及重复提交。
"""
import importlib.util
import sys
import unittest
from pathlib import Path
from unittest import mock

SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"


def load_module():
    """脚本依赖 pyjwt,而它只在发布作业里装。缺了就跳过,而不是把整个套件拖红。"""
    if importlib.util.find_spec("jwt") is None:
        raise unittest.SkipTest("pyjwt is not installed; the release job installs it")
    spec = importlib.util.spec_from_file_location("submit_testflight_review",
                                                  SCRIPTS / "submit_testflight_review.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class TestFlightSubmissionTests(unittest.TestCase):
    def setUp(self):
        self.module = load_module()

    def test_the_exact_build_is_chosen_and_a_miss_names_what_is_there(self):
        builds = {"data": [{"id": "b1", "attributes": {"version": "1003.1.1"}}]}
        with mock.patch.object(self.module, "request", return_value=builds):
            self.assertEqual(self.module.find_build("t", "1", "1003.1.1")["id"], "b1")

        # 过滤是服务端做的,但返回里混进别的版本时不能将就着用 —— 提交错一个 build 比失败更难发现。
        def answer(method, path, auth, body=None):
            if "sort=-uploadedDate" in path:
                return {"data": [{"attributes": {"version": "1002.71.1"}},
                                 {"attributes": {"version": "1002.69.1"}}]}
            return {"data": [{"id": "other", "attributes": {"version": "1002.71.1"}}]}

        with mock.patch.object(self.module, "request", side_effect=answer):
            with self.assertRaises(self.module.Failure) as raised:
                self.module.find_build("t", "1", "1003.1.1")
        # 报错要说出它看到了什么,否则发布当天只知道"没找到"。
        self.assertIn("1003.1.1", str(raised.exception))
        self.assertIn("1002.71.1", str(raised.exception))

    def test_processing_is_awaited_until_valid(self):
        states = iter(["PROCESSING", "PROCESSING", "VALID"])
        answer = lambda *a, **k: {"data": {"attributes": {"processingState": next(states)}}}
        with mock.patch.object(self.module, "request", side_effect=answer), \
             mock.patch.object(self.module.time, "sleep"):
            self.module.await_processing("t", "b1", timeout=600)

    def test_a_build_that_fails_processing_stops_the_step(self):
        for state in ("INVALID", "FAILED"):
            answer = lambda *a, **k: {"data": {"attributes": {"processingState": state}}}
            with self.subTest(state=state), \
                 mock.patch.object(self.module, "request", side_effect=answer), \
                 mock.patch.object(self.module.time, "sleep"):
                with self.assertRaises(self.module.Failure) as raised:
                    self.module.await_processing("t", "b1", timeout=600)
                self.assertIn(state, str(raised.exception))

    def test_waiting_forever_is_a_failure_not_a_hang(self):
        answer = lambda *a, **k: {"data": {"attributes": {"processingState": "PROCESSING"}}}
        clock = iter([0, 1, 2_000, 2_000])
        with mock.patch.object(self.module, "request", side_effect=answer), \
             mock.patch.object(self.module.time, "sleep"), \
             mock.patch.object(self.module.time, "time", side_effect=lambda: next(clock)):
            with self.assertRaises(self.module.Failure):
                self.module.await_processing("t", "b1", timeout=1)

    def test_the_group_is_found_by_name_and_a_miss_lists_the_names(self):
        groups = {"data": [{"id": "g1", "attributes": {"name": "外部测试"}},
                           {"id": "g2", "attributes": {"name": "内部"}}]}
        with mock.patch.object(self.module, "request", return_value=groups):
            self.assertEqual(self.module.group_id("t", "1", "外部测试"), "g1")
            with self.assertRaises(self.module.Failure) as raised:
                self.module.group_id("t", "1", "没有这个组")
        self.assertIn("外部测试", str(raised.exception))

    def test_a_rerun_of_a_submitted_build_is_not_a_failure(self):
        """发布重跑一次不该因为"活已经干完了"而变红。"""
        calls = []

        def answer(method, path, auth, body=None):
            calls.append((method, path))
            if path == "/betaAppReviewSubmissions":
                raise self.module.Failure("POST -> 409\nENTITY_ERROR.ATTRIBUTE.INVALID already exists")
            if path.startswith("/builds?filter[app]"):
                return {"data": [{"id": "b1", "attributes": {"version": "1003.1.1"}}]}
            if path.startswith("/builds/"):
                return {"data": {"attributes": {"processingState": "VALID"}}}
            if path.startswith("/betaGroups?"):
                return {"data": [{"id": "g1", "attributes": {"name": "外部测试"}}]}
            return {}

        argv = ["submit", "--app", "1", "--build-version", "1003.1.1", "--group", "外部测试",
                "--key-id", "K", "--issuer-id", "I", "--key-path", str(SCRIPTS)]
        with mock.patch.object(self.module, "request", side_effect=answer), \
             mock.patch.object(self.module, "token", return_value="t"), \
             mock.patch.object(sys, "argv", argv):
            self.assertEqual(self.module.main(), 0)
        # 分组在提交之前 —— 顺序反了的话,审核提交的是一个还没分发给任何人的 build。
        posts = [path for method, path in calls if method == "POST"]
        self.assertEqual(posts, ["/betaGroups/g1/relationships/builds", "/betaAppReviewSubmissions"])


if __name__ == "__main__":
    unittest.main()
