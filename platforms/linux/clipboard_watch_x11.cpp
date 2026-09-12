#include <X11/Xlib.h>
#include <X11/extensions/Xfixes.h>
#include <cstdio>

// Emit event markers only. Clipboard text remains in the bounded capture path.
int main() {
  Display *display = XOpenDisplay(nullptr);
  if (!display) return 1;
  int event_base = 0, error_base = 0;
  if (!XFixesQueryExtension(display, &event_base, &error_base)) {
    XCloseDisplay(display);
    return 1;
  }
  const Atom clipboard = XInternAtom(display, "CLIPBOARD", False);
  XFixesSelectSelectionInput(display, DefaultRootWindow(display), clipboard,
      XFixesSetSelectionOwnerNotifyMask | XFixesSelectionWindowDestroyNotifyMask |
      XFixesSelectionClientCloseNotifyMask);
  XFlush(display);
  std::puts("");
  std::fflush(stdout);
  for (;;) {
    XEvent event{};
    XNextEvent(display, &event);
    if (event.type == event_base + XFixesSelectionNotify) {
      if (std::puts("") == EOF || std::fflush(stdout) != 0) break;
    }
  }
  XCloseDisplay(display);
  return 0;
}
