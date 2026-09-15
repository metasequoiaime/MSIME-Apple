#include "msime_client.h"
#include <napi/native_api.h>
#include <cstring>
#include <fstream>
#include <limits>
#include <string>
#include <vector>

// Mirrors platforms/android/native/client_jni.cpp. The shared C ABI takes UTF-8 JSON in and returns
// UTF-8 JSON out, so every binding here is the same three steps: read the arguments, call one
// msime_client_* entry point, hand the response back and free it.

struct SnapshotReader {
    explicit SnapshotReader(const std::string &path) : input(path, std::ios::in | std::ios::binary) {}
    std::ifstream input;
};

static intptr_t snapshotNext(void *context, uint8_t *buffer, size_t capacity) noexcept {
    auto *reader = static_cast<SnapshotReader *>(context);
    if (!reader || !buffer || capacity == 0) return -1;
    for (;;) {
        size_t length = 0;
        bool ended = false;
        while (length < capacity) {
            const int value = reader->input.get();
            if (value == EOF) {
                if (!reader->input.eof()) return -1;
                ended = true;
                break;
            }
            if (value == '\n') {
                ended = true;
                break;
            }
            if (value == '\r' && reader->input.peek() == '\n') {
                reader->input.get();
                ended = true;
                break;
            }
            buffer[length++] = static_cast<uint8_t>(value);
        }
        if (!ended || length == 0) return ended && length == 0 ? 0 : -1;
        buffer[length] = 0;
        const char *type = std::strstr(reinterpret_cast<const char *>(buffer), "\"type\":\"");
        if (!type) return -1;
        type += 8;
        const bool engine_record = std::strncmp(type, "overlay\"", 8) == 0
            || std::strncmp(type, "position\"", 9) == 0
            || std::strncmp(type, "selection\"", 10) == 0;
        if (engine_record) return static_cast<intptr_t>(length);
        if (std::strncmp(type, "header\"", 7) == 0
                || std::strncmp(type, "entry\"", 6) == 0
                || std::strncmp(type, "footer\"", 7) == 0) continue;
        return -1;
    }
}

// The Rust side owns the response buffer until it is handed back, so every exit path frees it.
static napi_value response(napi_env env, char *value) {
    if (!value) return nullptr;
    const size_t length = std::strlen(value);
    napi_value output = nullptr;
    const napi_status status = napi_create_string_utf8(env, value, length, &output);
    msime_client_string_free(value);
    return status == napi_ok ? output : nullptr;
}

// Arguments arrive as ArkTS strings holding UTF-8 JSON. napi_create/get_string_utf8 is plain UTF-8,
// unlike JNI's modified form, so supplementary characters in candidates and resource paths cross
// unchanged without a byte-array detour.
static bool argumentText(napi_env env, napi_value value, std::string &out) {
    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok) return false;
    out.assign(length, '\0');
    size_t written = 0;
    if (napi_get_value_string_utf8(env, value, out.data(), length + 1, &written) != napi_ok) {
        return false;
    }
    out.resize(written);
    return true;
}

static bool argumentHandle(napi_env env, napi_value value, uint64_t &out) {
    int64_t handle = 0;
    if (napi_get_value_int64(env, value, &handle) != napi_ok || handle < 0) return false;
    out = static_cast<uint64_t>(handle);
    return true;
}

static bool argumentFlag(napi_env env, napi_value value, bool &out) {
    return napi_get_value_bool(env, value, &out) == napi_ok;
}

static bool argumentIndex(napi_env env, napi_value value, size_t &out) {
    int64_t index = 0;
    if (napi_get_value_int64(env, value, &index) != napi_ok) return false;
    if (index < 0 || static_cast<uint64_t>(index) > std::numeric_limits<size_t>::max()) return false;
    out = static_cast<size_t>(index);
    return true;
}

static bool arguments(napi_env env, napi_callback_info info, size_t expected,
                      std::vector<napi_value> &out) {
    size_t count = expected;
    out.assign(expected, nullptr);
    if (napi_get_cb_info(env, info, &count, out.data(), nullptr, nullptr) != napi_ok) return false;
    return count >= expected;
}

static napi_value invalid(napi_env env, const char *message) {
    napi_throw_error(env, nullptr, message);
    return nullptr;
}

// A malformed document reaches the Rust side as an empty buffer, which answers with the same
// structured error every other host sees rather than a native crash.
#define TEXT_ENTRY(name, call)                                                                     \
    static napi_value name(napi_env env, napi_callback_info info) {                                 \
        std::vector<napi_value> argv;                                                               \
        std::string text;                                                                           \
        if (!arguments(env, info, 1, argv) || !argumentText(env, argv[0], text)) {                  \
            return response(env, call(nullptr, 0));                                                 \
        }                                                                                           \
        return response(env,                                                                        \
            call(reinterpret_cast<const uint8_t *>(text.data()), text.size()));                     \
    }

