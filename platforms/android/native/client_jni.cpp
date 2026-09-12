#include <jni.h>
#include "msime_client.h"
#include <cstring>
#include <limits>

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
JNIEXPORT jbyteArray JNICALL Java_app_msime_client_NativeClient_prepareHostRaw(JNIEnv *env, jclass, jbyteArray options) {
    if (!options) return response(env, msime_client_prepare_host(nullptr, 0));
    jsize length = env->GetArrayLength(options);
    jbyte *bytes = env->GetByteArrayElements(options, nullptr);
    if (!bytes) return nullptr;
    char *result = msime_client_prepare_host(reinterpret_cast<const uint8_t *>(bytes), static_cast<size_t>(length));
    env->ReleaseByteArrayElements(options, bytes, JNI_ABORT);
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
JNIEXPORT jbyteArray JNICALL Java_app_msime_client_NativeClient_destroyRaw(JNIEnv *env, jclass, jlong handle) {
    return response(env, msime_client_destroy(static_cast<uint64_t>(handle)));
}
}
