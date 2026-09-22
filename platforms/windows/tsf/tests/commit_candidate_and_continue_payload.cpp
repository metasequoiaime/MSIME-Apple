#include "IPC/CommitCandidateAndContinuePayload.h"

#include <stdexcept>

namespace
{
void require(bool condition)
{
    if (!condition)
    {
        throw std::runtime_error("commit-and-continue payload assertion failed");
    }
}
} // namespace

int main()
{
    std::size_t consumed = 0;
    std::wstring text;
    require(ParseCommitCandidateAndContinuePayload(L"4\t合成候选", consumed, text));
    require(consumed == 4 && text == L"合成候选");
    require(ParseCommitCandidateAndContinuePayload(L"4\t", consumed, text));
    require(consumed == 4 && text.empty());
    require(ParseCommitCandidateAndContinuePayload(L"1\ta\tb", consumed, text));
    require(consumed == 1 && text == L"a\tb");
    require(!ParseCommitCandidateAndContinuePayload(L"4", consumed, text));
    require(!ParseCommitCandidateAndContinuePayload(L"\t合成候选", consumed, text));
    require(!ParseCommitCandidateAndContinuePayload(L"4x\t合成候选", consumed, text));
    require(!ParseCommitCandidateAndContinuePayload(L"-4\t合成候选", consumed, text));
    require(!ParseCommitCandidateAndContinuePayload(L"99999999\t合成候选", consumed, text));
    require(!ParseCommitCandidateAndContinuePayload(L"", consumed, text));
    return 0;
}