TEXT_ENTRY(LoadPreferences, msime_client_load_preferences)
TEXT_ENTRY(TypingStatistics, msime_client_typing_statistics)
TEXT_ENTRY(PersonalDictionarySync, msime_client_personal_dictionary_sync)
TEXT_ENTRY(PrepareHost, msime_client_prepare_host)
TEXT_ENTRY(SnapshotVersion, msime_client_snapshot_version)
TEXT_ENTRY(Create, msime_client_create)

#define PAIR_ENTRY(name, call)                                                                     \
    static napi_value name(napi_env env, napi_callback_info info) {                                 \
        std::vector<napi_value> argv;                                                               \
        std::string first;                                                                          \
        std::string second;                                                                         \
        if (!arguments(env, info, 2, argv) || !argumentText(env, argv[0], first)                    \
                || !argumentText(env, argv[1], second)) {                                           \
            return response(env, call(nullptr, 0, nullptr, 0));                                     \
        }                                                                                           \
        return response(env,                                                                        \
            call(reinterpret_cast<const uint8_t *>(first.data()), first.size(),                     \
                 reinterpret_cast<const uint8_t *>(second.data()), second.size()));                 \
    }

PAIR_ENTRY(EmojiCatalog, msime_client_emoji_catalog_request)
PAIR_ENTRY(CandidateGlosses, msime_client_candidate_gloss_request)

#define HANDLE_ENTRY(name, call)                                                                   \
    static napi_value name(napi_env env, napi_callback_info info) {                                 \
        std::vector<napi_value> argv;                                                               \
        uint64_t handle = 0;                                                                        \
        if (!arguments(env, info, 1, argv) || !argumentHandle(env, argv[0], handle)) {              \
            return invalid(env, "Session handle must be a non-negative integer");                    \
        }                                                                                           \
        return response(env, call(handle));                                                         \
    }

HANDLE_ENTRY(SnapshotDiscard, msime_client_snapshot_discard)
HANDLE_ENTRY(View, msime_client_view)
HANDLE_ENTRY(AllCandidates, msime_client_all_candidates)
HANDLE_ENTRY(Destroy, msime_client_destroy)

#define FLAG_ENTRY(name, call)                                                                      \
    static napi_value name(napi_env env, napi_callback_info info) {                                 \
        std::vector<napi_value> argv;                                                               \
        uint64_t handle = 0;                                                                        \
        bool enabled = false;                                                                       \
        if (!arguments(env, info, 2, argv) || !argumentHandle(env, argv[0], handle)                 \
                || !argumentFlag(env, argv[1], enabled)) {                                          \
            return invalid(env, "Expected a session handle and a boolean");                          \
        }                                                                                           \
        return response(env, call(handle, enabled));                                                \
    }

FLAG_ENTRY(Focus, msime_client_focus)
FLAG_ENTRY(SetNineKeyMode, msime_client_set_nine_key_mode)
FLAG_ENTRY(SetEnglishMode, msime_client_set_english_mode)

// Candidate identity is the generation plus the index, so a stale page cannot act on a fresh one.
#define CANDIDATE_ENTRY(name, call, message)                                                        \
    static napi_value name(napi_env env, napi_callback_info info) {                                 \
        std::vector<napi_value> argv;                                                               \
        uint64_t handle = 0;                                                                        \
        uint64_t generation = 0;                                                                    \
        size_t index = 0;                                                                           \
        if (!arguments(env, info, 3, argv) || !argumentHandle(env, argv[0], handle)                 \
                || !argumentHandle(env, argv[1], generation)                                        \
                || !argumentIndex(env, argv[2], index)) {                                           \
            return invalid(env, message);                                                           \
        }                                                                                           \
        return response(env, call(handle, generation, index));                                      \
    }

CANDIDATE_ENTRY(Select, msime_client_select, "Invalid candidate index")
CANDIDATE_ENTRY(SelectAnyCandidate, msime_client_select_any_candidate, "Invalid candidate index")
CANDIDATE_ENTRY(PinCandidate, msime_client_pin_candidate, "Invalid candidate index")
CANDIDATE_ENTRY(ClearCandidatePosition, msime_client_clear_candidate_position,
                "Invalid candidate index")
