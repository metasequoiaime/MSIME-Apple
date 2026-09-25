#include <shellapi.h>
#include <windows.h>

#include <cstdlib>
#include <filesystem>
#include <optional>
#include <string>
#include <string_view>
#include <utility>

#include "msime_client.h"

#include <winrt/Microsoft.UI.Dispatching.h>
#include <winrt/Microsoft.UI.Xaml.Controls.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>
#include <winrt/Microsoft.UI.Xaml.h>
#include <winrt/Windows.ApplicationModel.Activation.h>
#include <winrt/Windows.ApplicationModel.DataTransfer.h>
#include <winrt/Windows.Data.Json.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.UI.Text.h>
#include <winrt/base.h>

using namespace winrt;
using namespace Microsoft::UI::Xaml;
using namespace Microsoft::UI::Xaml::Controls;
using namespace Microsoft::UI::Xaml::Media;
using namespace Windows::ApplicationModel::Activation;
using namespace Windows::Data::Json;

namespace {

struct Response {
  std::string text;
  bool ok = false;
};

std::string utf8(hstring value) { return to_string(value); }

hstring text(std::string_view value) { return to_hstring(std::string(value)); }

Response take_response(char *raw) {
  if (!raw) {
    return {"{\"ok\":false,\"error\":\"empty host response\"}", false};
  }
  std::string value(raw);
  msime_client_string_free(raw);
  try {
    const auto object = JsonObject::Parse(text(value));
    return {std::move(value), object.GetNamedBoolean(L"ok", false)};
  } catch (...) {
    return {std::move(value), false};
  }
}

std::filesystem::path state_directory() {
  if (const auto *raw = _wgetenv(L"MSIME_CLIENT_STATE_DIR"); raw && *raw) {
    std::filesystem::path path(raw);
    if (path.is_absolute()) {
      return path;
    }
  }
  if (const auto *local = _wgetenv(L"LOCALAPPDATA"); local && *local) {
    return std::filesystem::path(local) / L"MSIME-Client";
  }
  return {};
}

std::string path_utf8(const std::filesystem::path &path) {
  const auto value = path.wstring();
  if (value.empty())
    return {};
  const int length = WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, value.data(),
      static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
  if (length <= 0)
    return {};
  std::string result(static_cast<size_t>(length), '\0');
  WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(),
                      static_cast<int>(value.size()), result.data(), length,
                      nullptr, nullptr);
  return result;
}

std::string route_page() {
  int argc = 0;
  auto *argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  std::string page;
  if (argv) {
    for (int i = 1; i < argc; ++i) {
      constexpr std::wstring_view prefix = L"--route=settings:";
      const std::wstring_view argument(argv[i]);
      if (argument.starts_with(prefix)) {
        page = utf8(hstring(argument.substr(prefix.size())));
        break;
      }
    }
    LocalFree(argv);
  }
  return page;
}

// The runtime options msime-mcp is pointed at: the file the Server hands this window, or the one in the state directory when started from the Start menu. None before the input method is set up.
std::optional<std::string> runtime_options_path() {
  std::error_code error;
  if (const auto *raw = _wgetenv(L"MSIME_CLIENT_HOST_OPTIONS"); raw && *raw) {
    std::filesystem::path path(raw);
    if (path.is_absolute() && std::filesystem::is_regular_file(path, error)) {
      if (auto value = path_utf8(path); !value.empty())
        return value;
    }
  }
  const auto directory = state_directory();
  if (directory.empty())
    return std::nullopt;
  const auto path = directory / L"runtime-options.json";
  if (!std::filesystem::is_regular_file(path, error))
    return std::nullopt;
  if (auto value = path_utf8(path); !value.empty())
    return value;
  return std::nullopt;
}

JsonObject mcp_request(std::optional<std::string> const &options) {
  JsonObject request;
  request.SetNamedValue(L"options",
                        options ? JsonValue::CreateStringValue(text(*options))
                                : JsonValue::CreateNullValue());
  return request;
}

Response call_mcp(char *(*entry)(const uint8_t *, size_t),
                  JsonObject const &request) {
  const auto body = utf8(request.Stringify());
  return take_response(
      entry(reinterpret_cast<const uint8_t *>(body.data()), body.size()));
}

std::wstring response_error(Response const &response) {
  try {
    return std::wstring(JsonObject::Parse(text(response.text))
                            .GetNamedString(L"error", L"")
                            .c_str());
  } catch (...) {
    return {};
  }
}

