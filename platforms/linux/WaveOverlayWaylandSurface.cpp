#include "WaveOverlayWaylandSurface.h"

#include "wlr-layer-shell-unstable-v1-client-protocol.h"

#include <wayland-client.h>

#include <algorithm>
#include <cerrno>
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <string>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

namespace msime::linux_host {
namespace {

constexpr int kWidth = 420;
constexpr int kHeight = 88;
constexpr int kStride = kWidth * 4;
constexpr std::size_t kBufferBytes = static_cast<std::size_t>(kStride) * kHeight;

int create_shm_file() {
#ifdef SYS_memfd_create
  const auto memfd = static_cast<int>(syscall(SYS_memfd_create,
                                              "msime-wave-overlay", MFD_CLOEXEC));
  if (memfd >= 0)
    return memfd;
#endif
  char name[64];
  std::snprintf(name, sizeof(name), "/msime-wave-%ld", static_cast<long>(getpid()));
  const auto fd = shm_open(name, O_CREAT | O_EXCL | O_RDWR, 0600);
  if (fd >= 0)
    shm_unlink(name);
  return fd;
}

}  // namespace

void WaveOverlayWaylandSurface::registry_global(
    void *data, wl_registry *registry, uint32_t name, const char *interface,
    uint32_t version) {
  auto *self = static_cast<WaveOverlayWaylandSurface *>(data);
  if (std::strcmp(interface, "wl_compositor") == 0 && !self->compositor_) {
    self->compositor_ = static_cast<wl_compositor *>(wl_registry_bind(
        registry, name, &wl_compositor_interface, std::min(version, 4u)));
  } else if (std::strcmp(interface, "wl_shm") == 0 && !self->shm_) {
    self->shm_ = static_cast<wl_shm *>(wl_registry_bind(
        registry, name, &wl_shm_interface, 1));
  } else if (std::strcmp(interface, "zwlr_layer_shell_v1") == 0 && !self->layer_shell_) {
    self->layer_shell_ = static_cast<zwlr_layer_shell_v1 *>(wl_registry_bind(
        registry, name, &zwlr_layer_shell_v1_interface, std::min(version, 4u)));
  }
}

void WaveOverlayWaylandSurface::registry_remove(void *, wl_registry *, uint32_t) {}

void WaveOverlayWaylandSurface::layer_configure(
    void *data, zwlr_layer_surface_v1 *surface, uint32_t serial, uint32_t width,
    uint32_t height) {
  auto *self = static_cast<WaveOverlayWaylandSurface *>(data);
  zwlr_layer_surface_v1_ack_configure(surface, serial);
  if (width != 0 && height != 0 && (width != kWidth || height != kHeight)) {
    // The fixed-size surface is intentionally advertised; a compositor may
    // still choose a different size, but the next frame remains bounded.
  }
  self->configured_ = true;
}

void WaveOverlayWaylandSurface::layer_closed(void *data,
                                             zwlr_layer_surface_v1 *) {
  static_cast<WaveOverlayWaylandSurface *>(data)->closed_ = true;
}

void WaveOverlayWaylandSurface::buffer_release(void *data, wl_buffer *) {
  auto *context = static_cast<BufferContext *>(data);
  context->owner->release_buffer(context->index);
}

WaveOverlayWaylandSurface::~WaveOverlayWaylandSurface() { destroy_surface(); }

bool WaveOverlayWaylandSurface::ensure_surface() {
  if (closed_)
    destroy_surface();
  if (display_ && surface_ && configured_ && !closed_)
    return true;
  if (!display_) {
    const auto *socket = std::getenv("WAYLAND_DISPLAY");
    if (!socket || !*socket)
      return false;
    display_ = wl_display_connect(nullptr);
    if (!display_)
      return false;
    registry_ = wl_display_get_registry(display_);
    static const wl_registry_listener registry_listener = {
        registry_global, registry_remove};
    wl_registry_add_listener(registry_, &registry_listener, this);
    if (wl_display_roundtrip(display_) < 0 || !compositor_ || !shm_ || !layer_shell_) {
      destroy_surface();
      return false;
    }
    surface_ = wl_compositor_create_surface(compositor_);
    layer_surface_ = zwlr_layer_shell_v1_get_layer_surface(
        layer_shell_, surface_, nullptr, ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY,
        "msime-client-wave-overlay");
    static const zwlr_layer_surface_v1_listener layer_listener = {
        layer_configure, layer_closed};
    zwlr_layer_surface_v1_add_listener(layer_surface_, &layer_listener, this);
    zwlr_layer_surface_v1_set_size(layer_surface_, kWidth, kHeight);
    zwlr_layer_surface_v1_set_anchor(
        layer_surface_, ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP |
                           ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT);
    zwlr_layer_surface_v1_set_margin(layer_surface_, 48, 24, 0, 0);
    zwlr_layer_surface_v1_set_exclusive_zone(layer_surface_, -1);
    zwlr_layer_surface_v1_set_keyboard_interactivity(
        layer_surface_, ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_NONE);
    wl_surface_commit(surface_);
    if (wl_display_roundtrip(display_) < 0 || !configured_ || closed_) {
      destroy_surface();
      return false;
    }
  }
  return ensure_buffers();
}

bool WaveOverlayWaylandSurface::ensure_buffers() {
  if (buffers_[0] && buffers_[1])
    return true;
  shm_fd_ = create_shm_file();
  if (shm_fd_ < 0 || ftruncate(shm_fd_, static_cast<off_t>(kBufferBytes * 2)) != 0) {
    if (shm_fd_ >= 0)
      close(shm_fd_);
    shm_fd_ = -1;
    return false;
  }
  buffer_size_ = kBufferBytes * 2;
  auto *mapped = mmap(nullptr, buffer_size_, PROT_READ | PROT_WRITE, MAP_SHARED, shm_fd_, 0);
  if (mapped == MAP_FAILED) {
    close(shm_fd_);
    shm_fd_ = -1;
    return false;
  }
  auto *pool = wl_shm_create_pool(shm_, shm_fd_, static_cast<int>(buffer_size_));
  if (!pool) {
    munmap(mapped, buffer_size_);
    close(shm_fd_);
    shm_fd_ = -1;
    buffer_size_ = 0;
    return false;
  }
  static const wl_buffer_listener buffer_listener = {buffer_release};
  for (std::size_t index = 0; index < buffers_.size(); ++index) {
    pixels_[index] = static_cast<std::byte *>(mapped) + index * kBufferBytes;
    buffers_[index] = wl_shm_pool_create_buffer(
        pool, static_cast<int>(index * kBufferBytes), kWidth, kHeight, kStride,
        WL_SHM_FORMAT_ARGB8888);
    if (!buffers_[index]) {
      wl_shm_pool_destroy(pool);
      munmap(mapped, buffer_size_);
      close(shm_fd_);
      shm_fd_ = -1;
      buffer_size_ = 0;
      buffers_.fill(nullptr);
      pixels_.fill(nullptr);
      return false;
    }
    buffer_contexts_[index] = {this, index};
    wl_buffer_add_listener(buffers_[index], &buffer_listener,
                           &buffer_contexts_[index]);
  }
  wl_shm_pool_destroy(pool);
  return true;
}

void WaveOverlayWaylandSurface::release_buffer(std::size_t index) {
  if (index < buffer_busy_.size())
    buffer_busy_[index] = false;
}

void WaveOverlayWaylandSurface::draw(const WaveOverlayModel &model) {
  if (!visible_ || !surface_ || !configured_)
    return;
  std::size_t index = next_buffer_++ % buffers_.size();
  if (buffer_busy_[index]) {
    index = (index + 1) % buffers_.size();
    if (buffer_busy_[index])
      return;
  }
  auto *pixels = static_cast<uint32_t *>(pixels_[index]);
  std::fill(pixels, pixels + kWidth * kHeight, 0xE6202124u);
  const auto status_color = model.locked ? 0xFFFFC857u
                           : model.compact_status == WaveOverlayModel::CompactStatus::Processing
                               ? 0xFFFF8A65u
                               : 0xFF73A7FFu;
  for (int y = 12; y < 64; ++y)
    for (int x = 0; x < kWidth; ++x)
      if (y < 16 || y >= 60 || x < 12 || x >= kWidth - 12)
        pixels[y * kWidth + x] = 0xFF30343Bu;
  const auto width = (kWidth - 48) / 12;
  for (std::size_t index_bar = 0; index_bar < model.levels.size(); ++index_bar) {
    const auto height = std::max(4, static_cast<int>(model.levels[index_bar] * 38.0f));
    for (int y = 56 - height / 2; y < 56 + height / 2; ++y)
      for (int x = 0; x < width - 3; ++x)
        pixels[y * kWidth + 24 + static_cast<int>(index_bar) * width + x] = status_color;
  }
  const auto transcript_marker = std::min<std::size_t>(kWidth - 48, model.transcript.size());
  for (std::size_t x = 0; x < transcript_marker; ++x)
    pixels[72 * kWidth + 24 + x] = 0xFF9AA4B2u;
  wl_surface_attach(surface_, buffers_[index], 0, 0);
  wl_surface_damage(surface_, 0, 0, kWidth, kHeight);
  wl_surface_commit(surface_);
  buffer_busy_[index] = true;
  wl_display_flush(display_);
}

bool WaveOverlayWaylandSurface::show(const WaveOverlayModel &model) {
  if (!ensure_surface())
    return false;
  visible_ = true;
  draw(model);
  return true;
}

void WaveOverlayWaylandSurface::update(const WaveOverlayModel &model) {
  if (!display_ || closed_)
    return;
  wl_display_dispatch_pending(display_);
  draw(model);
}

void WaveOverlayWaylandSurface::hide() {
  if (display_ && surface_ && visible_) {
    wl_surface_attach(surface_, nullptr, 0, 0);
    wl_surface_damage(surface_, 0, 0, kWidth, kHeight);
    wl_surface_commit(surface_);
    wl_display_flush(display_);
  }
  visible_ = false;
}

void WaveOverlayWaylandSurface::destroy_surface() {
  if (display_)
    wl_display_roundtrip(display_);
  for (auto *buffer : buffers_)
    if (buffer)
      wl_buffer_destroy(buffer);
  if (pixels_[0] && buffer_size_)
    munmap(pixels_[0], buffer_size_);
  if (shm_fd_ >= 0)
    close(shm_fd_);
  if (layer_surface_)
    zwlr_layer_surface_v1_destroy(layer_surface_);
  if (surface_)
    wl_surface_destroy(surface_);
  if (layer_shell_)
    zwlr_layer_shell_v1_destroy(layer_shell_);
  if (registry_)
    wl_registry_destroy(registry_);
  if (compositor_)
    wl_compositor_destroy(compositor_);
  if (shm_)
    wl_shm_destroy(shm_);
  if (display_)
    wl_display_disconnect(display_);
  display_ = nullptr;
  registry_ = nullptr;
  compositor_ = nullptr;
  shm_ = nullptr;
  layer_shell_ = nullptr;
  surface_ = nullptr;
  layer_surface_ = nullptr;
  buffers_.fill(nullptr);
  pixels_.fill(nullptr);
  buffer_busy_.fill(false);
  shm_fd_ = -1;
  buffer_size_ = 0;
  configured_ = false;
  visible_ = false;
  closed_ = false;
}

}  // namespace msime::linux_host
