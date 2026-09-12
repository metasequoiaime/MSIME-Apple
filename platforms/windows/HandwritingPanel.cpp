#define NOMINMAX
// Windows.h first: its DrawText macro has to reach the Direct2D declarations.
#include <Windows.h>
#include "CandidatePalette.h"
#include <algorithm>
#include <msimeui/DeviceResources.h>
#include <cmath>
#include <cwctype>
#include <cstring>
#include <string>
#include <thread>
#include <vector>

#if defined(MSIME_ENABLE_WINDOWS_INK)
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Foundation.Numerics.h>
#include <winrt/Windows.UI.Input.Inking.h>
#endif

namespace {
constexpr wchar_t kClassName[] = L"MSIMEClient.HandwritingPanel";
constexpr wchar_t kTitle[] = L"水杉手写识别板";
constexpr size_t kInvalid = static_cast<size_t>(-1);
struct Point { float x; float y; };
struct Panel {
  HWND hwnd = nullptr; std::vector<std::vector<Point>> strokes; std::vector<std::wstring> candidates;
  std::wstring hint = L"请在左侧书写，松开鼠标后自动识别"; RECT close{}, canvas{}, results{}, undo{}, clear{};
  // Direct2D through the shared UI stack, with the candidate card's tokens.
  msimeui::DeviceResources device;
  msime::windows::CandidatePalette palette;
  std::vector<RECT> candidate_rects; bool drawing = false, close_hovered = false, close_pressed = false;
  size_t hovered_candidate = kInvalid, pressed_candidate = kInvalid;
  static bool contains(const RECT &r, POINT p) { return p.x >= r.left && p.x < r.right && p.y >= r.top && p.y < r.bottom; }
  void layout() {
    RECT b{}; GetClientRect(hwnd, &b); const LONG width = std::max<LONG>(1, b.right), height = std::max<LONG>(1, b.bottom);
    constexpr LONG pad = 24, gap = 28; const LONG content = std::max<LONG>(1, width - pad * 2), top = 58;
    const LONG left = std::max<LONG>(1, static_cast<LONG>(content * 0.43f)); const LONG side = std::max<LONG>(1, std::min(left, height - top - 100));
    const LONG right = std::max<LONG>(1, content - left - gap); close = {width - 38, 7, width - 8, 31};
    canvas = {pad, top, pad + side, top + side}; results = {canvas.right + gap, top, canvas.right + gap + right, height - pad};
    undo = {canvas.left, canvas.bottom + 18, canvas.left + 112, canvas.bottom + 60}; clear = {undo.right + 12, undo.top, undo.right + 124, undo.bottom};
    candidate_rects.clear(); constexpr LONG cell_gap = 8; const LONG cell_width = std::max<LONG>(1, (results.right - results.left - cell_gap * 3) / 4); const LONG grid_top = results.top + 42;
    const LONG cell_height = std::max<LONG>(1, std::min(cell_width, (results.bottom - grid_top - 58 - cell_gap * 2) / 3));
    for (size_t i = 0; i < 12; ++i) { const LONG column = static_cast<LONG>(i % 4), row = static_cast<LONG>(i / 4); const LONG x = results.left + column * (cell_width + cell_gap), y = grid_top + row * (cell_height + cell_gap); candidate_rects.push_back({x, y, x + cell_width, y + cell_height}); }
  }
  size_t hit_candidate(POINT p) const { for (size_t i = 0; i < candidate_rects.size() && i < candidates.size(); ++i) if (contains(candidate_rects[i], p)) return i; return kInvalid; }
  void invalidate() const { InvalidateRect(hwnd, nullptr, FALSE); }
  void recognize();
  void clear_strokes() { strokes.clear(); candidates.clear(); hint = L"已清空，请重新书写"; invalidate(); }
  void copy_candidate(size_t i) {
    if (i >= candidates.size() || !OpenClipboard(hwnd)) { hint = L"无法打开剪贴板"; invalidate(); return; }
    EmptyClipboard(); const SIZE_T bytes = (candidates[i].size() + 1) * sizeof(wchar_t); HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, bytes);
    if (memory) { void *destination = GlobalLock(memory); if (destination) { std::memcpy(destination, candidates[i].c_str(), bytes); GlobalUnlock(memory); if (SetClipboardData(CF_UNICODETEXT, memory)) memory = nullptr; } if (memory) GlobalFree(memory); }
    CloseClipboard(); hint = L"已复制：" + candidates[i]; invalidate();
  }
  void paint() {
    PAINTSTRUCT ps{};
    const HDC dc = BeginPaint(hwnd, &ps);
    struct End {
      HWND window;
      PAINTSTRUCT &state;
      ~End() { EndPaint(window, &state); }
    } end{hwnd, ps};
    if (!dc || !device.EnsureForWindow(hwnd))
      return;
    auto *target = device.GetRenderTarget();
    if (!target)
      return;
    using msime::windows::CandidateColor;
    auto brush = [&](const CandidateColor &color) {
      return device.GetSolidColorBrush(
          D2D1::ColorF(color.r, color.g, color.b, color.a));
    };
    auto format = [&](DWRITE_TEXT_ALIGNMENT alignment) {
      return device.GetTextFormat(L"Segoe UI", 16.0f, DWRITE_FONT_WEIGHT_NORMAL,
                                  alignment, DWRITE_PARAGRAPH_ALIGNMENT_CENTER,
                                  DWRITE_WORD_WRAPPING_NO_WRAP);
    };
    auto *leading = format(DWRITE_TEXT_ALIGNMENT_LEADING);
    auto *centered = format(DWRITE_TEXT_ALIGNMENT_CENTER);
    auto *surface = brush(palette.surface);
    auto *border = brush(palette.border);
    auto *text_brush = brush(palette.text);
    auto *muted = brush(palette.number);
    auto *hover = brush(palette.hover);
    auto *accent = brush(palette.accent);
    if (!leading || !centered || !surface || !border || !text_brush || !muted ||
        !hover || !accent)
      return;
    auto rect_of = [](const RECT &value) {
      return D2D1_RECT_F{static_cast<float>(value.left),
                         static_cast<float>(value.top),
                         static_cast<float>(value.right),
                         static_cast<float>(value.bottom)};
    };
    auto write = [&](const wchar_t *value, D2D1_RECT_F where,
                     ID2D1SolidColorBrush *color, IDWriteTextFormat *with) {
      target->DrawText(value, static_cast<UINT32>(wcslen(value)), with, where,
                       color);
    };
    target->BeginDraw();
    target->Clear(D2D1::ColorF(palette.surface.r, palette.surface.g,
                               palette.surface.b, palette.surface.a));
    write(kTitle, D2D1_RECT_F{14.0f, 0.0f, 250.0f, 38.0f}, text_brush, leading);
    if (close_hovered || close_pressed)
      target->FillRectangle(rect_of(close), hover);
    const float cx = static_cast<float>(close.left + close.right) / 2.0f;
    const float cy = static_cast<float>(close.top + close.bottom) / 2.0f;
    target->DrawLine({cx - 6.0f, cy - 6.0f}, {cx + 6.0f, cy + 6.0f}, text_brush,
                     2.0f);
    target->DrawLine({cx + 6.0f, cy - 6.0f}, {cx - 6.0f, cy + 6.0f}, text_brush,
                     2.0f);
    const D2D1_ROUNDED_RECT board{rect_of(canvas), 12.0f, 12.0f};
    target->FillRoundedRectangle(board, hover);
    target->DrawRoundedRectangle(board, border, 1.0f);
    // Ink is drawn as segments; the stroke points are already in client space.
    for (const auto &stroke : strokes)
      for (size_t i = 1; i < stroke.size(); ++i)
        target->DrawLine({static_cast<float>(stroke[i - 1].x),
                          static_cast<float>(stroke[i - 1].y)},
                         {static_cast<float>(stroke[i].x),
                          static_cast<float>(stroke[i].y)},
                         text_brush, 4.0f);
    write(L"\u8bc6\u522b\u7ed3\u679c",
          D2D1_RECT_F{static_cast<float>(results.left),
                      static_cast<float>(results.top),
                      static_cast<float>(results.right),
                      static_cast<float>(results.top + 30)},
          text_brush, leading);
    for (size_t i = 0; i < candidate_rects.size(); ++i) {
      const bool selected = i == hovered_candidate;
      const D2D1_ROUNDED_RECT cell{rect_of(candidate_rects[i]), 10.0f, 10.0f};
      target->FillRoundedRectangle(cell, selected ? hover : surface);
      target->DrawRoundedRectangle(cell, selected ? accent : border,
                                   selected ? 2.0f : 1.0f);
      if (i < candidates.size())
        target->DrawText(candidates[i].c_str(),
                         static_cast<UINT32>(candidates[i].size()), centered,
                         cell.rect, text_brush);
    }
    target->DrawText(hint.c_str(), static_cast<UINT32>(hint.size()), leading,
                     D2D1_RECT_F{static_cast<float>(results.left),
                                 static_cast<float>(results.bottom - 38),
                                 static_cast<float>(results.right),
                                 static_cast<float>(results.bottom - 8)},
                     muted);
    auto button = [&](const RECT &value, const wchar_t *label) {
      const D2D1_ROUNDED_RECT shape{rect_of(value), 10.0f, 10.0f};
      target->FillRoundedRectangle(shape, surface);
      target->DrawRoundedRectangle(shape, border, 1.0f);
      write(label, shape.rect, text_brush, centered);
    };
    button(undo, L"\u21b6 \u64a4\u9500");
    button(clear, L"\u00d7 \u91cd\u5199");
    if (target->EndDraw() == D2DERR_RECREATE_TARGET)
      device.DiscardTarget();
  }
};