CANDIDATE_ENTRY(RemoveCandidate, msime_client_remove_candidate, "Invalid candidate index")
CANDIDATE_ENTRY(ChooseNineKeySpelling, msime_client_choose_nine_key_spelling,
                "Invalid nine-key spelling index")

static napi_value SavePreferences(napi_env env, napi_callback_info info) {
    std::vector<napi_value> argv;
    std::string directory;
    std::string snapshot;
    uint64_t revision = 0;
    if (!arguments(env, info, 3, argv) || !argumentText(env, argv[0], directory)
            || !argumentHandle(env, argv[1], revision)
            || !argumentText(env, argv[2], snapshot)) {
        return response(env, msime_client_save_preferences(nullptr, 0, 0, nullptr, 0));
    }
    return response(env, msime_client_save_preferences(
        reinterpret_cast<const uint8_t *>(directory.data()), directory.size(), revision,
        reinterpret_cast<const uint8_t *>(snapshot.data()), snapshot.size()));
}

static napi_value SnapshotPrepare(napi_env env, napi_callback_info info) {
    std::vector<napi_value> argv;
    std::string request;
    std::string file;
    if (!arguments(env, info, 2, argv) || !argumentText(env, argv[0], request)
            || !argumentText(env, argv[1], file)) {
        return response(env, msime_client_snapshot_prepare(nullptr, 0, nullptr, nullptr));
    }
    SnapshotReader reader(file);
    return response(env, msime_client_snapshot_prepare(
        reinterpret_cast<const uint8_t *>(request.data()), request.size(), snapshotNext, &reader));
}

static napi_value SnapshotActivate(napi_env env, napi_callback_info info) {
    std::vector<napi_value> argv;
    uint64_t handle = 0;
    std::string expected;
    if (!arguments(env, info, 2, argv) || !argumentHandle(env, argv[0], handle)
            || !argumentText(env, argv[1], expected)) {
        return response(env, msime_client_snapshot_activate(0, nullptr, 0));
    }
    return response(env, msime_client_snapshot_activate(
        handle, reinterpret_cast<const uint8_t *>(expected.data()), expected.size()));
}

static napi_value UpdatePreferences(napi_env env, napi_callback_info info) {
    std::vector<napi_value> argv;
    uint64_t handle = 0;
    std::string snapshot;
    if (!arguments(env, info, 2, argv) || !argumentHandle(env, argv[0], handle)) {
        return invalid(env, "Session handle must be a non-negative integer");
    }
    if (!argumentText(env, argv[1], snapshot)) {
        return response(env, msime_client_update_preferences(handle, nullptr, 0));
    }
    return response(env, msime_client_update_preferences(
        handle, reinterpret_cast<const uint8_t *>(snapshot.data()), snapshot.size()));
}

static napi_value Character(napi_env env, napi_callback_info info) {
    std::vector<napi_value> argv;
    uint64_t handle = 0;
    int32_t ascii = 0;
    bool shift = false;
    if (!arguments(env, info, 3, argv) || !argumentHandle(env, argv[0], handle)
            || napi_get_value_int32(env, argv[1], &ascii) != napi_ok
            || !argumentFlag(env, argv[2], shift)) {
        return invalid(env, "Expected a session handle, an ASCII code and a boolean");
    }
    if (ascii < 0 || ascii > 127) return invalid(env, "Engine character must be ASCII");
    return response(env,
        msime_client_character(handle, static_cast<uint8_t>(ascii), shift));
}

static napi_value PunctuationWithContext(napi_env env, napi_callback_info info) {
    std::vector<napi_value> argv;
    uint64_t handle = 0;
    int32_t ascii = 0;
    int32_t preceding = 0;
    if (!arguments(env, info, 3, argv) || !argumentHandle(env, argv[0], handle)
            || napi_get_value_int32(env, argv[1], &ascii) != napi_ok
            || napi_get_value_int32(env, argv[2], &preceding) != napi_ok) {
        return invalid(env, "Expected a session handle, an ASCII code and a preceding code point");
    }
    if (ascii < 0 || ascii > 127 || preceding < 0) {
        return invalid(env, "Invalid punctuation context");
    }
    return response(env, msime_client_punctuation_with_context(
        handle, static_cast<uint8_t>(ascii), static_cast<uint32_t>(preceding)));
}

static napi_value Command(napi_env env, napi_callback_info info) {
    std::vector<napi_value> argv;
    uint64_t handle = 0;
    uint32_t command = 0;
    if (!arguments(env, info, 2, argv) || !argumentHandle(env, argv[0], handle)
            || napi_get_value_uint32(env, argv[1], &command) != napi_ok) {
        return invalid(env, "Expected a session handle and a command code");
    }
    return response(env, msime_client_command(handle, command));
}

