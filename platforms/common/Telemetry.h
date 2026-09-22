#pragma once
#include <string>

namespace msime::telemetry {
void start(const std::string &platform, const std::string &version);
void crash(const std::string &platform, const std::string &version, const std::string &message);
}