void Panel::recognize() {
  candidates.clear(); if(strokes.empty()){hint=L"请在左侧书写，松开鼠标后自动识别";invalidate();return;}
#if defined(MSIME_ENABLE_WINDOWS_INK)
  const auto input=strokes; const float ox=static_cast<float>(canvas.left), oy=static_cast<float>(canvas.top); std::wstring error;
  std::thread worker([&]{try{winrt::init_apartment(winrt::apartment_type::multi_threaded);using namespace winrt::Windows::Foundation;using namespace winrt::Windows::Foundation::Numerics;using namespace winrt::Windows::UI::Input::Inking;InkRecognizerContainer container;bool chinese=false;for(const auto &r:container.GetRecognizers()){std::wstring name(r.Name().c_str(),r.Name().size());std::transform(name.begin(),name.end(),name.begin(),[](wchar_t v){return std::towlower(v);});if(name.find(L"中文")!=std::wstring::npos||name.find(L"简体")!=std::wstring::npos||name.find(L"chinese")!=std::wstring::npos||name.find(L"zh-cn")!=std::wstring::npos){container.SetDefaultRecognizer(r);chinese=true;break;}}if(!chinese){error=L"未找到简体中文手写识别器";return;}InkStrokeContainer strokes_container;InkStrokeBuilder builder;for(const auto &source:input){auto points=winrt::single_threaded_vector<InkPoint>();for(const auto &p:source)points.Append(InkPoint({p.x-ox,p.y-oy},0.5f));const float3x2 identity={1.0f,0.0f,0.0f,1.0f,0.0f,0.0f};strokes_container.AddStroke(builder.CreateStrokeFromInkPoints(points,identity));}std::vector<std::wstring> cjk,other;const auto results=container.RecognizeAsync(strokes_container,InkRecognitionTarget::All).get();for(const auto &result:results)for(const auto &candidate:result.GetTextCandidates()){std::wstring value(candidate.c_str(),candidate.size());const bool is_cjk=std::any_of(value.begin(),value.end(),[](wchar_t ch){return(ch>=0x3400&&ch<=0x4DBF)||(ch>=0x4E00&&ch<=0x9FFF)||(ch>=0xF900&&ch<=0xFAFF);});auto &bucket=is_cjk?cjk:other;if(!value.empty()&&bucket.size()<12&&std::find(bucket.begin(),bucket.end(),value)==bucket.end())bucket.push_back(std::move(value));}for(const auto &v:cjk)if(candidates.size()<12)candidates.push_back(v);for(const auto &v:other)if(candidates.size()<12)candidates.push_back(v);}catch(const winrt::hresult_error &e){error.assign(e.message().c_str(),e.message().size());}});worker.join();hint=!error.empty()?L"Windows Ink 识别失败："+error:candidates.empty()?L"未识别到内容，请确认已安装中文手写包":L"点击候选结果即可复制";
#else
  hint=L"Windows Ink 识别运行库未随当前交叉构建环境提供";
#endif
  invalidate();
}