static napi_value FixCandidatePosition(napi_env env, napi_callback_info info) {
    std::vector<napi_value> argv;
    uint64_t handle = 0;
    uint64_t generation = 0;
    size_t index = 0;
    int32_t position = 0;
    if (!arguments(env, info, 4, argv) || !argumentHandle(env, argv[0], handle)
            || !argumentHandle(env, argv[1], generation) || !argumentIndex(env, argv[2], index)
            || napi_get_value_int32(env, argv[3], &position) != napi_ok) {
        return invalid(env, "Invalid candidate index");
    }
    if (position < 1 || position > 5) {
        return invalid(env, "Candidate position must be between 1 and 5");
    }
    return response(env, msime_client_fix_candidate_position(
        handle, generation, index, static_cast<uint8_t>(position)));
}

static napi_value ApplyTranslations(napi_env env, napi_callback_info info) {
    std::vector<napi_value> argv;
    uint64_t handle = 0;
    uint64_t generation = 0;
    std::string translations;
    if (!arguments(env, info, 3, argv) || !argumentHandle(env, argv[0], handle)
            || !argumentHandle(env, argv[1], generation)
            || !argumentText(env, argv[2], translations)) {
        return response(env, msime_client_apply_translations(0, 0, nullptr, 0));
    }
    return response(env, msime_client_apply_translations(handle, generation,
        reinterpret_cast<const uint8_t *>(translations.data()), translations.size()));
}

static napi_value AbiVersion(napi_env env, napi_callback_info) {
    napi_value output = nullptr;
    if (napi_create_uint32(env, msime_client_abi_version(), &output) != napi_ok) return nullptr;
    return output;
}

static napi_value HostCapabilities(napi_env env, napi_callback_info info) {
    std::vector<napi_value> argv;
    std::string platform;
    if (!arguments(env, info, 1, argv) || !argumentText(env, argv[0], platform)) {
        return response(env, msime_client_host_capabilities(nullptr, 0));
    }
    return response(env, msime_client_host_capabilities(
        reinterpret_cast<const uint8_t *>(platform.data()), platform.size()));
}

#define ENTRY(exported, function)                                                                  \
    { exported, nullptr, function, nullptr, nullptr, nullptr, napi_default, nullptr }

static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor properties[] = {
        ENTRY("abiVersion", AbiVersion),
        ENTRY("hostCapabilities", HostCapabilities),
        ENTRY("loadPreferences", LoadPreferences),
        ENTRY("savePreferences", SavePreferences),
        ENTRY("updatePreferences", UpdatePreferences),
        ENTRY("typingStatistics", TypingStatistics),
        ENTRY("emojiCatalog", EmojiCatalog),
        ENTRY("candidateGlosses", CandidateGlosses),
        ENTRY("personalDictionarySync", PersonalDictionarySync),
        ENTRY("prepareHost", PrepareHost),
        ENTRY("snapshotVersion", SnapshotVersion),
        ENTRY("snapshotPrepare", SnapshotPrepare),
        ENTRY("snapshotDiscard", SnapshotDiscard),
        ENTRY("snapshotActivate", SnapshotActivate),
        ENTRY("create", Create),
        ENTRY("destroy", Destroy),
        ENTRY("focus", Focus),
        ENTRY("setNineKeyMode", SetNineKeyMode),
        ENTRY("setEnglishMode", SetEnglishMode),
        ENTRY("character", Character),
        ENTRY("punctuationWithContext", PunctuationWithContext),
        ENTRY("command", Command),
        ENTRY("select", Select),
        ENTRY("selectAnyCandidate", SelectAnyCandidate),
        ENTRY("pinCandidate", PinCandidate),
        ENTRY("fixCandidatePosition", FixCandidatePosition),
        ENTRY("clearCandidatePosition", ClearCandidatePosition),
        ENTRY("removeCandidate", RemoveCandidate),
        ENTRY("chooseNineKeySpelling", ChooseNineKeySpelling),
        ENTRY("view", View),
        ENTRY("allCandidates", AllCandidates),
        ENTRY("applyTranslations", ApplyTranslations),
    };
    if (napi_define_properties(env, exports,
            sizeof(properties) / sizeof(properties[0]), properties) != napi_ok) {
        return nullptr;
    }
    return exports;
}

static napi_module client_module = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "msimeclient",
    .nm_priv = nullptr,
    .reserved = { nullptr },
};

extern "C" __attribute__((constructor)) void RegisterClientModule(void) {
    napi_module_register(&client_module);
}
