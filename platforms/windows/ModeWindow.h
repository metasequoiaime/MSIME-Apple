#pragma once
#include "CandidateClickWorker.h"
#include "CandidatePalette.h"
#include "ModeLayout.h"
#include "ModeMailbox.h"
#include "ReplyCodec.h"
// windows.h first: its DrawText macro has to reach the Direct2D declarations.
#include <windows.h>
#include <msimeui/DeviceResources.h>

namespace msime::windows {
struct ModeClick {
  FocusLease lease;
  WorkerMode mode;
};
using ModeClickWorker = SingleClickWorker<ModeClick>;
// UI-thread owned, explicit commands rather than optimistic state toggles.
class ModeWindow final {
public:
  using Reader = std::function<std::optional<ModePresentation>()>;
  using Click = std::function<void(const ModeClick &)>;
  ModeWindow(Reader reader, Click click);
  ~ModeWindow();
  ModeWindow(const ModeWindow &) = delete;
  ModeWindow &operator=(const ModeWindow &) = delete;
  void refresh();
  // Share the candidate card's resolved tokens so one skin theme covers both.
  void set_palette(CandidatePalette palette);
  void hide();
  bool failed() const { return failed_; }
  HWND handle() const { return window_; }

private:
  static LRESULT CALLBACK procedure(HWND, UINT, WPARAM, LPARAM) noexcept;
  void paint();
  // Direct2D's imaging factory is a COM server; this thread owns an apartment.
  struct Apartment {
    Apartment();
    ~Apartment();
    Apartment(const Apartment &) = delete;
    Apartment &operator=(const Apartment &) = delete;
    bool owned = false;
  } apartment_;
  msimeui::DeviceResources device_;
  CandidatePalette palette_;
  std::optional<ModeClick> hit(int x, int y);
  Reader reader_;
  Click click_;
  HWND window_ = nullptr;
  std::optional<ModePresentation> shown_, painted_;
  std::optional<ModeClick> pressed_;
  unsigned dpi_ = 0;
  std::optional<ModeLayout> layout_;
  HMONITOR monitor_ = nullptr;
  bool failed_ = false;
};
} // namespace msime::windows
