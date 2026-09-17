"""Synthetic keystrokes into a real Gtk.Entry on an isolated Xvfb display."""
import subprocess

import dbus
import gi

gi.require_version("Gtk", "3.0")
gi.require_version("GdkX11", "3.0")
from gi.repository import Gtk, GdkX11
from daemon import wait


window = Gtk.Window(title="MSIME synthetic GTK editor")
entry = Gtk.Entry()
entry.set_property("im-module", "fcitx")
window.add(entry)
window.show_all()
entry.grab_focus()
wait(lambda: window.get_window() is not None)
xid = GdkX11.X11Window.get_xid(window.get_window())
subprocess.run(["xdotool", "windowfocus", "--sync", str(xid)], check=True, timeout=5)
wait(lambda: entry.has_focus())
bus = dbus.SessionBus()
control = dbus.Interface(bus.get_object("org.fcitx.Fcitx5", "/controller"),
                         "org.fcitx.Fcitx.Controller1")
# GTK creates/focuses its D-Bus input context asynchronously after X focus.
wait(lambda: bool(str(control.CurrentInputMethod())))
control.SetCurrentIM("msime")
control.Activate()
wait(lambda: str(control.CurrentInputMethod()) == "msime")
typing = subprocess.Popen(["xdotool", "type", "--clearmodifiers", "--delay", "100", "nihao "])
try:
    wait(lambda: entry.get_text() == "你好")
    assert typing.wait(timeout=5) == 0, "Synthetic key injection failed"
finally:
    if typing.poll() is None:
        typing.terminate()
        typing.wait(timeout=5)
    window.destroy()
print("Fcitx5 GTK3 editor commit passed")
