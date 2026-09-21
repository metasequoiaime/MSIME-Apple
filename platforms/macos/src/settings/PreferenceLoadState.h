#pragma once
#include <cstdint>

// Main-thread gate. A stale completion must not release a newer in-flight load.
struct MSIMEPreferenceLoadState {
    std::uint64_t generation = 0;
    bool loading = false;
    /// The revision last applied to this session, so an unchanged document read by the poll is not
    /// applied again. Zero means nothing has been applied yet - the store's revisions start at one.
    std::uint64_t appliedRevision = 0;
    /// Whether a document at `revision` still has to be applied. A local edit calls `reset`, which
    /// forgets what was applied and therefore lets the next read through even at the same revision.
    bool needsApply(std::uint64_t revision) const { return revision == 0 || revision != appliedRevision; }
    void applied(std::uint64_t revision) { appliedRevision = revision; }
    void reset() { ++generation; loading = false; appliedRevision = 0; }
    bool begin() {
        if (loading) return false;
        loading = true;
        return true;
    }
    bool finish(std::uint64_t requestGeneration) {
        if (requestGeneration != generation || !loading) return false;
        loading = false;
        return true;
    }
};
