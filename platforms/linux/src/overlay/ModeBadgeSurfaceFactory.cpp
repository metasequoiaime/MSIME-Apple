#include "ModeBadgeSurface.h"

#ifdef MSIME_BADGE_HAS_WAYLAND
#include "ModeBadgeWaylandSurface.h"
#endif
#ifdef MSIME_BADGE_HAS_X11
#include "ModeBadgeX11Surface.h"
#endif

namespace msime::linux_host {

// 先 Wayland 后 X11：会话类型由环境变量决定，两个后端各自在环境不对时返回空指针，
// 所以这里只是依次试，不需要另外判断当前是哪种会话。
std::unique_ptr<ModeBadgeSurface> ModeBadgeSurface::create() {
#ifdef MSIME_BADGE_HAS_WAYLAND
  if (auto wayland = ModeBadgeWaylandSurface::create()) return wayland;
#endif
#ifdef MSIME_BADGE_HAS_X11
  if (auto x11 = ModeBadgeX11Surface::create()) return x11;
#endif
  return nullptr;
}

}  // namespace msime::linux_host
