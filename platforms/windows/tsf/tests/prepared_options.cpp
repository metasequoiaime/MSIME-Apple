#include "../HostOptionsPaths.h"
#include <chrono>
#include <cstdlib>
#include <fstream>

int main() {
    const auto root = std::filesystem::temp_directory_path() /
        ("msime-prepared-options-" + std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
    if (!std::filesystem::create_directory(root)) return EXIT_FAILURE;
    const auto path = root / "runtime-options.json";
    const auto write = [&](const std::string &text) {
        std::ofstream stream(path, std::ios::binary | std::ios::trunc);
        stream.write(text.data(), static_cast<std::streamsize>(text.size()));
        if (!stream) std::abort();
    };
    bool ok = msime::tsf::read_prepared_host_options(path).empty();
    // Synthetic fixture: schema/Engine validation belongs to the C ABI.
    const std::string document = R"({"api_version":1,"preferences":{"scheme":"shuangpin","shuangpin_profile":"microsoft","candidate_page_size":7,"learning":false,"chinese_punctuation":false},"preferences_directory":"synthetic-state"})";
    write(document);
    ok = ok && msime::tsf::read_prepared_host_options(path) == document;
    write("");
    ok = ok && msime::tsf::read_prepared_host_options(path).empty();
    write(std::string(16384, ' '));
    ok = ok && msime::tsf::read_prepared_host_options(path).size() == 16384;
    write(std::string(16385, ' '));
    ok = ok && msime::tsf::read_prepared_host_options(path).empty();
    std::filesystem::remove(path);
    std::filesystem::remove(root);
    return ok ? EXIT_SUCCESS : EXIT_FAILURE;
}
