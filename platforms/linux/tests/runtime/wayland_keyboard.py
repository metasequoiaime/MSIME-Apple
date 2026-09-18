"""Persistent synthetic Wayland keyboard shared by native editor tests."""
import atexit
import select
import subprocess
import time


class WaylandKeyboard:
    def __init__(self, pump, wait):
        self.pump, self.wait = pump, wait
        self.process = subprocess.Popen(["msime-test-wayland-keyboard"],
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        atexit.register(self.close)
        self.reply("ready")

    def close(self):
        if self.process.poll() is None:
            self.process.terminate()
        self.process.wait()

    def reply(self, expected):
        self.wait(lambda: bool(select.select([self.process.stdout], [], [], 0)[0]),
                  "Wayland keyboard did not acknowledge input")
        assert self.process.stdout.readline().strip() == expected

    def keys(self, *values):
        for value in values:
            self.process.stdin.write(value + "\n")
            self.process.stdin.flush()
            self.reply("sent")
            end = time.monotonic() + 0.04
            while time.monotonic() < end:
                self.pump()
                time.sleep(0.005)
        self.pump()