std::wstring mcp_client_name(std::wstring_view id) {
  if (id == L"claude_desktop")
    return L"Claude Desktop";
  if (id == L"cursor")
    return L"Cursor";
  return std::wstring(id);
}

// Same wording as the shared settings page (packages/ui/src/settings/mcp-connect.tsx).
std::wstring mcp_failure(std::wstring const &code, std::wstring const &name) {
  if (code == L"mcp_client_missing")
    return L"没有找到 " + name + L" 的配置目录。请先安装并打开一次 " + name +
           L"。";
  if (code == L"mcp_config_invalid")
    return name + L" 的配置文件不是有效的 JSON，已保持原样。请先修正该文件。";
  if (code == L"mcp_server_missing")
    return L"没有找到 msime-mcp，请重新安装输入法。";
  if (code == L"mcp_options_missing")
    return L"输入法尚未完成初始化，请先完成设置向导。";
  return L"无法写入 " + name + L" 的配置文件。";
}

class PreferencesDocument {
public:
  PreferencesDocument() { reset_defaults(); }

  bool Load(std::wstring &error) {
    const auto directory = state_directory();
    if (directory.empty()) {
      error = L"找不到水杉输入法的数据目录。请先完成输入法安装。";
      return false;
    }
    const auto path = path_utf8(directory);
    auto response = take_response(msime_client_load_preferences(
        reinterpret_cast<const uint8_t *>(path.data()), path.size()));
    if (!response.ok) {
      error = L"读取设置失败，请稍后重试。";
      reset_defaults();
      return false;
    }
    try {
      document_ =
          JsonObject::Parse(text(response.text)).GetNamedObject(L"value");
      preferences_ = document_.GetNamedObject(L"preferences");
      revision_ =
          static_cast<uint64_t>(document_.GetNamedNumber(L"revision", 0));
      return true;
    } catch (...) {
      error = L"设置文件格式无效。";
      return false;
    }
  }

  bool Save(std::wstring &error) {
    const auto directory = state_directory();
    const auto path = path_utf8(directory);
    const auto snapshot = utf8(document_.Stringify());
    auto response = take_response(msime_client_save_preferences(
        reinterpret_cast<const uint8_t *>(path.data()), path.size(), revision_,
        reinterpret_cast<const uint8_t *>(snapshot.data()), snapshot.size()));
    if (!response.ok) {
      error = L"保存失败：设置可能已在其他窗口中更新，请重新读取后再保存。";
      return false;
    }
    try {
      document_ =
          JsonObject::Parse(text(response.text)).GetNamedObject(L"value");
      preferences_ = document_.GetNamedObject(L"preferences");
      revision_ = static_cast<uint64_t>(
          document_.GetNamedNumber(L"revision", revision_));
      return true;
    } catch (...) {
      error = L"设置已写入，但返回内容无法读取。";
      return false;
    }
  }

  bool Boolean(std::wstring_view key, bool fallback) const {
    if (!preferences_)
      return fallback;
    const auto [object, leaf] = object_for_key(key);
    return object ? object.GetNamedBoolean(leaf, fallback) : fallback;
  }

  void SetBoolean(std::wstring_view key, bool value) {
    if (!preferences_)
      return;
    const auto [object, leaf] = object_for_key(key, true);
    if (object)
      object.SetNamedValue(leaf, JsonValue::CreateBooleanValue(value));
  }

private:
  void reset_defaults() {
    auto defaults = take_response(msime_client_default_preferences());
    if (!defaults.ok) {
      document_ = JsonObject();
      preferences_ = JsonObject();
      revision_ = 0;
      return;
    }
    try {
      preferences_ =
          JsonObject::Parse(text(defaults.text)).GetNamedObject(L"value");
      document_ = JsonObject();
      document_.SetNamedValue(L"format_version",
                              JsonValue::CreateNumberValue(1));
      document_.SetNamedValue(L"revision", JsonValue::CreateNumberValue(0));
      document_.SetNamedValue(L"preferences", preferences_);
      revision_ = 0;
    } catch (...) {
      document_ = JsonObject();
      preferences_ = JsonObject();
      revision_ = 0;
    }
  }

