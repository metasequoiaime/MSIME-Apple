#define NOMINMAX
#include <Windows.h>
#include "CandidatePalette.h"
#include <msimeui/DeviceResources.h>
#include <shellapi.h>
#include <sqlite3.h>

#include <algorithm>
#include <cwctype>
#include <cstring>
#include <filesystem>
#include <iterator>
#include <string>
#include <vector>

namespace {
constexpr wchar_t kClassName[] = L"MSIMEClient.EmojiPanel";
constexpr wchar_t kTitle[] = L"Emoji and more";
constexpr size_t kInvalid = static_cast<size_t>(-1);
constexpr int kHeaderHeight = 38;
constexpr int kSearchTop = 50;
constexpr int kSearchHeight = 32;
constexpr int kTabsTop = 94;
constexpr int kTabsHeight = 48;
constexpr int kSubTabsTop = 145;
constexpr int kContentTop = 190;
constexpr int kCellHeight = 70;
constexpr int kGroupTitleHeight = 34;
constexpr int kGridLeft = 18;
constexpr int kGridRight = 18;
constexpr int kGap = 6;

enum class Page : size_t { Home, Emoji, Sticker, Gif, Kaomoji, Symbols, Clipboard };

struct Item {
  std::wstring text;
  std::wstring keywords;
};

struct Group {
  std::wstring title;
  std::wstring icon;
  std::vector<Item> items;
};

struct VisibleGroup {
  std::wstring title;
  std::wstring icon;
  std::vector<const Item *> items;
};

std::wstring utf8_to_wide(const unsigned char *value) {
  if (!value || !*value) return {};
  const char *text = reinterpret_cast<const char *>(value);
  const int length = MultiByteToWideChar(CP_UTF8, 0, text, -1, nullptr, 0);
  if (length <= 1) return {};
  std::wstring result(static_cast<size_t>(length - 1), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text, -1, result.data(), length);
  return result;
}

std::wstring lower(std::wstring value) {
  std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) { return static_cast<wchar_t>(towlower(ch)); });
  return value;
}

bool contains(const RECT &rect, POINT point) {
  return point.x >= rect.left && point.x < rect.right && point.y >= rect.top && point.y < rect.bottom;
}

bool copy_to_clipboard(HWND owner, const std::wstring &text) {
  if (!OpenClipboard(owner)) return false;
  EmptyClipboard();
  const SIZE_T bytes = (text.size() + 1) * sizeof(wchar_t);
  HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, bytes);
  if (!memory) {
    CloseClipboard();
    return false;
  }
  void *destination = GlobalLock(memory);
  if (!destination) {
    GlobalFree(memory);
    CloseClipboard();
    return false;
  }
  memcpy(destination, text.c_str(), bytes);
  GlobalUnlock(memory);
  if (!SetClipboardData(CF_UNICODETEXT, memory)) {
    GlobalFree(memory);
    CloseClipboard();
    return false;
  }
  CloseClipboard();
  return true;
}

class Panel {
 public:
  HWND hwnd = nullptr;
  HWND search = nullptr;
  HBRUSH search_brush = nullptr;
  HFONT search_font = nullptr;
  Page page = Page::Home;
  size_t category = 0;
  size_t hovered_item = kInvalid;
  size_t pressed_item = kInvalid;
  size_t pressed_tab = kInvalid;
  size_t pressed_category = kInvalid;
  bool close_hovered = false;
  bool close_pressed = false;
  bool back_hovered = false;
  bool back_pressed = false;
  int scroll = 0;
  std::wstring search_text;
  std::wstring notice = L"Click an item to copy";
  // Direct2D through the shared UI stack, with the candidate card tokens.
  msimeui::DeviceResources device;
  msime::windows::CandidatePalette palette;
  std::vector<Group> emoji;
  std::vector<Group> kaomoji;
  std::vector<Group> symbols;
  std::vector<Item> recent;

  ~Panel() {
    if (search_brush) DeleteObject(search_brush);
    if (search_font) DeleteObject(search_font);
  }

  void layout() {
    RECT bounds{};
    GetClientRect(hwnd, &bounds);
    if (search) MoveWindow(search, 18, kSearchTop, std::max<LONG>(bounds.right - 72, 120), kSearchHeight, TRUE);
  }

