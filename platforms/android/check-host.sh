#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/../.." && pwd)
android_sdk=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}
if [[ -z "$android_sdk" ]]; then
  echo "Set ANDROID_SDK_ROOT to an installed Android SDK" >&2
  exit 1
fi
android_jar="$android_sdk/platforms/android-35/android.jar"
if [[ ! -f "$android_jar" ]]; then
  echo "Android API 35 platform is required" >&2
  exit 1
fi
output_dir=$(mktemp -d)
trap 'rm -f "$output_dir/manifest.apk" "$output_dir/resources.zip"; find "$output_dir" -name "*.class" -delete; find "$output_dir" -depth -type d -empty -delete' EXIT
# Command 9 was unmapped when this guard was added; it is now Action::Finish in
# crates/host-api/src/ffi/input.rs, and the declined-punctuation path needs it.
# What must not come back is the literal, which is how the unmapped call got in.
if rg -n 'NativeClient\.command\([^,]+, 9\)' "$repo_root/platforms/android/java/app/msime/client/core/MSIMEInputService.java"; then
  echo "Android input service must name command 9 (FINISH_COMPOSITION_COMMAND), not inline it" >&2
  exit 1
fi
if ! rg -q 'msime_client_command' "$repo_root/crates/host-api/src/ffi/input.rs" \
  || ! rg -q '^\s*9 => Action::Finish,' "$repo_root/crates/host-api/src/ffi/input.rs"; then
  echo "Shared host command 9 is no longer Action::Finish; FINISH_COMPOSITION_COMMAND is stale" >&2
  exit 1
fi
# The JNI translation unit is the one place a Java declaration and a shared FFI
# signature have to agree, and nothing else in this script reads it: a method
# declared native in Java compiles whether or not the C++ side exists. Compiling
# it for the real target catches that without the full native build, which needs
# vcpkg and the Engine. A machine without the pinned NDK skips it and says so.
ndk=${MSIME_ANDROID_NDK:-${android_sdk}/ndk/28.2.13676358}
case $(uname -s) in
  Darwin) host_tag=darwin-x86_64 ;;
  Linux) host_tag=linux-x86_64 ;;
  *) host_tag="" ;;
esac
jni_compiler="$ndk/toolchains/llvm/prebuilt/$host_tag/bin/aarch64-linux-android28-clang++"
if [[ -n "$host_tag" && -x "$jni_compiler" ]]; then
  "$jni_compiler" -std=c++20 -fsyntax-only -Wall -Werror \
    -I"$repo_root/crates/host-api/include" \
    "$repo_root/platforms/android/native/client_jni.cpp"
  echo "client_jni.cpp: aarch64-linux-android compile against the shared header passed"
else
  echo "client_jni.cpp: skipped (pinned NDK 28.2.13676358 not installed)"
fi
# This script compiles against API 35 while the manifest declares minSdk 28, so a
# newer java.nio API passes here and only fails in the real APK build. These two
# arrived in API 34 and are the ones that actually got in; neither has a runtime
# version guard anywhere in this host. This is a targeted guard, not a general
# API-level check - Gradle lint is what covers the rest.
if rg -n 'Files\.(readString|writeString)\(' "$repo_root/platforms/android/java" --glob '*.java'; then
  echo "Files.readString/writeString need API 34; this host declares minSdk 28" >&2
  exit 1
