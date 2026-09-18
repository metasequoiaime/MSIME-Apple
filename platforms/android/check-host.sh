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
if rg -n 'NativeClient\.command\([^,]+, 9\)' "$repo_root/platforms/android/java/app/msime/client/core/MSIMEInputService.java"; then
  echo "Android input service must not use unmapped command 9" >&2
  exit 1
fi
mapfile -t client_sources < <(find "$repo_root/platforms/android/java/app/msime/client" -name "*.java" -print)
javac --release 17 -Xlint:all -Werror -cp "$android_jar" -d "$output_dir" \
  "${client_sources[@]}" \
  "$repo_root/platforms/android/tests/core/EditorSmoke.java" \
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
  "$repo_root/platforms/android/tests/keyboard/KeyboardInputContextSmoke.java" \
  "$repo_root/platforms/android/tests/keyboard/KeyboardGeometrySmoke.java" \
  "$repo_root/platforms/android/tests/voice/VoiceResultStoreSmoke.java" \
  "$repo_root/platforms/android/tests/voice/AiPolishClientSmoke.java" \
  "$repo_root/platforms/android/tests/candidate/ReplyKeyboardSmoke.java" \
  "$repo_root/platforms/android/tests/keyboard/KeyboardSkinSmoke.java" \
  "$repo_root/platforms/android/tests/keyboard/KeyboardFeedbackSmoke.java" \
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
java -cp "$output_dir" KeyboardInputContextSmoke
java -cp "$output_dir" KeyboardGeometrySmoke
java -cp "$output_dir" VoiceResultStoreSmoke
java -cp "$output_dir" AiPolishClientSmoke
java -cp "$output_dir" ReplyKeyboardSmoke
java -cp "$output_dir" app.msime.client.KeyboardSkinSmoke
java -cp "$output_dir" KeyboardFeedbackSmoke
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
"$android_sdk/build-tools/35.0.0/aapt2" compile --dir "$repo_root/platforms/android/res" -o "$output_dir/resources.zip"
"$android_sdk/build-tools/35.0.0/aapt2" link -I "$android_jar" \
  --manifest "$repo_root/platforms/android/AndroidManifest.xml" \
  -o "$output_dir/manifest.apk" "$output_dir/resources.zip"
for alias in MainActivityForest MainActivitySky MainActivityDusk MainActivityVermilion; do
  if ! rg -q "android:name=\"\\.${alias}\"" "$repo_root/platforms/android/AndroidManifest.xml"; then
    echo "Android app icon alias missing: $alias" >&2
    exit 1
  fi
done
echo "Android service Java/API and manifest/resource checks passed; no installable/native APK produced"
