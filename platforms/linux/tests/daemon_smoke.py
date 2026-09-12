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
assert bus.set_global_engine("msime-client-preview"), "Global engine activation failed"
wait(lambda: context.get_engine() is not None and context.get_engine().get_name() == "msime-client-preview")
context.property_activate("ChinesePunctuation", IBus.PropState.UNCHECKED)
context.property_activate("EnglishCandidates", IBus.PropState.CHECKED)
context.property_activate("EmojiCandidates", IBus.PropState.CHECKED)
context.property_activate("KaomojiCandidates", IBus.PropState.CHECKED)
for character in "nihao":
    assert context.process_key_event(ord(character), 0, 0)
assert context.process_key_event(IBus.KEY_space, 0, 0)
wait(lambda: commits == ["你好"])
# This fixture uses global CN/EN mode. A different input source must clear
# that authority so returning starts with the configured Chinese default.
context.property_activate("InputMode", IBus.PropState.UNCHECKED)
assert not context.process_key_event(ord("n"), 0, 0)
assert bus.set_global_engine("xkb:us::eng"), "US input source activation failed"
wait(lambda: context.get_engine() is not None and context.get_engine().get_name() == "xkb:us::eng")
assert bus.set_global_engine("msime-client-preview"), "Input source reactivation failed"
wait(lambda: context.get_engine() is not None and context.get_engine().get_name() == "msime-client-preview")
for character in "nihao":
    assert context.process_key_event(ord(character), 0, 0), "Source switch retained global English mode"
assert context.process_key_event(IBus.KEY_space, 0, 0)
wait(lambda: commits == ["你好", "你好"])
context.focus_out()
context.destroy()
print("IBus daemon factory and input-context acceptance passed")