fi
# The host compiles against AndroidX and Material now, and those are AARs that only Gradle resolves,
# so this script no longer compiles the whole source set -- `platforms/android/gradle-app` does, and
# build-apk.sh drives it. What stays here is the part that is worth having without a Gradle daemon:
# the pure-Java models and their smokes, which have no Android dependency at all and run in a second.
client_sources=()
while IFS= read -r source; do
  case "$source" in
    */home/*) continue ;;
  esac
  if rg -q '^import (androidx|com\.google\.android\.material)\.' "$source"; then continue; fi
  client_sources+=("$source")
done < <(find "$repo_root/platforms/android/java/app/msime/client" -name "*.java" -print)
javac --release 17 -Xlint:all -Werror -cp "$android_jar" -d "$output_dir" \
  "${client_sources[@]}" \
  "$repo_root/platforms/android/tests/core/EditorSmoke.java" \
  "$repo_root/platforms/android/tests/core/InputViewRefreshPolicySmoke.java" \
  "$repo_root/platforms/android/tests/core/EditorContextSnapshotSmoke.java" \
  "$repo_root/platforms/android/tests/settings/PreferencesSmoke.java" \
  "$repo_root/platforms/android/tests/keyboard/KeyboardLayoutSmoke.java" \
  "$repo_root/platforms/android/tests/keyboard/LetterKeyFacePolicySmoke.java" \
  "$repo_root/platforms/android/tests/keyboard/ReturnKeyActionSmoke.java" \
  "$repo_root/platforms/android/tests/keyboard/SpaceCursorMovementSmoke.java" \
  "$repo_root/platforms/android/tests/settings/EnglishCapitalizationPolicySmoke.java" \
  "$repo_root/platforms/android/tests/settings/EnglishLetterCaseStateSmoke.java" \
  "$repo_root/platforms/android/tests/dictionary/ChineseHelpcodePolicySmoke.java" \
  "$repo_root/platforms/android/tests/keyboard/MicrosoftShuangpinKeyPolicySmoke.java" \
  "$repo_root/platforms/android/tests/dictionary/ChineseOutputPolicySmoke.java" \
  "$repo_root/platforms/android/tests/core/FullWidthInputPolicySmoke.java" \
  "$repo_root/platforms/android/tests/core/DeclinedKeyPolicySmoke.java" \
  "$repo_root/platforms/android/tests/keyboard/KeyboardInputContextSmoke.java" \
  "$repo_root/platforms/android/tests/keyboard/KeyboardGeometrySmoke.java" \
  "$repo_root/platforms/android/tests/keyboard/KeyboardLayoutAdjustPolicySmoke.java" \
  "$repo_root/platforms/android/tests/voice/VoiceResultStoreSmoke.java" \
  "$repo_root/platforms/android/tests/voice/AiPolishClientSmoke.java" \
  "$repo_root/platforms/android/tests/candidate/ReplyKeyboardSmoke.java" \
  "$repo_root/platforms/android/tests/keyboard/KeyboardSkinSmoke.java" \
  "$repo_root/platforms/android/tests/keyboard/KeyboardFeedbackSmoke.java" \
  "$repo_root/platforms/android/tests/keyboard/KeyboardFeedbackStoreSmoke.java" \
  "$repo_root/platforms/android/tests/keyboard/KeyboardShortcutIconPolicySmoke.java" \
  "$repo_root/platforms/android/tests/voice/TypingSourceSmoke.java" \
  "$repo_root/platforms/android/tests/keyboard/EmojiCatalogModelSmoke.java" \
  "$repo_root/platforms/android/tests/core/MoreToolsLayoutSmoke.java" \
  "$repo_root/platforms/android/tests/keyboard/LocalInputModeSmoke.java" \
  "$repo_root/platforms/android/tests/keyboard/KeyboardSchemeSmoke.java" \
  "$repo_root/platforms/android/tests/keyboard/NineKeyLayoutSmoke.java" \
  "$repo_root/platforms/android/tests/keyboard/JapaneseNineKeyLayoutSmoke.java" \
  "$repo_root/platforms/android/tests/keyboard/JapaneseNineKeyActionsSmoke.java" \
  "$repo_root/platforms/android/tests/core/JapaneseVariantPolicySmoke.java" \
  "$repo_root/platforms/android/tests/voice/HandwritingContractSmoke.java" \
  "$repo_root/platforms/android/tests/candidate/CandidateAppearanceSmoke.java" \
  "$repo_root/platforms/android/tests/candidate/CandidateGlossModelSmoke.java" \
  "$repo_root/platforms/android/tests/candidate/CandidateTranslationPolicySmoke.java" \
  "$repo_root/platforms/android/tests/candidate/CandidateTranslationStoreSmoke.java" \
  "$repo_root/platforms/android/tests/candidate/OnlineCandidatePolicySmoke.java" \
  "$repo_root/platforms/android/tests/dictionary/WubiCodeHintPolicySmoke.java" \
  "$repo_root/platforms/android/tests/keyboard/ChineseSymbolFacesSmoke.java" \
  "$repo_root/platforms/android/tests/keyboard/ShuangpinKeyHintPolicySmoke.java" \
  "$repo_root/platforms/android/tests/keyboard/EnglishSuggestionPolicySmoke.java" \
  "$repo_root/platforms/android/tests/keyboard/EnglishSuggestionModelSmoke.java" \
  "$repo_root/platforms/android/tests/candidate/CandidatePanelSmoke.java" \
  "$repo_root/platforms/android/tests/candidate/CandidateManagementSmoke.java" \
  "$repo_root/platforms/android/tests/dictionary/ClipboardHistoryPolicySmoke.java" \
  "$repo_root/platforms/android/tests/dictionary/DictionarySnapshotQueueSmoke.java" \
  "$repo_root/platforms/android/tests/settings/DiagnosticPolicySmoke.java" \
  "$repo_root/platforms/android/tests/settings/SmartPunctuationContextSmoke.java" \
  "$repo_root/platforms/android/tests/keyboard/SymbolPanelModelSmoke.java"
java -cp "$output_dir" EditorSmoke
java -cp "$output_dir" InputViewRefreshPolicySmoke
java -cp "$output_dir" EditorContextSnapshotSmoke
java -cp "$output_dir" PreferencesSmoke
java -cp "$output_dir" KeyboardLayoutSmoke
java -cp "$output_dir" LetterKeyFacePolicySmoke
java -cp "$output_dir" ReturnKeyActionSmoke
java -cp "$output_dir" SpaceCursorMovementSmoke
java -cp "$output_dir" EnglishCapitalizationPolicySmoke
java -cp "$output_dir" EnglishLetterCaseStateSmoke
java -cp "$output_dir" app.msime.client.test.ChineseHelpcodePolicySmoke
java -cp "$output_dir" MicrosoftShuangpinKeyPolicySmoke
java -cp "$output_dir" ChineseOutputPolicySmoke
java -cp "$output_dir" FullWidthInputPolicySmoke
java -cp "$output_dir" DeclinedKeyPolicySmoke
java -cp "$output_dir" KeyboardInputContextSmoke
java -cp "$output_dir" KeyboardGeometrySmoke
java -cp "$output_dir" KeyboardLayoutAdjustPolicySmoke
java -cp "$output_dir" VoiceResultStoreSmoke
java -cp "$output_dir" AiPolishClientSmoke
java -cp "$output_dir" ReplyKeyboardSmoke
java -cp "$output_dir" app.msime.client.KeyboardSkinSmoke
java -cp "$output_dir" KeyboardFeedbackSmoke
java -cp "$output_dir" app.msime.client.KeyboardFeedbackStoreSmoke
java -cp "$output_dir" KeyboardShortcutIconPolicySmoke
java -cp "$output_dir" TypingSourceSmoke
java -cp "$output_dir" EmojiCatalogModelSmoke
java -cp "$output_dir" MoreToolsLayoutSmoke
java -cp "$output_dir" LocalInputModeSmoke
java -cp "$output_dir" KeyboardSchemeSmoke
java -cp "$output_dir" NineKeyLayoutSmoke
java -cp "$output_dir" JapaneseNineKeyLayoutSmoke
java -cp "$output_dir" JapaneseNineKeyActionsSmoke
java -cp "$output_dir" JapaneseVariantPolicySmoke
java -cp "$output_dir" HandwritingContractSmoke
java -cp "$output_dir" CandidateAppearanceSmoke
java -cp "$output_dir" CandidateGlossModelSmoke
java -cp "$output_dir" CandidateTranslationPolicySmoke
java -cp "$output_dir" app.msime.client.CandidateTranslationStoreSmoke
java -cp "$output_dir" OnlineCandidatePolicySmoke
java -cp "$output_dir" WubiCodeHintPolicySmoke
java -cp "$output_dir" ChineseSymbolFacesSmoke
java -cp "$output_dir" ShuangpinKeyHintPolicySmoke
java -cp "$output_dir" EnglishSuggestionPolicySmoke
java -cp "$output_dir" EnglishSuggestionModelSmoke
java -cp "$output_dir" CandidatePanelSmoke
java -cp "$output_dir" CandidateManagementSmoke
java -cp "$output_dir" ClipboardHistoryPolicySmoke
java -cp "$output_dir" DictionarySnapshotQueueSmoke
java -cp "$output_dir" DiagnosticPolicySmoke
java -cp "$output_dir" SmartPunctuationContextSmoke
java -cp "$output_dir" SymbolPanelModelSmoke
# Resources are compiled but not linked here: they reference Material's theme attributes, and linking
# those needs the library's own resources, which is Gradle's job. Compiling still catches a malformed
# drawable, layout or values file, which is what this step was for.
"$android_sdk/build-tools/35.0.0/aapt2" compile --dir "$repo_root/platforms/android/res" -o "$output_dir/resources.zip"
for alias in MainActivityForest MainActivitySky MainActivityDusk MainActivityVermilion; do
  if ! rg -q "android:name=\"\\.${alias}\"" "$repo_root/platforms/android/AndroidManifest.xml"; then
    echo "Android app icon alias missing: $alias" >&2
    exit 1
  fi
done
echo "Android service Java/API and manifest/resource checks passed; no installable/native APK produced"
