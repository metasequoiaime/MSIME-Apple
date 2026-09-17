"""Run under dbus-run-session; real daemon/frontend, synthetic input only."""
import ctypes
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

import dbus
import dbus.mainloop.glib
from gi.repository import GLib


def wait(predicate):
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        while GLib.MainContext.default().iteration(False):
            pass
        if predicate():
            return
        time.sleep(0.02)
    raise AssertionError("Expected frontend state was not observed")


def main():
    resources, library, addon = map(Path, sys.argv[1:])
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    assert not bus.name_has_owner("org.fcitx.Fcitx5"), "Requires isolated D-Bus session"
    with tempfile.TemporaryDirectory(prefix="msime-fcitx-daemon-") as directory:
        root = Path(directory)
        host = ctypes.CDLL(str(library))
        host.msime_client_prepare_host.argtypes = [ctypes.c_char_p, ctypes.c_size_t]
        host.msime_client_prepare_host.restype = ctypes.c_void_p
        host.msime_client_string_free.argtypes = [ctypes.c_void_p]
        request = json.dumps({"resources": str(resources), "state_root": str(root / "state")}).encode()
        raw = host.msime_client_prepare_host(request, len(request))
        assert raw, "Host preparation returned no result"
        try:
            result = json.loads(ctypes.string_at(raw))
        finally:
            host.msime_client_string_free(raw)
        assert result["ok"], "Host preparation failed"
        options = result["value"]
        options["preferences"].update(learning=False, cloud_candidates=False)
        (root / "options.json").write_text(json.dumps(options))
        config = root / "config" / "fcitx5"
        config.mkdir(parents=True)
        (config / "profile").write_text(
            "[Groups/0]\nName=Default\nDefault Layout=us\nDefaultIM=msime\n"
            "[Groups/0/Items/0]\nName=keyboard-us\nLayout=\n"
            "[Groups/0/Items/1]\nName=msime\nLayout=\n[GroupOrder]\n0=Default\n")
        runtime = root / "run"
        runtime.mkdir(mode=0o700)
        data = root / "data" / "fcitx5"
        (data / "addon").mkdir(parents=True)
        (data / "inputmethod").mkdir()
        source = Path(__file__).resolve().parents[1]
        (data / "addon" / "msime.conf").write_bytes((source / "msime.conf").read_bytes())
        (data / "inputmethod" / "msime.conf").write_bytes((source / "msime-inputmethod.conf").read_bytes())
        system_lib = subprocess.check_output(
            ["pkg-config", "--variable=libdir", "Fcitx5Core"], text=True).strip()
        env = dict(os.environ, XDG_CONFIG_HOME=str(root / "config"),
                   XDG_DATA_HOME=str(root / "data"), XDG_RUNTIME_DIR=str(runtime),
                   MSIME_FCITX5_OPTIONS=str(root / "options.json"),
                   FCITX_ADDON_DIRS=f"{addon.parent}:{system_lib}/fcitx5")
        with (root / "daemon.log").open("w") as log:
            daemon = subprocess.Popen(["fcitx5", "-D", "--keep"], env=env,
                                      stdout=log, stderr=log)
            try:
                wait(lambda: bus.name_has_owner("org.fcitx.Fcitx5"))
                service = "org.fcitx.Fcitx5"
                control = dbus.Interface(bus.get_object(service, "/controller"),
                                         "org.fcitx.Fcitx.Controller1")
                frontend = dbus.Interface(bus.get_object(service, "/org/freedesktop/portal/inputmethod"),
                                          "org.fcitx.Fcitx.InputMethod1")
                path, _ = frontend.CreateInputContext([("program", "msime-synthetic-editor")])
                context = dbus.Interface(bus.get_object(service, path), "org.fcitx.Fcitx.InputContext1")
                commits = []
                preedits = []
                context.connect_to_signal("CommitString", lambda text: commits.append(str(text)))
                context.connect_to_signal("UpdateFormattedPreedit",
                                          lambda parts, cursor: preedits.append("".join(str(p[0]) for p in parts)))
                context.SetCapability(dbus.UInt64(2 | 16 | 64))
                context.FocusIn()
                control.SetCurrentIM("msime")
                control.Activate()
                wait(lambda: str(control.CurrentInputMethod()) == "msime")
                for character in "nihao":
                    assert context.ProcessKeyEvent(ord(character), 0, 0, False, 0), "Composition key rejected"
                wait(lambda: "nihao" in preedits)
                assert context.ProcessKeyEvent(32, 0, 0, False, 0), "Commit key rejected"
                wait(lambda: len(commits) == 1)
                assert commits == ["你好"], "Unexpected committed result"
                context.FocusOut()
                context.DestroyIC()
                if os.environ.get("MSIME_TEST_GTK") == "1":
                    subprocess.run([sys.executable, str(source / "tests" / "gtk_editor.py")],
                                   env=dict(env, GTK_IM_MODULE="fcitx", GDK_BACKEND="x11"),
                                   check=True, timeout=30)
                control.Exit()
                assert daemon.wait(timeout=10) == 0, "Daemon failed on shutdown"
            finally:
                if daemon.poll() is None:
                    daemon.terminate()
                    try:
                        daemon.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        daemon.kill()
                        daemon.wait()
    print("Fcitx5 daemon/frontend composition and commit passed")


if __name__ == "__main__":
    main()
