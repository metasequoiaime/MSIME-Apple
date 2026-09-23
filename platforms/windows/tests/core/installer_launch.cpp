#include "ServerLaunch.h"
#include <fstream>
#include <iostream>
#include <iterator>
#include <regex>
#include <stdexcept>
#include <string>

namespace {
std::string between(const std::string &text, const std::string &begin,
                    const std::string &end) {
  const auto first = text.find(begin);
  const auto last = text.find(end, first == std::string::npos ? 0 : first);
  if (first == std::string::npos || last == std::string::npos || last <= first)
    throw std::runtime_error("Missing installer policy block: " + begin);
  return text.substr(first, last - first);
}

void contains(const std::string &text, const std::string &needle,
              const char *error) {
  if (text.find(needle) == std::string::npos)
    throw std::runtime_error(error);
}
} // namespace

// Run with the path to installer/msime_setup.iss. Read the actual invocation,
// not a duplicated argument constant, and check it against the Server parser.
int main(int argc, char **argv) {
  try {
    if (argc != 2)
      throw std::runtime_error("Expected installer script path");
    std::ifstream input(argv[1]);
    if (!input)
      throw std::runtime_error("Cannot read installer script");
    const std::string script{std::istreambuf_iterator<char>(input), {}};
    const auto start = script.find("procedure LaunchInstalledComponents;");
    const auto end = script.find("function NextButtonClick", start);
    if (start == std::string::npos || end == std::string::npos)
      throw std::runtime_error("Missing installer launch procedure");
    const auto launch = script.substr(start, end - start);
    const std::regex call(
        R"(ShellExecAsOriginalUser\(\s*'',\s*ExpandConstant\('[^']*\{#(MyAppExeName|MyWatchdogName)\}'\),\s*'([^']*)')");
    int servers = 0;
    int watchdogs = 0;
    for (auto it = std::sregex_iterator(launch.begin(), launch.end(), call);
         it != std::sregex_iterator(); ++it) {
      const auto parameter = (*it)[2].str();
      if ((*it)[1].str() == "MyAppExeName") {
        ++servers;
        const std::wstring argument(parameter.begin(), parameter.end());
        const wchar_t *arguments[] = {L"MetasequoiaImeServer.exe",
                                      argument.c_str()};
        const auto parsed = msime::windows::parse_server_arguments(
            parameter.empty() ? 1 : 2, arguments);
        if (parsed.kind != msime::windows::ServerLaunchKind::Managed ||
            !parsed.config.empty())
          throw std::runtime_error(
              "Installer must launch Server in managed mode");
      } else {
        ++watchdogs;
        if (!parameter.empty())
          throw std::runtime_error("Installer changed Watchdog arguments");
      }
    }
    if (servers != 1 || watchdogs != 1)
      throw std::runtime_error(
          "Expected one Server and one Watchdog invocation");

    // The product data can be hundreds of MiB, so the fixed source exposes a
    // visible destination page instead of making /DATADIR an undocumented
    // deployment-only escape hatch. The target is later recursively removed
    // when it carries our ownership marker, which makes these guards a data
    // safety contract rather than merely wizard copy.
    const auto wizard = between(script, "procedure InitializeWizard;",
                                "function ShouldSkipPage");
    contains(wizard, "DataDirPage := CreateInputDirPage(",
             "Installer has no visible data-directory page");
    contains(wizard, "DataDirPage.Values[0] := GetDataDir('')",
             "Data-directory page ignores the command-line/previous value");
    contains(wizard, "DataDirPage.Buttons[0].OnClick := @DataDirBrowseClick",
             "Data-directory page cannot create a destination while browsing");
    contains(wizard, "DataDirPage.ID,",
             "Network page is ordered before data selection");
    contains(wizard, "#ifndef LightPackage\n  { 程序本体保留在 Program Files",
             "Light package exposes a destination it cannot populate");

    const auto get_data_dir =
        between(script, "function GetDataDir", "function IsPathInside");
    contains(get_data_dir,
             "#ifdef LightPackage\n    { "
             "轻量包不携带词库和静态资源，只能原地更新已有安装。}",
             "Light package does not pin the existing data directory");
    contains(get_data_dir, "function LightPackageDataDirRejectionReason",
             "Light package silently accepts a data-directory override");
    contains(get_data_dir,
             "RemoveBackslashUnlessRoot(Requested), ResolvePreviousDataDir",
             "Light package does not compare /DATADIR with the existing path");

    const auto validation = between(script, "function DataDirRejectionReason",
                                    "procedure DataDirBrowseClick");
    contains(validation, "IsPathInside(Critical[Index], Directory)",
             "Data directory may contain a system or user root");
    contains(validation, "IsPathInside(Directory, ProtectedDirs[Index])",
             "Data directory may be placed inside a protected root");
    contains(validation, "Pos('\\..\\', WithSlash)",
             "Data-directory traversal is not rejected");
    contains(validation, "ExpandFileName(Directory)",
             "Non-canonical path aliases can bypass protected roots");
    contains(
        validation,
        "(not DirectoryIsEmpty(Directory)) and (not OwnsDataDir(Directory))",
        "Installer may claim and later delete a non-empty foreign directory");
    contains(validation, "'msime-write-probe-' + IntToStr(Index)",
             "Fixed probe name can overwrite an existing user file");
    contains(validation, "SaveStringToFile(ProbePath, 'probe', False)",
             "Data-directory writability is not checked before installation");
    contains(validation, "if not DeleteFile(ProbePath) then",
             "Installer accepts a directory where its probe cannot be cleaned");

    const auto next =
        between(script, "function NextButtonClick", "function UpdateReadyMemo");
    contains(next, "Reason := DataDirRejectionReason(Chosen)",
             "Wizard accepts a data directory without validation");
    contains(next, "DataDirValue := Chosen",
             "Validated wizard choice never reaches package paths");
    contains(
        next, "UserConfigExistedBeforeInstall := FileExists(UserConfigPath)",
        "Network consent is evaluated against the previous data directory");

    const auto prepare = between(script, "function PrepareToInstall",
                                 "procedure CurStepChanged");
    contains(prepare, "DataDirError := DataDirRejectionReason(GetDataDir(''))",
             "Silent /DATADIR bypasses data-directory validation");
    contains(prepare, "DataDirError := LightPackageDataDirRejectionReason",
             "Light package can migrate into a directory without resources");
    contains(prepare, "WriteDataDirMarker(GetDataDir(''))",
             "A failed migration can leave an unowned non-empty destination");
    contains(prepare, "if not OwnsDataDir(GetDataDir('')) then",
             "Installer proceeds after failing to claim the data directory");
    contains(script, "'数据目录（词库、用户配置、皮肤）：'",
             "Ready page does not disclose the selected data directory");
    std::cout << "Installer launch and data-directory contracts passed\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