  Group *find_group(std::vector<Group> &groups, const std::wstring &title, const std::wstring &icon) {
    if (!groups.empty() && groups.back().title == title) return &groups.back();
    groups.push_back({title, icon, {}});
    return &groups.back();
  }

  void load(const std::filesystem::path &database) {
    if (database.empty() || !std::filesystem::exists(database)) {
      notice = L"Emoji database not found";
      return;
    }
    sqlite3 *db = nullptr;
    const std::string path = database.u8string();
    if (sqlite3_open(path.c_str(), &db) != SQLITE_OK) {
      if (db) sqlite3_close(db);
      notice = L"Emoji database unavailable";
      return;
    }
    sqlite3_busy_timeout(db, 3000);
    load_emoji(db);
    load_kaomoji(db);
    load_symbols(db);
    sqlite3_close(db);
    if (!emoji.empty() || !kaomoji.empty() || !symbols.empty()) notice = L"Click an item to copy";
  }

  void load_emoji(sqlite3 *db) {
    sqlite3_stmt *statement = nullptr;
    constexpr char sql[] = "SELECT emoji, category, keywords FROM emoji ORDER BY sort_order";
    if (sqlite3_prepare_v2(db, sql, -1, &statement, nullptr) != SQLITE_OK) return;
    while (sqlite3_step(statement) == SQLITE_ROW) {
      const std::wstring text = utf8_to_wide(sqlite3_column_text(statement, 0));
      const std::wstring group = utf8_to_wide(sqlite3_column_text(statement, 1));
      const std::wstring keywords = utf8_to_wide(sqlite3_column_text(statement, 2));
      if (text.empty() || group.empty()) continue;
      find_group(emoji, group, L"😀")->items.push_back({text, keywords.empty() ? text : keywords});
    }
    sqlite3_finalize(statement);
  }

  void load_kaomoji(sqlite3 *db) {
    sqlite3_stmt *statement = nullptr;
    constexpr char sql[] = "SELECT kaomoji, keywords FROM kaomoji_catalog ORDER BY sort_order";
    if (sqlite3_prepare_v2(db, sql, -1, &statement, nullptr) != SQLITE_OK) return;
    Group *group = find_group(kaomoji, L"All", L";-)");
    while (sqlite3_step(statement) == SQLITE_ROW) {
      const std::wstring text = utf8_to_wide(sqlite3_column_text(statement, 0));
      const std::wstring keywords = utf8_to_wide(sqlite3_column_text(statement, 1));
      if (!text.empty()) group->items.push_back({text, keywords.empty() ? text : keywords});
    }
    sqlite3_finalize(statement);
    if (group->items.empty()) kaomoji.clear();
  }

  void load_symbols(sqlite3 *db) {
    sqlite3_stmt *statement = nullptr;
    constexpr char sql[] = "SELECT symbol, category, parent_category, keywords FROM symbol_catalog ORDER BY sort_order";
    if (sqlite3_prepare_v2(db, sql, -1, &statement, nullptr) != SQLITE_OK) return;
    while (sqlite3_step(statement) == SQLITE_ROW) {
      const std::wstring text = utf8_to_wide(sqlite3_column_text(statement, 0));
      const std::wstring group = utf8_to_wide(sqlite3_column_text(statement, 1));
      const std::wstring parent = utf8_to_wide(sqlite3_column_text(statement, 2));
      const std::wstring keywords = utf8_to_wide(sqlite3_column_text(statement, 3));
      if (text.empty() || group.empty()) continue;
      const std::wstring icon = text.substr(0, std::min<size_t>(text.size(), 2));
      (void)parent;
      find_group(symbols, group, icon)->items.push_back({text, keywords.empty() ? group : keywords});
    }
    sqlite3_finalize(statement);
  }

  bool matches(const Item &item) const {
    if (search_text.empty()) return true;
    const std::wstring query = lower(search_text);
    return lower(item.text + L" " + item.keywords).find(query) != std::wstring::npos;
  }

