#include "../src/LocalResourceModes.h"
#include "PublicSessionTestOptions.h"
// Idle Shift+letter opens a local mode. During a composition the same capital is helpcode input,
// and the engine still refuses to open a mode on top of one. These tests pin which capitals open a
// mode, that the rest stay unhandled so the application still inserts them, and that a disabled
// mode gives its trigger letter back.
#include <metasequoia/session.h>

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <stdexcept>
#include <string>

namespace
{
void Require(bool condition, const char *message)
{
    if (!condition)
    {
        throw std::runtime_error(message);
    }
}

metasequoia::LocalModeOptions AppleOptions(bool enabled)
{
    return metasequoia::mac::LocalResourceModes(enabled, metasequoia::RuntimePaths::legacy());
}

int RunBundledTest(const std::filesystem::path &resources)
{
    const auto directory = std::filesystem::temp_directory_path() /
        ("metasequoia-bundled-modes-" + std::to_string(std::chrono::high_resolution_clock::now().time_since_epoch().count()));
    std::filesystem::create_directories(directory);
    struct Cleanup { std::filesystem::path directory; ~Cleanup() { std::filesystem::remove_all(directory); } } cleanup{directory};
    metasequoia::SessionOptions options;
    options.paths = {resources, directory / "user", directory / "cache", resources};
    options.helpcode = false;
    options.learning = false;
    options.local_modes = metasequoia::mac::LocalResourceModes(true, options.paths);
    Require(options.local_modes.emoji && options.local_modes.kaomoji && options.local_modes.temporary_japanese,
            "Bundled resources did not enable native local modes.");
    for (const auto scheme : {SchemeType::Quanpin, SchemeType::Shuangpin})
    {
        options.scheme = scheme;
        metasequoia::Session session(options);
        for (const auto trigger : {'E', 'M', 'R'})
        {
            Require(session.character(trigger, true).handled, "A bundled local trigger was not handled.");
            const std::string code = trigger == 'E' ? "xl" : trigger == 'M' ? "hx" : "ka";
            for (const char character : code) Require(session.character(character).handled, "Local input was rejected.");
            const auto snapshot = session.snapshot();
            Require(!snapshot.candidates.empty(), "Bundled resource produced no candidates.");
            const auto expected = snapshot.candidates.front().word;
            const auto result = session.finish(0);
            Require(result.commit == expected && session.snapshot().local_mode == metasequoia::LocalInputMode::None,
                    "Resource candidate failed to finish and restore original input mode.");
            Require(session.character(trigger, true).handled, "A local mode failed to reopen.");
            session.command(metasequoia::Command::Cancel);
            Require(session.snapshot().local_mode == metasequoia::LocalInputMode::None,
                    "Cancel failed to restore the original input mode.");
        }
    }
    options.local_modes = metasequoia::mac::LocalResourceModes(false, options.paths);
    metasequoia::Session disabled(options);
    for (const char trigger : {'E', 'M', 'R'})
        Require(!disabled.character(trigger, true).handled, "Disabled resource mode swallowed its trigger.");
    return 0;
}

int RunTest()
{
    const std::filesystem::path dataDirectory =
        std::filesystem::temp_directory_path() /
        ("metasequoia-local-input-modes-" +
         std::to_string(std::chrono::high_resolution_clock::now().time_since_epoch().count()));
    std::filesystem::create_directories(dataDirectory);
    if (setenv("METASEQUOIA_IME_DATA_DIR", dataDirectory.c_str(), 1) != 0)
    {
        throw std::runtime_error("Failed to set the test data directory.");
    }

    {
        auto options = SessionTestOptions();
        options.local_modes = AppleOptions(true);
        metasequoia::Session session(options);

        const auto unicode = session.character('U', true);
        Require(unicode.handled && session.snapshot().preedit == "U", "Shift+U did not open the Unicode mode.");
        Require(session.snapshot().local_mode == metasequoia::LocalInputMode::Unicode,
                "Shift+U did not report the Unicode mode.");

        // The code point is hexadecimal, so the mode has to take digits as input. The controller routes
        // them here only while this mode is open; every other mode leaves digits to candidate numbers.
        Require(session.character('4').handled && session.snapshot().preedit == "U4",
                "The Unicode mode rejected a hexadecimal digit.");
        Require(session.command(metasequoia::Command::Cancel).handled, "Cancel did not close the Unicode mode.");
        Require(session.snapshot().local_mode == metasequoia::LocalInputMode::None, "Cancel left a local mode open.");
    }

    {
        auto options = SessionTestOptions();
        options.local_modes = AppleOptions(true);
        metasequoia::Session session(options);

        // A capital that opens nothing has to come back unhandled, or the keyboard would swallow it
        // instead of letting the application insert it.
        const auto passthrough = session.character('Z', true);
        Require(!passthrough.handled, "A capital that opens no mode was swallowed by the session.");
        Require(session.snapshot().local_mode == metasequoia::LocalInputMode::None,
                "A capital that opens no mode still changed the local mode.");

        // Modes without resources in the legacy fixture must not open at all.
        for (const char trigger : {'E', 'M', 'Y', 'R'})
        {
            const auto result = session.character(trigger, true);
            Require(!result.handled, "A local mode without packaged data was opened by its trigger.");
            Require(session.snapshot().local_mode == metasequoia::LocalInputMode::None,
                    "A local mode without packaged data reported itself as open.");
        }
    }

    {
        auto options = SessionTestOptions();
        options.local_modes = AppleOptions(false);
        metasequoia::Session session(options);

        // With the preference off the trigger is an ordinary capital again.
        const auto disabled = session.character('U', true);
        Require(!disabled.handled, "Shift+U opened the Unicode mode while local modes were disabled.");
        Require(session.snapshot().local_mode == metasequoia::LocalInputMode::None,
                "A disabled local mode still opened.");
    }

    {
        auto options = SessionTestOptions();
        options.local_modes = AppleOptions(true);
        metasequoia::Session session(options);

        Require(session.character('n').handled, "The guard fixture did not start a composition.");
        const auto duringComposition = session.character('U', true);
        Require(duringComposition.handled && session.snapshot().preedit == "nU",
                "An uppercase letter during composition was not taken as helpcode.");
        Require(session.snapshot().local_mode == metasequoia::LocalInputMode::None,
                "A trigger opened a local mode on top of a live composition.");
    }

    std::filesystem::remove_all(dataDirectory);
    return 0;
}
} // namespace

int main(int argc, char **argv)
{
    try
    {
        return argc == 3 && std::string(argv[1]) == "--resources" ? RunBundledTest(argv[2]) : RunTest();
    }
    catch (const std::exception &exception)
    {
        std::fprintf(stderr, "%s\n", exception.what());
        return 1;
    }
}
