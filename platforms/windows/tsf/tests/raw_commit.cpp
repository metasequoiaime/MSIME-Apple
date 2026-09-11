#include "../HostRawCommit.h"
#include <cstdlib>
#include <vector>
using msime::tsf::RawCommitStatus;
struct Host {
    bool succeeds = true;
    unsigned calls = 0;
    std::string response;
    bool command(uint32_t command, std::string *raw, std::string *) {
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
    return EXIT_SUCCESS;
}