  std::vector<VisibleGroup> visible_groups() const {
    const auto add = [this](std::vector<VisibleGroup> &result, const Group &group, size_t limit) {
      VisibleGroup visible{group.title, group.icon, {}};
      for (const Item &item : group.items) {
        if (matches(item) && (limit == 0 || visible.items.size() < limit)) visible.items.push_back(&item);
      }
      if (!visible.items.empty()) result.push_back(std::move(visible));
    };
    std::vector<VisibleGroup> result;
    if (page == Page::Home) {
      if (!recent.empty()) {
        VisibleGroup recent_group{L"Recently used", L"◷", {}};
        for (const Item &item : recent) {
          if (matches(item)) recent_group.items.push_back(&item);
        }
        if (!recent_group.items.empty()) result.push_back(std::move(recent_group));
      }
      if (!emoji.empty()) for (const Group &group : emoji) add(result, group, 18);
      if (!kaomoji.empty()) add(result, kaomoji.front(), 12);
      if (!symbols.empty()) for (const Group &group : symbols) add(result, group, 12);
      return result;
    }
    const std::vector<Group> *groups = page == Page::Emoji ? &emoji : page == Page::Kaomoji ? &kaomoji : &symbols;
    if (groups && category < groups->size()) add(result, (*groups)[category], 0);
    return result;
  }

  int content_height() const {
    int height = 0;
    for (const VisibleGroup &group : visible_groups()) {
      height += kGroupTitleHeight + static_cast<int>((group.items.size() + 5) / 6) * kCellHeight + 12;
    }
    return height;
  }

  void clamp_scroll() {
    RECT bounds{};
    GetClientRect(hwnd, &bounds);
    scroll = std::clamp(scroll, 0, std::max(content_height() - (static_cast<int>(bounds.bottom) - kContentTop - 30), 0));
  }

  void enter(Page next) {
    page = next;
    category = 0;
    scroll = 0;
    search_text.clear();
    if (search) SetWindowTextW(search, L"");
    notice = L"Click an item to copy";
    InvalidateRect(hwnd, nullptr, FALSE);
  }

  void activate_item(size_t index) {
    size_t current = 0;
    for (const VisibleGroup &group : visible_groups()) {
      for (const Item *item : group.items) {
        if (current++ != index) continue;
        const bool copied = copy_to_clipboard(hwnd, item->text);
        notice = copied ? L"Copied  " + item->text : L"Could not access the clipboard";
        if (copied && page != Page::Clipboard) {
          recent.erase(std::remove_if(recent.begin(), recent.end(), [item](const Item &entry) { return entry.text == item->text; }), recent.end());
          recent.insert(recent.begin(), *item);
          if (recent.size() > 28) recent.resize(28);
        }
        InvalidateRect(hwnd, nullptr, FALSE);
        return;
      }
    }
  }

  size_t hit_item(POINT point) const {
    if (point.y < kContentTop) return kInvalid;
    int y = kContentTop - scroll;
    size_t index = 0;
    for (const VisibleGroup &group : visible_groups()) {
      y += kGroupTitleHeight;
      const int width = std::max(1, (GetClientWidth() - kGridLeft - kGridRight - 5 * kGap) / 6);
      for (size_t item = 0; item < group.items.size(); ++item) {
        const int row = static_cast<int>(item / 6);
        const int column = static_cast<int>(item % 6);
        RECT cell{kGridLeft + column * (width + kGap), y + row * kCellHeight, kGridLeft + column * (width + kGap) + width, y + row * kCellHeight + kCellHeight - kGap};
        if (contains(cell, point)) return index + item;
      }
      index += group.items.size();
      y += static_cast<int>((group.items.size() + 5) / 6) * kCellHeight + 12;
    }
    return kInvalid;
  }

  int GetClientWidth() const {
    RECT bounds{};
    GetClientRect(hwnd, &bounds);
    return bounds.right;
  }

  size_t hit_tab(POINT point) const {
    if (point.y < kTabsTop || point.y >= kTabsTop + kTabsHeight) return kInvalid;
    const int width = std::max(1, (GetClientWidth() - 36 - 6 * 4) / 7);
    for (size_t index = 0; index < 7; ++index) {
      RECT tab{18 + static_cast<int>(index) * (width + 4), kTabsTop, 18 + static_cast<int>(index + 1) * width + static_cast<int>(index) * 4, kTabsTop + kTabsHeight};
      if (contains(tab, point)) return index;
    }
    return kInvalid;
  }

