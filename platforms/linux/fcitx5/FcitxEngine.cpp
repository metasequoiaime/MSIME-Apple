#include "msime_client.h"
#include <fcitx-utils/capabilityflags.h>
#include <fcitx-utils/key.h>
#include <fcitx/addonfactory.h>
#include <fcitx/addonmanager.h>
#include <fcitx/candidatelist.h>
#include <fcitx/inputcontext.h>
#include <fcitx/inputcontextmanager.h>
#include <fcitx/inputcontextproperty.h>
#include <fcitx/inputmethodengine.h>
#include <fcitx/inputpanel.h>
#include <fcitx/instance.h>
#include <fcitx/surroundingtext.h>
#include <fcitx/userinterface.h>
#include <nlohmann/json.hpp>
#include <algorithm>
#include <array>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <memory>
#include <stdexcept>

#ifndef MSIME_SYSTEM_OPTIONS
#define MSIME_SYSTEM_OPTIONS "/etc/msime-client/runtime-options.json"
#endif

namespace msime::fcitx_host {
using Json = nlohmann::json;
class FcitxEngine;

// ABI buffers and errors never escape into diagnostics or the panel.
Json response(char *raw) {
  std::unique_ptr<char, decltype(&msime_client_string_free)> owned(raw, msime_client_string_free);
  if (!raw) throw std::runtime_error("MSIME request failed");
  auto value = Json::parse(raw);
  if (!value.value("ok", false)) throw std::runtime_error("MSIME request failed");
  return value.at("value");
}

Json readOptions() {
  std::filesystem::path path;
  if (const auto *overridePath = std::getenv("MSIME_FCITX5_OPTIONS")) {
    path = overridePath;
  } else {
    const auto *config = std::getenv("XDG_CONFIG_HOME");
    const auto *home = std::getenv("HOME");
    path = config && *config ? std::filesystem::path(config) :
           home && *home ? std::filesystem::path(home) / ".config" : std::filesystem::path();
    if (!path.is_absolute()) throw std::runtime_error("MSIME configuration unavailable");
    path /= "msime-client/runtime-options.json";
    if (!std::filesystem::exists(path) && !std::filesystem::is_symlink(path))
      path = MSIME_SYSTEM_OPTIONS;
  }
  if (!path.is_absolute()) throw std::runtime_error("MSIME configuration unavailable");
  std::ifstream file(path);
  std::array<char, 16385> data{};
  file.read(data.data(), data.size());
  if (file.bad() || file.gcount() <= 0 || file.gcount() >= static_cast<std::streamsize>(data.size()))
    throw std::runtime_error("MSIME configuration unavailable");
  return Json::parse(data.data(), data.data() + file.gcount());
}

class FcitxState : public fcitx::InputContextProperty {
public:
  explicit FcitxState(fcitx::InputContext &ic, FcitxEngine *engine) : ic_(ic), engine_(engine) {}
  ~FcitxState() override { close(); }
  void close() {
    if (session_) msime_client_string_free(msime_client_destroy(session_));
    session_ = 0;
    view_ = Json::object();
  }
  void clearPanel() {
    ic_.inputPanel().reset();
    ic_.updatePreedit();
    ic_.updateUserInterface(fcitx::UserInterfaceComponent::InputPanel);
  }
  bool restricted() const {
    return ic_.capabilityFlags().testAny(fcitx::CapabilityFlags{
      fcitx::CapabilityFlag::Password, fcitx::CapabilityFlag::Digit,
      fcitx::CapabilityFlag::Number, fcitx::CapabilityFlag::Dialable,
      fcitx::CapabilityFlag::Disable});
  }
  bool privateInput() const {
    return ic_.capabilityFlags().testAny(fcitx::CapabilityFlags{
      fcitx::CapabilityFlag::Sensitive, fcitx::CapabilityFlag::NoSpellCheck});
  }
  bool ensure() {
    if (!ic_.hasFocus() || restricted()) { close(); clearPanel(); return false; }
    if (session_ && private_ != privateInput()) { close(); clearPanel(); }
    if (session_) return true;
    auto options = readOptions();
    private_ = privateInput();
    preferences_ = options.value("preferences", Json::object());
    if (private_) {
      preferences_["learning"] = false;
      preferences_["cloud_candidates"] = false;
      options["preferences"] = preferences_;
    }
    const auto document = options.dump();
    view_ = response(msime_client_create(reinterpret_cast<const uint8_t *>(document.data()), document.size()));
    session_ = view_.at("session").get<uint64_t>();
    view_ = response(msime_client_focus(session_, true));
    return true;
  }
  bool apply(char *raw) {
    auto result = response(raw);
    if (result.contains("commit") && result["commit"].is_string())
      ic_.commitString(result["commit"].get<std::string>());
    view_ = result.contains("view") ? result.at("view") : result;
    render();
    return result.value("handled", false);
  }
  bool command(uint32_t command) { return apply(msime_client_command(session_, command)); }
  void select(uint64_t session, uint64_t generation, size_t index) {
    if (!ensure() || session_ != session || view_.value("generation", uint64_t{}) != generation) return;
    apply(msime_client_select(session_, generation, index));
  }
  void render();
  bool key(fcitx::KeyEvent &event);
  uint64_t session_ = 0;
  Json view_ = Json::object();
  Json preferences_ = Json::object();
  fcitx::InputContext &ic_;
  FcitxEngine *engine_;
  bool private_ = false;
};

class FcitxCandidate : public fcitx::CandidateWord {
public:
  FcitxCandidate(fcitx::FactoryFor<FcitxState> *factory, const Json &candidate)
      : CandidateWord(fcitx::Text(candidate.at("text").get<std::string>() +
          (candidate.value("annotation", std::string()).empty() ? "" :
           "  " + candidate.at("annotation").get<std::string>()))), factory_(factory),
        session_(candidate.at("id").at("session")), generation_(candidate.at("id").at("generation")),
        index_(candidate.at("id").at("index")) {}
  void select(fcitx::InputContext *ic) const override {
    try { ic->propertyFor(factory_)->select(session_, generation_, index_); } catch (...) {}
  }
private:
  fcitx::FactoryFor<FcitxState> *factory_;
  uint64_t session_, generation_;
  size_t index_;
};

// The runtime already pages candidates. Never page its current page a second time.
class FcitxPage : public fcitx::CandidateList, public fcitx::PageableCandidateList {
public:
  FcitxPage(FcitxState &state, fcitx::FactoryFor<FcitxState> *factory) : state_(state),
      session_(state.session_), generation_(state.view_.at("generation")),
      page_(state.view_.at("page")), pages_(state.view_.at("page_count")) {
    setPageable(this);
    for (const auto &candidate : state.view_.at("candidates")) {
      if (candidate.value("highlighted", false)) cursor_ = words_.size();
      words_.push_back(std::make_unique<FcitxCandidate>(factory, candidate));
      labels_.emplace_back(std::to_string(words_.size()) + ". ");
    }
  }
  const fcitx::Text &label(int index) const override { return labels_.at(index); }
  const fcitx::CandidateWord &candidate(int index) const override { return *words_.at(index); }
  int size() const override { return words_.size(); }
  int cursorIndex() const override { return cursor_; }
  fcitx::CandidateLayoutHint layoutHint() const override { return fcitx::CandidateLayoutHint::Vertical; }
  bool hasPrev() const override { return page_ > 0; }
  bool hasNext() const override { return page_ + 1 < pages_; }
  bool usedNextBefore() const override { return page_ > 0; }
  int totalPages() const override { return pages_; }
  int currentPage() const override { return page_; }
  void prev() override { move(MSIME_PREVIOUS_PAGE); }
  void next() override { move(MSIME_NEXT_PAGE); }
private:
  void move(uint32_t command) {
    // render() replaces this list. Do not access members after dispatch.
    try {
      if (state_.ensure() && state_.session_ == session_ &&
          state_.view_.value("generation", uint64_t{}) == generation_)
        state_.command(command);
    } catch (...) {}
  }
  FcitxState &state_;
  uint64_t session_, generation_;
  int page_, pages_, cursor_ = -1;
  std::vector<std::unique_ptr<FcitxCandidate>> words_;
  std::vector<fcitx::Text> labels_;
};

// Each context owns a thread-bound Host API session. Fcitx never copies composing state.
class FcitxEngine : public fcitx::InputMethodEngine {
public:
  explicit FcitxEngine(fcitx::Instance *instance) {
    instance->inputContextManager().registerProperty("msimeState", &factory_);
  }
  void activate(const fcitx::InputMethodEntry &, fcitx::InputContextEvent &event) override {
    auto *state = event.inputContext()->propertyFor(&factory_);
    try { if (state->ensure()) state->render(); } catch (...) { unavailable(*state); }
  }
  void deactivate(const fcitx::InputMethodEntry &, fcitx::InputContextEvent &event) override {
    auto *state = event.inputContext()->propertyFor(&factory_);
    state->close(); state->clearPanel();
  }
  void reset(const fcitx::InputMethodEntry &, fcitx::InputContextEvent &event) override {
    auto *state = event.inputContext()->propertyFor(&factory_);
    try { if (state->session_) state->command(MSIME_CANCEL); } catch (...) { state->close(); }
    state->clearPanel();
  }
  void keyEvent(const fcitx::InputMethodEntry &, fcitx::KeyEvent &event) override {
    auto *state = event.inputContext()->propertyFor(&factory_);
    try { if (state->ensure() && state->key(event)) event.filterAndAccept(); }
    catch (...) { unavailable(*state); }
  }
  static void unavailable(FcitxState &state) {
    state.close(); state.clearPanel();
    state.ic_.inputPanel().setAuxUp(fcitx::Text("MSIME：请检查运行配置"));
    state.ic_.updateUserInterface(fcitx::UserInterfaceComponent::InputPanel);
  }
  fcitx::FactoryFor<FcitxState> factory_{[this](fcitx::InputContext &ic) { return new FcitxState(ic, this); }};
};

void FcitxState::render() {
  ic_.inputPanel().reset();
  const auto editing = view_.value("editing_text", std::string());
  fcitx::Text preedit(editing, fcitx::TextFormatFlag::Underline);
  preedit.setCursor(std::min(editing.size(), view_.value("caret_position", size_t{})));
  if (ic_.capabilityFlags().test(fcitx::CapabilityFlag::Preedit))
    ic_.inputPanel().setClientPreedit(preedit);
  else ic_.inputPanel().setPreedit(preedit);
  if (!view_.at("candidates").empty()) {
    // Look up the registered factory via the owning engine for stable candidate callbacks.
    if (engine_) ic_.inputPanel().setCandidateList(std::make_unique<FcitxPage>(*this, &engine_->factory_));
    ic_.inputPanel().setAuxDown(fcitx::Text(std::to_string(view_.at("page").get<int>() + 1) +
        "/" + std::to_string(view_.at("page_count").get<int>())));
  }
  ic_.updatePreedit();
  ic_.updateUserInterface(fcitx::UserInterfaceComponent::InputPanel);
}

bool FcitxState::key(fcitx::KeyEvent &event) {
  const auto &key = event.key();
  if (event.isRelease() || key.isModifier()) return false;
  const bool composing = !view_.value("editing_text", std::string()).empty();
  if (key.states().testAny(fcitx::KeyStates{fcitx::KeyState::Ctrl, fcitx::KeyState::Alt,
                                         fcitx::KeyState::Super, fcitx::KeyState::Hyper})) {
    if (composing) command(MSIME_CANCEL);
    return false;
  }
  const auto sym = key.sym();
  if (composing) {
    switch (sym) {
    case FcitxKey_Escape: return command(MSIME_CANCEL);
    case FcitxKey_BackSpace: return command(MSIME_BACKSPACE);
    case FcitxKey_Delete: case FcitxKey_KP_Delete: return command(MSIME_DELETE_FORWARD);
    case FcitxKey_Return: case FcitxKey_KP_Enter: return command(MSIME_COMMIT_RAW);
    case FcitxKey_space: return command(MSIME_COMMIT_CANDIDATE);
    case FcitxKey_Left: case FcitxKey_KP_Left: return command(MSIME_MOVE_LEFT);
    case FcitxKey_Right: case FcitxKey_KP_Right: return command(MSIME_MOVE_RIGHT);
    case FcitxKey_Home: return command(MSIME_FIRST_CANDIDATE_ON_PAGE);
    case FcitxKey_End: return command(MSIME_LAST_CANDIDATE_ON_PAGE);
    case FcitxKey_Page_Up: return command(MSIME_PREVIOUS_PAGE);
    case FcitxKey_Page_Down: return command(MSIME_NEXT_PAGE);
    case FcitxKey_Up: return command(MSIME_PREVIOUS_CANDIDATE);
    case FcitxKey_Down: return command(MSIME_NEXT_CANDIDATE);
    default: break;
    }
    if (sym >= FcitxKey_1 && sym <= FcitxKey_9 && !view_.value("nine_key", false) &&
        preferences_.value("number_row_selection", true)) {
      const size_t index = sym - FcitxKey_1;
      if (index < view_.at("candidates").size()) {
        const auto id = view_.at("candidates").at(index).at("id");
        return apply(msime_client_select(session_, id.at("generation"), id.at("index")));
      }
      return false;
    }
  }
  const auto text = fcitx::Key::keySymToUTF8(sym);
  if (text.size() == 1 && text[0] >= 0x20 && text[0] <= 0x7e)
    return apply(msime_client_character(session_, static_cast<uint8_t>(text[0]), key.states().test(fcitx::KeyState::Shift)));
  if (composing) command(MSIME_FINISH_COMPOSITION);
  return false;
}

class FcitxFactory : public fcitx::AddonFactory {
public:
  fcitx::AddonInstance *create(fcitx::AddonManager *manager) override { return new FcitxEngine(manager->instance()); }
};
} // namespace msime::fcitx_host

FCITX_ADDON_FACTORY(msime::fcitx_host::FcitxFactory)
