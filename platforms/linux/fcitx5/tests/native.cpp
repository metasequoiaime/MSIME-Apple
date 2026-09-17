// Real Fcitx input contexts and the real Host API. All input is synthetic.
#include "../FcitxEngine.cpp"
#include <iostream>
#include <filesystem>

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
    const auto key = [&](fcitx::KeySym sym) {
      fcitx::KeyEvent event(&ic, fcitx::Key(sym));
      engine.keyEvent(entry, event);
      return event.accepted();
    };
    require(key(FcitxKey_n) && key(FcitxKey_i), "composition keys");
    require(ic.inputPanel().clientPreedit().toString() == "ni", "native preedit");
    auto page = ic.inputPanel().candidateList();
    require(page && page->size() == 2 && page->toPageable()->hasNext(), "runtime candidate page");
    require(key(FcitxKey_Page_Down), "page down");
    const auto oldCommit = ic.committed;
    page->candidate(0).select(&ic);
    require(ic.committed == oldCommit, "stale page must not commit");
    page = ic.inputPanel().candidateList();
    page->candidate(0).select(&ic);
    require(!ic.committed.empty(), "native candidate selection");
    const auto beforePunctuation = ic.committed;
    ic.surroundingText().setText("😀A", 2, 2);
    require(!key(FcitxKey_comma), "ASCII punctuation remains with editor");
    require(ic.committed == beforePunctuation, "ASCII pass-through must not also commit");
    ic.surroundingText().setText("A😀", 2, 2);
    require(key(FcitxKey_comma), "non-ASCII surrounding context");
    require(ic.committed == beforePunctuation + "，", "Unicode scalar cursor context");
    require(key(FcitxKey_n), "restart composition");
    ic.setCapabilityFlags(fcitx::CapabilityFlag::Password);
    require(!key(FcitxKey_i) && state->session_ == 0, "password context closes session");
    require(ic.inputPanel().clientPreedit().empty(), "password clears preedit");
    std::filesystem::remove_all(directory);
    std::cout << "Fcitx5 native context tests passed\n";
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
