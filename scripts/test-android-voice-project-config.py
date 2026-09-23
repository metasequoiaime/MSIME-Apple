import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class AndroidVoiceProjectConfigurationTests(unittest.TestCase):
    def test_shared_voice_panel_is_wired_to_the_android_plugin(self):
        plugin_rust = (ROOT / "crates/tauri-mobile-platform/src/lib.rs").read_text()
        # The voice commands are split across two files: the recognition path moved out into
        # voice.rs while the handoff stayed in lib.rs. This read only lib.rs and went red the day
        # they moved; nothing noticed, because nothing ran this file - see the verify-local.sh
        # stage added alongside this fix. Read both and assert against the shell as a whole,
        # which is what these assertions were ever about.
        app_rust = "\n".join(
            (ROOT / f"apps/desktop/src-tauri/src/{name}").read_text()
            for name in ("lib.rs", "voice.rs")
        )
        manifest = (ROOT / "apps/desktop/src-tauri/Cargo.toml").read_text()
        generated_manifest = (
            ROOT / "apps/desktop/src-tauri/gen/android/app/src/main/AndroidManifest.xml"
        ).read_text()
        gradle = (ROOT / "apps/desktop/src-tauri/gen/android/app/build.gradle.kts").read_text()
        plugin = (ROOT / "platforms/android/java/app/msime/client/voice/VoicePlugin.kt").read_text()
        activity = (
            ROOT
            / "platforms/android/java/app/msime/client/voice/VoiceRecognitionActivity.java"
        ).read_text()

        self.assertIn(
            'register_android_plugin("app.msime.client", "VoicePlugin")', plugin_rust
        )
        self.assertIn("pub struct AndroidVoicePlatform", plugin_rust)
        self.assertIn(
            ".recognize_voice(&request.request_id, &request.language, provider, polish)", app_rust
        )
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
        self.assertIn("VoiceRecognitionActivity.isRequestActive(job.requestId)", plugin)
        self.assertIn("VoiceRecognitionActivity.stopActive()", plugin)
        self.assertIn("public static void markLaunched(String requestId)", activity)
        self.assertIn("public static boolean isRequestActive(String requestId)", activity)
        self.assertIn("EXTRA_REQUEST_ID", activity)
        self.assertIn("markLaunched(requestId)", activity)
        self.assertIn("SpeechRecognizer", activity)
        self.assertIn("stopListening()", activity)
        self.assertIn("cancel()", activity)
        self.assertIn("android.permission.RECORD_AUDIO", (ROOT / "platforms/android/AndroidManifest.xml").read_text())
        self.assertIn("android.permission.RECORD_AUDIO", generated_manifest)
        self.assertIn('String requestId = "ime-"', (ROOT / "platforms/android/java/app/msime/client/core/MSIMEInputService.java").read_text())
        self.assertIn("public static void cancelActive()", activity)

    def test_a_configured_provider_reaches_the_host_without_taking_away_the_platform_recognizer(self):
        """The Kotlin plugin is not compiled by any gate on this machine or in CI - the APK build
        is what compiles it, and that runs neither here nor on a runner. These assertions are what
        stands in for a compiler on the wiring between the shared request and the two engines."""
        plugin = (
            ROOT / "platforms/android/java/app/msime/client/voice/VoicePlugin.kt"
        ).read_text()
        activity = (
            ROOT / "platforms/android/java/app/msime/client/voice/VoiceRecognitionActivity.java"
        ).read_text()
        shared = (ROOT / "crates/tauri-mobile-platform/src/lib.rs").read_text()
        desktop = (ROOT / "apps/desktop/src-tauri/src/voice.rs").read_text()

        # The request the shared layer builds is the one both mobile hosts receive.
        self.assertIn("provider: Option<MobileVoiceTranscriptionRequest>", shared)
        self.assertIn("provider.filter(MobileVoiceTranscriptionRequest::is_valid)", shared)
        # Android now resolves the same configuration iOS does, rather than only a language.
        self.assertIn('#[cfg(any(target_os = "ios", target_os = "android", test))]', desktop)
        self.assertIn("mobile_voice_provider_configuration(&snapshot.preferences)", desktop)

        # The plugin passes the provider through and decides nothing about which providers exist.
        self.assertIn("var provider: VoiceProviderArgs? = null", plugin)
        self.assertIn("HttpAsrPolicy.usable(", plugin)
        self.assertIn("provider?.provider, provider?.endpoint, provider?.model, provider?.token", plugin)
        # Absent or unusable provider must still reach the platform recognizer: that is the
        # default this host shipped with and it needs no account of any kind.
        self.assertIn("provider == null && streaming == null", plugin)
        self.assertIn("!VoiceRecognitionActivity.available(hostActivity)", plugin)

        # The activity runs whichever engine the request calls for.
        self.assertIn("private boolean usesProvider()", activity)
        self.assertIn("startProviderRecognition()", activity)
        self.assertIn("HttpAsrRecognizer", activity)
        self.assertIn("!usesProvider() && !available(this)", activity)
        # Cancelling has to release the microphone the recorder is holding.
        self.assertIn("provider.cancel()", activity)

    def test_polishing_runs_off_the_main_thread_and_never_loses_the_transcript(self):
        """The rewrite is a network round trip over text the user already has. Doing it on the
        thread that delivers SpeechRecognizer results would hang the window, and treating a failed
        rewrite as a failed recognition would throw away a sentence that was recognised fine."""
        activity = (
            ROOT / "platforms/android/java/app/msime/client/voice/VoiceRecognitionActivity.java"
        ).read_text()
        polisher = (
            ROOT / "platforms/android/java/app/msime/client/voice/VoicePolisher.java"
        ).read_text()
        shared = (ROOT / "crates/tauri-mobile-platform/src/lib.rs").read_text()

        self.assertIn("polish: Option<AndroidVoicePolishRequest>", shared)
        self.assertIn("polish.filter(AndroidVoicePolishRequest::is_valid)", shared)
        # onResults arrives on the main thread, so it must hand off rather than polish inline.
        self.assertIn("deliver(values.get(0));", activity)
        self.assertIn("providerWorker.execute", activity)
        # A failed rewrite keeps what was recognised.
        self.assertIn("return polished == null ? text : polished;", activity)
        self.assertIn("return null;", polisher)

    def test_the_streaming_protocol_reaches_the_host_and_builds_no_frames_of_its_own(self):
        """Android has no platform WebSocket, so this host carries one for a single endpoint. What
        it must not carry is a second copy of the protocol: the frames and the authentication
        headers are the shared implementation's, and drifting from them is silent."""
        plugin = (
            ROOT / "platforms/android/java/app/msime/client/voice/VoicePlugin.kt"
        ).read_text()
        activity = (
            ROOT / "platforms/android/java/app/msime/client/voice/VoiceRecognitionActivity.java"
        ).read_text()
        recognizer = (
            ROOT / "platforms/android/java/app/msime/client/voice/DoubaoRecognizer.java"
        ).read_text()

        # The two protocols are chosen between, never both.
        self.assertIn("DoubaoAsrPolicy.usable(", plugin)
        self.assertIn("streaming == null && HttpAsrPolicy.usable(", plugin)
        self.assertIn("VoiceRecognitionActivity.Streaming(", plugin)
        self.assertIn("startStreamingRecognition()", activity)
        self.assertIn("if (!usesStreaming() && !usesProvider() && !available(this))", activity)

        # Frames come from the shared builders; nothing here encodes the protocol.
        self.assertIn("NativeClient.doubaoStartFrame(", recognizer)
        self.assertIn("NativeClient.doubaoAudioFrame(", recognizer)
        self.assertIn("NativeClient.doubaoDecodeFrame(", recognizer)
        # Cancelling has to release both the microphone and the socket.
        self.assertIn("streaming.cancel()", activity)
        self.assertIn("socket.close()", recognizer)

    def test_the_keyboards_own_voice_entry_reads_the_same_configuration_as_the_settings_app(self):
        """The keyboard has its own voice button and never goes through the settings app. It used
        to launch the platform recogniser unconditionally, so the same device transcribed one way
        from the keyboard and another from the panel. The resolution is shared; a second copy of
        the provider rules in Java is how the two would drift apart again."""
        service = (
            ROOT / "platforms/android/java/app/msime/client/core/MSIMEInputService.java"
        ).read_text()
        configuration = (
            ROOT / "platforms/android/java/app/msime/client/voice/VoiceConfiguration.java"
        ).read_text()
        shared = (ROOT / "crates/host-api/src/ffi/host.rs").read_text()
        header = (ROOT / "crates/host-api/include/msime_client.h").read_text()
        client_core = (ROOT / "crates/client-core/src/voice/provider.rs").read_text()
        shell = (ROOT / "apps/desktop/src-tauri/src/voice.rs").read_text()

        # One resolver, in the shared crate, reached two ways.
        self.assertIn("pub fn mobile_voice_provider_configuration(", client_core)
        self.assertIn("pub fn mobile_voice_polish_configuration(", client_core)
        self.assertIn("use msime_client_core::voice::provider::{", shell)
        self.assertIn("msime_client_mobile_voice_configuration", shared)
        self.assertIn("msime_client_mobile_voice_configuration", header)

        # The keyboard asks for it and passes the answer to its own voice entry.
        self.assertIn("VoiceConfiguration.read(preferencesDirectory, requestId)", service)
        self.assertIn("configured.providerName(), configured.endpoint(), configured.model()",
                      service)
        self.assertIn("configured.streaming(), configured.polish()", service)
        # A configured provider must not be refused for want of the platform recogniser.
        self.assertIn(
            "configured.provider() == null && !VoiceRecognitionActivity.available(this)", service
        )
        # Nothing configured stays the platform recogniser rather than a failure.
        self.assertIn("return none();", configuration)
        # The provider rules stay in the two policies rather than being restated here.
        self.assertIn("DoubaoAsrPolicy.usable(", configuration)
        self.assertIn("HttpAsrPolicy.usable(", configuration)
        # The keyboard's own copy must not name an engine the request may not use. It said
        # "系统语音识别" on the button that now honours a configured provider, which was wrong for
        # exactly the users who had configured one.
        self.assertNotIn("开始系统语音识别", service)
        self.assertNotIn("点击下方按钮使用系统语音识别", service)
        self.assertIn("开始语音识别", service)


if __name__ == "__main__":
    unittest.main()
