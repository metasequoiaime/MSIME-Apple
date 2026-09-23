#!/usr/bin/env python3
"""msime-client-ibus-launcher 的崩溃守护：宿主崩溃后按退避重启，维护退出、总线断开、配置失效和停止请求都不重启。

用桩代替 msime-client-ibus，按预设剧本逐次崩溃或退出，只看启动器起了它几次、间隔多久、带了什么参数。不需要 IBus、D-Bus 或词库。
"""
import json
import os
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LAUNCHER = ROOT / "scripts/msime-client-ibus-launcher"
STOP_STATUS = 77

STUB = r'''#!{python}
import json, os, signal, sys, time
from pathlib import Path
scratch = Path({scratch!r})
log = scratch / "runs.log"
runs = log.read_text().splitlines() if log.exists() else []
plan = json.loads((scratch / "plan.json").read_text())
action = plan[len(runs)] if len(runs) < len(plan) else "exit 3"
with log.open("a") as output:
    output.write(json.dumps({{"pid": os.getpid(), "args": sys.argv[1:], "time": time.monotonic()}}) + "\n")
def terminated(signum, frame):
    with (scratch / "signals.log").open("a") as output:
        output.write(f"{{signum}}\n")
    sys.exit(143)
signal.signal(signal.SIGTERM, terminated)
if action == "segv":
    os.kill(os.getpid(), signal.SIGSEGV)
elif action == "kill":
    os.kill(os.getpid(), signal.SIGKILL)
elif action == "unlink-config":
    Path(sys.argv[-1]).unlink()
    os.kill(os.getpid(), signal.SIGSEGV)
elif action == "hang":
    while True:
        time.sleep(0.05)
elif action.startswith("exit "):
    sys.exit(int(action.split()[1]))
time.sleep(5)
sys.exit(4)
'''


class Fixture:
    def __init__(self, scratch: Path):
        self.scratch = scratch
        self.bin_dir = scratch / "bin"
        self.bin_dir.mkdir()
        launcher = self.bin_dir / "msime-client-ibus-launcher"
        launcher.write_text(LAUNCHER.read_text())
        launcher.chmod(0o755)
        stub = self.bin_dir / "msime-client-ibus"
        stub.write_text(STUB.format(python=sys.executable, scratch=str(scratch)))
        stub.chmod(0o755)
        self.options = scratch / "options/runtime-options.json"
        self.options.parent.mkdir()
        self.environment = {
            key: value for key, value in os.environ.items() if not key.startswith("MSIME_")
        }
        self.environment.update(HOME=str(scratch / "home"), XDG_CONFIG_HOME=str(scratch / "config"))

    def reset(self, plan: list) -> None:
        for name in ("runs.log", "signals.log"):
            (self.scratch / name).unlink(missing_ok=True)
        (self.scratch / "plan.json").write_text(json.dumps(plan))
        self.options.write_text("{}")

    def start(self) -> subprocess.Popen:
        return subprocess.Popen(
            [str(self.bin_dir / "msime-client-ibus-launcher"), str(self.options)],
            env=self.environment, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True,
        )

    def runs(self) -> list:
        log = self.scratch / "runs.log"
        return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []

    def signals(self) -> list:
        log = self.scratch / "signals.log"
        return [int(line) for line in log.read_text().splitlines()] if log.exists() else []


def wait_for(predicate, message: str, timeout: float = 10) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.02)
    raise AssertionError(message)


def main() -> int:
    with tempfile.TemporaryDirectory() as name:
        fixture = Fixture(Path(name))
        options = str(fixture.options)

        # 崩溃（含被信号杀死）与非零退出都重启，间隔与 Windows watchdog 相同，从 2 秒起翻倍（2、4、8 秒）；重启后的宿主带 --recovered。exit 0 是总线断开（ibus-daemon 在退出或重启），守护不重启，随之退出。
        fixture.reset(["segv", "kill", "exit 1", "exit 0"])
        launcher = fixture.start()
        _, errors = launcher.communicate(timeout=30)
        assert launcher.returncode == 0, (launcher.returncode, errors)
        runs = fixture.runs()
        assert [run["args"] for run in runs] == [[options]] + [["--recovered", options]] * 3, runs
        gaps = [later["time"] - earlier["time"] for earlier, later in zip(runs, runs[1:])]
        for gap, expected in zip(gaps, (2, 4, 8)):
            assert expected - 0.2 <= gap <= expected + 1.5, gaps
        assert errors.count("restarting in") == 3, errors
        assert "restarting in 2s" in errors and "restarting in 8s" in errors, errors

        # 退避期间 ibus-daemon 被 SIGKILL 或崩溃、没来得及停止守护：重启的宿主连不上总线，以 0 退出。守护必须就此结束，不能成为孤儿每 30 秒重试，更不能在之后启动的新 daemon 上重复注册 component。
        fixture.reset(["segv", "exit 0"])
        launcher = fixture.start()
        _, errors = launcher.communicate(timeout=10)
        assert launcher.returncode == 0, (launcher.returncode, errors)
        time.sleep(1.5)
        runs = fixture.runs()
        assert [run["args"] for run in runs] == [[options], ["--recovered", options]], runs
        assert errors.count("restarting in") == 1, errors

        # 维护退出（Ctrl+Shift+Alt+T）是有意停止：原样退出，不重启。
        fixture.reset([f"exit {STOP_STATUS}", "exit 0"])
        launcher = fixture.start()
        _, errors = launcher.communicate(timeout=10)
        assert launcher.returncode == STOP_STATUS, (launcher.returncode, errors)
        time.sleep(1.5)
        assert len(fixture.runs()) == 1, fixture.runs()
        assert "restarting" not in errors, errors

        # 配置在崩溃后读不到了：重启也救不回来，报错退出。
        fixture.reset(["unlink-config", "exit 0"])
        launcher = fixture.start()
        _, errors = launcher.communicate(timeout=10)
        assert launcher.returncode == 1, (launcher.returncode, errors)
        assert "no longer readable" in errors, errors
        assert len(fixture.runs()) == 1, fixture.runs()

        # ibus-daemon 用 SIGTERM 停组件；SIGINT、SIGHUP 同样当作停止请求。守护把它作为 SIGTERM 转给宿主，宿主退出后不再重启。
        for request in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
            fixture.reset(["hang", "exit 0"])
            launcher = fixture.start()
            wait_for(lambda: len(fixture.runs()) == 1, "host was not started")
            time.sleep(0.2)
            launcher.send_signal(request)
            _, errors = launcher.communicate(timeout=10)
            assert fixture.signals() == [signal.SIGTERM], (request, fixture.signals())
            assert launcher.returncode == 143, (request, launcher.returncode, errors)
            time.sleep(1.5)
            assert len(fixture.runs()) == 1, (request, fixture.runs())

        # 退避等待期间收到停止请求：立即退出，不等满等待时间，也不再起宿主。
        fixture.reset(["segv", "exit 0"])
        launcher = fixture.start()
        wait_for(lambda: len(fixture.runs()) == 1, "host was not started")
        time.sleep(0.3)
        requested = time.monotonic()
        launcher.terminate()
        launcher.communicate(timeout=10)
        assert time.monotonic() - requested < 0.8, "stop request waited for the backoff to elapse"
        time.sleep(1.5)
        assert len(fixture.runs()) == 1, fixture.runs()

    print("IBus launcher supervisor tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
