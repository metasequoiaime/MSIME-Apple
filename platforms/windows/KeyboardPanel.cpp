#define NOMINMAX
#include <Windows.h>
#include <algorithm>
#include <array>
#include <cwctype>
#include <string>
#include <vector>

namespace {
constexpr wchar_t kClassName[] = L"MSIMEClient.KeyboardPanel";
constexpr wchar_t kTitle[] = L"Touch keyboard";
constexpr size_t kInvalid = static_cast<size_t>(-1);
struct Key { std::wstring normal, shifted; float weight; WORD vk; bool modifier; RECT rect{}; };
struct Panel {
  HWND hwnd = nullptr, target = nullptr;
  std::vector<std::vector<Key>> rows;
  std::vector<Key *> flat;
  bool shift = false, caps = false, ctrl = false, alt = false, win = false;
  RECT close{}; size_t hovered = kInvalid, pressed = kInvalid;
  bool close_hovered = false, close_pressed = false;
  Panel()
      : rows({
            {{L"`", L"~", 1, VK_OEM_3, false}, {L"1", L"!", 1, '1', false},
             {L"2", L"@", 1, '2', false}, {L"3", L"#", 1, '3', false},
             {L"4", L"$", 1, '4', false}, {L"5", L"%", 1, '5', false},
             {L"6", L"^", 1, '6', false}, {L"7", L"&", 1, '7', false},
             {L"8", L"*", 1, '8', false}, {L"9", L"(", 1, '9', false},
             {L"0", L")", 1, '0', false}, {L"-", L"_", 1, VK_OEM_MINUS, false},
             {L"=", L"+", 1, VK_OEM_PLUS, false}, {L"Backspace", L"", 1.9f, VK_BACK, false}},
            {{L"Tab", L"", 1.5f, VK_TAB, false}, {L"q", L"Q", 1, 'Q', false},
             {L"w", L"W", 1, 'W', false}, {L"e", L"E", 1, 'E', false},
             {L"r", L"R", 1, 'R', false}, {L"t", L"T", 1, 'T', false},
             {L"y", L"Y", 1, 'Y', false}, {L"u", L"U", 1, 'U', false},
             {L"i", L"I", 1, 'I', false}, {L"o", L"O", 1, 'O', false},
             {L"p", L"P", 1, 'P', false}, {L"[", L"{", 1, VK_OEM_4, false},
             {L"]", L"}", 1, VK_OEM_6, false}, {L"\\", L"|", 1.4f, VK_OEM_5, false}},
            {{L"Caps Lock", L"", 1.85f, VK_CAPITAL, true}, {L"a", L"A", 1, 'A', false},
             {L"s", L"S", 1, 'S', false}, {L"d", L"D", 1, 'D', false},
             {L"f", L"F", 1, 'F', false}, {L"g", L"G", 1, 'G', false},
             {L"h", L"H", 1, 'H', false}, {L"j", L"J", 1, 'J', false},
             {L"k", L"K", 1, 'K', false}, {L"l", L"L", 1, 'L', false},
             {L";", L":", 1, VK_OEM_1, false}, {L"'", L"\"", 1, VK_OEM_7, false},
             {L"Enter", L"", 2, VK_RETURN, false}},
            {{L"Shift", L"", 2.35f, VK_SHIFT, true}, {L"z", L"Z", 1, 'Z', false},
             {L"x", L"X", 1, 'X', false}, {L"c", L"C", 1, 'C', false},
             {L"v", L"V", 1, 'V', false}, {L"b", L"B", 1, 'B', false},
             {L"n", L"N", 1, 'N', false}, {L"m", L"M", 1, 'M', false},
             {L",", L"<", 1, VK_OEM_COMMA, false}, {L".", L">", 1, VK_OEM_PERIOD, false},
             {L"/", L"?", 1, VK_OEM_2, false}, {L"Shift", L"", 2.15f, VK_SHIFT, true}},
            {{L"Ctrl", L"", 1.25f, VK_CONTROL, true}, {L"Win", L"", 1.25f, VK_LWIN, true},
             {L"Alt", L"", 1.25f, VK_MENU, true}, {L"Space", L" ", 6.7f, VK_SPACE, false},
             {L"Alt", L"", 1.25f, VK_MENU, true}, {L"Win", L"", 1.25f, VK_LWIN, true},
             {L"Del", L"", 1.25f, VK_DELETE, false}, {L"Ctrl", L"", 1.25f, VK_CONTROL, true}}}) {}
  bool inside(const RECT &r, POINT p) const { return p.x >= r.left && p.x <= r.right && p.y >= r.top && p.y <= r.bottom; }
  bool letter(const Key &key) const { return key.normal.size() == 1 && std::iswalpha(key.normal.front()) != 0; }
  bool sticky(const Key &key) const { return !(key.vk == VK_SPACE || key.vk == VK_RETURN || key.vk == VK_TAB || key.vk == VK_BACK || key.vk == VK_DELETE || (key.vk >= '0' && key.vk <= '9')); }
  bool shifted(const Key &key) const { return shift || (letter(key) && caps != shift); }
  bool active(const Key &key) const { if (key.vk == VK_SHIFT) return shift; if (key.vk == VK_CAPITAL) return caps; if (key.vk == VK_CONTROL) return ctrl; if (key.vk == VK_MENU) return alt; if (key.vk == VK_LWIN) return win; return false; }
  void toggle(const Key &key) { if (key.vk == VK_SHIFT) shift = !shift; else if (key.vk == VK_CAPITAL) caps = !caps; else if (key.vk == VK_CONTROL) ctrl = !ctrl; else if (key.vk == VK_MENU) alt = !alt; else if (key.vk == VK_LWIN) win = !win; }
  void layout() {
    RECT bounds{}; GetClientRect(hwnd, &bounds); close = {bounds.right - 34, 3, bounds.right - 6, 25}; flat.clear();
    const float row_height = std::max((static_cast<float>(bounds.bottom) - 51.0f) / 5.0f, 1.0f);
    for (size_t row_index = 0; row_index < rows.size(); ++row_index) {
      float total = 0; for (const auto &key : rows[row_index]) total += key.weight;
      const float available = std::max(static_cast<float>(bounds.right) - 14.0f - 4.0f * (rows[row_index].size() - 1), 1.0f);
      float x = 7;
      for (auto &key : rows[row_index]) { const float width = available * key.weight / total; const LONG top = static_cast<LONG>(28 + row_index * (row_height + 4)); key.rect = {static_cast<LONG>(x), top, static_cast<LONG>(x + width), static_cast<LONG>(top + row_height)}; flat.push_back(&key); x += width + 4; }
    }
  }
  size_t hit(POINT point) const { for (size_t index = 0; index < flat.size(); ++index) if (inside(flat[index]->rect, point)) return index; return kInvalid; }
  void remember_target() { const HWND foreground = GetForegroundWindow(); if (foreground && foreground != hwnd && IsWindow(foreground)) target = foreground; }
  bool can_send() const { const HWND foreground = GetForegroundWindow(); return (foreground && foreground != hwnd && IsWindow(foreground)) || (target && target != hwnd && IsWindow(target)); }
  bool extended(WORD key) const { switch (key) { case VK_DELETE: case VK_LWIN: case VK_RWIN: case VK_RMENU: case VK_RCONTROL: case VK_INSERT: case VK_HOME: case VK_END: case VK_PRIOR: case VK_NEXT: case VK_LEFT: case VK_RIGHT: case VK_UP: case VK_DOWN: case VK_NUMLOCK: case VK_DIVIDE: case VK_APPS: return true; default: return false; } }
  void send(WORD key, bool with_shift, bool use_sticky) {
    if (!key || !can_send()) return;
    std::array<INPUT, 16> inputs{}; size_t count = 0; const ULONG_PTR extra = GetMessageExtraInfo();
    const auto push = [&](WORD virtual_key, DWORD event_flags) { if (count >= inputs.size()) return; INPUT &input = inputs[count++]; input = {}; input.type = INPUT_KEYBOARD; input.ki.wVk = virtual_key; input.ki.wScan = static_cast<WORD>(MapVirtualKeyW(virtual_key, MAPVK_VK_TO_VSC)); input.ki.dwFlags = event_flags; input.ki.dwExtraInfo = extra; };
    const auto flags = [&](WORD virtual_key, bool up) { return (up ? KEYEVENTF_KEYUP : 0) | (extended(virtual_key) ? KEYEVENTF_EXTENDEDKEY : 0); };
    if (use_sticky && ctrl) push(VK_CONTROL, 0); if (use_sticky && alt) push(VK_MENU, 0); if (use_sticky && win) push(VK_LWIN, 0); if (with_shift) push(VK_SHIFT, 0); push(key, flags(key, false)); push(key, flags(key, true)); if (with_shift) push(VK_SHIFT, KEYEVENTF_KEYUP); if (use_sticky && win) push(VK_LWIN, KEYEVENTF_KEYUP | KEYEVENTF_EXTENDEDKEY); if (use_sticky && alt) push(VK_MENU, KEYEVENTF_KEYUP); if (use_sticky && ctrl) push(VK_CONTROL, KEYEVENTF_KEYUP);
    if (count) SendInput(static_cast<UINT>(count), inputs.data(), sizeof(INPUT));
  }
  void activate(size_t index) { if (index >= flat.size() || !can_send()) return; Key &key = *flat[index]; if (key.modifier) { toggle(key); return; } const bool use_sticky = sticky(key); send(key.vk, shifted(key) && use_sticky, use_sticky); if (shift) shift = false; }
  void paint() {
    PAINTSTRUCT paint{}; HDC dc = BeginPaint(hwnd, &paint); RECT bounds{}; GetClientRect(hwnd, &bounds); HBRUSH background = CreateSolidBrush(RGB(23, 24, 29)); FillRect(dc, &bounds, background); DeleteObject(background); SetBkMode(dc, TRANSPARENT); HFONT font = CreateFontW(-14, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_SWISS, L"Segoe UI"); HGDIOBJ old_font = SelectObject(dc, font); SetTextColor(dc, RGB(215, 216, 221)); RECT title{10, 0, 210, 28}; DrawTextW(dc, kTitle, -1, &title, DT_SINGLELINE | DT_VCENTER | DT_LEFT); HBRUSH close_brush = CreateSolidBrush(close_hovered || close_pressed ? RGB(65, 67, 77) : RGB(23, 24, 29)); FillRect(dc, &close, close_brush); DeleteObject(close_brush); HPEN close_pen = CreatePen(PS_SOLID, 2, RGB(241, 241, 243)); HGDIOBJ old_pen = SelectObject(dc, close_pen); const int cx = (close.left + close.right) / 2, cy = (close.top + close.bottom) / 2; MoveToEx(dc, cx - 6, cy - 6, nullptr); LineTo(dc, cx + 6, cy + 6); MoveToEx(dc, cx + 6, cy - 6, nullptr); LineTo(dc, cx - 6, cy + 6); SelectObject(dc, old_pen); DeleteObject(close_pen);
    for (size_t index = 0; index < flat.size(); ++index) { Key &key = *flat[index]; const COLORREF color = index == pressed ? RGB(102, 106, 119) : (active(key) ? RGB(83, 88, 102) : (index == hovered ? RGB(65, 67, 77) : RGB(43, 45, 52))); HBRUSH brush = CreateSolidBrush(color); HPEN pen = CreatePen(PS_SOLID, 1, RGB(59, 61, 69)); HGDIOBJ old_brush = SelectObject(dc, brush); old_pen = SelectObject(dc, pen); RoundRect(dc, key.rect.left, key.rect.top, key.rect.right, key.rect.bottom, 10, 10); SelectObject(dc, old_pen); SelectObject(dc, old_brush); DeleteObject(pen); DeleteObject(brush); std::wstring label = key.normal; if (key.normal.size() == 1 && shifted(key) && !key.shifted.empty()) label = key.shifted; RECT text = key.rect; SetTextColor(dc, key.normal.size() == 1 ? RGB(241, 241, 243) : RGB(198, 199, 207)); DrawTextW(dc, label.c_str(), static_cast<int>(label.size()), &text, DT_SINGLELINE | DT_CENTER | DT_VCENTER | DT_NOPREFIX); }
    SelectObject(dc, old_font); DeleteObject(font); EndPaint(hwnd, &paint);
  }
};
Panel *panel_for(HWND hwnd) { return reinterpret_cast<Panel *>(GetWindowLongPtrW(hwnd, GWLP_USERDATA)); }
LRESULT CALLBACK window_proc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_NCCREATE) { const auto *create = reinterpret_cast<const CREATESTRUCTW *>(lparam); SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(create->lpCreateParams)); }
  Panel *panel = panel_for(hwnd);
  switch (message) {
  case WM_CREATE: panel->hwnd = hwnd; panel->layout(); return 0;
  case WM_MOUSEACTIVATE: return MA_NOACTIVATE;
  case WM_ERASEBKGND: return 1;
  case WM_SIZE: if (panel) panel->layout(); return 0;
  case WM_MOUSEMOVE: if (panel) { POINT point{static_cast<short>(LOWORD(lparam)), static_cast<short>(HIWORD(lparam))}; panel->close_hovered = panel->inside(panel->close, point); panel->hovered = panel->close_hovered ? kInvalid : panel->hit(point); InvalidateRect(hwnd, nullptr, FALSE); } return 0;
  case WM_LBUTTONDOWN: if (panel) { panel->remember_target(); POINT point{static_cast<short>(LOWORD(lparam)), static_cast<short>(HIWORD(lparam))}; panel->close_pressed = panel->inside(panel->close, point); panel->pressed = panel->close_pressed ? kInvalid : panel->hit(point); SetCapture(hwnd); InvalidateRect(hwnd, nullptr, FALSE); } return 0;
  case WM_LBUTTONUP: if (panel) { POINT point{static_cast<short>(LOWORD(lparam)), static_cast<short>(HIWORD(lparam))}; const bool close = panel->close_pressed && panel->inside(panel->close, point); const size_t hit = panel->hit(point); if (panel->pressed != kInvalid && panel->pressed == hit) panel->activate(hit); panel->pressed = kInvalid; panel->close_pressed = false; if (GetCapture() == hwnd) ReleaseCapture(); InvalidateRect(hwnd, nullptr, FALSE); if (close) DestroyWindow(hwnd); } return 0;
  case WM_PAINT: if (panel) panel->paint(); return 0;
  case WM_DESTROY: PostQuitMessage(0); return 0;
  default: return DefWindowProcW(hwnd, message, wparam, lparam);
  }
}
} // namespace
int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR command_line, int show_command) {
  if (command_line && std::wstring(command_line) == L"--help") return 0;
  HANDLE mutex = CreateMutexW(nullptr, FALSE, L"Local\\MSIMEClientKeyboardPanel.SingleInstance"); if (!mutex || GetLastError() == ERROR_ALREADY_EXISTS) { if (mutex) CloseHandle(mutex); return 0; }
  WNDCLASSEXW window_class{}; window_class.cbSize = sizeof(window_class); window_class.hInstance = instance; window_class.lpfnWndProc = window_proc; window_class.lpszClassName = kClassName; window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW); if (!RegisterClassExW(&window_class)) { CloseHandle(mutex); return 1; }
  RECT work_area{}; SystemParametersInfoW(SPI_GETWORKAREA, 0, &work_area, 0); constexpr int width = 1100, height = 400; const int x = work_area.left + std::max(0, (work_area.right - work_area.left - width) / 2); const int y = std::max(work_area.top, work_area.bottom - height - 12); Panel state; HWND window = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_TOPMOST, kClassName, kTitle, WS_POPUP, x, y, width, height, nullptr, nullptr, instance, &state); if (!window) { UnregisterClassW(kClassName, instance); CloseHandle(mutex); return 1; }
  ShowWindow(window, show_command == SW_HIDE ? SW_SHOWNOACTIVATE : SW_SHOWNOACTIVATE); UpdateWindow(window); MSG message{}; while (GetMessageW(&message, nullptr, 0, 0) > 0) { TranslateMessage(&message); DispatchMessageW(&message); } UnregisterClassW(kClassName, instance); CloseHandle(mutex); return static_cast<int>(message.wParam);
}
