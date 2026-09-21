#include "../../HostRawCommit.h"
#include <cstdlib>
#include <vector>
using msime::tsf::RawCommitStatus;
struct Host {
    bool succeeds = true;
    unsigned calls = 0;
    unsigned reading_calls = 0;
    std::string response;
    // What the Engine answers for MSIME_COMMIT_READING. Its own rule is that only a Japanese
    // composition has a reading at all, so the default here is the empty answer every other
    // scheme gets.
    std::string reading_response =
        R"({"ok":true,"value":{"handled":false,"commit":null,"view":{"preedit":"","editing_text":""}}})";
    bool reading_succeeds = true;
    bool command(uint32_t command, std::string *raw, std::string *) {
        if (command == MSIME_COMMIT_READING) {
            ++reading_calls;
            *raw = reading_response;
            return reading_succeeds;
        }
        if (command != MSIME_COMMIT_RAW) std::abort();
        ++calls;
        *raw = response;
        return succeeds;
    }
};
int main() {
    Host host;
    host.response = R"({"ok":true,"value":{"handled":true,"commit":"synthetic-原文","diagnostic":null,"view":{"preedit":"","editing_text":""}}})";
    std::vector<std::string> events;
    std::string error;
    auto insert = [&](const std::string &text) { events.push_back(text); return true; };
    auto cleanup = [&] { events.push_back("cleanup"); };
    auto status = msime::tsf::CommitHostRaw(host, insert, cleanup, &error);
    if (status != RawCommitStatus::Completed || host.calls != 1 ||
        events != std::vector<std::string>{"synthetic-原文", "cleanup"}) return EXIT_FAILURE;
    events.clear();
    status = msime::tsf::CommitHostRaw(host, [&](const std::string &) { events.push_back("failed-write"); return false; }, cleanup, &error);
    if (status != RawCommitStatus::Failed || events != std::vector<std::string>{"failed-write"}) return EXIT_FAILURE;
    events.clear();
    host.succeeds = false;
    if (msime::tsf::CommitHostRaw(host, insert, cleanup, &error) != RawCommitStatus::Failed || !events.empty()) return EXIT_FAILURE;
    host.succeeds = true;
    host.response = "invalid";
    if (msime::tsf::CommitHostRaw(host, insert, cleanup, &error) != RawCommitStatus::Failed || !events.empty()) return EXIT_FAILURE;
    host.response = R"({"ok":true,"value":{"handled":false,"commit":null,"view":{"preedit":"active","editing_text":"active"}}})";
    if (msime::tsf::CommitHostRaw(host, insert, cleanup, &error) != RawCommitStatus::Unhandled || !events.empty()) return EXIT_FAILURE;
    host.response = R"({"ok":true,"value":{"handled":false,"commit":null,"view":{"preedit":"","editing_text":""}}})";
    if (msime::tsf::CommitHostRaw(host, insert, cleanup, &error) != RawCommitStatus::Completed ||
        events != std::vector<std::string>{"cleanup"}) return EXIT_FAILURE;
    // Japanese: the kana is what Enter commits, and the raw command is never asked for.
    {
        Host japanese;
        japanese.reading_response =
            R"({"ok":true,"value":{"handled":true,"commit":"にほん","diagnostic":null,"view":{"preedit":"","editing_text":""}}})";
        std::vector<std::string> japanese_events;
        auto japanese_insert = [&](const std::string &text) { japanese_events.push_back(text); return true; };
        auto japanese_cleanup = [&] { japanese_events.push_back("cleanup"); };
        if (msime::tsf::CommitHostRaw(japanese, japanese_insert, japanese_cleanup, &error) !=
                RawCommitStatus::Completed ||
            japanese.reading_calls != 1 || japanese.calls != 0 ||
            japanese_events != std::vector<std::string>{"にほん", "cleanup"}) return EXIT_FAILURE;

        // A failed write is a failed commit, and the raw command must not be tried as a second
        // chance: that would put the romaji in after the kana failed to go in.
        japanese_events.clear();
        japanese.reading_calls = 0;
        if (msime::tsf::CommitHostRaw(japanese, [&](const std::string &) { return false; },
                                      japanese_cleanup, &error) != RawCommitStatus::Failed ||
            japanese.calls != 0) return EXIT_FAILURE;

        // A host that cannot answer the reading command at all falls back rather than failing:
        // every scheme but Japanese lives on that path.
        japanese.reading_succeeds = false;
        japanese.reading_calls = 0;
        japanese_events.clear();
        japanese.response =
            R"({"ok":true,"value":{"handled":true,"commit":"fallback","diagnostic":null,"view":{"preedit":"","editing_text":""}}})";
        if (msime::tsf::CommitHostRaw(japanese, japanese_insert, japanese_cleanup, &error) !=
                RawCommitStatus::Completed ||
            japanese.calls != 1 ||
            japanese_events != std::vector<std::string>{"fallback", "cleanup"}) return EXIT_FAILURE;
    }
    return EXIT_SUCCESS;
}
