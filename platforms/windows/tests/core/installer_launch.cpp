#include "ServerLaunch.h"
#include <fstream>
#include <iostream>
#include <iterator>
#include <regex>
#include <stdexcept>
#include <string>

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
        const wchar_t *arguments[] = {L"MetasequoiaImeServer.exe", argument.c_str()};
        const auto parsed = msime::windows::parse_server_arguments(
            parameter.empty() ? 1 : 2, arguments);
        if (parsed.kind != msime::windows::ServerLaunchKind::Managed ||
            !parsed.config.empty())
          throw std::runtime_error("Installer must launch Server in managed mode");
      } else {
        ++watchdogs;
        if (!parameter.empty())
          throw std::runtime_error("Installer changed Watchdog arguments");
      }
    }
    if (servers != 1 || watchdogs != 1)
      throw std::runtime_error("Expected one Server and one Watchdog invocation");
    std::cout << "Installer launch contract passed\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
