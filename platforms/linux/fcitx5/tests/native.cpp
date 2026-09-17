// Real Fcitx input contexts and the real Host API. All input is synthetic.
#include "../FcitxEngine.cpp"
#include <iostream>
#include <filesystem>
#include <thread>
#include <chrono>

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
    require(argc == 2, "usage: fcitx5-native-test <verified-resources>");
    char temporary[] = "/tmp/msime-fcitx5-test-XXXXXX";
    const auto *directory = mkdtemp(temporary);
    require(directory != nullptr, "fixture directory");
    const auto request = Json{{"resources", argv[1]}, {"state_root", directory}}.dump();
    auto options = response(msime_client_prepare_host(
        reinterpret_cast<const uint8_t *>(request.data()), request.size()));
    options["preferences"]["learning"] = false;
    options["preferences"]["candidate_page_size"] = 2;
    const auto path = std::string(directory) + "/runtime-options.json";
    std::ofstream(path) << options.dump();
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
    state->refreshPreferences();
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
    state->refreshPreferences();
    require(!state->preferences_.value("number_row_selection", true),
            "runtime preferences reload in active Fcitx session");
    require(ic.statusArea().actions(fcitx::StatusGroup::InputMethod).size() == 2,
            "native status actions attached");
    require(!engine.english_action_.isChecked(&ic), "English candidates initially disabled");
    engine.english_action_.activate(&ic);
    require(engine.english_action_.isChecked(&ic), "status action enables English candidates");
    engine.english_action_.activate(&ic);
    require(!engine.english_action_.isChecked(&ic), "status action disables English candidates");
    engine.width_action_.activate(&ic);
    require(engine.width_action_.isChecked(&ic), "status action enables fullwidth");
    engine.width_action_.activate(&ic);
    require(!engine.width_action_.isChecked(&ic), "status action restores halfwidth");
    const auto key = [&](fcitx::KeySym sym) {
      fcitx::KeyEvent event(&ic, fcitx::Key(sym));
      engine.keyEvent(entry, event);
      return event.accepted();
    };
    require(key(FcitxKey_n) && key(FcitxKey_i), "composition keys");
    require(ic.inputPanel().clientPreedit().toString() == "ni", "native preedit");
    ic.focusOut();
    require(state->session_ == 0, "focus out destroys host session");
    require(ic.inputPanel().clientPreedit().empty(), "focus out clears preedit");
    ic.focusIn();
    engine.activate(entry, focus);
    require(state->session_ != 0, "focus in creates a fresh host session");
    require(key(FcitxKey_n) && key(FcitxKey_i), "composition after refocus");
    auto page = ic.inputPanel().candidateList();
    require(page && page->size() == 2 && page->toPageable()->hasNext(), "runtime candidate page");
    require(key(FcitxKey_Page_Down), "page down");
    const auto oldCommit = ic.committed;
    page->candidate(0).select(&ic);
    require(ic.committed == oldCommit, "stale page must not commit");
    page = ic.inputPanel().candidateList();
    page->candidate(0).select(&ic);
    require(!ic.committed.empty(), "native candidate selection");
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
