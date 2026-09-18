// Real Fcitx input contexts and the real Host API. All input is synthetic.
#include "../FcitxEngine.cpp"
#include <iostream>
#include <filesystem>
#include <thread>
#include <chrono>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <sys/stat.h>
#include <cstring>
#include <poll.h>

using namespace msime::fcitx_host;
class FixtureContext : public fcitx::InputContext {
public:
  explicit FixtureContext(fcitx::InputContextManager &manager) : InputContext(manager, "msime-test") { created(); }
  ~FixtureContext() override { destroy(); }
  const char *frontend() const override { return "msime-test"; }
  void commitStringImpl(const std::string &text) override { committed += text; }
  void deleteSurroundingTextImpl(int, unsigned int) override {}
  void forwardKeyImpl(const fcitx::ForwardKeyEvent &) override {}
  void updatePreeditImpl() override {}
  std::string committed;
};
void require(bool ok, const char *message) { if (!ok) throw std::runtime_error(message); }
int main(int argc, char **argv) {
  try {
    require(argc == 2 || (argc == 3 && std::string(argv[2]) == "--ai"),
            "usage: fcitx5-native-test <verified-resources> [--ai]");
    const bool ai = argc == 3;
    const std::string suggestion = ai ? "合成候选" : "在线";
    char temporary[] = "/tmp/msime-fcitx5-test-XXXXXX";
    const auto *directory = mkdtemp(temporary);
    require(directory != nullptr, "fixture directory");
    const auto request = Json{{"resources", argv[1]}, {"state_root", directory}}.dump();
    auto options = response(msime_client_prepare_host(
        reinterpret_cast<const uint8_t *>(request.data()), request.size()));
    options["preferences"]["learning"] = false;
    options["preferences"]["candidate_page_size"] = 2;
    options["preferences"]["clipboard_history"] = true;
    const auto clipboardPath = std::filesystem::path(options.at("preferences_directory").get<std::string>()) /
                               "clipboard_history.json";
    std::ofstream(clipboardPath) << Json::array({"剪贴板合成测试", "第二条"}).dump();
    options["preferences"]["cloud_candidates"] = !ai;
    options["preferences"]["ai_assistant"]["enabled"] = ai;
    options["preferences"]["ai_assistant"]["candidate_limit"] = 1;
    options["preferences"]["ai_assistant"]["endpoint"] = "https://synthetic.invalid/v1/chat/completions";
    options["preferences"]["ai_assistant"]["model"] = "synthetic";
    options["preferences"]["ai_assistant"]["token"] = "synthetic-token";
    const auto socketPath = std::string(directory) + "/online.sock";
    const int providerServer = socket(AF_UNIX, SOCK_STREAM, 0);
    require(providerServer >= 0, "online provider socket");
    sockaddr_un providerAddress{};
    providerAddress.sun_family = AF_UNIX;
    require(socketPath.size() < sizeof(providerAddress.sun_path), "online socket path length");
    std::strncpy(providerAddress.sun_path, socketPath.c_str(), sizeof(providerAddress.sun_path) - 1);
    require(bind(providerServer, reinterpret_cast<sockaddr *>(&providerAddress), sizeof(providerAddress)) == 0,
            "online provider bind");
    require(listen(providerServer, 1) == 0, "online provider listen");
    options["online_provider_socket"] = socketPath;
    const auto cloudSocketPath = std::string(directory) + "/cloud-clipboard.sock";
    const int cloudServer = socket(AF_UNIX, SOCK_STREAM, 0);
    require(cloudServer >= 0, "cloud clipboard socket");
    sockaddr_un cloudAddress{};
    cloudAddress.sun_family = AF_UNIX;
    std::strncpy(cloudAddress.sun_path, cloudSocketPath.c_str(), sizeof(cloudAddress.sun_path) - 1);
    require(bind(cloudServer, reinterpret_cast<sockaddr *>(&cloudAddress), sizeof(cloudAddress)) == 0 &&
            listen(cloudServer, 1) == 0, "cloud clipboard listener");
    options["cloud_clipboard_provider_socket"] = cloudSocketPath;
    const auto voiceSocketPath = std::string(directory) + "/voice.sock";
    const int voiceServer = socket(AF_UNIX, SOCK_STREAM, 0);
    require(voiceServer >= 0, "voice socket");
    sockaddr_un voiceAddress{};
    voiceAddress.sun_family = AF_UNIX;
    std::strncpy(voiceAddress.sun_path, voiceSocketPath.c_str(), sizeof(voiceAddress.sun_path) - 1);
    require(bind(voiceServer, reinterpret_cast<sockaddr *>(&voiceAddress), sizeof(voiceAddress)) == 0 &&
            listen(voiceServer, 1) == 0, "voice listener");
    options["voice_provider_socket"] = voiceSocketPath;
    const auto path = std::string(directory) + "/runtime-options.json";
    std::ofstream(path) << options.dump();
    std::thread provider([providerServer, ai, suggestion] {
      const auto reply = Json{{"text", suggestion}, {"source", ai ? 1 : 0}}.dump() + "\n";
      for (int attempt = 0; attempt < 1; ++attempt) {
        pollfd descriptor{providerServer, POLLIN, 0};
        if (poll(&descriptor, 1, 7000) <= 0) break;
        const int client = accept(providerServer, nullptr, nullptr);
        if (client < 0) break;
        std::string request;
        const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(2);
        while (request.size() < 16384 && request.find('\n') == std::string::npos &&
               std::chrono::steady_clock::now() < deadline) {
          pollfd input{client, POLLIN, 0};
          if (poll(&input, 1, 100) <= 0) continue;
          char chunk[1024];
          const auto count = read(client, chunk, sizeof(chunk));
          if (count <= 0) break;
          request.append(chunk, count);
        }
        if (request.find('\n') == std::string::npos ||
            send(client, reply.data(), reply.size(), MSG_NOSIGNAL) != static_cast<ssize_t>(reply.size())) {
          close(client); break;
        }
        close(client);
      }
      close(providerServer);
    });
    struct ProviderJoiner { std::thread &thread; ~ProviderJoiner() { if (thread.joinable()) thread.join(); } } providerJoiner{provider};
    auto cloudProvider = std::async(std::launch::async, [cloudServer] {
      pollfd ready{cloudServer, POLLIN, 0};
      if (poll(&ready, 1, 5000) <= 0) { close(cloudServer); return false; }
      const int client = accept(cloudServer, nullptr, nullptr);
      if (client < 0) { close(cloudServer); return false; }
      char request[4096]{};
      const auto count = read(client, request, sizeof(request) - 1);
      const auto reply = "{\"entries\":[{\"id\":\"synthetic-1\",\"text\":\"云剪贴板测试\"},{\"id\":\"synthetic-2\",\"text\":\"云剪贴板第二条\"}]}\n";
      const bool valid = count > 0 && std::string(request, count).find("cloud_clipboard") != std::string::npos;
      const bool sent = send(client, reply, std::strlen(reply), MSG_NOSIGNAL) == static_cast<ssize_t>(std::strlen(reply));
      close(client); close(cloudServer);
      return valid && sent;
    });
    auto voiceProvider = std::async(std::launch::async, [voiceServer] {
      pollfd ready{voiceServer, POLLIN, 0};
      if (poll(&ready, 1, 5000) <= 0) { close(voiceServer); return false; }
      const int client = accept(voiceServer, nullptr, nullptr);
      if (client < 0) { close(voiceServer); return false; }
      char request[4096]{};
      const auto count = read(client, request, sizeof(request) - 1);
      uint64_t generation = 1;
      try {
        generation = Json::parse(request, request + std::max<ssize_t>(count, 0))
                         .at("query").at("generation").get<uint64_t>();
      } catch (...) {}
      const auto partial = Json{{"type", "partial"}, {"generation", generation},
                                {"text", "语音中"}}.dump() + "\n";
      const auto status = Json{{"type", "status"}, {"generation", generation},
                               {"phase", "recognizing"}}.dump() + "\n";
      const auto level = Json{{"type", "level"}, {"generation", generation},
                              {"level", 0.7}}.dump() + "\n";
      const auto final = Json{{"type", "final"}, {"generation", generation},
                              {"text", "语音测试"}}.dump() + "\n";
      const bool valid = count > 0 && std::string(request, count).find("voice") != std::string::npos;
      const bool partialSent = send(client, partial.data(), partial.size(), MSG_NOSIGNAL) ==
                               static_cast<ssize_t>(partial.size());
      const bool statusSent = send(client, status.data(), status.size(), MSG_NOSIGNAL) ==
                              static_cast<ssize_t>(status.size());
      const bool levelSent = send(client, level.data(), level.size(), MSG_NOSIGNAL) ==
                             static_cast<ssize_t>(level.size());
      std::this_thread::sleep_for(std::chrono::milliseconds(100));
      const bool finalSent = send(client, final.data(), final.size(), MSG_NOSIGNAL) ==
                             static_cast<ssize_t>(final.size());
      close(client); close(voiceServer);
      return valid && partialSent && statusSent && levelSent && finalSent;
    });
    setenv("MSIME_FCITX5_OPTIONS", path.c_str(), 1);
    char name[] = "fcitx5-native-test";
    char disable[] = "--disable=all";
    char *args[] = {name, disable, nullptr};
    fcitx::Instance instance(2, args);
    instance.initialize();
    FcitxEngine engine(&instance);
    FixtureContext ic(instance.inputContextManager());
    ic.setCapabilityFlags(fcitx::CapabilityFlags{fcitx::CapabilityFlag::Preedit,
                                               fcitx::CapabilityFlag::SurroundingText});
    ic.focusIn();
    fcitx::InputMethodEntry entry("msime", "MSIME", "zh_CN", "msime");
    fcitx::InputContextEvent focus(&ic, fcitx::EventType::InputContextFocusIn);
    engine.activate(entry, focus);
    auto *state = ic.propertyFor(&engine.factory_);
    require(state->session_ != 0 && state->view_.contains("candidates"), "focus must unpack transition view");
    auto changedPreferences = options["preferences"];
    changedPreferences["number_row_selection"] = false;
    changedPreferences["candidate_layout"] = "horizontal";
    changedPreferences["smart_punctuation"] = true;
    changedPreferences["smart_punctuation_repeat"] = true;
    changedPreferences["learning"] = true;
    const auto preferenceDirectory = options["preferences_directory"].get<std::string>();
    const auto currentSnapshot = response(msime_client_load_preferences(
        reinterpret_cast<const uint8_t *>(preferenceDirectory.data()), preferenceDirectory.size()));
    const auto changed = Json{{"format_version", 1},
                              {"revision", currentSnapshot.value("revision", uint64_t{}) + 1},
                              {"preferences", changedPreferences}};
    const auto changedDocument = changed.dump();
    auto saved = response(msime_client_save_preferences(
        reinterpret_cast<const uint8_t *>(preferenceDirectory.data()), preferenceDirectory.size(),
        currentSnapshot.value("revision", uint64_t{}),
        reinterpret_cast<const uint8_t *>(changedDocument.data()), changedDocument.size()));
    require(saved.value("revision", uint64_t{}) > currentSnapshot.value("revision", uint64_t{}),
            "preference store update");
    const auto reloadDeadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
    while (state->preferences_.value("number_row_selection", true) &&
           std::chrono::steady_clock::now() < reloadDeadline) {
      state->refreshPreferences();
      std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
    require(!state->preferences_.value("number_row_selection", true),
            "runtime preferences reload in active Fcitx session");
    require(ic.statusArea().actions(fcitx::StatusGroup::InputMethod).size() == 37,
            "native status actions attached");
    require(engine.candidate_layout_action_.shortText(&ic) == "候选：横向",
            "candidate layout action reflects reloaded preference");
    engine.candidate_layout_action_.activate(&ic);
    require(state->preferences_.value("candidate_layout", std::string{}) == "vertical",
            "candidate layout action cycles to vertical");
    engine.candidate_layout_action_.activate(&ic);
    require(state->preferences_.value("candidate_layout", std::string{}) == "horizontal",
            "candidate layout action cycles back to horizontal");
    require(engine.learning_action_.isChecked(&ic),
            "learning status action reflects reloaded preference");
    engine.learning_action_.activate(&ic);
    require(!state->preferences_.value("learning", true),
            "learning status action disables user learning");
    engine.learning_action_.activate(&ic);
    require(state->preferences_.value("learning", false),
            "learning status action restores user learning");
    require(engine.mode_scope_action_.shortText(&ic) == "模式：应用",
            "mode scope action starts at application scope");
    engine.mode_scope_action_.activate(&ic);
    require(state->preferences_.value("ime_mode_scope", std::string{}) == "global",
            "mode scope action switches to global scope");
    engine.mode_scope_action_.activate(&ic);
    require(state->preferences_.value("ime_mode_scope", std::string{}) == "app",
            "mode scope action restores application scope");
    if (state->preferences_.value("cloud_candidates", false)) {
      require(engine.cloud_candidates_action_.isChecked(&ic),
              "cloud candidates status action reflects preference");
      engine.cloud_candidates_action_.activate(&ic);
      require(!state->preferences_.value("cloud_candidates", true),
              "cloud candidates status action disables live mode");
      engine.cloud_candidates_action_.activate(&ic);
      require(state->preferences_.value("cloud_candidates", false),
              "cloud candidates status action restores live mode");
    } else {
      require(!engine.cloud_candidates_action_.isChecked(&ic),
              "cloud candidates status action reflects disabled preference");
    }
    require(ic.statusArea().actions(fcitx::StatusGroup::InputMethod).size() == 37,
            "AI status action attached");
    require(engine.emoji_category_action_.shortText(&ic) == "表情：Emoji",
            "emoji category starts in the default catalog");
    engine.emoji_category_action_.activate(&ic);
    const auto kaomojiDeadline = std::chrono::steady_clock::now() + std::chrono::seconds(2);
    while ((state->emoji_category_ != "kaomoji" || state->emoji_items_.empty()) &&
           std::chrono::steady_clock::now() < kaomojiDeadline) {
      state->refreshEmoji();
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    require(state->emoji_category_ == "kaomoji" && !state->emoji_items_.empty(),
            "emoji category action loads kaomoji catalog");
    engine.emoji_category_action_.activate(&ic);
    const auto symbolsDeadline = std::chrono::steady_clock::now() + std::chrono::seconds(2);
    while (state->emoji_job_.valid() && std::chrono::steady_clock::now() < symbolsDeadline) {
      state->refreshEmoji();
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    engine.emoji_category_action_.activate(&ic);
    require(state->emoji_category_.empty(), "emoji category action cycles back to default catalog");
    const auto defaultEmojiDeadline = std::chrono::steady_clock::now() + std::chrono::seconds(2);
    while (state->emoji_job_.valid() && std::chrono::steady_clock::now() < defaultEmojiDeadline) {
      state->refreshEmoji();
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    engine.emoji_group_action_.activate(&ic);
    const auto groupsDeadline = std::chrono::steady_clock::now() + std::chrono::seconds(2);
    while (state->emoji_groups_job_.valid() && std::chrono::steady_clock::now() < groupsDeadline) {
      state->refreshEmoji();
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    require(!state->emoji_groups_.empty(), "emoji group action loads catalog groups");
    engine.emoji_group_action_.activate(&ic);
    require(!state->emoji_group_.empty(), "emoji group action selects a group");
    const bool aiEnabled = state->preferences_.value("ai_assistant", Json::object())
                               .value("enabled", false);
    require(engine.ai_candidates_action_.isChecked(&ic) == aiEnabled,
            "AI status action reflects preference");
    engine.ai_candidates_action_.activate(&ic);
    require(state->preferences_.value("ai_assistant", Json::object()).value("enabled", false) != aiEnabled,
            "AI status action toggles live mode");
    engine.ai_candidates_action_.activate(&ic);
    require(state->preferences_.value("ai_assistant", Json::object()).value("enabled", false) == aiEnabled,
            "AI status action restores live mode");
    require(engine.translation_language_action_.shortText(&ic) == "翻译：英语",
            "translation language action starts in English");
    engine.translation_language_action_.activate(&ic);
    require(state->preferences_.value("translation_target_language", std::string{}) == "fr" &&
            engine.translation_language_action_.shortText(&ic) == "翻译：法语",
            "translation language action cycles to French");
    for (int index = 0; index < 6; ++index) engine.translation_language_action_.activate(&ic);
    require(state->preferences_.value("translation_target_language", std::string{}) == "en",
            "translation language action cycles back to English");
    require(engine.punctuation_lock_action_.shortText(&ic) == "标点：跟随",
            "punctuation lock status action starts in follow mode");
    engine.punctuation_lock_action_.activate(&ic);
    require(state->punctuation_lock_ == 1 && engine.punctuation_lock_action_.shortText(&ic) == "标点：中文",
            "punctuation lock cycles to Chinese mode");
    engine.punctuation_lock_action_.activate(&ic);
    require(state->punctuation_lock_ == 2 && engine.punctuation_lock_action_.shortText(&ic) == "标点：英文",
            "punctuation lock cycles to English mode");
    engine.punctuation_lock_action_.activate(&ic);
    require(state->punctuation_lock_ == 0 && engine.punctuation_lock_action_.shortText(&ic) == "标点：跟随",
            "punctuation lock cycles back to follow mode");
    require(engine.smart_punctuation_action_.isChecked(&ic),
            "smart punctuation status action reflects preference");
    engine.smart_punctuation_action_.activate(&ic);
    require(!state->preferences_.value("smart_punctuation", true),
            "smart punctuation status action toggles live mode");
    engine.smart_punctuation_action_.activate(&ic);
    require(state->preferences_.value("smart_punctuation", false),
            "smart punctuation status action restores live mode");
    require(engine.smart_punctuation_repeat_action_.isChecked(&ic),
            "smart punctuation repeat status action reflects preference");
    engine.smart_punctuation_repeat_action_.activate(&ic);
    require(!state->preferences_.value("smart_punctuation_repeat", true),
            "smart punctuation repeat action toggles live mode");
    engine.smart_punctuation_repeat_action_.activate(&ic);
    require(state->preferences_.value("smart_punctuation_repeat", false),
            "smart punctuation repeat status action restores live mode");
    require(engine.chinese_punctuation_action_.isChecked(&ic),
            "Chinese punctuation status action reflects preference");
    engine.chinese_punctuation_action_.activate(&ic);
    require(!state->chinese_punctuation_, "Chinese punctuation status action toggles live mode");
    engine.chinese_punctuation_action_.activate(&ic);
    require(state->chinese_punctuation_, "Chinese punctuation status action restores live mode");
    require(engine.paired_punctuation_action_.isChecked(&ic),
            "paired punctuation status action reflects preference");
    engine.paired_punctuation_action_.activate(&ic);
    require(!state->paired_punctuation_, "paired punctuation status action toggles live mode");
    engine.paired_punctuation_action_.activate(&ic);
    require(state->paired_punctuation_, "paired punctuation status action restores live mode");
    require(engine.candidate_translation_action_.isChecked(&ic),
            "candidate translation status action reflects preference");
    engine.candidate_translation_action_.activate(&ic);
    require(!state->preferences_.value("candidate_translations", true),
            "candidate translation status action disables live mode");
    engine.candidate_translation_action_.activate(&ic);
    require(state->preferences_.value("candidate_translations", false),
            "candidate translation status action restores live mode");
    require(engine.maintenance_menu_.actions().size() == 8,
            "candidate maintenance menu attached");
    require(engine.clipboard_menu_.actions().size() == 11,
            "clipboard history management menu attached");
    require(engine.cloud_clipboard_menu_.actions().size() == 5,
            "cloud clipboard menu attached");
    require(engine.desktop_tools_menu_.actions().size() == 9,
            "desktop tools menu attached");
    require(engine.emoji_menu_.actions().size() == 7,
            "emoji paging menu attached");
    const auto routeScript = std::string(directory) + "/route-helper.sh";
    const auto routeOutput = std::string(directory) + "/route-output";
    std::ofstream(routeScript) << "#!/bin/sh\nprintf '%s\\n' \"$MSIME_CLIENT_ROUTE\" > \"$MSIME_TEST_ROUTE_OUTPUT\"\n";
    require(chmod(routeScript.c_str(), 0700) == 0, "desktop route helper permissions");
    setenv("MSIME_CLIENT_SETTINGS_COMMAND", routeScript.c_str(), 1);
    setenv("MSIME_TEST_ROUTE_OUTPUT", routeOutput.c_str(), 1);
    engine.handwriting_action_.activate(&ic);
    const auto routeDeadline = std::chrono::steady_clock::now() + std::chrono::seconds(2);
    while (!std::filesystem::exists(routeOutput) && std::chrono::steady_clock::now() < routeDeadline)
      std::this_thread::sleep_for(std::chrono::milliseconds(5));
    require(std::filesystem::exists(routeOutput), "desktop route helper launched");
    std::ifstream routeFile(routeOutput);
    std::string route;
    std::getline(routeFile, route);
    require(route == "handwriting", "desktop route environment propagated");
    engine.emoji_action_.activate(&ic);
    const auto emojiDeadline = std::chrono::steady_clock::now() + std::chrono::seconds(2);
    while (state->emoji_items_.empty() && std::chrono::steady_clock::now() < emojiDeadline) {
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
      state->refreshEmoji();
    }
    require(!state->emoji_items_.empty() && state->emoji_items_.size() <= 5,
            "emoji first page loaded asynchronously");
    const auto firstEmoji = state->emoji_items_.front().value("text", std::string{});
    require(!firstEmoji.empty() && !state->emoji_complete_, "emoji page exposes continuation");
    engine.emoji_next_action_.activate(&ic);
    const auto nextEmojiDeadline = std::chrono::steady_clock::now() + std::chrono::seconds(2);
    while (state->emoji_offset_ == 0 && std::chrono::steady_clock::now() < nextEmojiDeadline) {
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
      state->refreshEmoji();
    }
    require(state->emoji_offset_ > 0 && !state->emoji_items_.empty(),
            "emoji next page loaded");
    require(state->emoji_items_.front().value("text", std::string{}).size() > 0,
            "emoji pagination returns catalog entries");
    const auto beforeEmoji = ic.committed;
    engine.emoji_item1_.activate(&ic);
    require(ic.committed != beforeEmoji, "emoji menu item commits selected text");
    engine.emoji_search_action_.activate(&ic);
    require(state->emoji_search_mode_, "emoji search action enters native search mode");
    auto searchKey = [&](fcitx::KeySym sym) {
      fcitx::KeyEvent event(&ic, fcitx::Key(sym));
      engine.keyEvent(entry, event);
      return event.accepted();
    };
    require(searchKey(FcitxKey_g), "emoji search accepts ASCII query input");
    const auto searchDeadline = std::chrono::steady_clock::now() + std::chrono::seconds(2);
    while (state->emoji_items_.empty() && std::chrono::steady_clock::now() < searchDeadline) {
      state->refreshEmoji();
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    require(!state->emoji_items_.empty() && state->emoji_search_ == "g",
            "emoji search returns filtered catalog entries");
    const auto beforeSearchCommit = ic.committed;
    require(searchKey(FcitxKey_Return), "emoji search accepts selection key");
    require(ic.committed != beforeSearchCommit && !state->emoji_search_mode_,
            "emoji search commits the first result and exits");
    require(!engine.english_action_.isChecked(&ic), "English candidates initially disabled");
    require(msime_linux_simplified_to_traditional("汉语") == "漢語", "traditional conversion available");
    engine.traditional_action_.activate(&ic);
    require(state->traditional_, "traditional status action enables conversion");
    const auto traditionalSaveDeadline = std::chrono::steady_clock::now() + std::chrono::seconds(2);
    Json savedTraditional;
    while (std::chrono::steady_clock::now() < traditionalSaveDeadline) {
      state->refreshPreferences();
      savedTraditional = response(msime_client_load_preferences(
          reinterpret_cast<const uint8_t *>(preferenceDirectory.data()), preferenceDirectory.size()));
      if (savedTraditional.value("preferences", Json::object())
              .value("traditional_chinese_output", false)) break;
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    require(savedTraditional.value("preferences", Json::object())
                .value("traditional_chinese_output", false),
            "traditional status action persists preference");
    engine.traditional_action_.activate(&ic);
    require(!state->traditional_, "traditional status action disables conversion");
    engine.english_action_.activate(&ic);
    require(engine.english_action_.isChecked(&ic), "status action enables English candidates");
    engine.english_action_.activate(&ic);
    require(!engine.english_action_.isChecked(&ic), "status action disables English candidates");
    engine.width_action_.activate(&ic);
    require(engine.width_action_.isChecked(&ic), "status action enables fullwidth");
    engine.width_action_.activate(&ic);
    require(!engine.width_action_.isChecked(&ic), "status action restores halfwidth");
    engine.input_mode_action_.activate(&ic);
    require(!state->input_enabled_, "input mode action disables Chinese input");
    fcitx::KeyEvent passthrough(&ic, fcitx::Key(FcitxKey_n));
    engine.keyEvent(entry, passthrough);
    require(!passthrough.accepted(), "disabled input mode passes keys through");
    engine.input_mode_action_.activate(&ic);
    require(state->input_enabled_, "input mode action restores Chinese input");
    const auto key = [&](fcitx::KeySym sym) {
      fcitx::KeyEvent event(&ic, fcitx::Key(sym));
      engine.keyEvent(entry, event);
      return event.accepted();
    };
    require(key(FcitxKey_n) && key(FcitxKey_i), "composition keys");
    require(ic.inputPanel().clientPreedit().toString() == "ni", "native preedit");
    auto horizontalPage = ic.inputPanel().candidateList();
    require(horizontalPage && horizontalPage->layoutHint() == fcitx::CandidateLayoutHint::Horizontal,
            "hot-loaded horizontal layout reaches native candidate list");
    ic.focusOut();
    require(state->session_ == 0, "focus out destroys host session");
    require(ic.inputPanel().clientPreedit().empty(), "focus out clears preedit");
    ic.focusIn();
    engine.activate(entry, focus);
    require(state->session_ != 0, "focus in creates a fresh host session");
    for (const auto sym : {FcitxKey_n, FcitxKey_i, FcitxKey_h, FcitxKey_a, FcitxKey_o,
                           FcitxKey_j, FcitxKey_i, FcitxKey_e})
      require(key(sym), "composition after refocus");
    const auto onlineQuery = response(msime_client_online_query(state->session_));
    state->refreshClipboard();
    const auto clipboardDeadline = std::chrono::steady_clock::now() + std::chrono::seconds(2);
    while (state->clipboard_items_.empty() && std::chrono::steady_clock::now() < clipboardDeadline) {
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
      state->refreshClipboard();
    }
    require(!state->clipboard_items_.empty(), "clipboard history loaded asynchronously");
    const auto beforeClipboard = ic.committed;
    engine.clipboard_action_.activate(&ic);
    require(ic.committed == beforeClipboard + "剪贴板合成测试", "clipboard action commits newest history");
    engine.clipboard_remove1_.activate(&ic);
    const auto removeClipboardDeadline = std::chrono::steady_clock::now() + std::chrono::seconds(2);
    while (std::any_of(state->clipboard_items_.begin(), state->clipboard_items_.end(),
                       [](const Json &item) { return (item.is_string() ? item.get<std::string>() : item.value("text", std::string{})) == "剪贴板合成测试"; }) &&
           std::chrono::steady_clock::now() < removeClipboardDeadline) {
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
      state->refreshClipboard();
    }
    require(std::none_of(state->clipboard_items_.begin(), state->clipboard_items_.end(),
                         [](const Json &item) { return (item.is_string() ? item.get<std::string>() : item.value("text", std::string{})) == "剪贴板合成测试"; }),
            "clipboard remove action updates history");
    engine.clipboard_clear_action_.activate(&ic);
    const auto clearClipboardDeadline = std::chrono::steady_clock::now() + std::chrono::seconds(2);
    while (!state->clipboard_items_.empty() && std::chrono::steady_clock::now() < clearClipboardDeadline) {
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
      state->refreshClipboard();
    }
    require(state->clipboard_items_.empty(), "clipboard clear action updates history");
    engine.cloud_clipboard_action_.activate(&ic);
    const auto cloudDeadline = std::chrono::steady_clock::now() + std::chrono::seconds(2);
    while (ic.committed.find("云剪贴板测试") == std::string::npos &&
           std::chrono::steady_clock::now() < cloudDeadline) {
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
      engine.cloud_clipboard_action_.activate(&ic);
    }
    require(ic.committed.find("云剪贴板测试") != std::string::npos, "cloud clipboard action commits provider entry");
    require(cloudProvider.get(), "cloud clipboard socket protocol");
    const auto beforeCloudSecond = ic.committed;
    engine.cloud_clipboard_item2_.activate(&ic);
    require(ic.committed == beforeCloudSecond + "云剪贴板第二条",
            "cloud clipboard menu commits selected provider entry");
    fcitx::KeyEvent voiceHotkey(&ic,
        fcitx::Key(FcitxKey_F9, fcitx::KeyStates{fcitx::KeyState::Ctrl}));
    engine.keyEvent(entry, voiceHotkey);
    require(voiceHotkey.accepted(), "Ctrl+F9 starts voice input");
    bool observedVoicePartial = false;
    const auto voiceDeadline = std::chrono::steady_clock::now() + std::chrono::seconds(2);
    while (ic.committed.find("语音测试") == std::string::npos &&
           std::chrono::steady_clock::now() < voiceDeadline) {
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
      if (state->voice_mailbox_) {
        std::lock_guard lock(state->voice_mailbox_->mutex);
        observedVoicePartial = observedVoicePartial || state->voice_mailbox_->partial == "语音中";
      }
      state->refreshVoice();
    }
    require(observedVoicePartial || state->voice_partial_seen_, "voice action receives provider partial text");
    require(state->voice_phase_seen_ && state->voice_level_seen_,
            "voice action receives provider status and level");
    require(ic.committed.find("语音测试") != std::string::npos, "voice action commits provider text");
    require(voiceProvider.get(), "voice socket protocol");
    if (ai) {
      require(onlineQuery.value("ai_eligible", false), "AI query eligible");
      require(onlineQuery.at("ai_assistant").value("enabled", false), "AI provider enabled");
      require(!onlineQuery.at("cloud_candidates").get<bool>(), "cloud disabled for AI-only test");
    }
    require(!state->online_socket_.empty(), "AI provider socket configured");
    const auto onlineDeadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
    while (response(msime_client_all_candidates(state->session_)).dump().find(suggestion) == std::string::npos &&
           std::chrono::steady_clock::now() < onlineDeadline) {
      state->refreshOnline();
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    require(response(msime_client_all_candidates(state->session_)).dump().find(suggestion) != std::string::npos,
            "provider candidate applied to full candidate list");
    provider.join();
    auto page = ic.inputPanel().candidateList();
    require(page && page->layoutHint() == fcitx::CandidateLayoutHint::Vertical,
            "bootstrap vertical layout reaches native candidate list");
    require(horizontalPage->layoutHint() == fcitx::CandidateLayoutHint::Horizontal,
            "previous candidate page retains its layout snapshot");
    require(page && page->size() == 2 && page->toPageable()->hasNext(), "runtime candidate page");
    require(key(FcitxKey_KP_End), "keypad end candidate navigation");
    require(key(FcitxKey_KP_Home), "keypad home candidate navigation");
    require(key(FcitxKey_Page_Down), "page down");
    const auto oldCommit = ic.committed;
    page->candidate(0).select(&ic);
    require(ic.committed == oldCommit, "stale page must not commit");
    require(key(FcitxKey_Page_Up), "return to first page");
    bool selected = false;
    for (int pages = 0; pages < 100 && !selected; ++pages) {
      page = ic.inputPanel().candidateList();
      for (int i = 0; i < page->size(); ++i) {
        const auto displayed = page->candidate(i).text().toString();
        if (displayed.rfind(suggestion, 0) == 0) {
          page->candidate(i).select(&ic);
          selected = true;
          break;
        }
      }
      if (!selected) {
        require(page->toPageable()->hasNext(), "provider candidate reachable by paging");
        require(key(FcitxKey_Page_Down), "page to provider candidate");
      }
    }
    require(selected && ic.committed == oldCommit + suggestion, "exact provider candidate commit");
    require(key(FcitxKey_n) && key(FcitxKey_i), "second composition keys");
    const auto beforeWordCharacter = ic.committed;
    require(key(FcitxKey_bracketleft), "configured word-to-character binding");
    require(ic.committed != beforeWordCharacter, "word-to-character commits selected edge");
    require(key(FcitxKey_n) && key(FcitxKey_i), "third composition keys");
    require(key(FcitxKey_KP_1), "keypad candidate selection");
    require(!ic.committed.empty(), "keypad selection commits candidate");
    require(key(FcitxKey_n) && key(FcitxKey_i), "fourth composition keys");
    require(key(FcitxKey_minus), "configured minus previous-page binding");
    require(key(FcitxKey_equal), "configured equal next-page binding");
    require(key(FcitxKey_Escape), "cancel after navigation");
    const auto beforePunctuation = ic.committed;
    ic.surroundingText().setText("😀A", 2, 2);
    require(!key(FcitxKey_comma), "ASCII punctuation remains with editor");
    require(ic.committed == beforePunctuation, "ASCII pass-through must not also commit");
    ic.surroundingText().setText("A😀", 2, 2);
    require(key(FcitxKey_comma), "non-ASCII surrounding context");
    require(ic.committed == beforePunctuation + "，", "Unicode scalar cursor context");
    require(key(FcitxKey_n), "restart composition");
    ic.setCapabilityFlags(fcitx::CapabilityFlag::Password);
    require(state->session_ == 0, "password capability immediately closes session");
    engine.english_action_.activate(&ic);
    require(state->session_ == 0, "status action cannot reopen password context");
    require(ic.inputPanel().clientPreedit().empty(), "password immediately clears preedit");
    require(!key(FcitxKey_i) && state->session_ == 0, "password context closes session");
    require(ic.inputPanel().clientPreedit().empty(), "password clears preedit");
    ic.setCapabilityFlags(fcitx::CapabilityFlag::Preedit);
    require(key(FcitxKey_n), "normal input resumes after restricted context");
    ic.setCapabilityFlags(fcitx::CapabilityFlags{fcitx::CapabilityFlag::Preedit,
                                               fcitx::CapabilityFlag::Sensitive});
    require(state->session_ == 0, "privacy transition closes old session immediately");
    require(ic.inputPanel().clientPreedit().empty(), "privacy transition clears previous composition");
    require(key(FcitxKey_n), "private context can compose");
    require(!state->preferences_.at("learning").get<bool>() &&
            !state->preferences_.at("cloud_candidates").get<bool>() &&
            !state->preferences_.at("ai_assistant").at("enabled").get<bool>(),
            "private context disables learning and remote candidates");
    ic.setCapabilityFlags(fcitx::CapabilityFlag::NoFlag);
    require(state->session_ == 0, "leaving private context invalidates session");
    require(key(FcitxKey_n), "panel preedit composition");
    require(ic.inputPanel().preedit().toString() == "n", "server preedit without client support");
    ic.setCapabilityFlags(fcitx::CapabilityFlag::Preedit);
    require(ic.inputPanel().preedit().empty() &&
            ic.inputPanel().clientPreedit().toString() == "n", "capability moves active preedit to client");
    state->close();
    state->clearPanel();
    auto capsEvent = fcitx::KeyEvent(&ic,
        fcitx::Key(FcitxKey_A, fcitx::KeyStates{fcitx::KeyState::CapsLock}));
    engine.keyEvent(entry, capsEvent);
    require(!capsEvent.accepted(), "CapsLock uppercase passes through idle editor");
    require(state->view_.value("editing_text", std::string{}).empty(),
            "CapsLock does not begin composition");
    state->close();
    state->clearPanel();
    // Real translation socket: no HTTP, credentials, or user input in this fixture.
    const auto translationPath = std::string(directory) + "/translation.sock";
    const int translationServer = socket(AF_UNIX, SOCK_STREAM, 0);
    require(translationServer >= 0, "translation socket");
    sockaddr_un translationAddress{};
    translationAddress.sun_family = AF_UNIX;
    std::strncpy(translationAddress.sun_path, translationPath.c_str(), sizeof(translationAddress.sun_path) - 1);
    require(bind(translationServer, reinterpret_cast<sockaddr *>(&translationAddress), sizeof(translationAddress)) == 0 &&
            listen(translationServer, 1) == 0, "translation listener");
    auto translationProvider = std::async(std::launch::async, [translationServer] {
      struct Descriptor { int fd; ~Descriptor() { if (fd >= 0) close(fd); } } server{translationServer};
      pollfd ready{server.fd, POLLIN, 0};
      if (poll(&ready, 1, 5000) <= 0) return false;
      Descriptor client{accept(server.fd, nullptr, nullptr)};
      if (client.fd < 0) return false;
      std::string request;
      const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(2);
      while (request.size() < 16384 && request.find('\n') == std::string::npos &&
             std::chrono::steady_clock::now() < deadline) {
        pollfd readable{client.fd, POLLIN, 0};
        if (poll(&readable, 1, 100) <= 0) continue;
        char buffer[1024];
        const auto count = read(client.fd, buffer, sizeof(buffer));
        if (count <= 0) return false;
        request.append(buffer, count);
      }
      const auto document = Json::parse(request);
      if (document.at("kind") != "translation" || document.at("query").at("target_language") != "en") return false;
      const auto &texts = document.at("query").at("candidates");
      if (texts.empty() || !texts.at(0).is_string()) return false;
      const auto reply = Json{{"translations", Json::array({
          Json{{"text", texts.at(0)}, {"translation", "synthetic-gloss"}}})}}.dump() + "\n";
      return send(client.fd, reply.data(), reply.size(), MSG_NOSIGNAL) == static_cast<ssize_t>(reply.size());
    });
    options["translation_provider_socket"] = translationPath;
    options["preferences"]["candidate_translations"] = true;
    options["preferences"]["candidate_english_gloss"] = false;
    options["preferences"]["translation_target_language"] = "en";
    std::ofstream(path) << options.dump();
    require(key(FcitxKey_n) && key(FcitxKey_i), "translation composition");
    state->refreshTranslations();
    require(!state->translation_job_.valid(), "translation waits for idle debounce");
    const auto translationDeadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
    while (state->view_.at("candidates").dump().find("synthetic-gloss") == std::string::npos &&
           std::chrono::steady_clock::now() < translationDeadline) {
      state->refreshTranslations();
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    require(translationProvider.get(), "translation socket protocol");
    require(ic.inputPanel().candidateList()->candidate(0).text().toString().find("synthetic-gloss") != std::string::npos,
            "translation visible in native Fcitx candidate");
    const auto glossPath = std::filesystem::path(options.at("user_data").get<std::string>()) /
                           "translation-glosses.db";
    require(std::filesystem::exists(glossPath), "English translation gloss database exists");
    std::ifstream glossFile(glossPath);
    const std::string glossContent((std::istreambuf_iterator<char>(glossFile)),
                                   std::istreambuf_iterator<char>());
    require(glossContent.find("synthetic-gloss") != std::string::npos,
            "English translation gloss is persisted");
    const auto translatedText = state->view_.at("candidates").at(0).at("text").get<std::string>();
    const auto beforeTranslatedCommit = ic.committed;
    ic.inputPanel().candidateList()->candidate(0).select(&ic);
    require(ic.committed == beforeTranslatedCommit + translatedText, "gloss excluded from committed text");
    state->close();
    state->clearPanel();
    options["preferences"]["scheme"] = "japanese";
    std::ofstream(path) << options.dump();
    require(key(FcitxKey_k) && key(FcitxKey_o), "Japanese romaji composition");
    require(state->view_.at("scheme") == 3, "Engine Japanese scheme active");
    require(key(FcitxKey_minus), "Japanese long vowel key");
    require(state->view_.at("editing_text") == "ko-", "minus extends romaji instead of paging");
    require(state->view_.at("reading") == "こー", "Engine resolves Japanese long vowel");
    require(key(FcitxKey_Escape), "cancel Japanese composition");
    state->close();
    state->clearPanel();
    std::filesystem::remove_all(directory);
    std::cout << "Fcitx5 native context tests passed\n";
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