  std::pair<JsonObject, hstring> object_for_key(std::wstring_view key,
                                                bool create = false) const {
    const auto separator = key.find(L'.');
    if (separator == std::wstring_view::npos) {
      return {preferences_, hstring(key)};
    }
    const auto parent = hstring(key.substr(0, separator));
    const auto leaf = hstring(key.substr(separator + 1));
    if (create) {
      auto nested = preferences_.GetNamedObject(parent, nullptr);
      if (!nested) {
        nested = JsonObject();
        preferences_.SetNamedValue(parent, nested);
      }
      return {nested, leaf};
    }
    return {preferences_.GetNamedObject(parent, nullptr), leaf};
  }

  JsonObject document_{nullptr};
  JsonObject preferences_{nullptr};
  uint64_t revision_ = 0;
};

struct MainWindow : WindowT<MainWindow> {
  MainWindow(std::string requested_page, PreferencesDocument &document)
      : document_(document), requested_page_(std::move(requested_page)) {
    Title(L"水杉输入法设置");
    ExtendsContentIntoTitleBar(true);
    SetTitleBar(make_title_bar());
    Content(make_content());
  }

private:
  UIElement make_title_bar() {
    auto bar = StackPanel();
    bar.Orientation(Orientation::Horizontal);
    bar.Padding(Thickness{20, 10, 20, 8});
    auto mark = TextBlock();
    mark.Text(L"水杉输入法");
    mark.FontSize(18);
    mark.FontWeight(Windows::UI::Text::FontWeights::SemiBold());
    bar.Children().Append(mark);
    auto caption = TextBlock();
    caption.Text(L"  设置");
    caption.Opacity(0.65);
    caption.VerticalAlignment(VerticalAlignment::Center);
    bar.Children().Append(caption);
    return bar;
  }

  UIElement make_content() {
    auto root = Grid();
    root.Padding(Thickness{20, 8, 20, 20});
    root.ColumnDefinitions().Append(ColumnDefinition());
    root.ColumnDefinitions().Append(ColumnDefinition());
    root.ColumnDefinitions().GetAt(0).Width(
        GridLength{230, GridUnitType::Pixel});
    root.ColumnDefinitions().GetAt(1).Width(GridLength{1, GridUnitType::Star});

    auto navigation = NavigationView();
    navigation.IsBackButtonVisible(NavigationViewBackButtonVisible::Collapsed);
    navigation.IsSettingsVisible(false);
    navigation.SelectionChanged({this, &MainWindow::on_navigation_changed});
    append_navigation_item(navigation, L"常用", L"home");
    append_navigation_item(navigation, L"输入", L"input");
    append_navigation_item(navigation, L"候选窗口", L"candidate");
    append_navigation_item(navigation, L"外观", L"appearance");
    append_navigation_item(navigation, L"词库", L"dictionary");
    append_navigation_item(navigation, L"AI 助手", L"ai");
    append_navigation_item(navigation, L"关于", L"about");
    Grid::SetColumn(navigation, 0);
    root.Children().Append(navigation);

    content_ = ScrollViewer();
    content_.Padding(Thickness{28, 4, 8, 12});
    Grid::SetColumn(content_, 1);
    root.Children().Append(content_);
    navigation.SelectedItem(find_navigation_item(navigation, requested_page_));
    if (!navigation.SelectedItem()) {
      navigation.SelectedItem(navigation.MenuItems().GetAt(0));
    }
    return root;
  }

  void append_navigation_item(NavigationView const &navigation, hstring label,
                              hstring tag) {
    auto item = NavigationViewItem();
    item.Content(box_value(label));
    item.Tag(box_value(tag));
    navigation.MenuItems().Append(item);
  }

  IInspectable find_navigation_item(NavigationView const &navigation,
                                    std::string const &page) {
    if (page.empty()) {
      return nullptr;
    }
    for (const auto &value : navigation.MenuItems()) {
      auto item = value.as<NavigationViewItem>();
      if (utf8(unbox_value<hstring>(item.Tag())) == page) {
        return item;
      }
    }
    return nullptr;
  }

  void on_navigation_changed(NavigationView const &sender,
                             NavigationViewSelectionChangedEventArgs const &) {
    auto item = sender.SelectedItem().try_as<NavigationViewItem>();
    if (!item) {
      return;
    }
    show_page(utf8(unbox_value<hstring>(item.Tag())));
  }

