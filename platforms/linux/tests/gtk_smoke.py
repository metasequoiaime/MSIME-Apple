"""Real GTK3 IM-module acceptance on a dedicated Xvfb display, synthetic text only."""
import ctypes
import os
import sys
import subprocess
import time

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GdkX11", "3.0")
gi.require_version("IBus", "1.0")
from gi.repository import Gdk, GdkX11, GLib, Gtk, IBus

assert os.environ.get("MSIME_ISOLATED_LINUX_TEST") == "1"
assert os.environ.get("GTK_IM_MODULE") == "ibus"
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


def keys(*values):
    # Process temporary XKB mappings while xdotool injects Unicode keysyms.
    process = subprocess.Popen(["xdotool", "key", "--clearmodifiers", "--delay", "40", *values])
    while process.poll() is None:
        pump()
        time.sleep(0.005)
    assert process.returncode == 0, "XTest keyboard injection failed"
    pump()


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
subprocess.run(["xdotool", "windowfocus", "--sync", str(window.get_window().get_xid())], check=True)
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
keys("n", "i", "h", "a", "o", "U1f600")
wait(lambda: first.get_text() == "nihao😀", "GTK Unicode keysym discarded pending spelling")
first.set_text("")
keys("q", "w", "e", "r", "Return")
wait(lambda: first.get_text() == "qwer", "GTK letter keys were mistaken for candidate slots")
first.set_text("")
keys("n", "i", "h", "a", "o", "1")
wait(lambda: first.get_text() == "你好", "GTK physical number row did not select a candidate")
# Inject a physical XKB number-row key, not a keysym which xdotool may remap.
x11 = ctypes.CDLL("libX11.so.6")
xtst = ctypes.CDLL("libXtst.so.6")
x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
x11.XOpenDisplay.restype = ctypes.c_void_p
x11.XSync.argtypes = [ctypes.c_void_p, ctypes.c_int]
x11.XCloseDisplay.argtypes = [ctypes.c_void_p]
xtst.XTestFakeKeyEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]
display = x11.XOpenDisplay(None)
assert display, "Physical-key fixture could not open X11 display"
try:
    subprocess.run(["setxkbmap", "fr"], check=True)
    wait(lambda: Gdk.Keymap.get_for_display(Gdk.Display.get_default()).get_entries_for_keycode(10)[2][0]
         == Gdk.KEY_ampersand, "French number row was not installed")
    first.set_text("")
    keys("n", "i", "h", "a", "o")
    wait(lambda: bool(preedit["text"]), "French layout did not compose")
    assert xtst.XTestFakeKeyEvent(display, 10, True, 0)
    assert xtst.XTestFakeKeyEvent(display, 10, False, 0)
    x11.XSync(display, False)
    wait(lambda: first.get_text() == "你好", "French physical number row did not select candidate")
    first.set_text("")
    keys("n", "i", "h", "a", "o", "ISO_Level3_Shift+agrave")
    wait(lambda: first.get_text() == "nihao@", "French AltGr text discarded pending spelling")
    first.set_text("")
    keys("ISO_Level3_Shift+agrave")
    wait(lambda: first.get_text() == "@", "Idle French AltGr text was intercepted")
    first.set_text("")
    keys("n", "i", "h", "a", "o", "dead_circumflex", "e")
    wait(lambda: first.get_text() == "nihaoê", "French dead key discarded pending spelling")
    first.set_text("")
    keys("n", "i", "h", "a", "o", "Multi_key", "apostrophe", "e")
    wait(lambda: first.get_text() == "nihaoé", "Compose sequence discarded pending spelling")
    # Compose a Unicode value on US, then select it with AZERTY Shift+row 1.
    # Its keysym is '1', unlike the US '!', so this must use the physical code.
    subprocess.run(["setxkbmap", "us"], check=True)
    wait(lambda: Gdk.Keymap.get_for_display(Gdk.Display.get_default()).get_entries_for_keycode(10)[2][0]
         == Gdk.KEY_1, "US number row was not restored")
    first.set_text("")
    keys("U", "plus", "4", "e", "2", "d")
    wait(lambda: preedit["text"] == "U+4e2d", "Unicode layout fixture did not compose")
    subprocess.run(["setxkbmap", "fr"], check=True)
    wait(lambda: Gdk.Keymap.get_for_display(Gdk.Display.get_default()).get_entries_for_keycode(10)[2][0]
         == Gdk.KEY_ampersand, "French Unicode number row was not installed")
    assert xtst.XTestFakeKeyEvent(display, 50, True, 0)  # Left Shift
    assert xtst.XTestFakeKeyEvent(display, 10, True, 0)
    assert xtst.XTestFakeKeyEvent(display, 10, False, 0)
    assert xtst.XTestFakeKeyEvent(display, 50, False, 0)
    x11.XSync(display, False)
    wait(lambda: first.get_text() == "中", "French Shift+number row did not select Unicode")
finally:
    subprocess.run(["setxkbmap", "us"], check=True)
    x11.XCloseDisplay(display)
    pump()
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
if "--custom-compose" in sys.argv:
    assert os.environ.get("XCOMPOSEFILE"), "Custom Compose fixture was not configured"
    first.grab_focus()
    first.set_text("")
    pump()
    keys("n", "i", "h", "a", "o", "Multi_key", "x", "x")
    wait(lambda: first.get_text() == "nihao水杉😀", "Custom Compose table did not insert its UTF-8 sequence")
    print("GTK3 custom Compose table acceptance passed")
from gtk_surrounding import check_surrounding, TextViewAdapter
check_surrounding(first, keys, pump, wait)
check_surrounding(TextViewAdapter(text_view), keys, pump, wait, selections=True)
window.destroy()
pump()
print("GTK3 X11 IM-module candidate/edit/layout/focus/password acceptance passed")
