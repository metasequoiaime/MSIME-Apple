#include "../../tsf/Global/PairedPunctuationHostPolicy.h"
#include <iostream>

int main() {
  using Global::IsPairedPunctuationExcludedProcess;
  for (const auto name : {L"EXCEL.EXE", L"excel.exe", L"ExCeL.ExE"}) {
    if (!IsPairedPunctuationExcludedProcess(name))
      return 1;
  }
  for (const auto name : {L"", L"WINWORD.EXE", L"excel.exe.bak", L"myexcel.exe",
                          L"excel", L"ｅxcel.exe"}) {
    if (IsPairedPunctuationExcludedProcess(name))
      return 1;
  }
  if (IsPairedPunctuationExcludedProcess(std::wstring_view(L"excel.exe\0other", 15)))
    return 1;
  std::cout << "Paired punctuation host policy passed\n";
}