  size_t hit_category(POINT point) const {
    if (page != Page::Emoji && page != Page::Symbols) return kInvalid;
    const auto &groups = page == Page::Emoji ? emoji : symbols;
    if (point.y < kSubTabsTop || point.y >= kSubTabsTop + 34) return kInvalid;
    const size_t count = std::max<size_t>(groups.size(), 1);
    const int width = std::max(1, (GetClientWidth() - 58) / static_cast<int>(count));
    for (size_t index = 0; index < groups.size(); ++index) {
      RECT tab{50 + static_cast<int>(index) * width, kSubTabsTop, 50 + static_cast<int>(index + 1) * width, kSubTabsTop + 34};
      if (contains(tab, point)) return index;
    }
    return kInvalid;
  }

  void paint() {
    PAINTSTRUCT paint{};
    const HDC dc = BeginPaint(hwnd, &paint);
    struct End {
      HWND window;
      PAINTSTRUCT &state;
      ~End() { EndPaint(window, &state); }
    } end{hwnd, paint};
    RECT bounds{};
    GetClientRect(hwnd, &bounds);
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
    auto format = [&](const wchar_t *family, float size,
                      DWRITE_TEXT_ALIGNMENT alignment) {
      return device.GetTextFormat(family, size, DWRITE_FONT_WEIGHT_NORMAL,
                                  alignment, DWRITE_PARAGRAPH_ALIGNMENT_CENTER,
                                  DWRITE_WORD_WRAPPING_NO_WRAP);
    };
    auto *leading = format(L"Segoe UI", 14.0f, DWRITE_TEXT_ALIGNMENT_LEADING);
    auto *centered = format(L"Segoe UI", 14.0f, DWRITE_TEXT_ALIGNMENT_CENTER);
    auto *glyphs =
        format(L"Segoe UI Emoji", 28.0f, DWRITE_TEXT_ALIGNMENT_CENTER);
    auto *text_brush = brush(palette.text);
    auto *muted = brush(palette.number);
    auto *hover = brush(palette.hover);
    auto *selected = brush(palette.selected);
    if (!leading || !centered || !glyphs || !text_brush || !muted || !hover ||
        !selected)
      return;
    auto box = [](int left, int top, int right, int bottom) {
      return D2D1_RECT_F{static_cast<float>(left), static_cast<float>(top),
                         static_cast<float>(right), static_cast<float>(bottom)};
    };
    auto write = [&](const std::wstring &value, D2D1_RECT_F where,
                     ID2D1SolidColorBrush *color, IDWriteTextFormat *with) {
      target->DrawText(value.c_str(), static_cast<UINT32>(value.size()), with,
                       where, color);
    };
    target->BeginDraw();
    target->Clear(D2D1::ColorF(palette.surface.r, palette.surface.g,
                               palette.surface.b, palette.surface.a));
    write(kTitle, box(18, 0, bounds.right - 48, kHeaderHeight), text_brush,
          leading);
    const auto close = box(bounds.right - 38, 6, bounds.right - 8, 32);
    if (close_hovered || close_pressed)
      target->FillRectangle(close, close_pressed ? selected : hover);
    const float cx = (close.left + close.right) / 2.0f;
    const float cy = (close.top + close.bottom) / 2.0f;
    target->DrawLine({cx - 6.0f, cy - 6.0f}, {cx + 6.0f, cy + 6.0f}, text_brush,
                     2.0f);
    target->DrawLine({cx + 6.0f, cy - 6.0f}, {cx - 6.0f, cy + 6.0f}, text_brush,
                     2.0f);
    if (page != Page::Home)
      write(L"\u2039", box(18, kSubTabsTop, 46, kSubTabsTop + 34), muted,
            centered);
    for (size_t index = 0; index < 7; ++index) {
      const int width =
          std::max(1, (static_cast<int>(bounds.right) - 36 - 6 * 4) / 7);
      const auto tab = box(18 + static_cast<int>(index) * (width + 4), kTabsTop,
                           18 + static_cast<int>(index + 1) * width +
                               static_cast<int>(index) * 4,
                           kTabsTop + kTabsHeight);
      if (index == static_cast<size_t>(page))
        target->FillRectangle(tab, selected);
      const wchar_t *icons[] = {L"\u25f7", L"\U0001F600", L"\U0001F5BC", L"GIF",
                                L"\u30FE", L"\u2605",     L"\u25A3"};
      const wchar_t *labels[] = {L"Recent",  L"Emoji",   L"Stickers", L"GIF",
                                 L"Kaomoji", L"Symbols", L"Clipboard"};
      auto icon = tab;
      icon.bottom -= 17.0f;
      write(icons[index], icon, text_brush, glyphs);
      auto label = tab;
      label.top = label.bottom - 19.0f;
      write(labels[index], label, muted, centered);
    }
    if (page == Page::Emoji || page == Page::Symbols) {
      const auto &groups = page == Page::Emoji ? emoji : symbols;
      const size_t count = std::max<size_t>(groups.size(), 1);
      const int width = std::max(
          1, (static_cast<int>(bounds.right) - 58) / static_cast<int>(count));
      for (size_t index = 0; index < groups.size(); ++index) {
        const auto tab = box(50 + static_cast<int>(index) * width, kSubTabsTop,
                             50 + static_cast<int>(index + 1) * width,
                             kSubTabsTop + 34);
        if (index == category)
          target->FillRectangle(tab, selected);
        write(groups[index].icon, tab, text_brush, glyphs);
      }
    } else if (page != Page::Home) {
      const wchar_t *label = page == Page::Kaomoji  ? L"Kaomoji"
                             : page == Page::Sticker ? L"Stickers"
                             : page == Page::Gif     ? L"GIF"
                                                     : L"Clipboard";
      write(label, box(50, kSubTabsTop, bounds.right - 18, kSubTabsTop + 34),
            text_brush, leading);
    }
    if (page == Page::Sticker || page == Page::Gif || page == Page::Clipboard) {
      const wchar_t *message =
          page == Page::Sticker ? L"Stickers can be connected here"
          : page == Page::Gif   ? L"GIF sources can be connected here"
                                : L"Clipboard history is provided by the host";
      write(message,
            box(18, kContentTop + 40, bounds.right - 18, kContentTop + 120),
            muted, centered);
    } else {
      const auto groups = visible_groups();
      int y = kContentTop - scroll;
      size_t flat = 0;
      for (const VisibleGroup &group : groups) {
        write(group.title,
              box(kGridLeft, y, bounds.right - kGridRight,
                  y + kGroupTitleHeight),
              muted, leading);
        y += kGroupTitleHeight;
        const int width =
            std::max(1, (static_cast<int>(bounds.right) - kGridLeft -
                         kGridRight - 5 * kGap) /
                            6);
        for (size_t item = 0; item < group.items.size(); ++item) {
          const int row = static_cast<int>(item / 6);
          const int column = static_cast<int>(item % 6);
          const auto cell =
              box(kGridLeft + column * (width + kGap), y + row * kCellHeight,
                  kGridLeft + column * (width + kGap) + width,
                  y + row * kCellHeight + kCellHeight - kGap);
          const size_t item_index = flat + item;
          if (item_index == hovered_item || item_index == pressed_item)
            target->FillRoundedRectangle(
                {cell, palette.item_radius, palette.item_radius},
                item_index == pressed_item ? selected : hover);
          write(group.items[item]->text, cell, text_brush, glyphs);
        }
        flat += group.items.size();
        y += static_cast<int>((group.items.size() + 5) / 6) * kCellHeight + 12;
      }
      (void)flat;
    }
    write(notice, box(18, bounds.bottom - 30, bounds.right - 18, bounds.bottom),
          muted, centered);
    if (target->EndDraw() == D2DERR_RECREATE_TARGET)
      device.DiscardTarget();
  }
};

