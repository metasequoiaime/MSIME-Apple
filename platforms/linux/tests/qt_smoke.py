"""Real Qt5/Qt6 IM-module acceptance on isolated X11 or Wayland displays, synthetic text only."""
import os
import sys
import subprocess
import time

import gi

gi.require_version("IBus", "1.0")
from gi.repository import GLib, IBus
if "--qt6" in sys.argv:
    from PyQt6.QtWidgets import QApplication, QLineEdit, QPlainTextEdit, QVBoxLayout, QWidget
    qt_version = "Qt6"
else:
    from PyQt5.QtWidgets import QApplication, QLineEdit, QPlainTextEdit, QVBoxLayout, QWidget
    qt_version = "Qt5"

assert os.environ.get("MSIME_ISOLATED_LINUX_TEST") == "1"
assert os.environ.get("QT_IM_MODULE") == "ibus"
app = QApplication([])
wayland = "--wayland" in sys.argv
if wayland:
    assert app.platformName().startswith("wayland"), "Qt did not use Wayland"
IBus.init()
bus = IBus.Bus.new()


def pump():
    app.processEvents()
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
    process = subprocess.Popen(["xdotool", "key", "--clearmodifiers", "--delay", "40", *values])
    while process.poll() is None:
        pump()
        time.sleep(0.005)
    assert process.returncode == 0, "XTest keyboard injection failed"
    pump()


if wayland:
    from wayland_keyboard import WaylandKeyboard
    keyboard = WaylandKeyboard(pump, wait)
    keys = keyboard.keys


wait(lambda: bus.is_connected(), "Qt fixture could not connect to IBus")
wait(lambda: any(engine.get_name() == "msime-client-preview" for engine in bus.list_active_engines()),
     "Native IBus engine was not registered")


class Entry(QLineEdit):
    preedit = ""

    def inputMethodEvent(self, event):
        self.preedit = event.preeditString()
        super().inputMethodEvent(event)


window = QWidget()
window.setWindowTitle("MSIME synthetic Qt acceptance")
layout = QVBoxLayout(window)
first, second, password = Entry(), Entry(), Entry()
password.setEchoMode(QLineEdit.EchoMode.Password)
for entry in (first, second, password):
    layout.addWidget(entry)
plain = QPlainTextEdit()
layout.addWidget(plain)
window.show()
pump()
if wayland:
    wait(window.isActiveWindow, "Wayland compositor did not focus Qt window")
else:
    subprocess.run(["xdotool", "windowfocus", "--sync", str(int(window.winId()))], check=True)
first.setFocus()
pump()
assert bus.set_global_engine("msime-client-preview")
wait(lambda: bus.get_global_engine() is not None and
     bus.get_global_engine().get_name() == "msime-client-preview", "Qt engine activation failed")
# Let the Qt IM module finish its asynchronous input-context setup.
end = time.monotonic() + 0.3
while time.monotonic() < end:
    pump()
    time.sleep(0.01)
if os.environ.get("MSIME_TEST_INITIAL_FOCUS") == "1":
    first.setText("😀a尾")
    first.setCursorPosition(3)  # Qt positions count the emoji's UTF-16 pair.
    pump()
    keys("period")
    wait(lambda: first.text() == "😀a.尾",
         "Initial Qt focus did not identify UTF-16 document positions")
    first.setText("")
    print(f"{qt_version} initial-focus Unicode document acceptance passed")
