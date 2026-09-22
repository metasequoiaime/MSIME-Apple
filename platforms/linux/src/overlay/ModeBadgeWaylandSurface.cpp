#include "ModeBadgeWaylandSurface.h"

#include <fcntl.h>
#include <cairo/cairo.h>
#include <pango/pangocairo.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <wayland-client.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "wlr-layer-shell-unstable-v1-client-protocol.h"

namespace msime::linux_host {

namespace {

constexpr int kWidth = 132;
constexpr int kHeight = 64;
constexpr int kStride = kWidth * 4;
constexpr std::size_t kBufferBytes = static_cast<std::size_t>(kStride) * kHeight;
constexpr int kEdgeMargin = 24;
constexpr int kIconSize = 36;
constexpr int kIconLeft = 14;

int shared_fd() {
#ifdef SYS_memfd_create
  const auto memfd = static_cast<int>(syscall(SYS_memfd_create, "msime-mode-badge", MFD_CLOEXEC));
  if (memfd >= 0) return memfd;
#endif
  char name[64];
  std::snprintf(name, sizeof(name), "/msime-badge-%ld", static_cast<long>(getpid()));
  const auto fd = shm_open(name, O_CREAT | O_EXCL | O_RDWR, 0600);
  if (fd >= 0) shm_unlink(name);
  return fd;
}

}  // namespace

void ModeBadgeWaylandSurface::registry_global(void *data, wl_registry *registry, uint32_t name,
                                              const char *interface, uint32_t version) {
  auto *self = static_cast<ModeBadgeWaylandSurface *>(data);
  if (std::strcmp(interface, "wl_compositor") == 0 && !self->compositor_) {
    self->compositor_ = static_cast<wl_compositor *>(
        wl_registry_bind(registry, name, &wl_compositor_interface, version < 4 ? version : 4));
  } else if (std::strcmp(interface, "wl_shm") == 0 && !self->shm_) {
    self->shm_ = static_cast<wl_shm *>(wl_registry_bind(registry, name, &wl_shm_interface, 1));
  } else if (std::strcmp(interface, "zwlr_layer_shell_v1") == 0 && !self->layer_shell_) {
    self->layer_shell_ = static_cast<zwlr_layer_shell_v1 *>(wl_registry_bind(
        registry, name, &zwlr_layer_shell_v1_interface, version < 4 ? version : 4));
  }
}

void ModeBadgeWaylandSurface::registry_remove(void *, wl_registry *, uint32_t) {}

void ModeBadgeWaylandSurface::layer_configure(void *data, zwlr_layer_surface_v1 *surface,
                                              uint32_t serial, uint32_t, uint32_t) {
  auto *self = static_cast<ModeBadgeWaylandSurface *>(data);
  zwlr_layer_surface_v1_ack_configure(surface, serial);
  self->configured_ = true;
}

void ModeBadgeWaylandSurface::layer_closed(void *data, zwlr_layer_surface_v1 *) {
  static_cast<ModeBadgeWaylandSurface *>(data)->closed_ = true;
}

std::unique_ptr<ModeBadgeWaylandSurface> ModeBadgeWaylandSurface::create() {
  const auto *socket = std::getenv("WAYLAND_DISPLAY");
  if (!socket || !*socket) return nullptr;
  std::unique_ptr<ModeBadgeWaylandSurface> surface(new ModeBadgeWaylandSurface());
  if (!surface->ensure_surface()) return nullptr;
  return surface;
}

ModeBadgeWaylandSurface::~ModeBadgeWaylandSurface() { destroy_surface(); }

bool ModeBadgeWaylandSurface::ensure_surface() {
  if (closed_) destroy_surface();
  if (display_ && surface_ && configured_ && !closed_) return true;
  if (!display_) {
    display_ = wl_display_connect(nullptr);
    if (!display_) return false;
    registry_ = wl_display_get_registry(display_);
    static const wl_registry_listener registry_listener = {registry_global, registry_remove};
    wl_registry_add_listener(registry_, &registry_listener, this);
    if (wl_display_roundtrip(display_) < 0 || !compositor_ || !shm_ || !layer_shell_) {
      destroy_surface();
      return false;
    }
  }
  if (!surface_) {
    surface_ = wl_compositor_create_surface(compositor_);
    layer_surface_ = zwlr_layer_shell_v1_get_layer_surface(
        layer_shell_, surface_, nullptr, ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY,
        "msime-client-mode-badge");
    static const zwlr_layer_surface_v1_listener layer_listener = {layer_configure, layer_closed};
    zwlr_layer_surface_v1_add_listener(layer_surface_, &layer_listener, this);
    zwlr_layer_surface_v1_set_size(layer_surface_, kWidth, kHeight);
    // 锚右下角。跟随光标做不到——layer-shell 要屏幕坐标，而 text-input 报的光标矩形是
    // 应用表面内的局部坐标，只有合成器能换算；跟随光标那一半由面板自己的文字提示承担。
    // 放角落是为了不压住正文。不占 exclusive zone，也不要键盘交互：这是提示，不是窗口。
    zwlr_layer_surface_v1_set_anchor(layer_surface_,
                                     ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM |
                                         ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT);
    zwlr_layer_surface_v1_set_margin(layer_surface_, 0, kEdgeMargin, kEdgeMargin, 0);
    zwlr_layer_surface_v1_set_exclusive_zone(layer_surface_, -1);
    zwlr_layer_surface_v1_set_keyboard_interactivity(
        layer_surface_, ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_NONE);
    // 整个浮层不接收指针输入：空的输入区域让点击穿透到下面的窗口。
    if (auto *region = wl_compositor_create_region(compositor_)) {
      wl_surface_set_input_region(surface_, region);
      wl_region_destroy(region);
    }
    wl_surface_commit(surface_);
    if (wl_display_roundtrip(display_) < 0 || !configured_ || closed_) {
      destroy_surface();
      return false;
    }
  }
  if (!buffer_) {
    const auto fd = shared_fd();
    if (fd < 0) return false;
    if (ftruncate(fd, static_cast<off_t>(kBufferBytes)) != 0) {
      close(fd);
      return false;
    }
    pixels_ = mmap(nullptr, kBufferBytes, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (pixels_ == MAP_FAILED) {
      pixels_ = nullptr;
      close(fd);
      return false;
    }
    auto *pool = wl_shm_create_pool(shm_, fd, static_cast<int32_t>(kBufferBytes));
    buffer_ = wl_shm_pool_create_buffer(pool, 0, kWidth, kHeight, kStride, WL_SHM_FORMAT_ARGB8888);
    wl_shm_pool_destroy(pool);
    close(fd);
  }
  return buffer_ != nullptr;
}

void ModeBadgeWaylandSurface::draw(const std::string &text, const std::string &icon_path,
                                   bool light_theme) {
  auto *image = cairo_image_surface_create_for_data(static_cast<unsigned char *>(pixels_),
                                                    CAIRO_FORMAT_ARGB32, kWidth, kHeight, kStride);
  auto *cairo = cairo_create(image);
  cairo_set_operator(cairo, CAIRO_OPERATOR_SOURCE);
  cairo_set_source_rgba(cairo, 0, 0, 0, 0);
  cairo_paint(cairo);
  cairo_set_operator(cairo, CAIRO_OPERATOR_OVER);

  // 圆角底板。深浅跟随共享偏好的候选主题，与面板观感一致。
  const double radius = 14.0;
  const double w = kWidth, h = kHeight;
  cairo_new_sub_path(cairo);
  cairo_arc(cairo, w - radius, radius, radius, -1.5708, 0);
  cairo_arc(cairo, w - radius, h - radius, radius, 0, 1.5708);
  cairo_arc(cairo, radius, h - radius, radius, 1.5708, 3.1416);
  cairo_arc(cairo, radius, radius, radius, 3.1416, 4.7124);
  cairo_close_path(cairo);
  if (light_theme)
    cairo_set_source_rgba(cairo, 0.96, 0.97, 0.98, 0.96);
  else
    cairo_set_source_rgba(cairo, 0.125, 0.129, 0.141, 0.96);
  cairo_fill_preserve(cairo);
  cairo_set_source_rgba(cairo, light_theme ? 0.85 : 0.22, light_theme ? 0.87 : 0.23,
                        light_theme ? 0.91 : 0.25, 1.0);
  cairo_set_line_width(cairo, 1.0);
  cairo_stroke(cairo);

  // logo。读不到就只画文字：提示缺一半也比不显示强。
  double text_left = kIconLeft;
  if (!icon_path.empty()) {
    if (auto *logo = cairo_image_surface_create_from_png(icon_path.c_str())) {
      if (cairo_surface_status(logo) == CAIRO_STATUS_SUCCESS) {
        const double source_w = cairo_image_surface_get_width(logo);
        const double source_h = cairo_image_surface_get_height(logo);
        if (source_w > 0 && source_h > 0) {
          const double scale = kIconSize / (source_w > source_h ? source_w : source_h);
          cairo_save(cairo);
          cairo_translate(cairo, kIconLeft, (kHeight - source_h * scale) / 2.0);
          cairo_scale(cairo, scale, scale);
          cairo_set_source_surface(cairo, logo, 0, 0);
          cairo_paint(cairo);
          cairo_restore(cairo);
          text_left = kIconLeft + source_w * scale + 12;
        }
      }
      cairo_surface_destroy(logo);
    }
  }

  auto *layout = pango_cairo_create_layout(cairo);
  auto *font = pango_font_description_from_string("Noto Sans CJK SC 26");
  pango_layout_set_font_description(layout, font);
  pango_font_description_free(font);
  pango_layout_set_text(layout, text.c_str(), -1);
  int text_w = 0, text_h = 0;
  pango_layout_get_pixel_size(layout, &text_w, &text_h);
  cairo_move_to(cairo, text_left, (kHeight - text_h) / 2.0);
  if (light_theme)
    cairo_set_source_rgb(cairo, 0.13, 0.13, 0.14);
  else
    cairo_set_source_rgb(cairo, 0.96, 0.97, 0.98);
  pango_cairo_show_layout(cairo, layout);
  g_object_unref(layout);

  cairo_destroy(cairo);
  cairo_surface_destroy(image);
}

bool ModeBadgeWaylandSurface::show(const std::string &text, const std::string &icon_path,
                                   bool light_theme) {
  if (!ensure_surface()) return false;
  draw(text, icon_path, light_theme);
  wl_surface_attach(surface_, buffer_, 0, 0);
  wl_surface_damage_buffer(surface_, 0, 0, kWidth, kHeight);
  wl_surface_commit(surface_);
  visible_ = true;
  // 用 roundtrip 而不是 flush：flush 在内核缓冲区写不下时返回 -1（EAGAIN），连接其实好
  // 好的，据此判失败会让提交永远发不出去。roundtrip 负责把队列写完并等一次同步，只有
  // 真正的连接错误才返回负值。
  return wl_display_roundtrip(display_) >= 0;
}

void ModeBadgeWaylandSurface::hide() {
  if (!visible_ || !surface_) return;
  visible_ = false;
  // 附一个空缓冲区即隐藏，保留 surface 和 layer 对象，下一次切换不必重新协商。
  wl_surface_attach(surface_, nullptr, 0, 0);
  wl_surface_commit(surface_);
  if (display_) wl_display_roundtrip(display_);
}

void ModeBadgeWaylandSurface::destroy_surface() {
  if (buffer_) {
    wl_buffer_destroy(buffer_);
    buffer_ = nullptr;
  }
  if (pixels_) {
    munmap(pixels_, kBufferBytes);
    pixels_ = nullptr;
  }
  if (layer_surface_) {
    zwlr_layer_surface_v1_destroy(layer_surface_);
    layer_surface_ = nullptr;
  }
  if (surface_) {
    wl_surface_destroy(surface_);
    surface_ = nullptr;
  }
  if (layer_shell_) {
    zwlr_layer_shell_v1_destroy(layer_shell_);
    layer_shell_ = nullptr;
  }
  if (shm_) {
    wl_shm_destroy(shm_);
    shm_ = nullptr;
  }
  if (compositor_) {
    wl_compositor_destroy(compositor_);
    compositor_ = nullptr;
  }
  if (registry_) {
    wl_registry_destroy(registry_);
    registry_ = nullptr;
  }
  if (display_) {
    wl_display_disconnect(display_);
    display_ = nullptr;
  }
  configured_ = false;
  closed_ = false;
  visible_ = false;
}

}  // namespace msime::linux_host