  void show_page(std::string const &page) {
    current_page_ = page.empty() ? "home" : page;
    auto panel = StackPanel();
    panel.Spacing(10);
    auto title = TextBlock();
    title.Text(page_title(page));
    title.FontSize(28);
    title.FontWeight(Windows::UI::Text::FontWeights::SemiBold());
    panel.Children().Append(title);

    if (page == "home" || page == "") {
      append_section(
          panel, L"输入法状态",
          L"设置会实时写入共享配置，正在输入的内容会在本次组词结束后应用。");
      append_switch(panel, L"开启词语学习",
                    L"记录已上屏的词语，用于调整候选顺序。", L"learning");
      append_switch(panel, L"中文标点", L"在中文模式下使用全角标点。",
                    L"chinese_punctuation");
      append_switch(panel, L"自动纠错", L"修正常见的相邻按键顺序。",
                    L"autocorrect");
    } else if (page == "input") {
      append_section(panel, L"输入方案",
                     L"选择全拼或双拼，并调整输入时的行为。");
      append_switch(panel, L"混合输入英文", L"在中文输入中直接接受英文单词。",
                    L"mixed_input.english");
      append_switch(panel, L"配对标点", L"输入左括号时自动补齐右括号。",
                    L"paired_punctuation");
      append_switch(panel, L"记忆候选", L"保存候选选择，用于下次排序。",
                    L"learning");
    } else if (page == "candidate") {
      append_section(panel, L"候选窗口", L"调整候选分页和候选窗口的行为。");
      append_switch(panel, L"候选窗口跟随光标", L"让候选窗口跟随当前编辑位置。",
                    L"candidate_follow_cursor");
      append_switch(panel, L"云端候选", L"允许使用已配置的云端候选服务。",
                    L"cloud_candidates");
    } else if (page == "appearance") {
      append_section(
          panel, L"外观",
          L"这些选项只影响水杉输入法的窗口，不会修改 Windows 主题。");
      append_switch(panel, L"悬浮工具栏", L"在输入法切换后显示快捷工具栏。",
                    L"floating_toolbar.enabled");
      append_switch(panel, L"全角字符", L"工具栏和候选窗口使用全角字符。",
                    L"floating_toolbar.fullwidth");
    } else if (page == "dictionary") {
      append_section(panel, L"词库",
                     L"管理个人词库和学习数据。词库文件不会离开本机。");
      append_switch(panel, L"剪贴板历史", L"保存复制过的文本供剪贴板面板使用。",
                    L"clipboard_history");
      append_switch(panel, L"显示候选翻译", L"在候选下方显示可用的翻译提示。",
                    L"candidate_translations");
    } else if (page == "ai") {
      append_mcp_section(panel);
    } else {
      append_section(panel, L"水杉输入法", L"Windows 原生 WinUI 3 设置窗口");
      append_section(panel, L"数据与隐私",
                     L"设置保存到当前输入法数据目录，详细说明见隐私政策。");
    }

    // The assistant page writes the assistants' files itself; it has no preferences to save.
    if (page == "ai") {
      content_.Content(panel);
      return;
    }
    auto actions = StackPanel();
    actions.Orientation(Orientation::Horizontal);
    actions.Spacing(10);
    actions.Margin(Thickness{0, 18, 0, 0});
    auto save = Button();
    save.Content(box_value(L"保存设置"));
    save.Click({this, &MainWindow::save});
    actions.Children().Append(save);
    auto reload = Button();
    reload.Content(box_value(L"重新读取"));
    reload.Click({this, &MainWindow::reload});
    actions.Children().Append(reload);
    panel.Children().Append(actions);
    content_.Content(panel);
  }

  hstring page_title(std::string const &page) const {
    if (page == "input")
      return L"输入";
    if (page == "candidate")
      return L"候选窗口";
    if (page == "appearance")
      return L"外观";
    if (page == "dictionary")
      return L"词库";
    if (page == "about")
      return L"关于";
    if (page == "ai")
      return L"连接 AI 助手";
    return L"常用";
  }

  void append_section(StackPanel const &panel, hstring heading,
                      hstring description) {
    auto heading_text = TextBlock();
    heading_text.Text(heading);
    heading_text.FontSize(16);
    heading_text.FontWeight(Windows::UI::Text::FontWeights::SemiBold());
    panel.Children().Append(heading_text);
    auto description_text = TextBlock();
    description_text.Text(description);
    description_text.TextWrapping(TextWrapping::Wrap);
    description_text.Opacity(0.72);
    panel.Children().Append(description_text);
  }

