#pragma once
#include "EngineSessionAdapter.h"

namespace msime::tsf {
enum class RawCommitStatus { Completed, Unhandled, Failed };

// The host owns input state; the editor write must precede UI teardown.
template<class Host, class Insert, class Cleanup>
RawCommitStatus CommitHostRaw(Host &host, Insert insert, Cleanup cleanup, std::string *error) {
    std::string raw;
    EngineResult result;
    if (!host.command(MSIME_COMMIT_RAW, &raw, error) ||
        !EngineSessionAdapter::parse_result(raw, &result, error)) return RawCommitStatus::Failed;
    if (!result.handled && !result.has_commit &&
        (!result.view.editing_text.empty() || !result.view.preedit.empty())) return RawCommitStatus::Unhandled;
    if (result.has_commit && !result.commit.empty() && !insert(result.commit)) return RawCommitStatus::Failed;
    cleanup();
    return RawCommitStatus::Completed;
}
}
