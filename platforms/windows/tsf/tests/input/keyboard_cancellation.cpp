#include "../../KeyboardCancellation.h"
#include "../../../../../vendor/MSIME-Engine/contracts/keyboard_composition_pipe.h"
#include <cassert>
#include <vector>

int main()
{
    using namespace msime::tsf;
    const KeyboardCancellationIdentity expected{19, 23};
    assert(keyboard_cancellation_matches(expected, expected, true, true));
    assert(!keyboard_cancellation_matches(expected, expected, false, true));
    assert(!keyboard_cancellation_matches(expected, expected, true, false));
    assert(!keyboard_cancellation_matches(expected, {20, 23}, true, true));
    assert(!keyboard_cancellation_matches(expected, {19, 24}, true, true));
    assert(!keyboard_cancellation_matches({}, {}, true, true));

    // The actual production orchestration runs these injected host operations.
    // A failure at each phase must propagate exactly and stop later phases.
    for (int failed = 0; failed <= 4; ++failed)
    {
        std::vector<int> calls;
        auto operation = [&](int phase) {
            calls.push_back(phase);
            return phase == failed ? -phase : 0;
        };
        const auto result = cancel_keyboard_composition(
            0, 1, [] { return true; }, [&] { return operation(1); },
            [&] { return operation(2); }, [&] { return operation(3); }, [&] { return operation(4); });
        assert(result == -failed);
        assert(calls.size() == static_cast<unsigned>(failed == 0 ? 4 : failed));
    }
    // Re-entrancy after GetRange / SetText invalidates focus or epoch, so the
    // next mutation must not run. Initially stale/idle requests do no work.
    for (int invalidate = 0; invalidate <= 2; ++invalidate)
    {
        int phase = 0;
        const auto result = cancel_keyboard_composition(
            0, 1, [&] { return phase != invalidate; }, [&] { ++phase; return 0; },
            [&] { ++phase; return 0; }, [&] { ++phase; return 0; }, [&] { ++phase; return 0; });
        assert(result == 1 && phase == invalidate);
    }
    // EndComposition may already retire its exact object through a callback;
    // successful completion still runs exact-object retirement, not a new one.
    bool oldObjectCurrent = true;
    bool newerObjectTouched = false;
    assert(cancel_keyboard_composition(0, 1, [&] { return oldObjectCurrent; }, [] { return 0; },
        [] { return 0; }, [&] { oldObjectCurrent = false; return 0; }, [&] {
            if (oldObjectCurrent) newerObjectTouched = true;
            return 0;
        }) == 0);
    assert(!newerObjectTouched);

    using namespace FanyImeProtocol;
    const auto caps = Capabilities | KeyboardCompositionCancel;
    const auto negotiated = Negotiate(Hello(7, 19, caps), caps);
    const auto frame = FanyImeKeyboardCompositionPipe::EncodeCancel(expected.focus, negotiated);
    assert(frame && FanyImeKeyboardCompositionPipe::ParseCancel(*frame) == expected.focus);
    assert(!FanyImeKeyboardCompositionPipe::CanCancel(Negotiate(Hello(7, 19), caps)));
    auto invalid = *frame;
    invalid.data[4] = '9';
    assert(!FanyImeKeyboardCompositionPipe::ParseCancel(invalid));
}
