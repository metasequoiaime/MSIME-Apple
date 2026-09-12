"""Real Qt5 IM-module acceptance on a dedicated Xvfb display, synthetic text only."""
import os
import subprocess
import time

import gi

gi.require_version("IBus", "1.0")
from gi.repository import GLib, IBus
from PyQt5.QtWidgets import QApplication, QLineEdit, QVBoxLayout, QWidget

assert os.environ.get("MSIME_ISOLATED_LINUX_TEST") == "1"
assert os.environ.get("QT_IM_MODULE") == "ibus"
app = QApplication([])
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
password.setEchoMode(QLineEdit.Password)
for entry in (first, second, password):
    layout.addWidget(entry)
window.show()
pump()
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
password.setFocus()
pump()
keys("n", "i", "h", "a", "o", "space")
wait(lambda: password.text() == "nihao ", "Qt password input was intercepted by the IME")
window.close()
pump()
print("Qt5 X11 IM-module candidate/edit/focus/password acceptance passed")
