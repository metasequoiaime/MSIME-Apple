"""Synthetic input through the session-bus IBus portal, not the private bus."""
import os
import time

import gi

gi.require_version("IBus", "1.0")
from gi.repository import Gio, GLib, IBus

assert os.environ.get("MSIME_ISOLATED_LINUX_TEST") == "1"
IBus.init()
admin = IBus.Bus.new()


def wait(predicate):
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        while GLib.MainContext.default().iteration(False):
            pass
        if predicate():
            return
        time.sleep(0.01)
    raise AssertionError("Expected portal input state was not observed")


wait(lambda: any(e.get_name() == "msime-client-preview" for e in admin.list_active_engines()))
assert admin.set_global_engine("msime-client-preview")
connection = Gio.bus_get_sync(Gio.BusType.SESSION, None)
service = "org.freedesktop.portal.IBus"


def call(path, interface, method, arguments=None, source=connection):
    return source.call_sync(service, path, interface, method, arguments, None,
                            Gio.DBusCallFlags.NONE, 10000, None)


path = call("/org/freedesktop/IBus", "org.freedesktop.IBus.Portal", "CreateInputContext",
            GLib.Variant("(s)", ("msime-synthetic-portal",))).unpack()[0]
interface = "org.freedesktop.IBus.InputContext"
commits = []


def signal(_connection, _sender, _path, _interface, _signal, parameters):
    commits.append(parameters.unpack()[0][2])


subscription = connection.signal_subscribe(service, interface, "CommitText", path, None,
                                           Gio.DBusSignalFlags.NONE, signal)
call(path, interface, "SetCapabilities", GLib.Variant("(u)", (int(IBus.Capabilite.FOCUS | IBus.Capabilite.PREEDIT_TEXT | IBus.Capabilite.LOOKUP_TABLE),)))
call(path, interface, "FocusIn")
for character in "nihao ":
    assert call(path, interface, "ProcessKeyEvent", GLib.Variant("(uuu)", (ord(character), 0, 0))).unpack()[0]
wait(lambda: commits == ["你好"])
# Abandon an in-progress reading across focus loss, then start fresh.
for character in "nihao":
    assert call(path, interface, "ProcessKeyEvent", GLib.Variant("(uuu)", (ord(character), 0, 0))).unpack()[0]
call(path, interface, "FocusOut")
call(path, interface, "FocusIn")
for character in "nihao ":
    assert call(path, interface, "ProcessKeyEvent", GLib.Variant("(uuu)", (ord(character), 0, 0))).unpack()[0]
wait(lambda: commits == ["你好", "你好"])
# Content-type properties must cancel pending input when entering a sensitive field.
for character in "nihao":
    assert call(path, interface, "ProcessKeyEvent", GLib.Variant("(uuu)", (ord(character), 0, 0))).unpack()[0]
for purpose in (IBus.InputPurpose.PASSWORD, IBus.InputPurpose.PIN):
    call(path, "org.freedesktop.DBus.Properties", "Set",
         GLib.Variant("(ssv)", (interface, "ContentType", GLib.Variant("(uu)", (int(purpose), 0)))))
    for character in "nihao ":
        assert not call(path, interface, "ProcessKeyEvent", GLib.Variant("(uuu)", (ord(character), 0, 0))).unpack()[0]
    assert commits == ["你好", "你好"], "Portal sensitive input produced an IME commit"
call(path, "org.freedesktop.DBus.Properties", "Set",
     GLib.Variant("(ssv)", (interface, "ContentType", GLib.Variant("(uu)", (int(IBus.InputPurpose.FREE_FORM), 0)))))
for character in "nihao ":
    assert call(path, interface, "ProcessKeyEvent", GLib.Variant("(uuu)", (ord(character), 0, 0))).unpack()[0]
wait(lambda: commits == ["你好", "你好", "你好"])
# A distinct session-bus connection must not operate another client's context.
other = Gio.DBusConnection.new_for_address_sync(
    os.environ["DBUS_SESSION_BUS_ADDRESS"],
    Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION,
    None, None)
try:
    call(path, interface, "FocusIn", source=other)
except GLib.Error as error:
    assert "Access denied" in str(error)
else:
    raise AssertionError("Portal input context accepted a different owner")
finally:
    other.close_sync(None)
call(path, interface, "FocusOut")
connection.signal_unsubscribe(subscription)
connection.close_sync(None)
print("IBus portal composition/focus/content-type/context-owner acceptance passed")