  void append_switch(StackPanel const &panel, hstring label,
                     hstring description, std::wstring_view key) {
    auto row = StackPanel();
    row.Margin(Thickness{0, 8, 0, 0});
    auto toggle = ToggleSwitch();
    toggle.Header(box_value(label));
    toggle.IsOn(document_.Boolean(key, false));
    toggle.Tag(box_value(hstring(key)));
    toggle.Toggled([this](IInspectable const &sender, RoutedEventArgs const &) {
      auto toggle = sender.as<ToggleSwitch>();
      const auto key = unbox_value<hstring>(toggle.Tag());
      document_.SetBoolean(key, toggle.IsOn());
    });
    row.Children().Append(toggle);
    auto hint = TextBlock();
    hint.Text(description);
    hint.TextWrapping(TextWrapping::Wrap);
    hint.Opacity(0.66);
    row.Children().Append(hint);
    panel.Children().Append(row);
  }

  void append_text(StackPanel const &panel, std::wstring const &value,
                   double opacity = 0.72) {
    auto block = TextBlock();
    block.Text(value);
    block.TextWrapping(TextWrapping::Wrap);
    block.IsTextSelectionEnabled(true);
    block.Opacity(opacity);
    panel.Children().Append(block);
  }

  // 「连接 AI 助手」: the msime-mcp entry an assistant runs, to copy or to write into Claude Desktop's or Cursor's configuration. The same section as the shared settings page, through msime_client_mcp_status and msime_client_mcp_install.
  void append_mcp_section(StackPanel const &panel) {
    append_text(panel, L"连接后，直接告诉 AI 助手输入法哪里不对劲（比如卡顿、候选框不见了），它会打开诊断日志、请你把出问题的操作再做一遍，然后读日志帮你找原因。它也能读取快捷短语、设置和打字统计。通过 MCP（Model Context Protocol）在本机运行，不联网；除了开关诊断日志，默认不改动任何设置。");
    const auto response =
        call_mcp(msime_client_mcp_status, mcp_request(runtime_options_path()));
    JsonObject status{nullptr};
    if (response.ok) {
      try {
        status =
            JsonObject::Parse(text(response.text)).GetNamedObject(L"value");
      } catch (...) {
      }
    }
    if (!status) {
      append_text(panel, L"无法读取 MCP 服务器的状态。", 1);
      return;
    }
    const bool installed = status.GetNamedBoolean(L"installed", false);
    append_section(
        panel, L"服务器程序",
        hstring(std::wstring(status.GetNamedString(L"command", L"").c_str()) +
                (installed ? L"" : L"（未找到，请重新安装输入法）")));
    const auto config =
        status.GetNamedValue(L"config", JsonValue::CreateNullValue());
    if (config.ValueType() != JsonValueType::String) {
      append_text(panel, L"输入法尚未完成初始化，完成设置向导后即可连接。", 1);
      append_mcp_result(panel);
      return;
    }
    const auto snippet = config.GetString();
    auto code = TextBox();
    code.Text(snippet);
    code.IsReadOnly(true);
    code.AcceptsReturn(true);
    code.TextWrapping(TextWrapping::NoWrap);
    code.FontFamily(Media::FontFamily(L"Consolas"));
    code.Header(box_value(L"MCP 配置"));
    panel.Children().Append(code);
    append_text(panel,
                L"要让助手修改快捷短语和设置，在 args 中加入 "
                L"--allow-write；要让它读取你的用户词库、查看编码的候选，加入 "
                L"--allow-dictionary-"
                L"read；两项都加才能增删、调整和导入词。这两项只应在你信任该助"
                L"手时开启。");
    auto copy = Button();
    copy.Content(box_value(L"复制配置"));
    copy.Click([snippet](IInspectable const &sender, RoutedEventArgs const &) {
      Windows::ApplicationModel::DataTransfer::DataPackage package;
      package.SetText(snippet);
      Windows::ApplicationModel::DataTransfer::Clipboard::SetContent(package);
      sender.as<Button>().Content(box_value(L"已复制"));
    });
    panel.Children().Append(copy);
    if (installed) {
      for (auto const &value : status.GetNamedArray(L"clients", JsonArray())) {
        const auto client = value.GetObject();
        const std::wstring id(client.GetNamedString(L"id", L"").c_str());
        const auto name = mcp_client_name(id);
        const bool configured = client.GetNamedBoolean(L"configured", false);
        append_section(
            panel, hstring(name),
            hstring(std::wstring(client.GetNamedString(L"path", L"").c_str()) +
                    (configured ? L"（已连接）" : L"")));
        auto write = Button();
        write.Content(box_value(hstring(L"写入 " + name)));
        write.IsEnabled(!configured && !mcp_busy_);
        write.Click([this, id](IInspectable const &, RoutedEventArgs const &) {
          write_mcp_client(id);
        });
        panel.Children().Append(write);
      }
    }
    append_mcp_result(panel);
  }

