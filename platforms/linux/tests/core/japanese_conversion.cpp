#include "../../src/core/JapaneseConversion.h"

#include <cassert>
#include <string>

using msime::linux_host::JapaneseConversion;
using Action = msime::linux_host::JapaneseConversion::Action;

int main()
{
    // Enter with nothing converted is the kana. This is the whole reason the class exists: both
    // front ends used to send the Engine's raw-input command here, which in Japanese is the romaji.
    {
        JapaneseConversion conversion;
        assert(conversion.enter("nihon") == Action::CommitReading);
    }

    // The first Space converts rather than committing, and leaves the first candidate named.
    {
        JapaneseConversion conversion;
        assert(conversion.space("nihon", 3) == Action::Start);
        assert(conversion.index() == 0);
        // Enter now takes that candidate instead of the kana.
        assert(conversion.enter("nihon") == Action::CommitCandidate);
        assert(conversion.index() == 0);
    }

    // Further presses step, and running off the end comes back to the first.
    {
        JapaneseConversion conversion;
        assert(conversion.space("nihon", 3) == Action::Start);
        assert(conversion.space("nihon", 3) == Action::StepNext);
        assert(conversion.index() == 1);
        assert(conversion.space("nihon", 3) == Action::StepNext);
        assert(conversion.index() == 2);
        assert(conversion.space("nihon", 3) == Action::StepFirst);
        assert(conversion.index() == 0);
        assert(conversion.enter("nihon") == Action::CommitCandidate);
        assert(conversion.index() == 0);
    }

    // A single candidate has nowhere to step: the next press is the first one again rather than an
    // index the caller would read past the end of its own list.
    {
        JapaneseConversion conversion;
        assert(conversion.space("na", 1) == Action::Start);
        assert(conversion.space("na", 1) == Action::StepFirst);
        assert(conversion.index() == 0);
    }

    // Editing the reading abandons the conversion that was running on the old one.
    {
        JapaneseConversion conversion;
        assert(conversion.space("nihon", 3) == Action::Start);
        assert(conversion.space("nihon", 3) == Action::StepNext);
        assert(conversion.enter("nihongo") == Action::CommitReading);
        // And the next Space starts over rather than continuing from where it was.
        assert(conversion.space("nihongo", 3) == Action::Start);
        assert(conversion.index() == 0);
    }

    // Nothing to convert: the caller keeps whatever Space meant before.
    {
        JapaneseConversion conversion;
        assert(conversion.space("nihon", 0) == Action::None);
        // And that non-answer starts nothing, so Enter is still the kana.
        assert(conversion.enter("nihon") == Action::CommitReading);
    }

    // A reset puts it back to the state a fresh composition starts in.
    {
        JapaneseConversion conversion;
        assert(conversion.space("nihon", 3) == Action::Start);
        conversion.reset();
        assert(conversion.enter("nihon") == Action::CommitReading);
    }

    return 0;
}