Panel *panel_for(HWND hwnd){return reinterpret_cast<Panel*>(GetWindowLongPtrW(hwnd,GWLP_USERDATA));}
LRESULT CALLBACK window_proc(HWND hwnd,UINT message,WPARAM,LPARAM lparam){
  if(message==WM_NCCREATE){const auto *create=reinterpret_cast<const CREATESTRUCTW*>(lparam);SetWindowLongPtrW(hwnd,GWLP_USERDATA,reinterpret_cast<LONG_PTR>(create->lpCreateParams));} Panel *panel=panel_for(hwnd);
  switch(message){case WM_CREATE:panel->hwnd=hwnd;panel->layout();return 0;case WM_MOUSEACTIVATE:return MA_NOACTIVATE;case WM_ERASEBKGND:return 1;case WM_SIZE:if(panel)panel->layout();return 0;
  case WM_MOUSEMOVE:if(panel){TRACKMOUSEEVENT tracking{sizeof(TRACKMOUSEEVENT),TME_LEAVE,hwnd,0};TrackMouseEvent(&tracking);const POINT p{static_cast<short>(LOWORD(lparam)),static_cast<short>(HIWORD(lparam))};panel->close_hovered=Panel::contains(panel->close,p);panel->hovered_candidate=panel->close_hovered?kInvalid:panel->hit_candidate(p);if(panel->drawing&&!panel->strokes.empty()){const Point clipped{std::clamp(static_cast<float>(p.x),static_cast<float>(panel->canvas.left),static_cast<float>(panel->canvas.right-1)),std::clamp(static_cast<float>(p.y),static_cast<float>(panel->canvas.top),static_cast<float>(panel->canvas.bottom-1))};const Point last=panel->strokes.back().back();if(std::abs(clipped.x-last.x)+std::abs(clipped.y-last.y)>=0.5f)panel->strokes.back().push_back(clipped);}panel->invalidate();}return 0;
  case WM_MOUSELEAVE:if(panel){panel->close_hovered=false;panel->hovered_candidate=kInvalid;panel->invalidate();}return 0;
  case WM_LBUTTONDOWN:if(panel){const POINT p{static_cast<short>(LOWORD(lparam)),static_cast<short>(HIWORD(lparam))};panel->close_pressed=Panel::contains(panel->close,p);panel->pressed_candidate=panel->close_pressed?kInvalid:panel->hit_candidate(p);if(!panel->close_pressed&&Panel::contains(panel->canvas,p)){panel->drawing=true;panel->strokes.push_back({{static_cast<float>(p.x),static_cast<float>(p.y)}});}SetCapture(hwnd);panel->invalidate();}return 0;
  case WM_LBUTTONUP:if(panel){const POINT p{static_cast<short>(LOWORD(lparam)),static_cast<short>(HIWORD(lparam))};const bool close=panel->close_pressed&&Panel::contains(panel->close,p);panel->close_pressed=false;if(panel->drawing){panel->drawing=false;if(!panel->strokes.empty()&&panel->strokes.back().size()<2)panel->strokes.pop_back();panel->recognize();}else if(!close&&panel->pressed_candidate!=kInvalid&&panel->pressed_candidate==panel->hit_candidate(p))panel->copy_candidate(panel->pressed_candidate);else if(!close&&Panel::contains(panel->undo,p)){if(!panel->strokes.empty())panel->strokes.pop_back();panel->recognize();}else if(!close&&Panel::contains(panel->clear,p))panel->clear_strokes();panel->pressed_candidate=kInvalid;if(GetCapture()==hwnd)ReleaseCapture();panel->invalidate();if(close)DestroyWindow(hwnd);}return 0;
  case WM_PAINT:if(panel)panel->paint();return 0;case WM_SETCURSOR:if(panel&&LOWORD(lparam)==HTCLIENT){SetCursor(LoadCursorW(nullptr,panel->drawing?MAKEINTRESOURCEW(32515):MAKEINTRESOURCEW(32649)));return TRUE;}break;case WM_DESTROY:PostQuitMessage(0);return 0;default:break;}return DefWindowProcW(hwnd,message,0,lparam);
}
} // namespace
int WINAPI wWinMain(HINSTANCE instance,HINSTANCE,PWSTR command_line,int show_command){if(command_line&&std::wstring(command_line)==L"--help")return 0;
// Direct2D's imaging factory is a COM server; --help answers first so the
// smoke runner never needs an apartment.
const HRESULT entered=CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED|COINIT_DISABLE_OLE1DDE);
if(FAILED(entered)&&entered!=RPC_E_CHANGED_MODE)return 1;
struct Apartment{bool owned;~Apartment(){if(owned)CoUninitialize();}}apartment{entered!=RPC_E_CHANGED_MODE};
HANDLE mutex=CreateMutexW(nullptr,FALSE,L"Local\\MSIMEClientHandwritingPanel.SingleInstance");if(!mutex||GetLastError()==ERROR_ALREADY_EXISTS){if(mutex)CloseHandle(mutex);return 0;}WNDCLASSEXW wc{};wc.cbSize=sizeof(wc);wc.hInstance=instance;wc.lpfnWndProc=window_proc;wc.lpszClassName=kClassName;wc.hCursor=LoadCursorW(nullptr,MAKEINTRESOURCEW(32512));if(!RegisterClassExW(&wc)){CloseHandle(mutex);return 1;}RECT work{};SystemParametersInfoW(SPI_GETWORKAREA,0,&work,0);constexpr int width=980,height=650;const int x=work.left+static_cast<int>(std::max<LONG>(0,(work.right-work.left-width)/2));const int y=std::max<LONG>(work.top,work.bottom-height-12);Panel state;HWND window=CreateWindowExW(WS_EX_TOOLWINDOW|WS_EX_NOACTIVATE|WS_EX_TOPMOST,kClassName,kTitle,WS_POPUP,x,y,width,height,nullptr,nullptr,instance,&state);if(!window){UnregisterClassW(kClassName,instance);CloseHandle(mutex);return 1;}ShowWindow(window,show_command==SW_HIDE?SW_SHOWNOACTIVATE:SW_SHOWNOACTIVATE);UpdateWindow(window);MSG message{};while(GetMessageW(&message,nullptr,0,0)>0){TranslateMessage(&message);DispatchMessageW(&message);}UnregisterClassW(kClassName,instance);CloseHandle(mutex);return static_cast<int>(message.wParam);}
