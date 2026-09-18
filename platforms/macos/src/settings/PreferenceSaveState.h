#pragma once

// Main-thread scheduling only. A burst during one save requires one fresh save.
struct MSIMEPreferenceSaveState {
    bool saving = false;
    bool pending = false;
    bool request() {
        if (saving) { pending = true; return false; }
        saving = true;
        return true;
    }
    bool finish() {
        saving = false;
        const bool again = pending;
        pending = false;
        return again;
    }
};
