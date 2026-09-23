#include "WaveOverlayX11Surface.h"

#include "WaveOverlayPlacement.h"

#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/Xresource.h>
#include <X11/Xutil.h>
#include <X11/extensions/Xfixes.h>
#include <X11/extensions/Xrandr.h>
#include <X11/extensions/shape.h>

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdlib>
#include <locale>
#include <optional>
#include <sstream>
#include <string>
#include <vector>

namespace msime::linux_host {
namespace {

// Logical geometry at a scale of 1; every length is multiplied by the current scale before it reaches the X server.
constexpr int kLogicalWidth = 420;
constexpr int kLogicalHeight = 132;
constexpr int kBarCount = 12;
constexpr int kActionCenterInset = 24;
constexpr int kActionCenterY = 66;
constexpr int kActionRadius = 14;
constexpr int kFontPixelSize = 14;
// Matches the Windows voice bar, which sits 10 px above the bottom of the work area.
constexpr int kBottomMargin = 10;
// update() runs for every input-level change, so the monitor, work area and scale are re-read at most this often while visible; show() always re-reads them.
constexpr auto kPlacementRefreshInterval = std::chrono::milliseconds(500);

std::vector<std::uint32_t> cardinal_property(Display *display, Window window,
                                              Atom property,
                                              Atom type = XA_CARDINAL) {
  Atom actual_type = None;
  int actual_format = 0;
  unsigned long item_count = 0;
  unsigned long bytes_after = 0;
  unsigned char *raw = nullptr;
  const auto status = XGetWindowProperty(
      display, window, property, 0, 4096, False, type, &actual_type,
      &actual_format, &item_count, &bytes_after, &raw);
  if (status != Success || actual_type != type || actual_format != 32 ||
      !raw) {
    if (raw)
      XFree(raw);
    return {};
  }
  const auto *values = reinterpret_cast<const unsigned long *>(raw);
  std::vector<std::uint32_t> result;
  result.reserve(item_count);
  for (unsigned long index = 0; index < item_count; ++index)
    result.push_back(static_cast<std::uint32_t>(values[index]));
  XFree(raw);
  return result;
}

std::optional<double> parse_number(const char *text) {
  if (!text || !*text)
    return std::nullopt;
  // The host process may run under a locale whose decimal separator is a comma; X resources and GDK_SCALE always use a period.
  std::istringstream stream(text);
  stream.imbue(std::locale::classic());
  double value = 0.0;
  if (!(stream >> value) || value <= 0.0)
    return std::nullopt;
  return value;
}

// Xft.dpi from the RESOURCE_MANAGER property, read from the root window each time because the copy Xlib takes at XOpenDisplay goes stale on this long-lived connection when the desktop changes its scale.
std::optional<double> xft_dpi(Display *display, Window root) {
  std::string resources;
  Atom actual_type = None;
  int actual_format = 0;
  unsigned long item_count = 0;
  unsigned long bytes_after = 0;
  unsigned char *raw = nullptr;
  if (XGetWindowProperty(display, root, XA_RESOURCE_MANAGER, 0, 1 << 16, False,
                         XA_STRING, &actual_type, &actual_format, &item_count,
                         &bytes_after, &raw) == Success &&
      actual_type == XA_STRING && actual_format == 8 && raw)
    resources.assign(reinterpret_cast<const char *>(raw), item_count);
  if (raw)
    XFree(raw);
  if (resources.empty()) {
    if (const auto *initial = XResourceManagerString(display))
      resources = initial;
  }
  if (resources.empty())
    return std::nullopt;
  XrmInitialize();
  const auto database = XrmGetStringDatabase(resources.c_str());
  if (!database)
    return std::nullopt;
  char *type = nullptr;
  XrmValue value{};
  std::optional<double> dpi;
  if (XrmGetResource(database, "Xft.dpi", "Xft.Dpi", &type, &value) &&
      value.addr)
    dpi = parse_number(value.addr);
  XrmDestroyDatabase(database);
  return dpi;
}

std::vector<WaveOverlayWorkArea>
work_area_rectangles(const std::vector<std::uint32_t> &values,
                     std::size_t first, std::size_t count) {
  std::vector<WaveOverlayWorkArea> areas;
  for (std::size_t index = first; index < first + count; ++index) {
    const auto offset = index * 4;
    if (offset + 4 > values.size())
      break;
    const WaveOverlayWorkArea area{static_cast<std::int32_t>(values[offset]),
                                   static_cast<std::int32_t>(values[offset + 1]),
                                   static_cast<std::int32_t>(values[offset + 2]),
                                   static_cast<std::int32_t>(values[offset + 3])};
    if (area.width > 0 && area.height > 0)
      areas.push_back(area);
  }
  return areas;
}

// The current desktop's work areas: Mutter's per-monitor _GTK_WORKAREAS_D<n> when it publishes one, otherwise the single EWMH _NET_WORKAREA rectangle.
std::vector<WaveOverlayWorkArea> desktop_work_areas(Display *display,
                                                    Window root) {
  std::size_t desktop = 0;
  const auto desktop_atom = XInternAtom(display, "_NET_CURRENT_DESKTOP", True);
  if (desktop_atom != None) {
    const auto current = cardinal_property(display, root, desktop_atom);
    if (!current.empty())
      desktop = current.front();
  }
  const auto gtk_name = "_GTK_WORKAREAS_D" + std::to_string(desktop);
  const auto gtk_atom = XInternAtom(display, gtk_name.c_str(), True);
  if (gtk_atom != None) {
    const auto values = cardinal_property(display, root, gtk_atom);
    auto areas = work_area_rectangles(values, 0, values.size() / 4);
    if (!areas.empty())
      return areas;
  }
  const auto workarea_atom = XInternAtom(display, "_NET_WORKAREA", True);
  if (workarea_atom == None)
    return {};
  const auto values = cardinal_property(display, root, workarea_atom);
  const auto desktop_count = values.size() / 4;
  if (desktop >= desktop_count)
    desktop = 0;
  return work_area_rectangles(values, desktop, 1);
}

int ignore_x_error(Display *, XErrorEvent *) { return 0; }

// Centre of the EWMH active window in root coordinates. The window can be destroyed between reading _NET_ACTIVE_WINDOW and querying it, and Xlib's default handler exits the process on the resulting BadWindow, so the queries run under a handler that ignores errors.
std::optional<WaveOverlayPosition> active_window_center(Display *display,
                                                        Window root) {
  const auto active_atom = XInternAtom(display, "_NET_ACTIVE_WINDOW", True);
  if (active_atom == None)
    return std::nullopt;
  const auto values = cardinal_property(display, root, active_atom, XA_WINDOW);
  if (values.empty() || values.front() == None)
    return std::nullopt;
  const Window active = values.front();
  XSync(display, False);
  const auto previous = XSetErrorHandler(ignore_x_error);
  std::optional<WaveOverlayPosition> center;
  XWindowAttributes attributes{};
  int x = 0;
  int y = 0;
  Window child = 0;
  if (XGetWindowAttributes(display, active, &attributes) &&
      attributes.map_state == IsViewable &&
      XTranslateCoordinates(display, active, root, attributes.width / 2,
                            attributes.height / 2, &x, &y, &child))
    center = WaveOverlayPosition{x, y};
  XSync(display, False);
  XSetErrorHandler(previous);
  return center;
}

std::optional<WaveOverlayPosition> pointer_position(Display *display,
                                                    Window root) {
  Window root_return = 0;
  Window child = 0;
  int root_x = 0;
  int root_y = 0;
  int window_x = 0;
  int window_y = 0;
  unsigned int mask = 0;
  if (!XQueryPointer(display, root, &root_return, &child, &root_x, &root_y,
                     &window_x, &window_y, &mask))
    return std::nullopt;
  return WaveOverlayPosition{root_x, root_y};
}

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
  int randr_event = 0;
  int randr_error = 0;
  int randr_major = 0;
  int randr_minor = 0;
  randr_monitors_ =
      XRRQueryExtension(display_, &randr_event, &randr_error) &&
      XRRQueryVersion(display_, &randr_major, &randr_minor) &&
      (randr_major > 1 || (randr_major == 1 && randr_minor >= 5));
  const auto root = RootWindow(display_, screen);
  XSetWindowAttributes attributes{};
  attributes.override_redirect = True;
  attributes.background_pixel = color(display_, screen, "#202124", BlackPixel(display_, screen));
  attributes.border_pixel = color(display_, screen, "#4a4d52", WhitePixel(display_, screen));
  window_ = XCreateWindow(display_, root, 0, 0, kLogicalWidth, kLogicalHeight, 1,
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
  light_background_ = color(display_, screen, "#f5f7fa", WhitePixel(display_, screen));
  light_foreground_ = color(display_, screen, "#202124", BlackPixel(display_, screen));
  light_accent_ = color(display_, screen, "#3367d6", BlackPixel(display_, screen));
  // Zero size makes the first place() apply the scale, resize the window and load the font set.
  scale_ = 1.0;
  width_ = 0;
  height_ = 0;
  XSelectInput(display_, window_, ExposureMask | ButtonPressMask |
                                       ButtonReleaseMask);
  set_input_region(false);
  return true;
}

int WaveOverlayX11Surface::scaled(int logical) const {
  return wave_overlay_scaled(logical, scale_);
}

void WaveOverlayX11Surface::load_font_set() {
  if (font_set_) {
    XFreeFontSet(display_, font_set_);
    font_set_ = nullptr;
  }
  const auto create = [this](int pixel_size, int &missing_count) {
    const auto pattern = "-misc-fixed-*-*-*-*-" + std::to_string(pixel_size) +
                         "-*-*-*-*-*-*-*";
    char **missing = nullptr;
    char *default_string = nullptr;
    missing_count = 0;
    const auto font_set = XCreateFontSet(display_, pattern.c_str(), &missing,
                                         &missing_count, &default_string);
    if (missing)
      XFreeStringList(missing);
    return font_set;
  };
  // The bitmap fixed fonts only come in a few sizes. When the scaled size is missing, or covers fewer charsets (CJK above all), the 1x size stays: small text beats unreadable text.
  int scaled_missing = 0;
  const auto pixel_size = scaled(kFontPixelSize);
  font_set_ = create(pixel_size, scaled_missing);
  if (pixel_size == kFontPixelSize || (font_set_ && scaled_missing == 0))
    return;
  int base_missing = 0;
  const auto base = create(kFontPixelSize, base_missing);
  if (base && (!font_set_ || base_missing < scaled_missing)) {
    if (font_set_)
      XFreeFontSet(display_, font_set_);
    font_set_ = base;
  } else if (base) {
    XFreeFontSet(display_, base);
  }
}

// Mirrors the Windows voice bar's update_window_bounds: the scale and the target monitor are re-read, the window resized when the scale changed, and the bar centred on the monitor holding the focused window, just above its work-area bottom.
void WaveOverlayX11Surface::place(bool force) {
  if (!display_ || !window_)
    return;
  const auto now = std::chrono::steady_clock::now();
  if (!force && width_ != 0 && now - placed_at_ < kPlacementRefreshInterval)
    return;
  placed_at_ = now;
  const auto screen = DefaultScreen(display_);
  const auto root = RootWindow(display_, screen);
  const auto scale = wave_overlay_scale(xft_dpi(display_, root),
                                        parse_number(std::getenv("GDK_SCALE")));
  const auto width =
      static_cast<unsigned>(wave_overlay_scaled(kLogicalWidth, scale));
  const auto height =
      static_cast<unsigned>(wave_overlay_scaled(kLogicalHeight, scale));
  if (width != width_ || height != height_ || scale != scale_) {
    scale_ = scale;
    width_ = width;
    height_ = height;
    XResizeWindow(display_, window_, width_, height_);
    const auto line_width = scaled(1);
    XSetLineAttributes(display_, gc_, line_width > 1 ? line_width : 0,
                       LineSolid, CapRound, JoinRound);
    load_font_set();
  }

  const auto work_areas = desktop_work_areas(display_, root);
  const WaveOverlayWorkArea root_area{0, 0, DisplayWidth(display_, screen),
                                      DisplayHeight(display_, screen)};
  // Without monitor information the whole EWMH work area stands in for the monitor, which keeps its multi-head negative coordinates.
  const auto fallback = work_areas.empty() ? root_area : work_areas.front();
  WaveOverlayMonitor target{fallback, fallback};
  if (randr_monitors_) {
    std::vector<WaveOverlayMonitor> monitors;
    std::optional<std::size_t> primary;
    int count = 0;
    if (auto *infos = XRRGetMonitors(display_, root, True, &count)) {
      for (int index = 0; index < count; ++index) {
        const WaveOverlayWorkArea full{infos[index].x, infos[index].y,
                                       infos[index].width, infos[index].height};
        if (full.width <= 0 || full.height <= 0)
          continue;
        if (infos[index].primary)
          primary = monitors.size();
        monitors.push_back({full, full});
      }
      XRRFreeMonitors(infos);
    }
    std::optional<WaveOverlayPosition> focus;
    std::optional<WaveOverlayPosition> pointer;
    // A single monitor needs no focus or pointer round-trips. With several, the pointer is read even when there is an active window, because that window's centre can lie outside every monitor (dragged partly off-screen, or in the dead zone beside a shorter monitor) and the pick then falls through to the pointer.
    if (monitors.size() > 1) {
      focus = active_window_center(display_, root);
      pointer = pointer_position(display_, root);
    }
    if (const auto index =
            wave_overlay_pick_monitor(monitors, focus, pointer, primary)) {
      target.full = monitors[*index].full;
      target.work = wave_overlay_monitor_work(target.full, work_areas);
    }
  }
  const auto position = wave_overlay_monitor_bottom_center(
      target, static_cast<int>(width_), static_cast<int>(height_),
      scaled(kBottomMargin));
  XMoveWindow(display_, window_, position.x, position.y);
}

void WaveOverlayX11Surface::set_input_region(bool actions_visible) {
  if (!display_ || !window_)
    return;
  const auto radius = scaled(kActionRadius);
  const auto top = scaled(kActionCenterY) - radius;
  const auto left_center = scaled(kActionCenterInset);
  const auto right_center = static_cast<int>(width_) - left_center;
  XRectangle buttons[2] = {
      {static_cast<short>(left_center - radius), static_cast<short>(top),
       static_cast<unsigned short>(2 * radius),
       static_cast<unsigned short>(2 * radius)},
      {static_cast<short>(right_center - radius), static_cast<short>(top),
       static_cast<unsigned short>(2 * radius),
       static_cast<unsigned short>(2 * radius)}};
  XserverRegion region = XFixesCreateRegion(
      display_, actions_visible ? buttons : nullptr, actions_visible ? 2 : 0);
  if (region) {
    XFixesSetWindowShapeRegion(display_, window_, ShapeInput, 0, 0, region);
    XFixesDestroyRegion(display_, region);
  }
}

bool WaveOverlayX11Surface::hit_test_action(
    int x, int y, WaveOverlayModel::Action &action) const {
  if (!actions_visible_)
    return false;
  const auto radius = scaled(kActionRadius);
  const auto center_y = scaled(kActionCenterY);
  const auto left_center = scaled(kActionCenterInset);
  const auto inside = [x, y, radius, center_y](int center_x) {
    const int dx = x - center_x;
    const int dy = y - center_y;
    return dx * dx + dy * dy <= radius * radius;
  };
  if (inside(left_center)) {
    action = WaveOverlayModel::Action::Cancel;
    return true;
  }
  if (inside(static_cast<int>(width_) - left_center)) {
    action = WaveOverlayModel::Action::Confirm;
    return true;
  }
  return false;
}

void WaveOverlayX11Surface::pump_events() {
  if (!display_ || !visible_)
    return;
  while (XPending(display_)) {
    XEvent event{};
    XNextEvent(display_, &event);
    if (event.type == ButtonPress && event.xbutton.button == Button1) {
      WaveOverlayModel::Action action;
      if (hit_test_action(event.xbutton.x, event.xbutton.y, action)) {
        pressed_action_ = action;
        action_pressed_ = true;
        XGrabPointer(display_, window_, False, ButtonReleaseMask,
                     GrabModeAsync, GrabModeAsync, None, None, CurrentTime);
      }
    } else if (event.type == ButtonRelease && event.xbutton.button == Button1 &&
               action_pressed_) {
      WaveOverlayModel::Action action;
      const bool activated = hit_test_action(event.xbutton.x, event.xbutton.y,
                                             action) &&
                             action == pressed_action_;
      action_pressed_ = false;
      XUngrabPointer(display_, CurrentTime);
      if (activated && action_handler_)
        action_handler_(action);
    }
  }
}

void WaveOverlayX11Surface::destroy_window() {
  if (!display_)
    return;
  if (action_pressed_)
    XUngrabPointer(display_, CurrentTime);
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
  place(false);
  set_input_region(model.actions_visible);
  if (!model.actions_visible)
    action_pressed_ = false;
  const auto background = model.light_theme ? light_background_ : background_;
  const auto foreground = model.light_theme ? light_foreground_ : foreground_;
  const auto accent = model.light_theme ? light_accent_ : accent_;
  XSetForeground(display_, gc_, background);
  XFillRectangle(display_, window_, gc_, 0, 0, width_, height_);
  XSetForeground(display_, gc_, accent);
  const auto inset = scaled(16);
  const auto bar_step = (static_cast<int>(width_) - 2 * inset) / kBarCount;
  const auto bar_width = std::max(2, bar_step - scaled(3));
  const auto bar_center = scaled(56);
  for (int index = 0; index < kBarCount; ++index) {
    const auto slot = static_cast<std::size_t>(index);
    const auto level = slot < model.levels.size() ? model.levels[slot] : 0.0f;
    const auto height =
        std::max(scaled(4), static_cast<int>(level * 38.0 * scale_));
    XFillRectangle(display_, window_, gc_, inset + index * bar_step,
                   bar_center - height / 2, static_cast<unsigned>(bar_width),
                   static_cast<unsigned>(height));
  }
  if (font_set_) {
    const auto font = font_set_;
    XSetForeground(display_, gc_, foreground);
    std::string status = model.locked
                             ? "录音已锁定 · 再按快捷键或点击语音菜单结束 · Esc 取消"
                             : one_line(model.status);
    if (status.empty())
      status = "正在录音…";
    Xutf8DrawString(display_, window_, font, gc_, inset, scaled(104),
                    status.c_str(), static_cast<int>(status.size()));
    if (model.show_transcript && !model.transcript.empty()) {
      auto transcript = utf8_prefix(one_line(model.transcript), 72);
      Xutf8DrawString(display_, window_, font, gc_, inset, scaled(124),
                      transcript.c_str(), static_cast<int>(transcript.size()));
    }
  }
  if (model.actions_visible) {
    const auto radius = scaled(kActionRadius);
    const auto center_y = scaled(kActionCenterY);
    const auto cancel_x = scaled(kActionCenterInset);
    const auto confirm_x = static_cast<int>(width_) - cancel_x;
    const auto diameter = static_cast<unsigned>(2 * radius);
    XSetForeground(display_, gc_, accent);
    XFillArc(display_, window_, gc_, cancel_x - radius, center_y - radius,
             diameter, diameter, 0, 360 * 64);
    XFillArc(display_, window_, gc_, confirm_x - radius, center_y - radius,
             diameter, diameter, 0, 360 * 64);
    XSetForeground(display_, gc_, background);
    XDrawLine(display_, window_, gc_, cancel_x - scaled(5),
              center_y - scaled(5), cancel_x + scaled(5), center_y + scaled(5));
    XDrawLine(display_, window_, gc_, cancel_x + scaled(5),
              center_y - scaled(5), cancel_x - scaled(5), center_y + scaled(5));
    XDrawLine(display_, window_, gc_, confirm_x - scaled(5), center_y,
              confirm_x - scaled(1), center_y + scaled(4));
    XDrawLine(display_, window_, gc_, confirm_x - scaled(1),
              center_y + scaled(4), confirm_x + scaled(6), center_y - scaled(5));
  }
  XFlush(display_);
}

bool WaveOverlayX11Surface::show(const WaveOverlayModel &model) {
  if (!ensure_window())
    return false;
  visible_ = true;
  actions_visible_ = model.actions_visible;
  // Placed before mapping so the bar never flashes at its previous monitor or size.
  place(true);
  XMapRaised(display_, window_);
  draw(model);
  pump_events();
  return true;
}

void WaveOverlayX11Surface::update(const WaveOverlayModel &model) {
  if (visible_) {
    actions_visible_ = model.actions_visible;
    pump_events();
    draw(model);
  }
}

void WaveOverlayX11Surface::hide() {
  if (display_ && window_ && visible_) {
    XUnmapWindow(display_, window_);
    XFlush(display_);
  }
  if (display_ && action_pressed_)
    XUngrabPointer(display_, CurrentTime);
  visible_ = false;
  action_pressed_ = false;
}

}  // namespace msime::linux_host
