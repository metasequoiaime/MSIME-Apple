"""Real IBus daemon/client acceptance inside an isolated D-Bus session only."""
import sys
import time

import gi

gi.require_version("IBus", "1.0")
from gi.repository import GLib, IBus

IBus.init()
bus = IBus.Bus.new()
if not bus.is_connected():
    sys.exit("Test IBus daemon is unavailable")


def wait(predicate):
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        while GLib.MainContext.default().iteration(False):
            pass
        if predicate():
            return
        time.sleep(0.02)
    raise AssertionError("Expected IBus state was not observed")


wait(lambda: any(engine.get_name() == "msime-client-preview" for engine in bus.list_active_engines()))
context = bus.create_input_context("msime-synthetic-editor")
commits = []
context.connect("commit-text", lambda _context, text: commits.append(text.get_text()))
context.set_capabilities(IBus.Capabilite.FOCUS | IBus.Capabilite.PREEDIT_TEXT | IBus.Capabilite.LOOKUP_TABLE)
context.focus_in()
context.set_engine("msime-client-preview")
wait(lambda: context.get_engine() is not None and context.get_engine().get_name() == "msime-client-preview")
for character in "nihao":
    assert context.process_key_event(ord(character), 0, 0)
assert context.process_key_event(IBus.KEY_space, 0, 0)
wait(lambda: commits == ["你好"])
context.focus_out()
context.destroy()
print("IBus daemon factory and input-context acceptance passed")
