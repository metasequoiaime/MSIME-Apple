#include "ModeBadgeX11Surface.h"

#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/extensions/shape.h>
#include <cairo/cairo-xlib.h>

#include <cstdlib>
#include <cstring>

#include "ModeBadgePainter.h"

namespace msime::linux_host {

namespace {

constexpr int kWidth = 132;
constexpr int kHeight = 64;
constexpr int kEdgeMargin = 24;
constexpr int kIconSize = 36;
constexpr int kIconLeft = 14;

}  // namespace

std::unique_ptr<ModeBadgeX11Surface> ModeBadgeX11Surface::create() {
  const auto *display_name = std::getenv("DISPLAY");
  if (!display_name || !*display_name) return nullptr;
  std::unique_ptr<ModeBadgeX11Surface> surface(new ModeBadgeX11Surface());
  if (!surface->ensure_window()) return nullptr;
  return surface;
}

ModeBadgeX11Surface::~ModeBadgeX11Surface() { destroy_window(); }

bool ModeBadgeX11Surface::ensure_window() {
  if (display_ && window_) return true;
  display_ = XOpenDisplay(nullptr);
  if (!display_) return false;
  const auto screen = DefaultScreen(display_);
  const auto root = RootWindow(display_, screen);
  // 右下角，与 Wayland 后端同一个位置和边距。X11 这边能直接算屏幕坐标，但仍然不跟随
  // 光标：跟随那一半由各自面板的文字提示承担，两个会话类型下的行为因此是一致的。
  const int x = DisplayWidth(display_, screen) - kWidth - kEdgeMargin;
  const int y = DisplayHeight(display_, screen) - kHeight - kEdgeMargin;
  // 找一个 32 位 ARGB visual，否则圆角之外那几个像素只能是纯色，在任何背景上都是一块
  // 黑角。拿不到就退回默认 visual：形状难看，但提示仍然可用。
  XVisualInfo visual_template{};
  visual_template.screen = screen;
  visual_template.depth = 32;
  visual_template.c_class = TrueColor;
  int visual_count = 0;
  XVisualInfo *visuals = XGetVisualInfo(
      display_, VisualScreenMask | VisualDepthMask | VisualClassMask, &visual_template,
      &visual_count);
  XSetWindowAttributes attributes{};
  attributes.override_redirect = True;  // 不进任务栏、不被窗口管理器摆布、不抢焦点
  attributes.background_pixel = 0;
  attributes.border_pixel = 0;
  unsigned long mask = CWOverrideRedirect | CWBackPixel | CWBorderPixel;
  Visual *visual = DefaultVisual(display_, screen);
  int depth = DefaultDepth(display_, screen);
  if (visuals && visual_count > 0) {
    visual = visuals[0].visual;
    depth = visuals[0].depth;
    attributes.colormap = XCreateColormap(display_, root, visual, AllocNone);
    colormap_ = attributes.colormap;
    mask |= CWColormap;
  }
  visual_ = visual;
  window_ = XCreateWindow(display_, root, x, y, kWidth, kHeight, 0, depth, InputOutput, visual,
                          mask, &attributes);
  if (visuals) XFree(visuals);
  if (!window_) {
    XCloseDisplay(display_);
    display_ = nullptr;
    return false;
  }
  // 提示不接受任何输入：空的输入形状让点击穿透到下面的窗口。没有 Shape 扩展时退而求其次，
  // 只是不选择任何输入事件。
  int shape_event = 0, shape_error = 0;
  if (XQueryExtension(display_, "SHAPE", &shape_event, &shape_error, &shape_error)) {
    const auto region = XCreateRegion();
    XShapeCombineRegion(display_, window_, ShapeInput, 0, 0, region, ShapeSet);
    XDestroyRegion(region);
  }
  XSelectInput(display_, window_, ExposureMask);
  return true;
}

bool ModeBadgeX11Surface::show(const std::string &text, const std::string &icon_path,
                               bool light_theme) {
  if (!ensure_window()) return false;
  XMapRaised(display_, window_);
  auto *surface = cairo_xlib_surface_create(display_, window_, visual_, kWidth, kHeight);
  auto *cairo = cairo_create(surface);
  paint_mode_badge(cairo, kWidth, kHeight, text, icon_path, light_theme, kIconSize, kIconLeft);
  cairo_destroy(cairo);
  cairo_surface_destroy(surface);
  XFlush(display_);
  visible_ = true;
  return true;
}

void ModeBadgeX11Surface::hide() {
  if (!visible_ || !display_ || !window_) return;
  visible_ = false;
  XUnmapWindow(display_, window_);
  XFlush(display_);
}

void ModeBadgeX11Surface::destroy_window() {
  if (display_ && window_) {
    XDestroyWindow(display_, window_);
    window_ = 0;
  }
  if (display_ && colormap_) {
    XFreeColormap(display_, colormap_);
    colormap_ = 0;
  }
  if (display_) {
    XCloseDisplay(display_);
    display_ = nullptr;
  }
  visible_ = false;
}

}  // namespace msime::linux_host
