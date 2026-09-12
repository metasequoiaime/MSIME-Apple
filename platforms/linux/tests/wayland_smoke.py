"""Real GTK3 Wayland IM-module acceptance on a dedicated headless compositor, synthetic text only."""
import os
import time

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("IBus", "1.0")
from gi.repository import Gdk, GLib, Gtk, IBus

assert os.environ.get("MSIME_ISOLATED_LINUX_TEST") == "1"
assert os.environ.get("GTK_IM_MODULE") == "ibus"
assert "Wayland" in type(Gdk.Display.get_default()).__name__, "GTK did not use Wayland"
IBus.init()
bus = IBus.Bus.new()


def pump():
    while GLib.MainContext.default().iteration(False):
        pass


def wait(predicate, description):
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        pump()
        if predicate():
            return
        time.sleep(0.01)
    raise AssertionError(description)


from wayland_keyboard import WaylandKeyboard

keyboard = WaylandKeyboard(pump, wait)
keys = keyboard.keys


wait(lambda: bus.is_connected(), "GTK fixture could not connect to IBus")
wait(lambda: any(engine.get_name() == "msime-client-preview" for engine in bus.list_active_engines()),
     "Native IBus engine was not registered")
window = Gtk.Window(title="MSIME synthetic GTK acceptance")
layout = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
window.add(layout)
first, second, password = Gtk.Entry(), Gtk.Entry(), Gtk.Entry()
password.set_visibility(False)
password.set_input_purpose(Gtk.InputPurpose.PASSWORD)
for entry in (first, second, password):
    layout.pack_start(entry, False, False, 0)
text_view = Gtk.TextView()
layout.pack_start(text_view, True, True, 0)
preedit = {"text": ""}
first.connect("preedit-changed", lambda _entry, text: preedit.update(text=text))
window.show_all()
pump()
wait(window.is_active, "Wayland compositor did not focus GTK window")
first.grab_focus()
pump()
assert bus.set_global_engine("msime-client-preview")
wait(lambda: bus.get_global_engine() is not None and
     bus.get_global_engine().get_name() == "msime-client-preview", "GTK engine activation failed")
# Let the GTK IM module finish its asynchronous input-context setup.
end = time.monotonic() + 0.3
while time.monotonic() < end:
    pump()
    time.sleep(0.01)
keys("n", "i", "h", "a", "o")
wait(lambda: bool(preedit["text"]), "GTK did not receive composition preedit")
assert first.get_text() == "", "GTK committed spelling before selection"
keys("space")
wait(lambda: first.get_text() == "你好", "GTK did not insert the selected candidate")
first.set_text("")
keys("n", "i", "h", "a", "o", "BackSpace", "Return")
wait(lambda: first.get_text() == "niha", "GTK composition editing/raw commit failed")
first.set_text("")
keys("n", "i", "h", "a", "o", "U1F600")
wait(lambda: first.get_text() == "nihao😀", "GTK Unicode keysym discarded pending spelling")
first.set_text("")
keys("q", "w", "e", "r", "Return")
wait(lambda: first.get_text() == "qwer", "GTK letter keys were mistaken for candidate slots")
first.set_text("")
keys("n", "i", "h", "a", "o", "1")
wait(lambda: first.get_text() == "你好", "GTK physical number row did not select a candidate")
first.set_text("")
keys("n", "i", "h", "a", "o")
wait(lambda: bool(preedit["text"]), "GTK focus fixture did not compose")
second.grab_focus()
pump()
keys("n", "i", "h", "a", "o", "space")
wait(lambda: second.get_text() == "你好", "GTK second input field did not receive a fresh candidate")
assert first.get_text() == "", "GTK focus loss committed abandoned composition"
second.set_text("")
keys("Multi_key", "Escape", "n", "i", "h", "a", "o", "space")
wait(lambda: second.get_text() == "你好", "GTK Compose cancellation did not restore IME input")
second.set_text("")
keys("dead_circumflex")
first.set_text("")
first.grab_focus()
pump()
keys("e", "Return")
wait(lambda: first.get_text() == "e", "GTK focus transfer retained the previous dead key")
assert second.get_text() == "", "GTK dead-key focus loss inserted text"
first.set_text("")
keys("Multi_key", "F1", "n", "i", "h", "a", "o", "space")
wait(lambda: first.get_text() == "你好", "Invalid Compose sequence did not restore candidate input")
first.set_text("")
keys("Shift_L", "dead_circumflex", "e", "n", "i", "h", "a", "o", "space")
wait(lambda: first.get_text() == "ênihao ", "GTK disabled IME did not preserve native Compose and direct text")
first.set_text("")
keys("Shift_L", "n", "i", "h", "a", "o", "space")
wait(lambda: first.get_text() == "你好", "GTK re-enabled IME did not restore candidates")
password.grab_focus()
pump()
keys("n", "i", "h", "a", "o", "space")
wait(lambda: password.get_text() == "nihao ", "GTK password input was intercepted by the IME")
from gtk_surrounding import check_surrounding, TextViewAdapter
check_surrounding(first, keys, pump, wait)
check_surrounding(TextViewAdapter(text_view), keys, pump, wait, selections=True)
window.destroy()
pump()
print("GTK3 Wayland IBus-module candidate/edit/focus/password acceptance passed")
