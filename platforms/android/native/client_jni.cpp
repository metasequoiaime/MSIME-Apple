#include <jni.h>
#include "msime_client.h"
#include <cstring>
#include <fstream>
#include <limits>
#include <string>

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

// Use UTF-8 byte arrays, not JNI modified UTF-8: supplementary characters in
// candidates and resource paths must survive the Java/native boundary unchanged.
static jbyteArray response(JNIEnv *env, char *value) {
    if (!value) return nullptr;
    size_t length = std::strlen(value);
    if (length > static_cast<size_t>(std::numeric_limits<jsize>::max())) {
        msime_client_string_free(value);
        env->ThrowNew(env->FindClass("java/lang/IllegalStateException"), "Native response too large");
        return nullptr;
    }
    jbyteArray output = env->NewByteArray(static_cast<jsize>(length));
    if (output) env->SetByteArrayRegion(output, 0, static_cast<jsize>(length), reinterpret_cast<const jbyte *>(value));
    msime_client_string_free(value);
    return output;
}

extern "C" {
JNIEXPORT jbyteArray JNICALL Java_app_msime_client_NativeClient_loadPreferencesRaw(JNIEnv *env, jclass, jbyteArray directory) {
    if (!directory) return response(env, msime_client_load_preferences(nullptr, 0));
    jsize length = env->GetArrayLength(directory);
    jbyte *bytes = env->GetByteArrayElements(directory, nullptr);
    if (!bytes) return nullptr;
    char *result = msime_client_load_preferences(reinterpret_cast<const uint8_t *>(bytes), static_cast<size_t>(length));
    env->ReleaseByteArrayElements(directory, bytes, JNI_ABORT);
    return response(env, result);
}
JNIEXPORT jbyteArray JNICALL Java_app_msime_client_NativeClient_typingStatisticsRaw(JNIEnv *env, jclass, jbyteArray request) {
    if (!request) return response(env, msime_client_typing_statistics(nullptr, 0));
    jsize length = env->GetArrayLength(request);
    jbyte *bytes = env->GetByteArrayElements(request, nullptr);
    if (!bytes) return nullptr;
    char *result = msime_client_typing_statistics(
        reinterpret_cast<const uint8_t *>(bytes), static_cast<size_t>(length));
    env->ReleaseByteArrayElements(request, bytes, JNI_ABORT);
    return response(env, result);
}
JNIEXPORT jbyteArray JNICALL Java_app_msime_client_NativeClient_emojiCatalogRaw(JNIEnv *env, jclass, jbyteArray query, jbyteArray resources) {
    if (!query || !resources) {
        return response(env, msime_client_emoji_catalog_request(nullptr, 0, nullptr, 0));
    }
    jsize query_length = env->GetArrayLength(query);
    jbyte *query_bytes = env->GetByteArrayElements(query, nullptr);
    if (!query_bytes) return nullptr;
    jsize resources_length = env->GetArrayLength(resources);
    jbyte *resources_bytes = env->GetByteArrayElements(resources, nullptr);
    if (!resources_bytes) {
        env->ReleaseByteArrayElements(query, query_bytes, JNI_ABORT);
        return nullptr;
    }
    char *result = msime_client_emoji_catalog_request(
        reinterpret_cast<const uint8_t *>(query_bytes), static_cast<size_t>(query_length),
        reinterpret_cast<const uint8_t *>(resources_bytes), static_cast<size_t>(resources_length));
    env->ReleaseByteArrayElements(resources, resources_bytes, JNI_ABORT);
    env->ReleaseByteArrayElements(query, query_bytes, JNI_ABORT);
    return response(env, result);
}
JNIEXPORT jbyteArray JNICALL Java_app_msime_client_NativeClient_candidateGlossesRaw(JNIEnv *env, jclass, jbyteArray request, jbyteArray resources) {
    if (!request || !resources) {
        return response(env, msime_client_candidate_gloss_request(nullptr, 0, nullptr, 0));
    }
    jsize request_length = env->GetArrayLength(request);
    jbyte *request_bytes = env->GetByteArrayElements(request, nullptr);
    if (!request_bytes) return nullptr;
    jsize resources_length = env->GetArrayLength(resources);
    jbyte *resources_bytes = env->GetByteArrayElements(resources, nullptr);
    if (!resources_bytes) {
        env->ReleaseByteArrayElements(request, request_bytes, JNI_ABORT);
        return nullptr;
    }
    char *result = msime_client_candidate_gloss_request(
        reinterpret_cast<const uint8_t *>(request_bytes), static_cast<size_t>(request_length),
        reinterpret_cast<const uint8_t *>(resources_bytes), static_cast<size_t>(resources_length));
    env->ReleaseByteArrayElements(resources, resources_bytes, JNI_ABORT);
    env->ReleaseByteArrayElements(request, request_bytes, JNI_ABORT);
    return response(env, result);
}
JNIEXPORT jbyteArray JNICALL Java_app_msime_client_NativeClient_savePreferencesRaw(JNIEnv *env, jclass, jbyteArray directory, jlong expected_revision, jbyteArray snapshot) {
    if (!directory || !snapshot || expected_revision < 0) {
        return response(env, msime_client_save_preferences(nullptr, 0, 0, nullptr, 0));
    }
    jsize directory_length = env->GetArrayLength(directory);
    jbyte *directory_bytes = env->GetByteArrayElements(directory, nullptr);
    if (!directory_bytes) return nullptr;
    jsize snapshot_length = env->GetArrayLength(snapshot);
    jbyte *snapshot_bytes = env->GetByteArrayElements(snapshot, nullptr);
    if (!snapshot_bytes) {
        env->ReleaseByteArrayElements(directory, directory_bytes, JNI_ABORT);
        return nullptr;
    }
    char *result = msime_client_save_preferences(
        reinterpret_cast<const uint8_t *>(directory_bytes), static_cast<size_t>(directory_length),
        static_cast<uint64_t>(expected_revision),
        reinterpret_cast<const uint8_t *>(snapshot_bytes), static_cast<size_t>(snapshot_length));
    env->ReleaseByteArrayElements(snapshot, snapshot_bytes, JNI_ABORT);
    env->ReleaseByteArrayElements(directory, directory_bytes, JNI_ABORT);
    return response(env, result);
}
JNIEXPORT jbyteArray JNICALL Java_app_msime_client_NativeClient_personalDictionarySyncRaw(JNIEnv *env, jclass, jbyteArray options) {
    if (!options) return response(env, msime_client_personal_dictionary_sync(nullptr, 0));
    jsize length = env->GetArrayLength(options);
    jbyte *bytes = env->GetByteArrayElements(options, nullptr);
    if (!bytes) return nullptr;
    char *result = msime_client_personal_dictionary_sync(
        reinterpret_cast<const uint8_t *>(bytes), static_cast<size_t>(length));
    env->ReleaseByteArrayElements(options, bytes, JNI_ABORT);
    return response(env, result);
}
JNIEXPORT jbyteArray JNICALL Java_app_msime_client_NativeClient_prepareHostRaw(JNIEnv *env, jclass, jbyteArray options) {
    if (!options) return response(env, msime_client_prepare_host(nullptr, 0));
    jsize length = env->GetArrayLength(options);
    jbyte *bytes = env->GetByteArrayElements(options, nullptr);
    if (!bytes) return nullptr;
    char *result = msime_client_prepare_host(reinterpret_cast<const uint8_t *>(bytes), static_cast<size_t>(length));
    env->ReleaseByteArrayElements(options, bytes, JNI_ABORT);
    return response(env, result);
}
JNIEXPORT jbyteArray JNICALL Java_app_msime_client_NativeClient_snapshotVersionRaw(JNIEnv *env, jclass, jbyteArray options) {
    if (!options) return response(env, msime_client_snapshot_version(nullptr, 0));
    jsize length = env->GetArrayLength(options);
    jbyte *bytes = env->GetByteArrayElements(options, nullptr);
    if (!bytes) return nullptr;
    char *result = msime_client_snapshot_version(
        reinterpret_cast<const uint8_t *>(bytes), static_cast<size_t>(length));
    env->ReleaseByteArrayElements(options, bytes, JNI_ABORT);
    return response(env, result);
}
JNIEXPORT jbyteArray JNICALL Java_app_msime_client_NativeClient_snapshotPrepareRaw(JNIEnv *env, jclass, jbyteArray request, jbyteArray file) {
    if (!request || !file) return response(env, msime_client_snapshot_prepare(nullptr, 0, nullptr, nullptr));
    jsize request_length = env->GetArrayLength(request);
    jbyte *request_bytes = env->GetByteArrayElements(request, nullptr);
    if (!request_bytes) return nullptr;
    jsize file_length = env->GetArrayLength(file);
    jbyte *file_bytes = env->GetByteArrayElements(file, nullptr);
    if (!file_bytes) {
        env->ReleaseByteArrayElements(request, request_bytes, JNI_ABORT);
        return nullptr;
    }
    std::string path(reinterpret_cast<const char *>(file_bytes), static_cast<size_t>(file_length));
    SnapshotReader reader(path);
    char *result = msime_client_snapshot_prepare(
        reinterpret_cast<const uint8_t *>(request_bytes), static_cast<size_t>(request_length),
        snapshotNext, &reader);
    env->ReleaseByteArrayElements(file, file_bytes, JNI_ABORT);
    env->ReleaseByteArrayElements(request, request_bytes, JNI_ABORT);
    return response(env, result);
}
JNIEXPORT jbyteArray JNICALL Java_app_msime_client_NativeClient_snapshotDiscardRaw(JNIEnv *env, jclass, jlong handle) {
    if (handle <= 0) return response(env, msime_client_snapshot_discard(0));
    return response(env, msime_client_snapshot_discard(static_cast<uint64_t>(handle)));
}
JNIEXPORT jbyteArray JNICALL Java_app_msime_client_NativeClient_snapshotActivateRaw(JNIEnv *env, jclass, jlong handle, jbyteArray expected) {
    if (!expected || handle <= 0) return response(env, msime_client_snapshot_activate(0, nullptr, 0));
    jsize length = env->GetArrayLength(expected);
    jbyte *bytes = env->GetByteArrayElements(expected, nullptr);
    if (!bytes) return nullptr;
    char *result = msime_client_snapshot_activate(
        static_cast<uint64_t>(handle), reinterpret_cast<const uint8_t *>(bytes),
        static_cast<size_t>(length));
    env->ReleaseByteArrayElements(expected, bytes, JNI_ABORT);
    return response(env, result);
}
JNIEXPORT jbyteArray JNICALL Java_app_msime_client_NativeClient_updatePreferencesRaw(JNIEnv *env, jclass, jlong handle, jbyteArray snapshot) {
    if (!snapshot) return response(env, msime_client_update_preferences(static_cast<uint64_t>(handle), nullptr, 0));
    jsize length = env->GetArrayLength(snapshot);
    jbyte *bytes = env->GetByteArrayElements(snapshot, nullptr);
    if (!bytes) return nullptr;
    char *result = msime_client_update_preferences(static_cast<uint64_t>(handle), reinterpret_cast<const uint8_t *>(bytes), static_cast<size_t>(length));
    env->ReleaseByteArrayElements(snapshot, bytes, JNI_ABORT);
    return response(env, result);
}
JNIEXPORT jbyteArray JNICALL Java_app_msime_client_NativeClient_createRaw(JNIEnv *env, jclass, jbyteArray options) {
    if (!options) return response(env, msime_client_create(nullptr, 0));
    jsize length = env->GetArrayLength(options);
    jbyte *bytes = env->GetByteArrayElements(options, nullptr);
    if (!bytes) return nullptr;
    char *result = msime_client_create(reinterpret_cast<const uint8_t *>(bytes), static_cast<size_t>(length));
    env->ReleaseByteArrayElements(options, bytes, JNI_ABORT);
    return response(env, result);
}
JNIEXPORT jbyteArray JNICALL Java_app_msime_client_NativeClient_focusRaw(JNIEnv *env, jclass, jlong handle, jboolean focused) {
    return response(env, msime_client_focus(static_cast<uint64_t>(handle), focused == JNI_TRUE));
}
JNIEXPORT jbyteArray JNICALL Java_app_msime_client_NativeClient_setNineKeyModeRaw(JNIEnv *env, jclass, jlong handle, jboolean enabled) {
    return response(env, msime_client_set_nine_key_mode(static_cast<uint64_t>(handle), enabled == JNI_TRUE));
}
JNIEXPORT jbyteArray JNICALL Java_app_msime_client_NativeClient_setEnglishModeRaw(JNIEnv *env, jclass, jlong handle, jboolean enabled) {
    return response(env, msime_client_set_english_mode(static_cast<uint64_t>(handle), enabled == JNI_TRUE));
}
JNIEXPORT jbyteArray JNICALL Java_app_msime_client_NativeClient_characterRaw(JNIEnv *env, jclass, jlong handle, jint ascii, jboolean shift) {
    if (ascii < 0 || ascii > 127) {
        env->ThrowNew(env->FindClass("java/lang/IllegalArgumentException"), "Engine character must be ASCII");
        return nullptr;
    }
    return response(env, msime_client_character(static_cast<uint64_t>(handle), static_cast<uint8_t>(ascii), shift == JNI_TRUE));
}
JNIEXPORT jbyteArray JNICALL Java_app_msime_client_NativeClient_commandRaw(JNIEnv *env, jclass, jlong handle, jint command) {
    return response(env, msime_client_command(static_cast<uint64_t>(handle), static_cast<uint32_t>(command)));
}
JNIEXPORT jbyteArray JNICALL Java_app_msime_client_NativeClient_selectRaw(JNIEnv *env, jclass, jlong handle, jlong generation, jlong index) {
    if (index < 0 || static_cast<uint64_t>(index) > std::numeric_limits<size_t>::max()) {
        env->ThrowNew(env->FindClass("java/lang/IllegalArgumentException"), "Invalid candidate index");
        return nullptr;
    }
    return response(env, msime_client_select(static_cast<uint64_t>(handle), static_cast<uint64_t>(generation), static_cast<size_t>(index)));
}
JNIEXPORT jbyteArray JNICALL Java_app_msime_client_NativeClient_selectAnyCandidateRaw(JNIEnv *env, jclass, jlong handle, jlong generation, jlong index) {
    if (index < 0 || static_cast<uint64_t>(index) > std::numeric_limits<size_t>::max()) {
        env->ThrowNew(env->FindClass("java/lang/IllegalArgumentException"), "Invalid candidate index");
        return nullptr;
    }
    return response(env, msime_client_select_any_candidate(static_cast<uint64_t>(handle), static_cast<uint64_t>(generation), static_cast<size_t>(index)));
}
JNIEXPORT jbyteArray JNICALL Java_app_msime_client_NativeClient_pinCandidateRaw(JNIEnv *env, jclass, jlong handle, jlong generation, jlong index) {
    if (index < 0 || static_cast<uint64_t>(index) > std::numeric_limits<size_t>::max()) {
        env->ThrowNew(env->FindClass("java/lang/IllegalArgumentException"), "Invalid candidate index");
        return nullptr;
    }
    return response(env, msime_client_pin_candidate(static_cast<uint64_t>(handle), static_cast<uint64_t>(generation), static_cast<size_t>(index)));
}
JNIEXPORT jbyteArray JNICALL Java_app_msime_client_NativeClient_fixCandidatePositionRaw(JNIEnv *env, jclass, jlong handle, jlong generation, jlong index, jint position) {
    if (index < 0 || static_cast<uint64_t>(index) > std::numeric_limits<size_t>::max()) {
        env->ThrowNew(env->FindClass("java/lang/IllegalArgumentException"), "Invalid candidate index");
        return nullptr;
    }
    if (position < 1 || position > 5) {
        env->ThrowNew(env->FindClass("java/lang/IllegalArgumentException"), "Candidate position must be between 1 and 5");
        return nullptr;
    }
    return response(env, msime_client_fix_candidate_position(static_cast<uint64_t>(handle), static_cast<uint64_t>(generation), static_cast<size_t>(index), static_cast<uint8_t>(position)));
}
JNIEXPORT jbyteArray JNICALL Java_app_msime_client_NativeClient_clearCandidatePositionRaw(JNIEnv *env, jclass, jlong handle, jlong generation, jlong index) {
    if (index < 0 || static_cast<uint64_t>(index) > std::numeric_limits<size_t>::max()) {
        env->ThrowNew(env->FindClass("java/lang/IllegalArgumentException"), "Invalid candidate index");
        return nullptr;
    }
    return response(env, msime_client_clear_candidate_position(static_cast<uint64_t>(handle), static_cast<uint64_t>(generation), static_cast<size_t>(index)));
}
JNIEXPORT jbyteArray JNICALL Java_app_msime_client_NativeClient_removeCandidateRaw(JNIEnv *env, jclass, jlong handle, jlong generation, jlong index) {
    if (index < 0 || static_cast<uint64_t>(index) > std::numeric_limits<size_t>::max()) {
        env->ThrowNew(env->FindClass("java/lang/IllegalArgumentException"), "Invalid candidate index");
        return nullptr;
    }
    return response(env, msime_client_remove_candidate(static_cast<uint64_t>(handle), static_cast<uint64_t>(generation), static_cast<size_t>(index)));
}
JNIEXPORT jbyteArray JNICALL Java_app_msime_client_NativeClient_chooseNineKeySpellingRaw(JNIEnv *env, jclass, jlong handle, jlong generation, jlong index) {
    if (index < 0 || static_cast<uint64_t>(index) > std::numeric_limits<size_t>::max()) {
        env->ThrowNew(env->FindClass("java/lang/IllegalArgumentException"), "Invalid nine-key spelling index");
        return nullptr;
    }
    return response(env, msime_client_choose_nine_key_spelling(static_cast<uint64_t>(handle), static_cast<uint64_t>(generation), static_cast<size_t>(index)));
}
JNIEXPORT jbyteArray JNICALL Java_app_msime_client_NativeClient_viewRaw(JNIEnv *env, jclass, jlong handle) {
    return response(env, msime_client_view(static_cast<uint64_t>(handle)));
}
JNIEXPORT jbyteArray JNICALL Java_app_msime_client_NativeClient_allCandidatesRaw(JNIEnv *env, jclass, jlong handle) {
    return response(env, msime_client_all_candidates(static_cast<uint64_t>(handle)));
}
JNIEXPORT jbyteArray JNICALL Java_app_msime_client_NativeClient_applyTranslationsRaw(JNIEnv *env, jclass, jlong handle, jlong generation, jbyteArray translations) {
    if (!translations || generation < 0) {
        return response(env, msime_client_apply_translations(static_cast<uint64_t>(handle),
            static_cast<uint64_t>(generation), nullptr, 0));
    }
    jsize length = env->GetArrayLength(translations);
    jbyte *bytes = env->GetByteArrayElements(translations, nullptr);
    if (!bytes) return nullptr;
    char *result = msime_client_apply_translations(static_cast<uint64_t>(handle),
        static_cast<uint64_t>(generation), reinterpret_cast<const uint8_t *>(bytes),
        static_cast<size_t>(length));
    env->ReleaseByteArrayElements(translations, bytes, JNI_ABORT);
    return response(env, result);
}
JNIEXPORT jbyteArray JNICALL Java_app_msime_client_NativeClient_destroyRaw(JNIEnv *env, jclass, jlong handle) {
    return response(env, msime_client_destroy(static_cast<uint64_t>(handle)));
}
}