  void append_mcp_result(StackPanel const &panel) {
    if (!mcp_result_.empty())
      append_text(panel, mcp_result_, 1);
  }

  fire_and_forget write_mcp_client(std::wstring id) {
    if (mcp_busy_)
      co_return;
    auto strong = get_strong();
    const auto name = mcp_client_name(id);
    mcp_busy_ = true;
    mcp_result_.clear();
    auto request = mcp_request(runtime_options_path());
    request.SetNamedValue(L"client", JsonValue::CreateStringValue(id));
    request.SetNamedValue(L"replace", JsonValue::CreateBooleanValue(false));
    auto response = call_mcp(msime_client_mcp_install, request);
    if (!response.ok && response_error(response) == L"mcp_entry_exists") {
      ContentDialog dialog;
      dialog.Title(box_value(hstring(L"替换 " + name + L" 中的 msime？")));
      dialog.Content(box_value(
          hstring(name + L" 的配置里已有另一个名为 msime "
                         L"的服务器。替换后，它原来的命令和参数（包括手动加上的"
                         L" --allow-write）会被这里的设置覆盖。")));
      dialog.PrimaryButtonText(L"替换");
      dialog.CloseButtonText(L"取消");
      dialog.DefaultButton(ContentDialogButton::Close);
      dialog.XamlRoot(content_.XamlRoot());
      if (co_await dialog.ShowAsync() != ContentDialogResult::Primary) {
        mcp_busy_ = false;
        co_return;
      }
      request.SetNamedValue(L"replace", JsonValue::CreateBooleanValue(true));
      response = call_mcp(msime_client_mcp_install, request);
    }
    if (response.ok) {
      std::wstring outcome;
      try {
        outcome = JsonObject::Parse(text(response.text))
                      .GetNamedString(L"value", L"")
                      .c_str();
      } catch (...) {
      }
      mcp_result_ =
          outcome == L"unchanged"
              ? name + L" 已经连接，无需改动。"
              : L"已写入 " + name + L" 的配置。重新启动 " + name + L" 后生效。";
    } else {
      mcp_result_ = mcp_failure(response_error(response), name);
    }
    mcp_busy_ = false;
    show_page("ai");
  }

  void save(IInspectable const &, RoutedEventArgs const &) {
    std::wstring error;
    if (!document_.Save(error)) {
      show_error(error);
    }
  }

  void reload(IInspectable const &, RoutedEventArgs const &) {
    std::wstring error;
    if (!document_.Load(error)) {
      show_error(error);
      return;
    }
    show_page(current_page_);
  }

  void show_error(std::wstring const &message) {
    ContentDialog dialog;
    dialog.Title(box_value(L"水杉输入法"));
    dialog.Content(box_value(message));
    dialog.CloseButtonText(L"确定");
    dialog.XamlRoot(content_.XamlRoot());
    dialog.ShowAsync();
  }

  PreferencesDocument &document_;
  std::string requested_page_;
  std::string current_page_ = "home";
  std::wstring mcp_result_;
  bool mcp_busy_ = false;
  ScrollViewer content_{nullptr};
};

struct App : ApplicationT<App> {
  App() { Suspending({this, &App::on_suspending}); }

  void OnLaunched(LaunchActivatedEventArgs const &) {
    std::wstring error;
    if (!document_.Load(error)) {
      window_ = make<MainWindow>(route_page(), document_);
      window_.Activate();
      return;
    }
    window_ = make<MainWindow>(route_page(), document_);
    window_.Activate();
  }

private:
  void on_suspending(IInspectable const &, SuspendingEventArgs const &) {}

  PreferencesDocument document_;
  MainWindow window_{nullptr};
};

} // namespace

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
  init_apartment(apartment_type::single_threaded);
  Application::Start([](auto &&) { make<App>(); });
  return 0;
}
