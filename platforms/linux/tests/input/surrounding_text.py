"""Synthetic document/caret cases shared by GTK and Qt on X11 and Wayland."""


def check_surrounding(entry, keys, pump, wait, selections=False, multiline=False):
    entry.grab_focus()
    pump()
    # Establish the native IM context before testing existing document text.
    entry.set_text("")
    keys("n", "i", "h", "a", "o", "space")
    wait(lambda: entry.get_text() == "你好", "Native editor surrounding fixture did not activate IME")
    cases = [
        ("a尾", 1, "a.尾"),
        ("中1尾", 2, "中1.尾"),
        ("😀a尾", 2, "😀a.尾"),
        ("A中尾", 2, "A中。尾"),
        ("a😀尾", 2, "a😀。尾"),
        ("尾", 0, "。尾"),
    ]
    if multiline:
        cases.append(("行\n中1尾", 4, "行\n中1.尾"))
    for text, cursor, expected in cases:
        entry.set_text(text)
        entry.set_position(cursor)
        pump()
        keys("period")
        wait(lambda: entry.get_text() == expected,
             "Native editor smart punctuation used the wrong surrounding character")
    entry.set_text("中1尾")
    entry.set_position(2)
    pump()
    keys("period", "period")
    wait(lambda: entry.get_text() == "中1。尾",
         "Native editor repeated punctuation did not replace the preceding mark")
    # IBus 1.5.27 reports selection anchors for GtkTextView, not GtkEntry.
    if selections:
        for text, position, inserted, bounds, expected in (
            ("aX尾", 1, "a.X尾", (2, 3), "a.。尾"),
            ("😀aX尾", 2, "😀a.X尾", (3, 4), "😀a.。尾"),
        ):
            for start, end in (bounds, bounds[::-1]):
                entry.set_text(text)
                entry.set_position(position)
                pump()
                keys("period")
                wait(lambda: entry.get_text() == inserted,
                     "Native editor selection fixture did not insert an ASCII mark")
                entry.select_region(start, end)
                pump()
                keys("period")
                wait(lambda: entry.get_text() == expected,
                     "Native editor punctuation deleted outside the selection or used its end")
    print("Native editor Unicode surrounding-text/caret acceptance passed")


class TextViewAdapter:
    def __init__(self, view):
        self.view = view
        self.buffer = view.get_buffer()

    def grab_focus(self):
        self.view.grab_focus()

    def set_text(self, text):
        self.buffer.set_text(text)

    def get_text(self):
        return self.buffer.get_text(*self.buffer.get_bounds(), True)

    def set_position(self, offset):
        self.buffer.place_cursor(self.buffer.get_iter_at_offset(offset))

    def select_region(self, start, end):
        self.buffer.select_range(self.buffer.get_iter_at_offset(end),
                                 self.buffer.get_iter_at_offset(start))
