#include "WaveOverlayX11Surface.h"

#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/extensions/Xfixes.h>
#include <X11/extensions/shape.h>

#include <algorithm>
#include <array>
#include <cstdlib>
#include <string>

namespace msime::linux_host {
namespace {

constexpr unsigned kWidth = 420;
constexpr unsigned kHeight = 132;
constexpr unsigned kBarCount = 12;

unsigned long color(Display *display, int screen, const char *value,
                    unsigned long fallback) {
  XColor exact{};
  XColor allocated{};
  const auto colormap = DefaultColormap(display, screen);
  if (!XParseColor(display, colormap, value, &exact) ||
      !XAllocColor(display, colormap, &exact))
    return fallback;
  allocated = exact;
  return allocated.pixel;
}

std::string one_line(std::string text) {
  for (auto &character : text)
    if (character == '\r' || character == '\n' || character == '\t')
      character = ' ';
  return text;
}

std::string utf8_prefix(const std::string &text, std::size_t characters) {
  std::size_t count = 0;
  std::size_t end = 0;
  while (end < text.size() && count < characters) {
    if ((static_cast<unsigned char>(text[end]) & 0xc0) != 0x80)
      ++count;
    ++end;
  }
  return text.substr(0, end);
}

}  // namespace

WaveOverlayX11Surface::~WaveOverlayX11Surface() { destroy_window(); }

bool WaveOverlayX11Surface::ensure_window() {
  if (display_)
    return true;
  const auto *display_name = std::getenv("DISPLAY");
  if (!display_name || !*display_name)
    return false;
  display_ = XOpenDisplay(display_name);
  if (!display_)
    return false;
  const auto screen = DefaultScreen(display_);
  int fixes_event = 0;
  int fixes_error = 0;
  if (!XFixesQueryExtension(display_, &fixes_event, &fixes_error)) {
    XCloseDisplay(display_);
    display_ = nullptr;
    return false;
  }
  const auto root = RootWindow(display_, screen);
  XSetWindowAttributes attributes{};
  attributes.override_redirect = True;
  attributes.background_pixel = color(display_, screen, "#202124", BlackPixel(display_, screen));
  attributes.border_pixel = color(display_, screen, "#4a4d52", WhitePixel(display_, screen));
  window_ = XCreateWindow(display_, root, 0, 0, kWidth, kHeight, 1,
                           CopyFromParent, InputOutput, CopyFromParent,
                           CWOverrideRedirect | CWBackPixel | CWBorderPixel,
                           &attributes);
  if (!window_) {
    XCloseDisplay(display_);
    display_ = nullptr;
    return false;
  }
  gc_ = XCreateGC(display_, window_, 0, nullptr);
  background_ = attributes.background_pixel;
  foreground_ = color(display_, screen, "#f5f7fa", WhitePixel(display_, screen));
  accent_ = color(display_, screen, "#73a7ff", WhitePixel(display_, screen));
  char **missing = nullptr;
  int missing_count = 0;
  char *default_string = nullptr;
  font_set_ = XCreateFontSet(
      display_, "-misc-fixed-*-*-*-*-14-*-*-*-*-*-*-*", &missing,
      &missing_count, &default_string);
  if (missing)
    XFreeStringList(missing);
  XSelectInput(display_, window_, ExposureMask);
  const auto input_region = XFixesCreateRegion(display_, nullptr, 0);
  XFixesSetWindowShapeRegion(display_, window_, ShapeInput, 0, 0,
                             input_region);
  XFixesDestroyRegion(display_, input_region);
  return true;
}

void WaveOverlayX11Surface::destroy_window() {
  if (!display_)
    return;
  if (font_set_)
    XFreeFontSet(display_, font_set_);
  if (gc_)
    XFreeGC(display_, gc_);
  if (window_)
    XDestroyWindow(display_, window_);
  XCloseDisplay(display_);
  display_ = nullptr;
  window_ = 0;
  gc_ = 0;
  font_set_ = 0;
  visible_ = false;
}

void WaveOverlayX11Surface::draw(const WaveOverlayModel &model) {
  if (!display_ || !window_ || !gc_)
    return;
  const auto screen = DefaultScreen(display_);
  const auto x = std::max(0, DisplayWidth(display_, screen) - static_cast<int>(kWidth) - 24);
  const auto y = 48;
  XMoveWindow(display_, window_, x, y);
  XSetForeground(display_, gc_, background_);
  XFillRectangle(display_, window_, gc_, 0, 0, kWidth, kHeight);
  XSetForeground(display_, gc_, accent_);
  const auto bar_width = (kWidth - 32) / kBarCount;
  for (unsigned index = 0; index < kBarCount; ++index) {
    const auto level = index < model.levels.size() ? model.levels[index] : 0.0f;
    const auto height = std::max(4, static_cast<int>(level * 38.0f));
    XFillRectangle(display_, window_, gc_,
                   16 + index * bar_width, 56 - height / 2,
                   std::max(2u, bar_width - 3), static_cast<unsigned>(height));
  }
  if (font_set_) {
    const auto font = font_set_;
    XSetForeground(display_, gc_, foreground_);
    std::string status = model.locked
                             ? "录音已锁定 · 再按快捷键或点击语音菜单结束 · Esc 取消"
                             : one_line(model.status);
    if (status.empty())
      status = "正在录音…";
    Xutf8DrawString(display_, window_, font, gc_, 16, 104,
                    status.c_str(), static_cast<int>(status.size()));
    if (model.show_transcript && !model.transcript.empty()) {
      auto transcript = utf8_prefix(one_line(model.transcript), 72);
      Xutf8DrawString(display_, window_, font, gc_, 16, 124,
                      transcript.c_str(), static_cast<int>(transcript.size()));
    }
  }
  XFlush(display_);
}

bool WaveOverlayX11Surface::show(const WaveOverlayModel &model) {
  if (!ensure_window())
    return false;
  visible_ = true;
  XMapRaised(display_, window_);
  draw(model);
  return true;
}

void WaveOverlayX11Surface::update(const WaveOverlayModel &model) {
  if (visible_)
    draw(model);
}

void WaveOverlayX11Surface::hide() {
  if (display_ && window_ && visible_) {
    XUnmapWindow(display_, window_);
    XFlush(display_);
  }
  visible_ = false;
}

}  // namespace msime::linux_host