Panel *panel_for(HWND hwnd) { return reinterpret_cast<Panel *>(GetWindowLongPtrW(hwnd, GWLP_USERDATA)); }

std::filesystem::path resource_database(int argc, wchar_t **argv) {
  std::filesystem::path value;
  for (int index = 1; index + 1 < argc; ++index) {
    if (std::wstring(argv[index]) == L"--resources") value = argv[++index];
  }
  if (value.empty()) {
    wchar_t buffer[32768]{};
    const DWORD length = GetEnvironmentVariableW(L"MSIME_CLIENT_RESOURCES", buffer, static_cast<DWORD>(std::size(buffer)));
    if (length > 0 && length < std::size(buffer)) value = buffer;
  }
  if (!value.empty() && std::filesystem::is_directory(value)) value /= L"others.db";
  if (!value.empty()) return value;
  wchar_t module[32768]{};
  const DWORD length = GetModuleFileNameW(nullptr, module, static_cast<DWORD>(std::size(module)));
  if (!length || length >= std::size(module)) return {};
  const auto parent = std::filesystem::path(module).parent_path();
  for (const auto &candidate : {parent / L"resources" / L"others.db", parent / L"others.db"}) {
    if (std::filesystem::exists(candidate)) return candidate;
  }
  return {};
}

