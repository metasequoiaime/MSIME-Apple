#include "PublicSessionTestOptions.h"
#include "../src/InputControllerKeyRouting.h"
#include "../src/CandidatePanelStyle.h"
#include "../src/CandidatePageSize.h"
#include "../src/CandidateFontSize.h"
#include "../src/CandidateDisplay.h"
#include "../src/InputModeRouting.h"
#include "../src/FullWidthInput.h"
#include "../src/HelpcodeSchemaPreference.h"
#include "../src/InputSchemePreference.h"
#include "../src/CandidateTranslationLanguage.h"
#include "../src/WubiCommitPolicy.h"
#include "../../../vendor/MetasequoiaImeEngine/contracts/punctuation/policy.h"

#import <InputMethodKit/InputMethodKit.h>

#include <Carbon/Carbon.h>
#include <sqlite3.h>

#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <initializer_list>
#include <cstring>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>

namespace
{
class Database
{
  public:
    explicit Database(const std::filesystem::path &path)
    {
        if (sqlite3_open(path.c_str(), &database_) != SQLITE_OK)
        {
            throw std::runtime_error("Failed to create the Wubi routing test dictionary.");
        }
    }

    ~Database()
    {
        sqlite3_close(database_);
    }

    void execute(const char *sql)
    {
        char *error = nullptr;
        if (sqlite3_exec(database_, sql, nullptr, nullptr, &error) != SQLITE_OK)
        {
            const std::string message = error == nullptr ? "SQLite operation failed." : error;
            sqlite3_free(error);
            throw std::runtime_error(message);
        }
    }

  private:
    sqlite3 *database_ = nullptr;
};

void require(bool condition, const char *message)
{
    if (!condition)
    {
        throw std::runtime_error(message);
    }
}
} // namespace

