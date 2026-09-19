#include "../../Global/FanyDefines.h"

#include <stdexcept>

namespace
{
void require(bool condition, const char *message)
{
    if (!condition)
    {
        throw std::runtime_error(message);
    }
}
} // namespace

int main()
{
    require(Global::IsPairedPunctuationExcludedProcess(L"EXCEL.EXE"), "Excel should be excluded");
    require(Global::IsPairedPunctuationExcludedProcess(L"excel.exe"), "matching is case insensitive");
    require(!Global::IsPairedPunctuationExcludedProcess(L"WINWORD.EXE"), "Word should remain enabled");
    require(!Global::IsPairedPunctuationExcludedProcess(L""), "empty process should remain enabled");
    return 0;
}
