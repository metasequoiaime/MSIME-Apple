#!/usr/bin/env python3
"""msime-client-setup 的判定规则，不需要词库也不联网。

这个入口要做的判断——这份词库能不能用、锁里没有 URL 的那一项归哪个固定归档、去哪里找锁
和已有词库——都是纯函数，钉在这里。容器门禁不带词库，凡是需要真实词库才注册的检查在那里
等于不存在，所以判定逻辑必须能脱离词库单独验证。
"""
import hashlib
import importlib.machinery
import importlib.util
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_loader(
    "msime_client_setup",
    importlib.machinery.SourceFileLoader(
        "msime_client_setup", str(ROOT / "scripts/msime-client-setup")
    ),
)
setup = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(setup)


def write(path: Path, payload: bytes) -> str:
    path.write_bytes(payload)
    return hashlib.sha256(payload).hexdigest()


def main() -> int:
    with tempfile.TemporaryDirectory() as name:
        root = Path(name)
        resources = root / "resources"
        resources.mkdir()
        payload = b"synthetic dictionary bytes"
        checksum = write(resources / "msime.db", payload)
        lock = {
            "artifacts": [
                {"name": "msime.db", "sha256": checksum, "size": len(payload),
                 "url": "https://example.invalid/msime.db"},
            ]
        }

        # 名称、大小、摘要三样都对才算这份词库可用。
        assert setup.verify_directory(resources, lock) == []

        # 大小对不上时不再去算摘要，报的就是大小。
        lock["artifacts"][0]["size"] = len(payload) + 1
        problems = setup.verify_directory(resources, lock)
        assert len(problems) == 1 and "大小不符" in problems[0], problems
        lock["artifacts"][0]["size"] = len(payload)

        # 大小相同而内容被换掉：只有摘要能发现，这正是它存在的理由。
        write(resources / "msime.db", b"synthetic dictionary bytez")
        problems = setup.verify_directory(resources, lock)
        assert len(problems) == 1 and "SHA-256" in problems[0], problems
        write(resources / "msime.db", payload)

        # 宿主拒绝锁之外的任何条目，这里同样报出来；只有 Engine 的 helpcodes 子目录例外。
        (resources / "helpcodes").mkdir()
        assert setup.verify_directory(resources, lock) == []
        (resources / "retired.db").write_bytes(b"dropped by a newer lock")
        (resources / "nested").mkdir()
        problems = setup.verify_directory(resources, lock)
        assert len(problems) == 2 and "nested" in problems[0] and "retired.db" in problems[1], problems
        assert setup.unexpected_entries(resources, lock) == problems
        (resources / "retired.db").unlink()
        (resources / "nested").rmdir()

        # 缺文件与内容不对是两种报告，不要混成一句「不可用」。
        (resources / "msime.db").unlink()
        problems = setup.verify_directory(resources, lock)
        assert len(problems) == 1 and "缺少" in problems[0], problems

    # 词库锁里没有 URL 的那一项来自引擎源码树，按 path 前缀归到对应的固定归档。
    engine_lock = {
        "dependencies": [
            {"path": "googlepinyinime-rev", "repository": "metasequoiaime/Google-PinyinIME-Rev",
             "archive": "https://example.invalid/a.tar.gz", "sha256": "0" * 64},
            {"path": "utfcpp", "repository": "nemtrif/utfcpp",
             "archive": "https://example.invalid/b.tar.gz", "sha256": "1" * 64},
        ]
    }
    found = setup.dependency_for("googlepinyinime-rev/data/dict_pinyin.dat", engine_lock)
    assert found is not None and found["path"] == "googlepinyinime-rev", found
    # 前缀必须落在目录边界上，不能让 utfcpp 匹配到 utfcpp-extra/...
    assert setup.dependency_for("utfcpp-extra/x.dat", engine_lock) is None
    assert setup.dependency_for("", engine_lock) is None
    assert setup.dependency_for("googlepinyinime-rev/data/dict_pinyin.dat", {}) is None

    # 查找顺序：显式环境变量优先于安装前缀，随包词库优先于用户自备的那一份。
    prefix = Path("/opt/msime")
    os.environ["MSIME_DICTIONARY_LOCK"] = "/tmp/explicit-lock.json"
    candidates = setup.lock_candidates(prefix)
    assert candidates[0] == Path("/tmp/explicit-lock.json"), candidates
    assert prefix / "share/msime-client/desktop-dictionary.lock.json" in candidates
    del os.environ["MSIME_DICTIONARY_LOCK"]
    assert setup.lock_candidates(prefix)[0] == prefix / "share/msime-client/desktop-dictionary.lock.json"

    os.environ["XDG_DATA_HOME"] = "/tmp/xdg-data"
    resources_order = setup.resource_candidates(prefix)
    assert resources_order == [
        prefix / "share/msime-client/resources",
        Path("/tmp/xdg-data/msime-client/resources"),
    ], resources_order

    # 在线和语音服务总是按 socket 启用（本地识别不需要私有配置）；剪贴板监视器只认默认位置的状态目录。
    with tempfile.TemporaryDirectory() as directory:
        config = Path(directory) / "msime-client"
        config.mkdir()
        assert setup.service_units(config, config) == [
            "msime-client-online.socket",
            "msime-client-voice.socket",
            "msime-client-clipboard.service",
        ]
        assert setup.service_units(Path(directory) / "elsewhere", config) == [
            "msime-client-online.socket",
            "msime-client-voice.socket",
        ]

    # 拒绝云候选时标志放在位置参数之前，这是 msime-client-prepare 唯一接受的位置。
    command = Path("/opt/msime/bin/msime-client-prepare")
    assert setup.prepare_command(command, Path("/r"), Path("/s"), True) == [str(command), "/r", "/s"]
    assert setup.prepare_command(command, Path("/r"), Path("/s"), False) == [
        str(command), "--no-cloud-candidates", "/r", "/s"
    ]

    print("setup resolution tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
