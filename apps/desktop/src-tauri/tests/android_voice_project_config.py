import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[4]


class AndroidVoiceProjectConfigurationTests(unittest.TestCase):
    def test_shared_voice_panel_is_wired_to_the_android_plugin(self):
        plugin_rust = (ROOT / "crates/tauri-mobile-platform/src/lib.rs").read_text()
        app_rust = (ROOT / "apps/desktop/src-tauri/src/lib.rs").read_text()
        manifest = (ROOT / "apps/desktop/src-tauri/Cargo.toml").read_text()
        gradle = (ROOT / "apps/desktop/src-tauri/gen/android/app/build.gradle.kts").read_text()
        plugin = (ROOT / "platforms/android/java/app/msime/client/VoicePlugin.kt").read_text()
        activity = (
            ROOT
            / "platforms/android/java/app/msime/client/VoiceRecognitionActivity.java"
        ).read_text()

        self.assertIn(
            'register_android_plugin("app.msime.client", "VoicePlugin")', plugin_rust
        )
        self.assertIn("pub struct AndroidVoicePlatform", plugin_rust)
        self.assertIn(".recognize_voice(&request.request_id, &request.language)", app_rust)
        self.assertIn(".stop_voice(&request_id)", app_rust)
        self.assertIn(".cancel_voice(request_id.as_deref())", app_rust)
        self.assertIn(".save_voice_text(&text)", app_rust)
        self.assertIn(
            "cfg(any(target_os = \"android\", target_os = \"ios\"))", manifest
        )
        self.assertIn('java.srcDir(clientRoot.resolve("platforms/android/java"))', gradle)
        self.assertIn("@TauriPlugin", plugin)
        for command in ["recognizeVoice", "stopVoice", "cancelVoice", "saveVoiceText"]:
            self.assertIn(f"fun {command}", plugin)
        self.assertIn("VoiceResultStore", plugin)
        self.assertIn("VoiceRecognitionActivity.markLaunched(args.requestId)", plugin)
        self.assertIn("VoiceRecognitionActivity.isRequestActive(requestId)", plugin)
        self.assertIn("public static void markLaunched(String requestId)", activity)
        self.assertIn("public static boolean isRequestActive(String requestId)", activity)
        self.assertIn("EXTRA_REQUEST_ID", activity)
        self.assertIn("markLaunched(requestId)", activity)
        self.assertIn('String requestId = "ime-"', (ROOT / "platforms/android/java/app/msime/client/MSIMEInputService.java").read_text())
        self.assertIn("public static void cancelActive()", activity)


if __name__ == "__main__":
    unittest.main()
