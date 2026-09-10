#pragma once
#include <metasequoia/session.h>
#include <filesystem>

namespace metasequoia::mac
{
inline LocalModeOptions LocalResourceModes(bool enabled, const RuntimePaths &paths)
{
    LocalModeOptions options;
    options.unicode = enabled;
    options.date_time = enabled;
    options.quick_phrase = enabled;
    options.super_jianpin = enabled;
    const auto available = [](const std::filesystem::path &path) {
        std::error_code error;
        return std::filesystem::is_regular_file(path, error);
    };
    options.emoji = enabled && available(paths.resources / "others.db");
    options.kaomoji = options.emoji;
    options.temporary_english = enabled && available(paths.dictionaries / "english.db");
    options.temporary_japanese = enabled && available(paths.resources / "dict_japanese.dat") &&
        available(paths.dictionaries / "msime.db");
    return options;
}
}
