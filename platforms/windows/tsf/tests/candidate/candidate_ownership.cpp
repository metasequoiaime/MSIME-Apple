#include "../Candidate/CandidateListItem.h"
#include <cstdlib>
#include <utility>
#include <vector>

static CCandidateListItem MakeCandidate(std::size_t index)
{
    CCandidateListItem item;
    const std::wstring text = index % 2 ? std::wstring(256, L'x') : L"sample";
    const std::wstring code = L"synthetic-code";
    item._ItemString.Set(text.c_str(), text.size());
    item._FindKeyCode.Set(code.c_str(), code.size());
    item._EngineGeneration = 73;
    item._EngineSession = 19;
    item._EngineIndex = static_cast<uint32_t>(index);
    item._EngineHighlighted = index == 11;
    return item;
}

int main()
{
    std::vector<CCandidateListItem> candidates;
    for (std::size_t i = 0; i < 512; ++i) candidates.push_back(MakeCandidate(i));
    for (std::size_t i = 0; i < candidates.size(); ++i)
    {
        const auto &item = candidates[i];
        if (item._ItemString.ToWString() != (i % 2 ? std::wstring(256, L'x') : L"sample") ||
            item._ItemString.Get()[item._ItemString.GetLength()] != L'\0' ||
            item._FindKeyCode.ToWString() != L"synthetic-code" ||
            item._EngineSession != 19 || item._EngineGeneration != 73 || item._EngineIndex != i ||
            item._EngineHighlighted != (i == 11)) return EXIT_FAILURE;
    }
    auto copied = candidates;
    CCandidateListItem assigned;
    assigned = candidates[11];
    candidates.clear();
    copied[11]._ItemString.Set(L"changed", 7);
    if (assigned._ItemString.ToWString() != std::wstring(256, L'x') ||
        assigned._EngineIndex != 11 || !assigned._EngineHighlighted) return EXIT_FAILURE;
    auto moved = std::move(assigned);
    if (!moved.MatchesEngineView(19, 73) || moved.MatchesEngineView(19, 74) ||
        moved.MatchesEngineView(20, 73) || CCandidateListItem{}.MatchesEngineView(19, 73) ||
        CCandidateListItem{}.MatchesEngineView(0, 0)) return EXIT_FAILURE;
    moved._FindKeyCode.Clear();
    if (moved._ItemString.GetLength() != 256 || moved._FindKeyCode.GetLength() != 0 ||
        copied[10]._FindKeyCode.ToWString() != L"synthetic-code") return EXIT_FAILURE;
    moved._ItemString.Set(moved._ItemString.Get() + 1, 255);
    if (moved._ItemString.GetLength() != 255) return EXIT_FAILURE;
    const wchar_t unicode[] = {0xD83C, 0xDF32, L'\0', L'a'};
    moved._ItemString.Set(unicode, 4);
    if (moved._ItemString.GetLength() != 4 || moved._ItemString.Get()[3] != L'a') return EXIT_FAILURE;
    moved._ItemString.Set(nullptr, 0);
    if (moved._ItemString.GetLength() != 0 || moved._ItemString.Get()[0] != L'\0') return EXIT_FAILURE;
    try {
        moved._ItemString.Set(nullptr, 1);
        return EXIT_FAILURE;
    } catch (const std::invalid_argument &) {
        if (moved._ItemString.GetLength() != 0) return EXIT_FAILURE;
    }
    return EXIT_SUCCESS;
}