keys("n", "i", "h", "a", "o")
wait(lambda: bool(first.preedit), "Qt did not receive composition preedit")
assert first.text() == "", "Qt committed spelling before selection"
keys("space")
wait(lambda: first.text() == "你好", "Qt did not insert the selected candidate")
first.setText("")
keys("n", "i", "h", "a", "o", "BackSpace", "Return")
wait(lambda: first.text() == "niha", "Qt composition editing/raw commit failed")
first.setText("")
keys("q", "w", "e", "r", "Return")
wait(lambda: first.text() == "qwer", "Qt letter keys were mistaken for candidate slots")
first.setText("")
keys("n", "i", "h", "a", "o", "1")
wait(lambda: first.text() == "你好", "Qt physical number row did not select a candidate")
first.setText("")
keys("n", "i", "h", "a", "o")
wait(lambda: bool(first.preedit), "Qt focus fixture did not compose")
# Qt5's IBus commit() inserts its cached preedit before resetting the engine.
# See qtbase v5.15.8-lts-lgpl qibusplatforminputcontext.cpp.
focus_preedit = first.preedit
second.setFocus()
pump()
keys("n", "i", "h", "a", "o", "space")
wait(lambda: second.text() == "你好", "Qt second input field did not receive a fresh candidate")
assert first.text() == focus_preedit, "Qt focus transfer changed the toolkit preedit commit"
second.setText("left right")
second.setCursorPosition(5)
keys("n", "i", "h", "a", "o", "space")
wait(lambda: second.text() == "left 你好right", "Qt candidate insertion ignored the cursor")
second.setText("left replace right")
second.setSelection(5, 7)
keys("n", "i", "h", "a", "o", "space")
wait(lambda: second.text() == "left 你好 right", "Qt candidate did not replace the selection")
second.setText("")
keys("n", "i", "h", "a", "o", "Escape")
wait(lambda: not second.preedit, "Qt Escape did not clear preedit")
assert second.text() == "", "Qt Escape committed cancelled composition"
second.setText("")
keys("Multi_key", "apostrophe", "e")
wait(lambda: second.text() == "é", "Qt native Compose sequence failed")
second.setText("")
keys("Multi_key", "Escape", "n", "i", "h", "a", "o", "space")
wait(lambda: second.text() == "你好", "Qt Compose cancellation did not restore IME input")
second.setText("")
keys("dead_circumflex")
first.setText("")
first.setFocus()
pump()
keys("e", "Return")
wait(lambda: first.text() == "e", "Qt focus transfer retained the previous dead key")
assert second.text() == "", "Qt dead-key focus loss inserted text"
first.setText("")
keys("Multi_key", "F1", "n", "i", "h", "a", "o", "space")
wait(lambda: first.text() == "你好", "Invalid Compose sequence did not restore candidate input")
first.setText("")
keys("Shift_L", "dead_circumflex", "e", "n", "i", "h", "a", "o", "space")
wait(lambda: first.text() == "ênihao ", "Qt disabled IME did not preserve native Compose and direct text")
first.setText("")
keys("Shift_L", "n", "i", "h", "a", "o", "space")
wait(lambda: first.text() == "你好", "Qt re-enabled IME did not restore candidates")
password.setFocus()
pump()
keys("n", "i", "h", "a", "o", "space")
wait(lambda: password.text() == "nihao ", "Qt password input was intercepted by the IME")
if os.environ.get("MSIME_TEST_INITIAL_FOCUS") != "1":
    # IBus 1.5.27 negotiates FocusId asynchronously without replaying the first
    # focus. Exercise the identified-client path after a separate context transfer.
    other_context = bus.create_input_context("msime-test-context-transfer")
    other_context.set_capabilities(IBus.Capabilite.FOCUS | IBus.Capabilite.PREEDIT_TEXT)
    other_context.focus_in()
    end = time.monotonic() + 0.3
    while time.monotonic() < end:
        pump()
        time.sleep(0.01)
    other_context.focus_out()
    first.clearFocus()
    first.setFocus()
    pump()

from surrounding_text import check_surrounding


def utf16_offset(text, offset):
    return len(text[:offset].encode("utf-16-le")) // 2


class LineAdapter:
    def __init__(self, entry):
        self.entry = entry

    def grab_focus(self):
        self.entry.setFocus()

    def set_text(self, text):
        self.entry.setText(text)

    def get_text(self):
        return self.entry.text()

    def set_position(self, offset):
        self.entry.setCursorPosition(utf16_offset(self.get_text(), offset))

    def select_region(self, start, end):
        text = self.get_text()
        first = utf16_offset(text, start)
        last = utf16_offset(text, end)
        self.entry.setSelection(first, last - first)


class PlainAdapter(LineAdapter):
    def set_text(self, text):
        self.entry.setPlainText(text)

    def get_text(self):
        return self.entry.toPlainText()

    def set_position(self, offset):
        cursor = self.entry.textCursor()
        cursor.setPosition(utf16_offset(self.get_text(), offset))
        self.entry.setTextCursor(cursor)

    def select_region(self, start, end):
        cursor = self.entry.textCursor()
        text = self.get_text()
        cursor.setPosition(utf16_offset(text, start))
        cursor.setPosition(utf16_offset(text, end), cursor.MoveMode.KeepAnchor)
        self.entry.setTextCursor(cursor)


check_surrounding(LineAdapter(first), keys, pump, wait, selections=True)
check_surrounding(PlainAdapter(plain), keys, pump, wait, selections=True, multiline=True)
window.close()
pump()
backend = "Wayland" if wayland else "X11"
print(f"{qt_version} {backend} IM-module candidate/edit/focus/password acceptance passed")
