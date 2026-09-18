#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <iostream>
#include <algorithm>
#include <cstring>
#include <iterator>
#include <string>

int main(int argc, char **argv) {
  const bool incremental = argc == 2 && std::strcmp(argv[1], "--incr") == 0;
  const std::string text{std::istreambuf_iterator<char>(std::cin), {}};
  Display *display = XOpenDisplay(nullptr);
  if (!display) return 1;
  const Window window = XCreateSimpleWindow(display, DefaultRootWindow(display), 0, 0, 1, 1, 0, 0, 0);
  const Atom clipboard = XInternAtom(display, "CLIPBOARD", False);
  const Atom utf8 = XInternAtom(display, "UTF8_STRING", False);
  const Atom incr = XInternAtom(display, "INCR", False);
  Window receiver = None;
  Atom transfer = None;
  size_t offset = 0;
  XSetSelectionOwner(display, clipboard, window, CurrentTime);
  XSync(display, False);
  std::cout << "ready" << std::endl;
  for (;;) {
    XEvent event{};
    XNextEvent(display, &event);
    if (incremental && event.type == PropertyNotify && event.xproperty.window == receiver &&
        event.xproperty.atom == transfer && event.xproperty.state == PropertyDelete) {
      const size_t count = std::min(size_t{4096}, text.size() - offset);
      XChangeProperty(display, receiver, transfer, utf8, 8, PropModeReplace,
          reinterpret_cast<const unsigned char *>(text.data() + offset), static_cast<int>(count));
      offset += count;
      if (!count) receiver = None;
      XFlush(display);
    }
    if (event.type != SelectionRequest) continue;
    const auto &request = event.xselectionrequest;
    XEvent reply{};
    reply.xselection.type = SelectionNotify;
    reply.xselection.display = display;
    reply.xselection.requestor = request.requestor;
    reply.xselection.selection = request.selection;
    reply.xselection.target = request.target;
    reply.xselection.time = request.time;
    reply.xselection.property = None;
    if (incremental && request.target == utf8 && request.property != None) {
      receiver = request.requestor;
      transfer = request.property;
      offset = 0;
      XSelectInput(display, receiver, PropertyChangeMask);
      const unsigned long size = text.size();
      XChangeProperty(display, receiver, transfer, incr, 32, PropModeReplace,
          reinterpret_cast<const unsigned char *>(&size), 1);
      reply.xselection.property = transfer;
      std::cout << "incr" << std::endl;
    } else if (!incremental && request.target == XA_STRING && request.property != None) {
      XChangeProperty(display, request.requestor, request.property, XA_STRING, 8,
          PropModeReplace, reinterpret_cast<const unsigned char *>(text.data()), static_cast<int>(text.size()));
      reply.xselection.property = request.property;
    }
    XSendEvent(display, request.requestor, False, 0, &reply);
    XFlush(display);
  }
}