LRESULT CALLBACK window_proc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_NCCREATE) {
    const auto *create = reinterpret_cast<const CREATESTRUCTW *>(lparam);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(create->lpCreateParams));
  }
  Panel *panel = panel_for(hwnd);
  if (!panel) return DefWindowProcW(hwnd, message, wparam, lparam);
  switch (message) {
    case WM_CREATE:
      panel->hwnd = hwnd;
      panel->search_brush = CreateSolidBrush(RGB(43, 43, 51));
      panel->search = CreateWindowExW(0, L"EDIT", L"", WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL, 18, kSearchTop, 620, kSearchHeight, hwnd, nullptr, GetModuleHandleW(nullptr), nullptr);
      panel->search_font = CreateFontW(-14, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_SWISS, L"Segoe UI");
      SendMessageW(panel->search, WM_SETFONT, reinterpret_cast<WPARAM>(panel->search_font), TRUE);
      panel->layout();
      return 0;
    case WM_CTLCOLOREDIT:
      if (reinterpret_cast<HWND>(lparam) == panel->search) {
        HDC dc = reinterpret_cast<HDC>(wparam);
        SetTextColor(dc, RGB(245, 245, 247)); SetBkColor(dc, RGB(43, 43, 51)); return reinterpret_cast<LRESULT>(panel->search_brush);
      }
      break;
    case WM_COMMAND:
      if (reinterpret_cast<HWND>(lparam) == panel->search && HIWORD(wparam) == EN_CHANGE) {
        wchar_t text[1024]{}; GetWindowTextW(panel->search, text, static_cast<int>(std::size(text)));
        panel->search_text = text; panel->scroll = 0; InvalidateRect(hwnd, nullptr, FALSE);
      }
      return 0;
    case WM_MOUSEACTIVATE: return MA_NOACTIVATE;
    case WM_ERASEBKGND: return 1;
    case WM_SIZE: panel->layout(); panel->clamp_scroll(); return 0;
    case WM_MOUSEWHEEL:
      panel->scroll -= GET_WHEEL_DELTA_WPARAM(wparam) / 4; panel->clamp_scroll(); InvalidateRect(hwnd, nullptr, FALSE); return 0;
    case WM_MOUSEMOVE: {
      POINT point{static_cast<short>(LOWORD(lparam)), static_cast<short>(HIWORD(lparam))};
      RECT bounds{}; GetClientRect(hwnd, &bounds);
      panel->close_hovered = contains({bounds.right - 38, 6, bounds.right - 8, 32}, point);
      panel->back_hovered = panel->page != Page::Home && contains({18, kSubTabsTop, 46, kSubTabsTop + 34}, point);
      panel->hovered_item = panel->close_hovered || panel->back_hovered ? kInvalid : panel->hit_item(point);
      InvalidateRect(hwnd, nullptr, FALSE); return 0;
    }
    case WM_LBUTTONDOWN: {
      POINT point{static_cast<short>(LOWORD(lparam)), static_cast<short>(HIWORD(lparam))};
      RECT bounds{}; GetClientRect(hwnd, &bounds);
      panel->close_pressed = contains({bounds.right - 38, 6, bounds.right - 8, 32}, point);
      panel->back_pressed = panel->page != Page::Home && contains({18, kSubTabsTop, 46, kSubTabsTop + 34}, point);
      panel->pressed_tab = panel->close_pressed || panel->back_pressed ? kInvalid : panel->hit_tab(point);
      panel->pressed_category = panel->pressed_tab == kInvalid ? panel->hit_category(point) : kInvalid;
      panel->pressed_item = panel->pressed_tab == kInvalid && panel->pressed_category == kInvalid ? panel->hit_item(point) : kInvalid;
      SetCapture(hwnd); InvalidateRect(hwnd, nullptr, FALSE); return 0;
    }
    case WM_LBUTTONUP: {
      POINT point{static_cast<short>(LOWORD(lparam)), static_cast<short>(HIWORD(lparam))};
      RECT bounds{}; GetClientRect(hwnd, &bounds);
      const bool close = panel->close_pressed && contains({bounds.right - 38, 6, bounds.right - 8, 32}, point);
      const bool back = panel->back_pressed && contains({18, kSubTabsTop, 46, kSubTabsTop + 34}, point);
      const size_t tab = panel->hit_tab(point);
      const size_t category = panel->hit_category(point);
      const size_t item = panel->hit_item(point);
      if (panel->pressed_item != kInvalid && panel->pressed_item == item) panel->activate_item(item);
      else if (panel->pressed_category != kInvalid && panel->pressed_category == category) { panel->category = category; panel->scroll = 0; InvalidateRect(hwnd, nullptr, FALSE); }
      else if (panel->pressed_tab != kInvalid && panel->pressed_tab == tab) panel->enter(static_cast<Page>(tab));
      else if (back) panel->enter(Page::Home);
      panel->close_pressed = false; panel->back_pressed = false; panel->pressed_item = panel->pressed_tab = panel->pressed_category = kInvalid;
      if (GetCapture() == hwnd) ReleaseCapture();
      if (close) DestroyWindow(hwnd);
      return 0;
    }
    case WM_PAINT: panel->paint(); return 0;
    case WM_DESTROY: PostQuitMessage(0); return 0;
    default: break;
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}
}  // namespace

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR command_line, int show_command) {
  if (command_line && std::wstring(command_line) == L"--help") return 0;
  // Direct2D imaging is a COM server; --help answers before the apartment so
  // the smoke runner still needs nothing.
  const HRESULT entered =
      CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
  if (FAILED(entered) && entered != RPC_E_CHANGED_MODE) return 1;
  struct Apartment {
    bool owned;
    ~Apartment() { if (owned) CoUninitialize(); }
  } apartment{entered != RPC_E_CHANGED_MODE};
  HANDLE mutex = CreateMutexW(nullptr, FALSE, L"Local\\MSIMEClientEmojiPanel.SingleInstance");
  if (!mutex || GetLastError() == ERROR_ALREADY_EXISTS) { if (mutex) CloseHandle(mutex); return 0; }
  WNDCLASSEXW window_class{};
  window_class.cbSize = sizeof(window_class); window_class.hInstance = instance; window_class.lpfnWndProc = window_proc; window_class.lpszClassName = kClassName; window_class.hCursor = LoadCursorW(nullptr, MAKEINTRESOURCEW(32512));
  if (!RegisterClassExW(&window_class)) { CloseHandle(mutex); return 1; }
  RECT work_area{}; SystemParametersInfoW(SPI_GETWORKAREA, 0, &work_area, 0);
  constexpr LONG width = 760, height = 720;
  const LONG x = work_area.left + std::max<LONG>(0, (work_area.right - work_area.left - width) / 2);
  const LONG y = std::max<LONG>(work_area.top, work_area.bottom - height - 12);
  int argc = 0;
  wchar_t **argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  Panel state;
  state.load(resource_database(argc, argv));
  if (argv) LocalFree(argv);
  HWND window = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_TOPMOST, kClassName, kTitle, WS_POPUP, x, y, width, height, nullptr, nullptr, instance, &state);
  if (!window) { UnregisterClassW(kClassName, instance); CloseHandle(mutex); return 1; }
  ShowWindow(window, show_command == SW_HIDE ? SW_SHOWNOACTIVATE : SW_SHOWNOACTIVATE); UpdateWindow(window);
  MSG message{}; while (GetMessageW(&message, nullptr, 0, 0) > 0) { TranslateMessage(&message); DispatchMessageW(&message); }
  UnregisterClassW(kClassName, instance); CloseHandle(mutex); return static_cast<int>(message.wParam);
}
