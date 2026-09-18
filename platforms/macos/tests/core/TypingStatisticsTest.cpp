#include "../src/core/TypingStatistics.h"
#include "msime_client.h"

#include <cassert>
#include <cstring>
#include <filesystem>
#include <string>

using msime::mac::ResolveTypingSource;
using msime::mac::TypingSource;

static std::string call(const std::filesystem::path &directory, const char *action) {
    const std::string request = "{\"directory\":\"" + directory.string() + "\",\"action\":" + action + "}";
    char *raw = msime_client_typing_statistics(reinterpret_cast<const uint8_t *>(request.data()), request.size());
    assert(raw);
    std::string result(raw);
    msime_client_string_free(raw);
    return result;
}

int main() {
    assert(ResolveTypingSource(0, false, false, "none", "xiaohe") == TypingSource::Quanpin);
    assert(ResolveTypingSource(0, true, false, "none", "xiaohe") == TypingSource::NineKey);
    assert(ResolveTypingSource(1, false, false, "none", "ziranma") == TypingSource::Ziranma);
    assert(ResolveTypingSource(1, false, false, "none", "microsoft") == TypingSource::Microsoft);
    assert(ResolveTypingSource(1, false, false, "none", "shoudao") == TypingSource::Shoudao);
    assert(ResolveTypingSource(2, false, false, "none", "xiaohe") == TypingSource::Wubi);
    assert(ResolveTypingSource(3, false, false, "none", "xiaohe") == TypingSource::Japanese);
    assert(ResolveTypingSource(0, false, true, "none", "xiaohe") == TypingSource::English);
    assert(ResolveTypingSource(0, false, false, "temporary_japanese", "xiaohe") == TypingSource::Japanese);
    assert(ResolveTypingSource(0, false, false, "emoji", "xiaohe") == TypingSource::Local);
    assert(ResolveTypingSource(99, false, false, "none", "xiaohe") == TypingSource::Unknown);
    assert(msime::mac::TypingSourceId(TypingSource::NineKey) == "nineKey");

    const auto directory = std::filesystem::temp_directory_path() / "msime-macos-typing-statistics-test";
    std::filesystem::remove_all(directory);
    const auto result = call(directory, "{\"operation\":\"record\",\"text\":\"合成🌲\",\"source\":\"japanese\",\"day\":\"2026-09-15\"}");
    assert(result.find("\"recorded\":3") != std::string::npos);
    const auto loaded = call(directory, "{\"operation\":\"load\"}");
    assert(loaded.find("\"total\":3") != std::string::npos);
    assert(loaded.find("合成🌲") == std::string::npos);
    std::filesystem::remove_all(directory);
    return 0;
}
