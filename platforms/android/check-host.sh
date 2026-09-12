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
javac --release 17 -Xlint:all -Werror -cp "$android_jar" -d "$output_dir" \
  "$repo_root"/platforms/android/java/app/msime/client/*.java \
  "$repo_root/platforms/android/tests/EditorSmoke.java" \
  "$repo_root/platforms/android/tests/EditorContextSnapshotSmoke.java" \
  "$repo_root/platforms/android/tests/PreferencesSmoke.java" \
  "$repo_root/platforms/android/tests/KeyboardLayoutSmoke.java" \
  "$repo_root/platforms/android/tests/ReturnKeyActionSmoke.java" \
  "$repo_root/platforms/android/tests/SpaceCursorMovementSmoke.java" \
  "$repo_root/platforms/android/tests/EnglishCapitalizationPolicySmoke.java" \
  "$repo_root/platforms/android/tests/EnglishLetterCaseStateSmoke.java" \
  "$repo_root/platforms/android/tests/ChineseOutputPolicySmoke.java" \
  "$repo_root/platforms/android/tests/KeyboardInputContextSmoke.java" \
  "$repo_root/platforms/android/tests/KeyboardGeometrySmoke.java" \
  "$repo_root/platforms/android/tests/VoiceResultStoreSmoke.java" \
  "$repo_root/platforms/android/tests/AiPolishClientSmoke.java" \
  "$repo_root/platforms/android/tests/ReplyKeyboardSmoke.java" \
  "$repo_root/platforms/android/tests/KeyboardSkinSmoke.java" \
  "$repo_root/platforms/android/tests/KeyboardFeedbackSmoke.java" \
  "$repo_root/platforms/android/tests/TypingSourceSmoke.java" \
  "$repo_root/platforms/android/tests/MoreToolsLayoutSmoke.java" \
  "$repo_root/platforms/android/tests/LocalInputModeSmoke.java" \
  "$repo_root/platforms/android/tests/KeyboardSchemeSmoke.java" \
  "$repo_root/platforms/android/tests/NineKeyLayoutSmoke.java" \
  "$repo_root/platforms/android/tests/JapaneseNineKeyLayoutSmoke.java" \
  "$repo_root/platforms/android/tests/HandwritingContractSmoke.java" \
  "$repo_root/platforms/android/tests/CandidateAppearanceSmoke.java" \
  "$repo_root/platforms/android/tests/CandidatePanelSmoke.java" \
  "$repo_root/platforms/android/tests/CandidateManagementSmoke.java" \
  "$repo_root/platforms/android/tests/ClipboardHistoryPolicySmoke.java"
java -cp "$output_dir" EditorSmoke
java -cp "$output_dir" EditorContextSnapshotSmoke
java -cp "$output_dir" PreferencesSmoke
java -cp "$output_dir" KeyboardLayoutSmoke
java -cp "$output_dir" ReturnKeyActionSmoke
java -cp "$output_dir" SpaceCursorMovementSmoke
java -cp "$output_dir" EnglishCapitalizationPolicySmoke
java -cp "$output_dir" EnglishLetterCaseStateSmoke
java -cp "$output_dir" ChineseOutputPolicySmoke
java -cp "$output_dir" KeyboardInputContextSmoke
java -cp "$output_dir" KeyboardGeometrySmoke
java -cp "$output_dir" VoiceResultStoreSmoke
java -cp "$output_dir" AiPolishClientSmoke
java -cp "$output_dir" ReplyKeyboardSmoke
java -cp "$output_dir" KeyboardSkinSmoke
java -cp "$output_dir" KeyboardFeedbackSmoke
java -cp "$output_dir" TypingSourceSmoke
java -cp "$output_dir" MoreToolsLayoutSmoke
java -cp "$output_dir" LocalInputModeSmoke
java -cp "$output_dir" KeyboardSchemeSmoke
java -cp "$output_dir" NineKeyLayoutSmoke
java -cp "$output_dir" JapaneseNineKeyLayoutSmoke
java -cp "$output_dir" HandwritingContractSmoke
java -cp "$output_dir" CandidateAppearanceSmoke
java -cp "$output_dir" CandidatePanelSmoke
java -cp "$output_dir" CandidateManagementSmoke
java -cp "$output_dir" ClipboardHistoryPolicySmoke
"$android_sdk/build-tools/35.0.0/aapt2" compile --dir "$repo_root/platforms/android/res" -o "$output_dir/resources.zip"
"$android_sdk/build-tools/35.0.0/aapt2" link -I "$android_jar" \
  --manifest "$repo_root/platforms/android/AndroidManifest.xml" \
  -o "$output_dir/manifest.apk" "$output_dir/resources.zip"
echo "Android service Java/API and manifest/resource checks passed; no installable/native APK produced"
