#pragma once

#include "WaveOverlaySurface.h"

#include <wayland-client.h>

#include <array>
#include <cstddef>
#include <functional>
#include <utility>

struct wl_buffer;
struct wl_display;
struct wl_registry;
struct wl_compositor;
struct wl_shm;
struct wl_seat;
struct wl_pointer;
struct wl_surface;
struct zwlr_layer_shell_v1;
struct zwlr_layer_surface_v1;

namespace msime::linux_host {

// Native wlroots layer-shell surface. It is deliberately output-independent
// and never requests keyboard focus; unsupported compositors use the factory's
// IBus fallback.
class WaveOverlayWaylandSurface final : public WaveOverlaySurface {
 public:
  explicit WaveOverlayWaylandSurface(ActionHandler action_handler = {})
      : action_handler_(std::move(action_handler)) {}
  ~WaveOverlayWaylandSurface() override;

  bool show(const WaveOverlayModel &model) override;
  void update(const WaveOverlayModel &model) override;
 void hide() override;

 private:
  static void registry_global(void *, wl_registry *, uint32_t, const char *, uint32_t);
  static void registry_remove(void *, wl_registry *, uint32_t);
  static void seat_capabilities(void *, wl_seat *, uint32_t);
  static void seat_name(void *, wl_seat *, const char *);
  static void pointer_enter(void *, wl_pointer *, uint32_t, wl_surface *,
                            wl_fixed_t, wl_fixed_t);
  static void pointer_leave(void *, wl_pointer *, uint32_t, wl_surface *);
  static void pointer_motion(void *, wl_pointer *, uint32_t, wl_fixed_t,
                             wl_fixed_t);
  static void pointer_button(void *, wl_pointer *, uint32_t, uint32_t,
                             uint32_t, uint32_t);
  static void pointer_axis(void *, wl_pointer *, uint32_t, uint32_t,
                           wl_fixed_t);
  static void pointer_frame(void *, wl_pointer *);
  static void pointer_axis_source(void *, wl_pointer *, uint32_t);
  static void pointer_axis_stop(void *, wl_pointer *, uint32_t, uint32_t);
  static void pointer_axis_discrete(void *, wl_pointer *, uint32_t, int32_t);
  static void pointer_axis_value120(void *, wl_pointer *, uint32_t, int32_t);
  static void layer_configure(void *, zwlr_layer_surface_v1 *, uint32_t, uint32_t,
                              uint32_t);
  static void layer_closed(void *, zwlr_layer_surface_v1 *);
  static void buffer_release(void *, wl_buffer *);
  bool ensure_surface();
  bool ensure_buffers();
  void draw(const WaveOverlayModel &model);
  void pump_events();
  void set_input_region(bool actions_visible);
  bool hit_test_action(int x, int y, WaveOverlayModel::Action &action) const;
  void destroy_surface();
  void release_buffer(std::size_t index);

  wl_display *display_ = nullptr;
  wl_registry *registry_ = nullptr;
  wl_compositor *compositor_ = nullptr;
  wl_shm *shm_ = nullptr;
  wl_seat *seat_ = nullptr;
  wl_pointer *pointer_ = nullptr;
  zwlr_layer_shell_v1 *layer_shell_ = nullptr;
  wl_surface *surface_ = nullptr;
  zwlr_layer_surface_v1 *layer_surface_ = nullptr;
  std::array<wl_buffer *, 2> buffers_{};
  std::array<void *, 2> pixels_{};
  std::array<bool, 2> buffer_busy_{};
  struct BufferContext {
    WaveOverlayWaylandSurface *owner = nullptr;
    std::size_t index = 0;
  };
  std::array<BufferContext, 2> buffer_contexts_{};
  int shm_fd_ = -1;
  std::size_t buffer_size_ = 0;
  std::size_t next_buffer_ = 0;
  bool configured_ = false;
  bool visible_ = false;
  bool closed_ = false;
  ActionHandler action_handler_;
  WaveOverlayModel::Action pressed_action_ = WaveOverlayModel::Action::Confirm;
  bool action_pressed_ = false;
  bool actions_visible_ = false;
  bool pointer_inside_ = false;
  int pointer_x_ = 0;
  int pointer_y_ = 0;
};

}  // namespace msime::linux_host