int main()
{
    using metasequoia::mac::CandidateDisplayText;
    using metasequoia::mac::CandidatePageEnd;
    using metasequoia::mac::CandidatePageShortcut;
    using metasequoia::mac::CandidatePageSizeForOptionIndex;
    using metasequoia::mac::CandidatePageSizeOptionIndex;
    using metasequoia::mac::CandidatePageStart;
    using metasequoia::mac::CandidatePanelStyle;
    using metasequoia::mac::CandidatePanelTypeForStyle;
    using metasequoia::mac::CandidateSelectionKeys;
    using metasequoia::mac::ClassifyControllerKey;
    using metasequoia::mac::ControllerKeyAction;
    using metasequoia::mac::EngineSchemeForStoredPreference;
    using metasequoia::mac::IsInputModeToggle;
    using metasequoia::mac::IsPrimaryCandidateDirection;
    using metasequoia::mac::NormalizeCandidatePageSize;
    using metasequoia::mac::NormalizeCandidatePanelStyle;
    using metasequoia::mac::NormalizeStoredInputScheme;

    using metasequoia::mac::ClassifyConfiguredControllerKey;
    metasequoia::mac::CandidateKeyOptions keys{true, true, true, true, true, false};
    for (char key : std::string("-,["))
        require(ClassifyConfiguredControllerKey(0, true, keys, key, false) == ControllerKeyAction::MoveCandidatePageUp,
                "Enabled paging combinations must coexist.");
    for (char key : std::string("=.]"))
        require(ClassifyConfiguredControllerKey(0, true, keys, key, false) ==
                    ControllerKeyAction::MoveCandidatePageDown,
                "Enabled next-page combinations must coexist.");
    keys.edgeSelection = true;
    require(ClassifyConfiguredControllerKey(0, true, keys, '[', false) == ControllerKeyAction::CommitFirstHan &&
                ClassifyConfiguredControllerKey(0, true, keys, ']', false) == ControllerKeyAction::CommitLastHan,
            "Edge selection must take priority over conflicting bracket paging.");
    require(ClassifyConfiguredControllerKey(0, false, keys, '[', false) == ControllerKeyAction::Character &&
                ClassifyConfiguredControllerKey(0, true, keys, '[', true) == ControllerKeyAction::Character,
            "Edge selection must not consume idle or modified punctuation.");
    keys.pageKeys = false;
    keys.verticalNavigation = false;
    require(ClassifyConfiguredControllerKey(kVK_PageDown, true, keys, '\0', false) == ControllerKeyAction::Character &&
                ClassifyConfiguredControllerKey(kVK_DownArrow, true, keys, '\0', false) ==
                    ControllerKeyAction::Character,
            "Disabled navigation keys must pass through.");

    require(NormalizeStoredInputScheme(0) == 0 && NormalizeStoredInputScheme(1) == 1 &&
                NormalizeStoredInputScheme(2) == 2 && NormalizeStoredInputScheme(99) == 0,
            "The stored input scheme was not normalized safely.");
    require(EngineSchemeForStoredPreference(0) == SchemeType::Quanpin &&
                EngineSchemeForStoredPreference(1) == SchemeType::Shuangpin &&
                EngineSchemeForStoredPreference(2) == SchemeType::Wubi,
            "A stored input scheme did not map to the matching engine scheme.");
    using metasequoia::mac::NormalizeShuangpinSchema;
    using metasequoia::mac::ShouldRouteSemicolonAsShuangpinInput;
    using metasequoia::mac::ShuangpinSchemaTitle;
    require(std::string_view(NormalizeShuangpinSchema("ziranma")) == "ziranma" &&
                std::string_view(NormalizeShuangpinSchema("shoudao")) == "shoudao" &&
                std::string_view(NormalizeShuangpinSchema("microsoft")) == "microsoft" &&
                std::string_view(NormalizeShuangpinSchema("bogus")) == "xiaohe" &&
                std::string_view(NormalizeShuangpinSchema("")) == "xiaohe",
            "A stored Shuangpin schema was not normalized to an engine profile name.");
    require(std::string_view(ShuangpinSchemaTitle("xiaohe")) == "小鹤双拼" &&
                std::string_view(ShuangpinSchemaTitle("ziranma")) == "自然码双拼" &&
                std::string_view(ShuangpinSchemaTitle("shoudao")) == "首道双拼" &&
                std::string_view(ShuangpinSchemaTitle("microsoft")) == "微软双拼",
            "A Shuangpin schema did not expose its product title.");
    require(metasequoia::punctuation_contract::is_supported(';') &&
                ShouldRouteSemicolonAsShuangpinInput(SchemeType::Shuangpin, "microsoft") &&
                !ShouldRouteSemicolonAsShuangpinInput(SchemeType::Shuangpin, "xiaohe") &&
                !ShouldRouteSemicolonAsShuangpinInput(SchemeType::Quanpin, "microsoft"),
            "Microsoft Shuangpin ing would be swallowed as punctuation without host routing.");
    require(metasequoia::mac::ShouldAutoCommitUniqueWubiCandidate(true, SchemeType::Wubi, 4, 1, false),
            "The enabled four-code unique Wubi policy did not auto-commit.");
    require(!metasequoia::mac::ShouldAutoCommitUniqueWubiCandidate(false, SchemeType::Wubi, 4, 1, false) &&
                !metasequoia::mac::ShouldAutoCommitUniqueWubiCandidate(true, SchemeType::Quanpin, 4, 1, false) &&
                !metasequoia::mac::ShouldAutoCommitUniqueWubiCandidate(true, SchemeType::Wubi, 3, 1, false) &&
                !metasequoia::mac::ShouldAutoCommitUniqueWubiCandidate(true, SchemeType::Wubi, 4, 2, false),
            "The four-code unique Wubi policy auto-committed outside its exact conditions.");
    // A four-letter code answered by the mixed-pinyin fallback looks identical to a unique wubi
    // candidate. Committing it would take away the fifth letter the fallback exists to allow.
    require(!metasequoia::mac::ShouldAutoCommitUniqueWubiCandidate(true, SchemeType::Wubi, 4, 1, true),
            "Auto-commit took a pinyin fallback candidate for a unique four-code Wubi candidate.");

    const std::filesystem::path helpcodeDataDirectory =
        std::filesystem::path(__FILE__).parent_path() / "../../../vendor/MetasequoiaImeEngine/helpcode";
    const char *expected[] = {"你(rX)", "你(rE)", "你(rP)", "你(rG)", "你(rX)"};
    const auto lantian = HelpcodeUtils::load_helpcode_keymap(helpcodeDataDirectory, "lantian");
    for (int schema = 0; schema < 5; ++schema)
    {
        const auto table = HelpcodeUtils::load_helpcode_keymap(helpcodeDataDirectory,
                                                               metasequoia::mac::HelpcodeSchemaIdentifier(schema));
        require(CandidateDisplayText(WordItem{"ni", "你", 1}, SchemeType::Quanpin, true, table.get()) ==
                    expected[schema],
                "A configured helpcode scheme did not select its packaged engine table.");
        require(CandidateDisplayText(WordItem{"ni", "你", 1}, SchemeType::Quanpin, true, lantian.get()) == "你(rX)",
                "Loading another display keymap changed an existing one.");
    }
    require(CandidateDisplayText(WordItem{"nimen", "你们", 1}, SchemeType::Shuangpin, true, lantian.get()) ==
                "你们(rR)",
            "Pinyin candidate display did not append the configured auxiliary code.");
    // A helpcode annotates a word the user could have typed in pinyin. compute_helpcodes still
    // finds Han characters in a synthesised candidate and appends letters for them, so "2026年9月6日"
    // came back carrying the codes for 年 and 日. Only the modes whose candidates are dictionary
    // words keep the annotation.
    using metasequoia::LocalInputMode;
    using metasequoia::mac::HelpcodesAnnotateLocalMode;
    require(HelpcodesAnnotateLocalMode(LocalInputMode::None) &&
                HelpcodesAnnotateLocalMode(LocalInputMode::SuperJianpin),
            "Ordinary and super-jianpin candidates lost their helpcode annotation.");
    require(
        !HelpcodesAnnotateLocalMode(LocalInputMode::DateTime) && !HelpcodesAnnotateLocalMode(LocalInputMode::Unicode) &&
            !HelpcodesAnnotateLocalMode(LocalInputMode::QuickPhrase) &&
            !HelpcodesAnnotateLocalMode(LocalInputMode::Emoji) && !HelpcodesAnnotateLocalMode(LocalInputMode::Kaomoji),
        "A synthesised local-mode candidate was annotated with a helpcode.");
    require(CandidateDisplayText(WordItem{"T", "2026年9月6日", 1}, SchemeType::Quanpin, false) == "2026年9月6日",
            "A date candidate did not come back unannotated.");
    require(CandidateDisplayText(WordItem{"T", "2026年9月6日", 1}, SchemeType::Quanpin, true, lantian.get()) !=
                "2026年9月6日",
            "The annotation this rule exists to suppress no longer happens, so the rule is dead.");

    // Traditional output chooses how to render a word. A Unicode code point is one exact character,
    // and its traditional counterpart is a different one than the user named.
    using metasequoia::mac::ScriptConversionAppliesToLocalMode;
    require(ScriptConversionAppliesToLocalMode(LocalInputMode::None) &&
                ScriptConversionAppliesToLocalMode(LocalInputMode::DateTime) &&
                ScriptConversionAppliesToLocalMode(LocalInputMode::QuickPhrase),
            "Traditional output stopped applying to candidates that are words.");
    require(!ScriptConversionAppliesToLocalMode(LocalInputMode::Unicode),
            "A Unicode code point was handed to the traditional-output conversion.");

    require(CandidateDisplayText(WordItem{"ni", "你", 1}, SchemeType::Quanpin, false) == "你" &&
                CandidateDisplayText(WordItem{"abcd", "你", 1}, SchemeType::Wubi, true) == "你",
            "Candidate display exposed auxiliary codes when the feature or scheme did not allow them.");

    // A wubi candidate is annotated with the keys that still single it out, so the hint is the tail
    // of its own code. Helpcodes have no say in it: they annotate a word with how to reach it in
    // pinyin, which is a different question than which key finishes the code in hand.
    using metasequoia::mac::WubiCodeHint;
    require(CandidateDisplayText(WordItem{"wqb", "爷", 1}, SchemeType::Wubi, false, nullptr, "wq") == "爷 b" &&
                CandidateDisplayText(WordItem{"wqbb", "父子", 1}, SchemeType::Wubi, true, lantian.get(), "wq") ==
                    "父子 bb",
            "A wubi candidate did not show the code that is left to type.");
    require(CandidateDisplayText(WordItem{"wq", "你", 1}, SchemeType::Wubi, false, nullptr, "wq") == "你",
            "A wubi candidate typed in full was annotated with an empty hint.");
    require(CandidateDisplayText(WordItem{"wqb", "爷", 1}, SchemeType::Wubi, false, nullptr, "") == "爷",
            "A wubi candidate was annotated with the hint switched off.");
    // The pinyin fallback keys its candidates by spelling, and those letters do not lead to the word
    // in wubi. The controller withholds the typed code there; this is the second line of defence.
    require(WubiCodeHint(WordItem{"ni'hao", "你好", 1}, "nihao").empty(),
            "A candidate keyed outside the typed code was annotated as though it extended it.");
    require(WubiCodeHint(WordItem{"wqb", "爷", 1}, "wq") == "b" && WubiCodeHint(WordItem{"wqb", "爷", 1}, "").empty(),
            "The wubi hint did not report the keys that are left to press.");

    // A stored language or provider index is written by whichever build the user last ran; a later
    // one that grew the list must not send an earlier one reading past it.
    {
        using metasequoia::mac::CandidateTranslationLanguageAt;
        using metasequoia::mac::CandidateTranslationProvider;
        using metasequoia::mac::CandidateTranslationProviderAt;
        using metasequoia::mac::kCandidateTranslationLanguageCount;

        require(std::string(CandidateTranslationLanguageAt(0).code) == "EN" &&
                    std::string(CandidateTranslationLanguageAt(0).name) == "English",
                "The first translation language was not English.");
        require(std::string(CandidateTranslationLanguageAt(3).code) == "ES" &&
                    std::string(CandidateTranslationLanguageAt(3).name) == "Spanish",
                "Spanish was not reachable among the translation languages.");
        require(std::string(CandidateTranslationLanguageAt(kCandidateTranslationLanguageCount).code) == "EN" &&
                    std::string(CandidateTranslationLanguageAt(999).code) == "EN",
                "An out-of-range language index was not clamped to the first language.");
        // Every entry carries both a service code and a name a model can read.
        for (std::size_t i = 0; i < kCandidateTranslationLanguageCount; ++i)
        {
            const auto &entry = CandidateTranslationLanguageAt(i);
            require(entry.title != nullptr && entry.code != nullptr && entry.name != nullptr &&
                        std::strlen(entry.code) == 2 && std::strlen(entry.name) > 2,
                    "A translation language was missing its title, service code or model name.");
        }

        require(CandidateTranslationProviderAt(0) == CandidateTranslationProvider::AccountModel,
                "The account model was not the default translation provider.");
        require(CandidateTranslationProviderAt(1) == CandidateTranslationProvider::TencentMachineTranslation &&
                    CandidateTranslationProviderAt(2) == CandidateTranslationProvider::DeepLX,
                "The phrase-based providers moved out from under their stored indexes.");
        require(CandidateTranslationProviderAt(99) == CandidateTranslationProvider::AccountModel,
                "An unknown provider index did not fall back to the account model.");
    }

    const auto dictionarySuffix = std::to_string(std::chrono::high_resolution_clock::now().time_since_epoch().count());
    const std::filesystem::path dictionaryDirectory =
        std::filesystem::temp_directory_path() / ("metasequoia-wubi-routing-" + dictionarySuffix);
    std::filesystem::create_directories(dictionaryDirectory);
    require(setenv("METASEQUOIA_IME_DATA_DIR", dictionaryDirectory.c_str(), 1) == 0,
            "The Wubi routing test could not select its fixture dictionary.");
    {
        Database database(dictionaryDirectory / "msime.db");
        database.execute("CREATE TABLE wubi86(key TEXT NOT NULL, value TEXT NOT NULL, weight INTEGER NOT NULL)");
        database.execute("INSERT INTO wubi86 VALUES"
                         "('abcd', '唯一候选', 100),"
                         "('aaaa', '候选一', 100),"
                         "('aaaa', '候选二', 90)");
    }
    {
        metasequoia::Session enabledSession(SessionTestOptions(SchemeType::Wubi, true, false));
        for (const char character : std::string("abc"))
        {
            const auto result = metasequoia::mac::HandleCharacterWithWubiAutoCommit(enabledSession, character, true);
            require(result.handled && !result.commit.has_value(), "Wubi auto-commit fired before the fourth code.");
        }
        const auto uniqueResult = metasequoia::mac::HandleCharacterWithWubiAutoCommit(enabledSession, 'd', true);
        require(uniqueResult.handled && uniqueResult.commit == "唯一候选" &&
                    !(!enabledSession.snapshot().preedit.empty()),
                "The fourth Wubi code did not commit its unique refreshed candidate.");

        metasequoia::Session disabledSession(SessionTestOptions(SchemeType::Wubi, true, false));
        for (const char character : std::string("abcd"))
        {
            const auto result = metasequoia::mac::HandleCharacterWithWubiAutoCommit(disabledSession, character, false);
            require(result.handled && !result.commit.has_value(),
                    "Disabled Wubi auto-commit unexpectedly committed a candidate.");
        }
        require(disabledSession.snapshot().preedit == "abcd",
                "Disabled Wubi auto-commit did not preserve the four-code composition.");

        metasequoia::Session multipleSession(SessionTestOptions(SchemeType::Wubi, true, false));
        for (const char character : std::string("aaaa"))
        {
            const auto result = metasequoia::mac::HandleCharacterWithWubiAutoCommit(multipleSession, character, true);
            require(result.handled && !result.commit.has_value(),
                    "Wubi auto-commit committed a code with multiple candidates.");
        }
        require(multipleSession.snapshot().preedit == "aaaa" && multipleSession.snapshot().candidates.size() == 2,
                "The multiple-candidate Wubi fixture did not remain available for selection.");
    }
    std::filesystem::remove_all(dictionaryDirectory);

    require(IsInputModeToggle(kVK_Space, NSEventModifierFlagShift), "Shift+Space did not map to input-mode switching.");
    require(!IsInputModeToggle(kVK_Space, 0) && !IsInputModeToggle(kVK_ANSI_A, NSEventModifierFlagShift) &&
                !IsInputModeToggle(kVK_Space, NSEventModifierFlagShift | NSEventModifierFlagCommand),
            "A non-toggle shortcut unexpectedly mapped to input-mode switching.");
    require(metasequoia::mac::ShouldToggleInputMode(true, kVK_Space, NSEventModifierFlagShift) &&
                !metasequoia::mac::ShouldToggleInputMode(false, kVK_Space, NSEventModifierFlagShift),
            "The input-mode shortcut preference did not gate Shift+Space.");

    // Shift on its own. The press cannot tell a tap from the start of Shift+A, so only the release
    // decides, and anything arriving in between takes the decision away.
    {
        using metasequoia::mac::ActionForSolitaryShift;
        using metasequoia::mac::SolitaryShiftAction;
        using metasequoia::mac::SolitaryShiftTracker;
        const auto shift = NSEventModifierFlagShift;

        SolitaryShiftTracker tap;
        require(!tap.flagsChanged(shift, 1.0), "Pressing Shift fired before it was released.");
        require(tap.flagsChanged(0, 1.1), "Releasing a solitary Shift did not fire.");
        require(!tap.flagsChanged(0, 1.2), "A release with no press behind it fired.");

        SolitaryShiftTracker withKey;
        (void)withKey.flagsChanged(shift, 2.0);
        withKey.keyDown();
        require(!withKey.flagsChanged(0, 2.1), "Shift+key was taken for a solitary Shift.");

        SolitaryShiftTracker held;
        (void)held.flagsChanged(shift, 3.0);
        require(!held.flagsChanged(0, 3.0 + metasequoia::mac::kSolitaryShiftInterval + 0.01),
                "A held Shift switched the input mode on release.");

        SolitaryShiftTracker chord;
        (void)chord.flagsChanged(shift | NSEventModifierFlagCommand, 4.0);
        require(!chord.flagsChanged(0, 4.1), "Command+Shift was taken for a solitary Shift.");

        SolitaryShiftTracker capsLock;
        (void)capsLock.flagsChanged(shift | NSEventModifierFlagCapsLock, 5.0);
        require(capsLock.flagsChanged(NSEventModifierFlagCapsLock, 5.1),
                "Caps Lock being on stopped Shift from switching the input mode.");

        SolitaryShiftTracker cleared;
        (void)cleared.flagsChanged(shift, 6.0);
        cleared.reset();
        require(!cleared.flagsChanged(0, 6.1), "A reset tracker still fired.");

        // Letters on screen mean the tap converts them; nothing composing means it switches modes;
        // the preference turns both off together.
        require(ActionForSolitaryShift(true, true) == SolitaryShiftAction::CommitComposition,
                "Shift during a composition did not commit what had been typed.");
        require(ActionForSolitaryShift(true, false) == SolitaryShiftAction::ToggleInputMode,
                "Shift with nothing composing did not switch the input mode.");
        require(ActionForSolitaryShift(false, true) == SolitaryShiftAction::Ignore &&
                    ActionForSolitaryShift(false, false) == SolitaryShiftAction::Ignore,
                "The disabled shortcut preference still acted on Shift.");
    }
    require(metasequoia::mac::ShouldPrepareInputSession(false) && !metasequoia::mac::ShouldPrepareInputSession(true),
            "Direct English mode did not bypass input-session preparation.");
    require(metasequoia::mac::NormalizeHelpcodeSchemaPreference(0) == 0 &&
                metasequoia::mac::NormalizeHelpcodeSchemaPreference(4) == 4 &&
                metasequoia::mac::NormalizeHelpcodeSchemaPreference(99) == 0,
            "The stored helpcode scheme was not normalized safely.");
    require(std::string(metasequoia::mac::HelpcodeSchemaIdentifier(0)) == "lantian" &&
                std::string(metasequoia::mac::HelpcodeSchemaIdentifier(1)) == "ziranma" &&
                std::string(metasequoia::mac::HelpcodeSchemaIdentifier(2)) == "shouyou2_0" &&
                std::string(metasequoia::mac::HelpcodeSchemaIdentifier(3)) == "shouyouplus" &&
                std::string(metasequoia::mac::HelpcodeSchemaIdentifier(4)) == "xiaohe",
            "The Mac helpcode choices did not map to the engine's five supported schemas.");

    require(NormalizeCandidatePanelStyle(0) == CandidatePanelStyle::Horizontal &&
                NormalizeCandidatePanelStyle(1) == CandidatePanelStyle::Vertical &&
                NormalizeCandidatePanelStyle(99) == CandidatePanelStyle::Horizontal,
            "The stored candidate layout was not normalized safely.");
    require(CandidatePanelTypeForStyle(CandidatePanelStyle::Horizontal) == kIMKSingleRowSteppingCandidatePanel &&
                CandidatePanelTypeForStyle(CandidatePanelStyle::Vertical) == kIMKSingleColumnScrollingCandidatePanel,
            "The candidate layout preference did not map to the expected native panel types.");
    require(IsPrimaryCandidateDirection(kVK_LeftArrow, kIMKSingleRowSteppingCandidatePanel) &&
                IsPrimaryCandidateDirection(kVK_RightArrow, kIMKSingleRowSteppingCandidatePanel) &&
                !IsPrimaryCandidateDirection(kVK_UpArrow, kIMKSingleRowSteppingCandidatePanel) &&
                !IsPrimaryCandidateDirection(kVK_DownArrow, kIMKSingleRowSteppingCandidatePanel),
            "The horizontal candidate panel did not restrict navigation to its primary axis.");
    require(!IsPrimaryCandidateDirection(kVK_LeftArrow, kIMKSingleColumnScrollingCandidatePanel) &&
                !IsPrimaryCandidateDirection(kVK_RightArrow, kIMKSingleColumnScrollingCandidatePanel) &&
                IsPrimaryCandidateDirection(kVK_UpArrow, kIMKSingleColumnScrollingCandidatePanel) &&
                IsPrimaryCandidateDirection(kVK_DownArrow, kIMKSingleColumnScrollingCandidatePanel),
            "The vertical candidate panel did not restrict navigation to its primary axis.");
    require(NormalizeCandidatePageSize(5) == 5 && NormalizeCandidatePageSize(7) == 7 &&
                NormalizeCandidatePageSize(9) == 9 && NormalizeCandidatePageSize(0) == 9 &&
                NormalizeCandidatePageSize(99) == 9,
            "The stored candidate page size was not normalized safely.");
    require(CandidatePageSizeForOptionIndex(0) == 1 && CandidatePageSizeForOptionIndex(5) == 6 &&
                CandidatePageSizeForOptionIndex(8) == 9 && CandidatePageSizeForOptionIndex(99) == 9 &&
                CandidatePageSizeOptionIndex(5) == 4 && CandidatePageSizeOptionIndex(7) == 6 &&
                CandidatePageSizeOptionIndex(9) == 8,
            "The candidate page-size options did not map to persisted values.");
    require(metasequoia::mac::NormalizeCandidateFontSize(16) == 16 &&
                metasequoia::mac::NormalizeCandidateFontSize(18) == 18 &&
                metasequoia::mac::NormalizeCandidateFontSize(20) == 20 &&
                metasequoia::mac::NormalizeCandidateFontSize(99) == 18,
            "The stored candidate font size was not normalized safely.");
    require(metasequoia::mac::CandidateFontSizeForOptionIndex(0) == 12 &&
                metasequoia::mac::CandidateFontSizeForOptionIndex(5) == 17 &&
                metasequoia::mac::CandidateFontSizeForOptionIndex(24) == 36 &&
                metasequoia::mac::CandidateFontSizeOptionIndex(16) == 4 &&
                metasequoia::mac::CandidateFontSizeOptionIndex(18) == 6 &&
                metasequoia::mac::CandidateFontSizeOptionIndex(20) == 8,
            "The candidate font-size options did not map to persisted values.");
    require(metasequoia::mac::NormalizeCandidatePageShortcut(0) == CandidatePageShortcut::MinusEqual &&
                metasequoia::mac::NormalizeCandidatePageShortcut(1) == CandidatePageShortcut::Brackets &&
                metasequoia::mac::NormalizeCandidatePageShortcut(2) == CandidatePageShortcut::PageKeys &&
                metasequoia::mac::NormalizeCandidatePageShortcut(99) == CandidatePageShortcut::MinusEqual,
            "The candidate page shortcut preference was not normalized safely.");
    NSDictionary *candidateAttributes = metasequoia::mac::CandidatePanelAttributes(20);
    require([candidateAttributes[IMKCandidatesSendServerKeyEventFirst] boolValue] &&
                [candidateAttributes[NSFontAttributeName] isKindOfClass:[NSFont class]] &&
                [candidateAttributes[NSFontAttributeName] pointSize] == 20.0,
            "The candidate font size did not map to InputMethodKit panel attributes.");
    NSArray<NSNumber *> *fiveSelectionKeys = CandidateSelectionKeys(5);
    NSArray<NSNumber *> *nineSelectionKeys = CandidateSelectionKeys(9);
    require(fiveSelectionKeys.count == 5 && nineSelectionKeys.count == 9 &&
                fiveSelectionKeys.firstObject.unsignedShortValue == kVK_ANSI_1 &&
                fiveSelectionKeys.lastObject.unsignedShortValue == kVK_ANSI_5 &&
                nineSelectionKeys.lastObject.unsignedShortValue == kVK_ANSI_9,
            "The candidate page size did not produce the expected number-key mappings.");

    require(ClassifyControllerKey(kVK_Return, true) == ControllerKeyAction::CommitRaw,
            "Return did not remain a raw commit while candidates were visible.");
    require(ClassifyControllerKey(kVK_ANSI_KeypadEnter, true) == ControllerKeyAction::CommitRaw,
            "Keypad Enter did not remain a raw commit while candidates were visible.");
    require(ClassifyControllerKey(kVK_Space, true) == ControllerKeyAction::CommitCandidate,
            "Space did not remain a leading-candidate commit while candidates were visible.");
    require(ClassifyControllerKey(kVK_ANSI_2, true) == ControllerKeyAction::Character,
            "Number keys no longer reached controller-side candidate selection.");
    require(ClassifyControllerKey(kVK_ANSI_Minus, true, CandidatePageShortcut::MinusEqual, '-', false) ==
                    ControllerKeyAction::MoveCandidatePageUp &&
                ClassifyControllerKey(kVK_ANSI_Equal, true, CandidatePageShortcut::MinusEqual, '=', false) ==
                    ControllerKeyAction::MoveCandidatePageDown &&
                ClassifyControllerKey(kVK_ANSI_LeftBracket, true, CandidatePageShortcut::Brackets, '[', false) ==
                    ControllerKeyAction::MoveCandidatePageUp &&
                ClassifyControllerKey(kVK_ANSI_RightBracket, true, CandidatePageShortcut::Brackets, ']', false) ==
                    ControllerKeyAction::MoveCandidatePageDown,
            "A configured candidate page shortcut did not map to its paging action.");
    require(ClassifyControllerKey(kVK_ANSI_Minus, true, CandidatePageShortcut::Brackets, '-', false) ==
                    ControllerKeyAction::Character &&
                ClassifyControllerKey(kVK_ANSI_LeftBracket, true, CandidatePageShortcut::PageKeys, '[', false) ==
                    ControllerKeyAction::Character &&
                ClassifyControllerKey(kVK_ANSI_Minus, true, CandidatePageShortcut::MinusEqual, '-', true) ==
                    ControllerKeyAction::Character &&
                ClassifyControllerKey(kVK_ANSI_Minus, false, CandidatePageShortcut::MinusEqual, '-', false) ==
                    ControllerKeyAction::Character,
            "An inactive, modified, or unconfigured candidate page shortcut was swallowed.");
    require(ClassifyControllerKey(kVK_ANSI_Minus, true, CandidatePageShortcut::MinusEqual, '^', false) ==
                    ControllerKeyAction::Character &&
                ClassifyControllerKey(kVK_ANSI_A, true, CandidatePageShortcut::MinusEqual, '-', false) ==
                    ControllerKeyAction::MoveCandidatePageUp,
            "Candidate paging followed a US physical key instead of the active keyboard layout.");
    require(metasequoia::mac::IsFullWidthInputToggle(kVK_ANSI_H, NSEventModifierFlagOption | NSEventModifierFlagShift),
            "Option+Shift+H was not recognized as the full-width toggle.");
    require(!metasequoia::mac::IsFullWidthInputToggle(kVK_ANSI_H, NSEventModifierFlagOption | NSEventModifierFlagShift |
                                                                      NSEventModifierFlagCommand),
            "A competing Command modifier incorrectly triggered the full-width toggle.");
    require(metasequoia::mac::IsFullWidthConvertibleCharacter('A') &&
                metasequoia::mac::FullWidthCharacter('A') == 0xFF21 &&
                metasequoia::mac::FullWidthCharacter(' ') == 0x3000,
            "ASCII full-width conversion did not preserve the expected Unicode mapping.");
    require(metasequoia::mac::IsFullWidthDirectCharacter('a', NSEventModifierFlagShift) &&
                !metasequoia::mac::IsFullWidthDirectCharacter('a', NSEventModifierFlagOption),
            "Direct full-width character routing did not honor competing modifiers.");

    const std::initializer_list<std::pair<unsigned short, ControllerKeyAction>> navigationKeys = {
        {kVK_LeftArrow, ControllerKeyAction::MoveCandidateLeft},
        {kVK_RightArrow, ControllerKeyAction::MoveCandidateRight},
        {kVK_UpArrow, ControllerKeyAction::MoveCandidateUp},
        {kVK_DownArrow, ControllerKeyAction::MoveCandidateDown},
        {kVK_PageUp, ControllerKeyAction::MoveCandidatePageUp},
        {kVK_PageDown, ControllerKeyAction::MoveCandidatePageDown},
        {kVK_Home, ControllerKeyAction::MoveCandidateHome},
        {kVK_End, ControllerKeyAction::MoveCandidateEnd},
    };
    for (const auto &[keyCode, expectedAction] : navigationKeys)
    {
        require(ClassifyControllerKey(keyCode, true) == expectedAction,
                "A navigation key did not map to its candidate-panel command.");
        require(ClassifyControllerKey(keyCode, false) == ControllerKeyAction::Character,
                "A navigation key was swallowed while the candidate panel was hidden.");
    }
    require([IMKCandidates instancesRespondToSelector:@selector(moveLeft:)],
            "IMKCandidates does not support moveLeft:.");
    require([IMKCandidates instancesRespondToSelector:@selector(moveRight:)],
            "IMKCandidates does not support moveRight:.");
    require([IMKCandidates instancesRespondToSelector:@selector(moveUp:)], "IMKCandidates does not support moveUp:.");
    require([IMKCandidates instancesRespondToSelector:@selector(moveDown:)],
            "IMKCandidates does not support moveDown:.");
    require([IMKCandidates instancesRespondToSelector:@selector(pageUp:)], "IMKCandidates does not support pageUp:.");
    require([IMKCandidates instancesRespondToSelector:@selector(pageDown:)],
            "IMKCandidates does not support pageDown:.");
    require([IMKCandidates instancesRespondToSelector:@selector(candidateIdentifierAtLineNumber:)],
            "IMKCandidates cannot map visible lines to candidate identifiers.");
    require([IMKCandidates instancesRespondToSelector:@selector(lineNumberForCandidateWithIdentifier:)],
            "IMKCandidates cannot validate candidate identifiers against visible lines.");
    require([IMKCandidates instancesRespondToSelector:@selector(selectCandidateWithIdentifier:)],
            "IMKCandidates cannot select candidates by identifier.");
    require([IMKCandidates instancesRespondToSelector:@selector(selectedCandidateString)],
            "IMKCandidates cannot report the selected candidate contents.");

    require(CandidatePageStart(0, 20, 9) == 0 && CandidatePageEnd(0, 20, 9) == 8,
            "The first candidate page boundaries were incorrect.");
    require(CandidatePageStart(11, 20, 9) == 9 && CandidatePageEnd(11, 20, 9) == 17,
            "The middle candidate page boundaries were incorrect.");
    require(CandidatePageStart(19, 20, 9) == 18 && CandidatePageEnd(19, 20, 9) == 19,
            "The partial final candidate page boundaries were incorrect.");
    require(CandidatePageStart(100, 20, 9) == 18 && CandidatePageEnd(100, 20, 9) == 19,
            "An out-of-range selection was not clamped to the final candidate page.");
    require(CandidatePageStart(0, 0, 9) == 0 && CandidatePageEnd(0, 0, 9) == 0,
            "An empty candidate list did not retain safe page boundaries.");
    return 0;
}
