#pragma once
#include <cstdint>

// Main-thread gate. A stale completion must not release a newer in-flight load.
struct MSIMEPreferenceLoadState {
    std::uint64_t generation = 0;
    bool loading = false;
    void reset() { ++generation; loading = false; }
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
