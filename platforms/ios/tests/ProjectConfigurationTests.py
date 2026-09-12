import os
import json
import plistlib
import re
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path


IOS_ROOT = Path(__file__).resolve().parents[1]


class ProjectConfigurationTests(unittest.TestCase):
    def test_app_store_icon_and_ipad_orientations(self):
        resources = IOS_ROOT / "App/Resources"
        with (resources / "Info.plist").open("rb") as source:
            info = plistlib.load(source)
        self.assertEqual(info["CFBundleIconName"], "AppIcon")
        self.assertEqual(set(info["UISupportedInterfaceOrientations~ipad"]), {
            "UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown",
            "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight",
        })
        icons = resources / "Assets.xcassets/AppIcon.appiconset"
        catalog = json.loads((icons / "Contents.json").read_text())
        self.assertEqual(len(catalog["images"]), 1)
        entry = catalog["images"][0]
        self.assertEqual(entry["size"], "1024x1024")
        image = (icons / entry["filename"]).read_bytes()
        self.assertEqual(image[:8], b"\x89PNG\r\n\x1a\n")
        self.assertEqual(struct.unpack(">II", image[16:24]), (1024, 1024))
        self.assertEqual(image[25], 2, "App Store icon must be RGB without an alpha channel")
        project = (IOS_ROOT / "project.yml").read_text()
        self.assertIn("path: platforms/ios/App/Resources/Assets.xcassets", project)
        self.assertIn("ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon", project)

    def test_every_keyboard_scroll_view_turns_off_the_ios26_edge_effect(self):
        # The effect assumes edges hold empty space. Keyboard panels are a few rows tall, so the
        # gradient lands on the content: it smudged the candidate chips and sat over the first line
        # of text in the service panels. It is on by default, so each new scroll view reintroduces
        # it, and it looks like a rendering glitch rather than a setting anyone chose.
        roots = [IOS_ROOT / "SharedUI", IOS_ROOT / "KeyboardExtension/Sources"]
        sources = sorted(path for root in roots for path in root.glob("*.swift"))
        self.assertTrue(sources)
        uikit, swiftui = [], []
        for path in sources:
            if path.name == "ScrollEdgeEffects.swift":
                continue
            text = path.read_text()
            if re.search(r"= UIScrollView\(\)|: UIScrollView \{", text) and "disableEdgeEffects()" not in text:
                uikit.append(path.name)
            if re.search(r"^\s*ScrollView \{", text, re.M) and "disablingScrollEdgeEffects()" not in text:
                swiftui.append(path.name)
        self.assertEqual(uikit, [], "UIKit scroll views must call disableEdgeEffects()")
        self.assertEqual(swiftui, [], "SwiftUI scroll views must call disablingScrollEdgeEffects()")

    def test_voice_recording_deep_link_scheme_is_registered(self):
        # The keyboard sends the user to the app to record, because an extension is denied the
        # microphone. If the plist and the URL in the code drift apart the button silently fails --
        # openURL just reports failure -- so pin them to each other rather than to a literal here.
        with (IOS_ROOT / "App/Resources/Info.plist").open("rb") as source:
            info = plistlib.load(source)
        registered = {scheme for entry in info["CFBundleURLTypes"] for scheme in entry["CFBundleURLSchemes"]}
        store = (IOS_ROOT / "SharedUI/VoiceTextHandoffStore.swift").read_text()
        url = re.search(r'recordingURL = URL\(string: "([a-z]+)://([a-z]+)"\)', store)
        self.assertIsNotNone(url, "VoiceTextHandoffStore must declare the recording deep link")
        self.assertIn(url.group(1), registered)
        navigation = (IOS_ROOT / "App/Sources/AppNavigation.swift").read_text()
        self.assertIn("VoiceTextHandoffStore.recordingURL.scheme", navigation)
        self.assertIn("VoiceTextHandoffStore.recordingURL.host", navigation)

    def test_testflight_upload_passes_xcode16_credentials_and_cleans_up_key(self):
        script = (IOS_ROOT / "scripts/package_ios_testflight.sh").read_text()
        upload = script[script.index('private_keys_dir="$build_root/private_keys"'):]
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            key = root / "custom key.p8"
            key.write_text("test private key")
            mock = root / "xcrun"
            mock.write_text('''#!/usr/bin/env python3
import os
import pathlib
import stat
import sys
assert sys.argv[1:] == ["altool", "--upload-app", "--file", "signed app.ipa", "--type", "ios", "--apiKey", "TESTKEY", "--apiIssuer", "TESTISSUER"]
key = pathlib.Path(os.environ["API_PRIVATE_KEYS_DIR"]) / "AuthKey_TESTKEY.p8"
assert key.read_text() == "test private key"
assert stat.S_IMODE(key.stat().st_mode) == 0o600
sys.exit(int(os.environ["UPLOAD_STATUS"]))
''')
            mock.chmod(0o755)
            for status in (0, 17):
                with self.subTest(status=status):
                    result = subprocess.run(
                        ["bash", "-eu", "-c", upload],
                        env={
                            **os.environ,
                            "PATH": f"{root}:{os.environ['PATH']}",
                            "build_root": str(root / "build"),
                            "METASEQUOIA_IOS_AUTH_KEY_PATH": str(key),
                            "METASEQUOIA_IOS_AUTH_KEY_ID": "TESTKEY",
                            "METASEQUOIA_IOS_AUTH_KEY_ISSUER_ID": "TESTISSUER",
                            "ipa": "signed app.ipa",
                            "tag_name": "v0.48.4",
                            "UPLOAD_STATUS": str(status),
                        },
                        capture_output=True,
                        text=True,
                    )
                    self.assertEqual(result.returncode, status, result.stderr)
                    self.assertFalse((root / "build/private_keys").exists())
                    self.assertTrue(key.exists())

    def test_host_and_keyboard_bundle_the_required_reason_privacy_manifest(self):
        project = (IOS_ROOT / "project.yml").read_text()
        manifest_path = IOS_ROOT / "SharedResources/PrivacyInfo.xcprivacy"

        with manifest_path.open("rb") as manifest_file:
            manifest = plistlib.load(manifest_file)

        self.assertFalse(manifest["NSPrivacyTracking"])
        self.assertEqual(manifest["NSPrivacyCollectedDataTypes"], [])
        # SystemBootTime covers ProcessInfo.processInfo.systemUptime, which the keyboard uses to
        # time the double tap on shift. It is on Apple's required-reason list, so leaving it out
        # returns ITMS-91053 at upload time rather than failing anything at runtime.
        self.assertEqual(
            manifest["NSPrivacyAccessedAPITypes"],
            [
                {
                    "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults",
                    "NSPrivacyAccessedAPITypeReasons": ["CA92.1", "1C8F.1"],
                },
                {
                    "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategorySystemBootTime",
                    "NSPrivacyAccessedAPITypeReasons": ["35F9.1"],
                },
            ],
        )
        controller_source = (
            IOS_ROOT / "KeyboardExtension/Sources/KeyboardViewController.swift"
        ).read_text()
        self.assertIn("ProcessInfo.processInfo.systemUptime", controller_source)
        self.assertEqual(
            project.count("platforms/ios/SharedResources/PrivacyInfo.xcprivacy"),
            2,
        )

    def test_host_and_keyboard_share_the_input_scheme_through_an_app_group(self):
        project = (IOS_ROOT / "project.yml").read_text()
        shared_preference = (IOS_ROOT / "SharedUI/InputSchemePreference.swift").read_text()
        controller = (IOS_ROOT / "KeyboardExtension/Sources/KeyboardViewController.swift").read_text()
        group_identifier = "group.app.msime.ios"

        for relative_path in (
            "App/Resources/MetasequoiaImeIOS.entitlements",
            "KeyboardExtension/Resources/MetasequoiaKeyboard.entitlements",
        ):
            with (IOS_ROOT / relative_path).open("rb") as entitlement_file:
                entitlements = plistlib.load(entitlement_file)
            self.assertEqual(entitlements["com.apple.security.application-groups"], [group_identifier])
            self.assertIn(relative_path, project)

        self.assertIn(f'static let appGroupIdentifier = "{group_identifier}"', shared_preference)
        self.assertIn('private static let key = "inputSchemeUsesShuangpin"', shared_preference)
        self.assertIn("UserDefaults(suiteName: appGroupIdentifier)", shared_preference)
        self.assertIn("UserDefaults.standard.object(forKey: key)", shared_preference)
        self.assertIn("InputSchemePreference.scheme", controller)
        self.assertNotIn("schemePreferenceKey", controller)

    def test_english_capitalization_policy(self):
        policy = IOS_ROOT / "KeyboardExtension/Sources/EnglishCapitalizationPolicy.swift"
        tests = IOS_ROOT / "tests/EnglishCapitalizationPolicyTests.swift"

        with tempfile.TemporaryDirectory() as temporary_directory:
            executable = Path(temporary_directory) / "EnglishCapitalizationPolicyTests"
            subprocess.run(
                ["swiftc", str(policy), str(tests), "-o", str(executable)],
                check=True,
            )
            subprocess.run([str(executable)], check=True)

    def test_chinese_output_conversion(self):
        conversion = IOS_ROOT / "SharedUI/ChineseTextConversion.swift"
        tests = IOS_ROOT / "tests/ChineseTextConversionTests.swift"

        with tempfile.TemporaryDirectory() as temporary_directory:
            executable = Path(temporary_directory) / "ChineseTextConversionTests"
            subprocess.run(
                ["swiftc", str(conversion), str(tests), "-o", str(executable)],
                check=True,
            )
            subprocess.run([str(executable)], check=True)

    def test_frequency_adjustment_preference(self):
        preference = IOS_ROOT / "SharedUI/FrequencyAdjustmentPreference.swift"
        scheme = IOS_ROOT / "SharedUI/InputSchemePreference.swift"
        tests = IOS_ROOT / "tests/FrequencyAdjustmentPreferenceTests.swift"
        settings = (IOS_ROOT / "App/Sources/FeatureSettingsViews.swift").read_text()
        controller = (IOS_ROOT / "KeyboardExtension/Sources/KeyboardViewController.swift").read_text()
        bridge = (IOS_ROOT.parents[1] / "shared/apple-bridge/MetasequoiaInputSessionBridge.h").read_text()

        self.assertIn('static let modeKey = "frequencyAdjustmentMode"', preference.read_text())
        self.assertIn("UserDefaults(suiteName: InputSchemePreference.appGroupIdentifier)", preference.read_text())
        self.assertIn('Picker("调频方式", selection: $frequencyMode)', settings)
        self.assertIn('.accessibilityIdentifier("frequencyAdjustmentModePicker")', settings)
        self.assertIn('.accessibilityIdentifier("frequencyAdjustmentTriggerPicker")', settings)
        self.assertIn('.accessibilityIdentifier("frequencyAdjustmentLinearStepPicker")', settings)
        self.assertIn("applyLearningPreferences()", controller)
        self.assertIn("setFrequencyAdjustmentMode", controller)
        self.assertIn("FrequencyAdjustmentPreference.mode", controller)
        apply = controller.split("private func applyLearningPreferences()", 1)[1].split(
            "private func applyInputScheme()", 1
        )[0]
        self.assertLess(
            apply.index("setFrequencyAdjustmentMode"),
            apply.index("setLearningEnabled"),
        )
        self.assertIn("MetasequoiaFrequencyAdjustmentMode", bridge)
        self.assertIn("setFrequencyAdjustmentMode", bridge)

        with tempfile.TemporaryDirectory() as temporary_directory:
            executable = Path(temporary_directory) / "FrequencyAdjustmentPreferenceTests"
            subprocess.run(
                ["swiftc", str(preference), str(scheme), str(tests), "-o", str(executable)],
                check=True,
            )
            subprocess.run([str(executable)], check=True)

    def test_host_and_keyboard_share_the_chinese_output_script(self):
        preference = (IOS_ROOT / "SharedUI/ChineseOutputPreference.swift").read_text()
        onboarding = (IOS_ROOT / "App/Sources/OnboardingView.swift").read_text()
        controller = (IOS_ROOT / "KeyboardExtension/Sources/KeyboardViewController.swift").read_text()

        self.assertIn('private static let key = "chineseOutputUsesTraditional"', preference)
        self.assertIn("UserDefaults(suiteName: InputSchemePreference.appGroupIdentifier)", preference)

        self.assertIn(
            "@State private var usesTraditionalOutput = ChineseOutputPreference.usesTraditional",
            onboarding,
        )
        self.assertIn('Picker("输出字形", selection: $usesTraditionalOutput)', onboarding)
        self.assertIn('Text("简体").tag(false)', onboarding)
        self.assertIn('Text("繁体").tag(true)', onboarding)
        self.assertIn('.accessibilityIdentifier("chineseOutputPicker")', onboarding)
        self.assertIn("ChineseOutputPreference.usesTraditional = value", onboarding)

        self.assertIn("usesTraditionalOutput = ChineseOutputPreference.usesTraditional", controller)
        self.assertIn("synchronizeChineseOutputPreference()", controller)

    def test_only_visible_candidates_and_commits_change_script(self):
        controller = (IOS_ROOT / "KeyboardExtension/Sources/KeyboardViewController.swift").read_text()

        # The engine and the packaged dictionary stay simplified, so conversion belongs at the
        # render and commit boundary only. Converting the preedit would rewrite pinyin, and
        # converting before selection would break the engine index the candidate chips carry.
        self.assertIn("insertOwnText(source == .japanese ? commitText : chineseOutput(commitText), source: source)", controller)
        self.assertIn("let display = chineseOutput(candidate)", controller)
        self.assertIn("configuration.title = display", controller)
        self.assertIn("self.render(self.session.selectCandidate(at: UInt(index)))", controller)

        preedit = controller.split("private func updatePreeditButton", 1)[1].split("\n  }", 1)[0]
        self.assertIn("visiblePreedit", preedit)
        self.assertNotIn("chineseOutput(visiblePreedit)", preedit)

    def test_backspace_repeats_only_while_the_delete_key_is_held(self):
        controller = (IOS_ROOT / "KeyboardExtension/Sources/KeyboardViewController.swift").read_text()

        self.assertIn("private var backspaceRepeatTimer: Timer?", controller)
        self.assertIn("#selector(beginBackspacePress)", controller)
        self.assertIn("for: .touchDown", controller)
        self.assertIn("#selector(finishBackspacePress)", controller)
        self.assertIn("for: .touchUpInside", controller)
        self.assertIn("#selector(cancelBackspacePress)", controller)
        self.assertIn("RunLoop.main.add(timer, forMode: .common)", controller)
        self.assertIn("timer.fireDate = Date(timeIntervalSinceNow: 0.4)", controller)
        self.assertIn("override func viewWillDisappear", controller)

    def test_keyboard_uses_system_input_click_feedback(self):
        controller = (IOS_ROOT / "KeyboardExtension/Sources/KeyboardViewController.swift").read_text()

        input_view = (IOS_ROOT / "KeyboardExtension/Sources/KeyboardInputView.swift").read_text()
        self.assertIn("UIInputViewAudioFeedback", input_view)
        self.assertIn("var enableInputClicksWhenVisible: Bool { KeyboardFeedbackPreference.soundEnabled }", input_view)
        self.assertIn("inputView = KeyboardInputView", controller)
        self.assertIn("UIDevice.current.playInputClick()", controller)
        self.assertIn("private func playInputClick()", controller)
        self.assertGreaterEqual(controller.count("playInputClick()"), 9)

    def test_every_target_resolves_a_product_name(self):
        # Xcode 26 stopped defaulting PRODUCT_NAME to the target name. Without the project-level
        # fallback the bridge library links as a bare `-l` that swallows the next linker flag, and
        # the UI-test target builds `.xctest` inside `-Runner.app`, which collide in the products
        # directory. Both failures only appear at link and test time, so pin the setting here.
        project = (IOS_ROOT / "project.yml").read_text()

        self.assertIn("PRODUCT_NAME: $(TARGET_NAME)", project)
        self.assertLess(
            project.index("PRODUCT_NAME: $(TARGET_NAME)"),
            project.index("targets:"),
        )

    def test_project_defines_distinct_host_and_keyboard_identifiers(self):
        project = (IOS_ROOT / "project.yml").read_text()

        self.assertIn("PRODUCT_BUNDLE_IDENTIFIER: app.msime.ios\n", project)
        self.assertIn("PRODUCT_BUNDLE_IDENTIFIER: app.msime.ios.keyboard\n", project)
        self.assertIn("deploymentTarget:\n    iOS: \"15.5\"", project)
        # The Podfile states the same floor, and the pods are compiled against whatever it says. The
        # two drifting apart builds the dependencies for a different iOS than the app declares.
        self.assertIn("platform :ios, '15.5'", (IOS_ROOT / "Podfile").read_text())

    def test_testflight_archive_uses_distribution_profiles(self):
        script = (IOS_ROOT / "scripts/package_ios_testflight.sh").read_text()

        self.assertIn('CODE_SIGN_IDENTITY="Apple Distribution"', script)
        self.assertIn("CODE_SIGN_STYLE=Manual", script)
        self.assertIn("METASEQUOIA_IOS_APP_PROVISIONING_PROFILE_PATH", script)
        self.assertIn("METASEQUOIA_IOS_KEYBOARD_PROVISIONING_PROFILE_PATH", script)
        self.assertIn('<string>app-store-connect</string>', script)
        self.assertIn('<string>manual</string>', script)

    def test_testflight_export_fails_when_xcode_cannot_sign_or_export(self):
        script = (IOS_ROOT / "scripts/package_ios_testflight.sh").read_text()

        self.assertNotIn("skip_testflight", script)
        self.assertIn("export_status=${PIPESTATUS[0]}", script)
        self.assertIn('exit "$export_status"', script)

    def test_testflight_archive_fails_on_signing_configuration_errors(self):
        script = (IOS_ROOT / "scripts/package_ios_testflight.sh").read_text()

        self.assertIn('archive_log="$build_root/archive.log"', script)
        self.assertIn("archive_status=${PIPESTATUS[0]}", script)
        self.assertIn("exit \"$archive_status\"", script)

    def test_testflight_archive_preserves_signed_release_artifacts(self):
        script = (IOS_ROOT / "scripts/package_ios_testflight.sh").read_text()

        self.assertIn("METASEQUOIA_IOS_RELEASE_DIR", script)
        self.assertIn("provisioningProfiles", script)
        self.assertIn("app.msime.ios.keyboard", script)
        self.assertIn("ios-testflight.xcarchive.zip", script)
        self.assertIn("ios-testflight.ipa", script)
        self.assertIn("Uploaded %s to TestFlight", script)

    def test_keyboard_declares_shared_statistics_access_and_system_extension_contract(self):
        with (IOS_ROOT / "KeyboardExtension/Resources/Info.plist").open("rb") as info_file:
            info = plistlib.load(info_file)

        extension = info["NSExtension"]
        attributes = extension["NSExtensionAttributes"]
        self.assertEqual(extension["NSExtensionPointIdentifier"], "com.apple.keyboard-service")
        self.assertEqual(extension["NSExtensionPrincipalClass"], "$(PRODUCT_MODULE_NAME).KeyboardViewController")
        self.assertEqual(attributes["PrimaryLanguage"], "zh-Hans")
        self.assertTrue(attributes["RequestsOpenAccess"])

    def test_keyboard_exposes_required_document_and_next_keyboard_actions(self):
        controller = (IOS_ROOT / "KeyboardExtension/Sources/KeyboardViewController.swift").read_text()

        self.assertIn("textDocumentProxy.insertText", controller)
        self.assertIn("textDocumentProxy.deleteBackward", controller)
        self.assertIn("handleInputModeList(from:", controller)
        self.assertNotIn("URLSession", controller)

    def test_candidates_past_the_strip_are_reached_by_expanding_not_by_paging(self):
        # The strip shows nine and the arrows advanced by nine, so the tail of a long answer was
        # unreachable in practice: quanpin returns 351 candidates for "yi" and 103 for "shurufa",
        # which is thirty-nine and eleven taps away. Paging is gone; one control opens the whole
        # list instead.
        controller = (IOS_ROOT / "KeyboardExtension/Sources/KeyboardViewController.swift").read_text()

        self.assertIn("static let candidatePageSize = 9", controller)
        self.assertIn('identifier: "expandCandidates")', controller)
        self.assertIn("private func showCandidatePanel()", controller)
        self.assertIn("KeyboardCandidatePanelView(", controller)
        self.assertNotIn("candidatePageStart", controller)
        self.assertNotIn("previousCandidatePage", controller)

        # Without a page offset the chip numbers and the engine's own numbering agree, so a digit
        # and the chip carrying it name the same candidate again.
        # A chip keeps its position for the life of the strip and selects by that position, which is
        # what keeps the digits and the engine's numbering in step. The chips are built once and
        # relabelled, so this pins the index reaching the engine rather than the call that fills them.
        self.assertIn("makeCandidateButton(index: Int)", controller)
        self.assertIn("number: offset + 1", controller)
        self.assertIn("self.render(self.session.selectCandidate(at: UInt(index)))", controller)

        # The control is for reaching what the strip cannot show, so it appears exactly then.
        expand = controller.split("private func updateExpandControl", 1)[1].split("\n  }", 1)[0]
        self.assertIn("visibleCandidates.count <= Self.candidatePageSize", expand)

        panel = (IOS_ROOT / "KeyboardExtension/Sources/KeyboardCandidatePanelView.swift").read_text()
        self.assertIn('accessibilityIdentifier = "candidatePanel"', panel)
        self.assertIn('accessibilityIdentifier = "closeCandidatePanel"', panel)
        self.assertIn('chip.accessibilityIdentifier = "panelCandidate-\\(number)"', panel)

    def test_committing_the_leading_candidate_takes_the_engines_first(self):
        # Space, return and the language switch all mean "take what is showing". The strip no longer
        # pages, so the leading chip is the engine's first and commitCandidate names it.
        controller = (IOS_ROOT / "KeyboardExtension/Sources/KeyboardViewController.swift").read_text()

        self.assertIn("private func commitVisibleCandidate() -> MetasequoiaInputSnapshot {", controller)
        helper = controller.split("private func commitVisibleCandidate", 1)[1].split("\n  }", 1)[0]
        # The unhandled report is what tells space and return to insert their own character, and
        # only commitCandidate produces it.
        self.assertIn("return session.commitCandidate()", helper)
        self.assertNotIn("selectCandidate", helper)

        space = controller.split("private func handleSpace()", 1)[1].split("\n  }", 1)[0]
        self.assertIn("commitVisibleCandidate()", space)
        self.assertNotIn("session.commitCandidate()", space)

        # Return and the language switch flush the whole pending composition rather than pick one
        # candidate, so they stay on finishComposition and are not part of this rule.
        for caller in ("private func handleReturn", "private func toggleInputMode"):
            body = controller.split(caller, 1)[1].split("\n  }", 1)[0]
            self.assertIn("finishComposition()", body)

    def test_double_pinyin_key_hints_come_from_the_engine_profile(self):
        # A hardcoded keymap in Swift would drift from whatever profile the session actually runs.
        # The hints are derived from the engine's own ShuangpinProfile and refreshed wherever the
        # scheme is, so the two cannot disagree.
        keymap = (IOS_ROOT.parents[1] / "shared/apple-bridge/ShuangpinKeymap.cpp").read_text()
        bridge_header = (IOS_ROOT.parents[1] / "shared/apple-bridge/MetasequoiaInputSessionBridge.h").read_text()
        controller = (IOS_ROOT / "KeyboardExtension/Sources/KeyboardViewController.swift").read_text()
        cmake = (IOS_ROOT.parents[1] / "CMakeLists.txt").read_text()

        self.assertIn("GetShuangpinProfile(profile_name)", keymap)
        self.assertIn("shuangpinKeyHints", bridge_header)
        self.assertIn("shared/apple-bridge/ShuangpinKeymap.cpp", cmake)

        self.assertIn("private var shuangpinKeyHints: [String: String] = [:]", controller)
        self.assertIn("shuangpinKeyHints = session.shuangpinKeyHints()", controller)
        self.assertIn("hintLabel.text = hint", controller)
        self.assertIn("label.numberOfLines = 1", controller)
        self.assertIn("label.adjustsFontSizeToFitWidth = true", controller)
        self.assertIn("button.accessibilityValue = hint", controller)
        # English mode feeds the client directly rather than a composition, so a double-pinyin hint
        # there would describe something the key does not do.
        self.assertIn("let hint = isChineseMode && !session.isInLocalMode ? shuangpinKeyHints[lowercase.uppercased()] : nil", controller)

    def test_local_input_modes_are_reachable_and_only_the_serviceable_ones(self):
        # The engine opens a local mode on a capital carried with its shift_only flag, which no iOS
        # key can produce. The frontend names the mode instead and the bridge turns it back into the
        # keystroke the engine expects.
        adapter_header = (IOS_ROOT.parents[1] / "shared/apple-bridge/InputSessionAdapter.h").read_text()
        adapter = (IOS_ROOT.parents[1] / "shared/apple-bridge/InputSessionAdapter.cpp").read_text()
        bridge_header = (IOS_ROOT.parents[1] / "shared/apple-bridge/MetasequoiaInputSessionBridge.h").read_text()
        controller = (IOS_ROOT / "KeyboardExtension/Sources/KeyboardViewController.swift").read_text()
        profile = (IOS_ROOT.parents[1] / "vendor/MetasequoiaImeEngine/dictionary/build_profile.py").read_text()

        self.assertIn("InputSnapshot open_local_mode(char trigger);", adapter_header)
        self.assertIn("openLocalMode:", bridge_header)

        # InputSessionAdapterTests exercises idle and in-composition mode triggers through the
        # real adapter. Do not couple this packaging check to the engine facade's method names.

        options = adapter.split("LocalModeOptions options;", 1)[1].split("return session_options", 1)[0]
        for enabled in ("unicode", "date_time", "super_jianpin", "quick_phrase", "emoji", "kaomoji", "temporary_english", "temporary_japanese"):
            self.assertIn(f"options.{enabled} = true;", options)
        self.assertIn('(trigger: "U", title: "Unicode 码点")', controller)
        self.assertIn('title: "快捷短语"', controller)
        self.assertIn("session.openLocalMode(trigger)", controller)
        self.assertIn('preeditButton.accessibilityIdentifier = "preeditButton"', controller)
        # The entry point is the strip's own name, which is only dead space while nothing is being
        # composed and the keyboard is in Chinese mode.
        self.assertIn("let offersModes = idle && supportsLocalTools", controller)
        # Disabling the button would dim the title, and the title is the preedit.
        self.assertNotIn("preeditButton.isEnabled", controller)
        self.assertIn("preeditButton.menu =", controller)
        # Unicode reads hexadecimal, so its digits are input rather than candidate numbers.
        self.assertIn("if session.isInUnicodeMode, symbol.count == 1, symbol >= \"0\", symbol <= \"9\" {", controller)

    def test_engine_diagnostics_reach_the_keyboard(self):
        # KeyResult carries a diagnostic when the key was handled but something behind it failed,
        # such as a candidate the user dictionary could not learn. The bridge used to drop it on the
        # floor, so the keyboard could not report anything and the failure was silent.
        adapter_header = (IOS_ROOT.parents[1] / "shared/apple-bridge/InputSessionAdapter.h").read_text()
        adapter = (IOS_ROOT.parents[1] / "shared/apple-bridge/InputSessionAdapter.cpp").read_text()
        bridge_header = (IOS_ROOT.parents[1] / "shared/apple-bridge/MetasequoiaInputSessionBridge.h").read_text()
        bridge = (IOS_ROOT.parents[1] / "shared/apple-bridge/MetasequoiaInputSessionBridge.mm").read_text()
        controller = (IOS_ROOT / "KeyboardExtension/Sources/KeyboardViewController.swift").read_text()

        self.assertIn("std::optional<std::string> diagnostic;", adapter_header)
        self.assertIn("snapshot.diagnostic = std::move(result.diagnostic);", adapter)
        self.assertIn("NSString *diagnosticText;", bridge_header)
        self.assertIn("diagnosticText:diagnosticText", bridge)

        self.assertIn("showDiagnostic(snapshot.diagnosticText)", controller)
        self.assertIn("private var diagnosticDismissTimer: Timer?", controller)
        self.assertIn('diagnosticLabel.accessibilityIdentifier = "diagnosticLabel"', controller)
        # The strip is the empty slot a diagnostic can occupy, and the message clears itself so it
        # never becomes permanent furniture in a 38pt bar.
        self.assertIn(
            "candidateScrollView.isHidden = visibleCandidates.isEmpty || visibleDiagnostic != nil",
            controller,
        )
        self.assertIn("override func viewWillDisappear", controller)
        disappear = controller.split("override func viewWillDisappear", 1)[1].split("\n  }", 1)[0]
        self.assertIn("diagnosticDismissTimer?.invalidate()", disappear)

    def test_onboarding_exposes_a_regular_text_field_for_keyboard_tryout(self):
        chat = (IOS_ROOT / "App/Sources/KeyboardChatView.swift").read_text()
        self.assertIn('TextField("输入消息，试试键盘"', chat)
        self.assertIn('.accessibilityIdentifier("keyboardTryoutField")', chat)
        self.assertIn("@FocusState private var focused: Bool", chat)
        self.assertIn(".focused($focused)", chat)
        self.assertIn('Button("收起键盘") { focused = false }', chat)
        self.assertIn('.accessibilityIdentifier("dismissKeyboardButton")', chat)

    def test_host_app_exposes_the_shared_input_scheme_setting(self):
        onboarding = (IOS_ROOT / "App/Sources/OnboardingView.swift").read_text()
        controller = (IOS_ROOT / "KeyboardExtension/Sources/KeyboardViewController.swift").read_text()

        self.assertIn(
            "@State private var inputScheme = InputSchemePreference.scheme",
            onboarding,
        )
        self.assertIn("ChineseInputScheme.allCases", onboarding)
        self.assertIn("InputSchemePreference.scheme = scheme", onboarding)
        self.assertIn("private var hasComposition = false", controller)
        self.assertIn("override func viewWillAppear", controller)
        self.assertIn("synchronizeInputSchemePreference()", controller)
        self.assertIn("guard !hasComposition else { return }", controller)
        self.assertIn("hasComposition = !snapshot.preedit.isEmpty", controller)

    def test_ci_creates_the_generated_project_output_directory(self):
        workflow = (IOS_ROOT.parents[1] / ".github/workflows/ci.yml").read_text()

        self.assertIn("mkdir -p build/ios", workflow)

    def test_keyboard_routes_composition_through_the_shared_engine_bridge(self):
        project = (IOS_ROOT / "project.yml").read_text()
        controller = (IOS_ROOT / "KeyboardExtension/Sources/KeyboardViewController.swift").read_text()

        self.assertIn("MetasequoiaAppleBridge:", project)
        self.assertIn("shared/apple-bridge", project)
        self.assertIn("vendor/MetasequoiaImeEngine/core", project)
        self.assertIn("MetasequoiaInputSessionBridge", controller)
        self.assertIn("session.handleCharacter", controller)
        self.assertIn("session.commitCandidate", controller)

    def test_keyboard_packages_the_compact_dictionary(self):
        project = (IOS_ROOT / "project.yml").read_text()
        workflow = (IOS_ROOT.parents[1] / ".github/workflows/ci.yml").read_text()

        self.assertIn("platforms/ios/KeyboardExtension/Resources/msime.db", project)
        self.assertIn("platforms/ios/KeyboardExtension/Resources/msime.db.sha256", project)
        self.assertIn("python3 platforms/ios/scripts/prepare_dictionary.py", workflow)

    def test_bridge_installs_the_bundled_dictionary_before_engine_startup(self):
        bridge = (IOS_ROOT.parents[1] / "shared/apple-bridge/MetasequoiaInputSessionBridge.mm").read_text()

        installer = (IOS_ROOT.parents[1] / "shared/apple-bridge/DictionaryInstallation.mm").read_text()
        self.assertIn("PrepareDictionaryInstallation", bridge)
        self.assertIn("InputSessionAdapter>(installation.paths)", bridge)
        self.assertLess(bridge.index("const auto &installation = ConfigureDataDirectory(true)"),
                        bridge.index("InputSessionAdapter>(installation.paths)"))
        self.assertIn("prepare_runtime_paths", installer)
        self.assertIn('@[@"msime.db",@"english.db",@"others.db",@"dict_japanese.dat"]', "".join(installer.split()))

    def test_keyboard_exposes_engine_owned_number_and_punctuation_routing(self):
        controller = (IOS_ROOT / "KeyboardExtension/Sources/KeyboardViewController.swift").read_text()
        bridge_header = (IOS_ROOT.parents[1] / "shared/apple-bridge/MetasequoiaInputSessionBridge.h").read_text()

        self.assertIn("symbolRows", controller)
        self.assertIn("toggleLayout", controller)
        self.assertIn("session.handleCandidateKey", controller)
        self.assertIn("session.handlePunctuation", controller)
        self.assertIn("handleCandidateKey", bridge_header)
        self.assertIn("handlePunctuation", bridge_header)

    def test_candidate_surface_exposes_native_chips_numbered_only_for_voiceover(self):
        controller = (IOS_ROOT / "KeyboardExtension/Sources/KeyboardViewController.swift").read_text()

        # The chips are built once and relabelled, so assert that each one is handed the candidate,
        # its wubi hint and its position, rather than pinning the shape of a single call.
        self.assertIn("wubiCodeHint(at: offset)", controller)
        self.assertIn("number: offset + 1", controller)
        self.assertIn("configuration.background.cornerRadius", controller)

        # A touch keyboard has no number row for the ordinal to answer to, so it is spoken rather
        # than drawn: the chip shows the candidate alone and VoiceOver still hears the position.
        self.assertIn("configuration.title = display", controller)
        self.assertNotIn('configuration.title = "\\(number)', controller)
        self.assertIn('"候选词 \\(number)：\\(display)"', controller)

        # The one thing drawn beside a candidate is the wubi code still to type, and only where it
        # leads somewhere: the wubi scheme, the setting on, and no local mode synthesising the list.
        self.assertIn("，还需输入 \\(hint)", controller)
        self.assertIn("guard inputScheme == .wubi, !session.isInLocalMode, WubiCodeHintPreference.isEnabled",
                      controller)

    def test_apostrophe_reaches_the_engine_before_punctuation_conversion(self):
        controller = (IOS_ROOT / "KeyboardExtension/Sources/KeyboardViewController.swift").read_text()

        separator_route = 'if symbol == "\'" {'
        punctuation_route = "let snapshot = session.handlePunctuation(symbol)"
        self.assertIn(separator_route, controller)
        self.assertIn("session.handleCharacter(symbol)", controller)
        self.assertLess(controller.index(separator_route), controller.index(punctuation_route))

    def test_own_document_edits_do_not_cancel_the_composition(self):
        controller = (IOS_ROOT / "KeyboardExtension/Sources/KeyboardViewController.swift").read_text()

        # UIKit delivers textWillChange for the keyboard's own insertions too, so cancelling there
        # destroyed every composition a partial commit was meant to leave running. Each own edit
        # raises a count that the matching callback consumes; a genuine host change commits.
        self.assertIn("private var pendingOwnEdits = 0", controller)
        will_change = controller.split("override func textWillChange", 1)[1].split("\n  }", 1)[0]
        self.assertIn("pendingOwnEdits > 0", will_change)
        self.assertIn("pendingOwnEdits -= 1", will_change)
        self.assertIn("session.finishComposition()", will_change)
        self.assertNotIn("session.cancel()", will_change)
        # Only the two funnels may touch the proxy, otherwise an edit escapes the accounting.
        self.assertEqual(controller.count("textDocumentProxy.insertText("), 1)
        self.assertEqual(controller.count("textDocumentProxy.deleteBackward("), 1)
        # Putting the keyboard away commits rather than discarding, as macOS does.
        disappear = controller.split("override func viewWillDisappear", 1)[1].split("\n  }", 1)[0]
        self.assertIn("session.finishComposition()", disappear)

    def test_keyboard_exposes_a_local_chinese_english_mode_switch(self):
        controller = (IOS_ROOT / "KeyboardExtension/Sources/KeyboardViewController.swift").read_text()

        self.assertIn("private var isChineseMode = true", controller)
        self.assertIn("bottomLanguageButton", controller)
        self.assertIn("toggleInputMode", controller)
        self.assertIn("render(session.handleCharacter(character))", controller)
        self.assertIn("insertOwnText(output)", controller)
        self.assertIn("if !isChineseMode {\n      insertOwnText(symbol)", controller)
        self.assertIn("isChineseMode ? session.finishComposition() : session.cancel()", controller)
        self.assertIn('inputScheme.isJapanese ? "日" : "中"', controller)
        self.assertIn('bottomLanguageButton?.accessibilityIdentifier = "bottomLanguageKey"', controller)
        self.assertIn("bottomLanguageButton?.configuration = configuration", controller)
        self.assertIn("bottomLanguageButton?.isHidden = false", controller)

    def test_english_keyboard_supports_one_shot_shift_and_caps_lock(self):
        controller = (IOS_ROOT / "KeyboardExtension/Sources/KeyboardViewController.swift").read_text()

        self.assertIn("private enum LetterCaseState", controller)
        self.assertIn("case lowercase, shifted, capsLock", controller)
        self.assertIn(
            "private var letterButtons: [(button: UIButton, lowercase: String, hint: UILabel)]",
            controller,
        )
        self.assertIn("private weak var shiftButton: UIButton?", controller)
        self.assertIn("toggleLetterCase", controller)
        self.assertIn("letterCaseState = .capsLock", controller)
        self.assertIn("if letterCaseState == .shifted", controller)
        self.assertIn("letterCaseState = .lowercase", controller)
        self.assertIn('button.accessibilityIdentifier = "shiftButton"', controller)

    def test_return_key_reflects_the_host_input_trait(self):
        controller = (IOS_ROOT / "KeyboardExtension/Sources/KeyboardViewController.swift").read_text()

        self.assertIn("private weak var enterButton: UIButton?", controller)
        self.assertIn("override func textDidChange", controller)
        self.assertIn("switch textDocumentProxy.returnKeyType ?? .default", controller)
        self.assertIn("case .go:", controller)
        self.assertIn("case .google, .search, .yahoo:", controller)
        self.assertIn("case .send:", controller)
        self.assertIn("case .done:", controller)
        self.assertIn("enterButton?.accessibilityLabel = title", controller)

        self.assertIn("textDocumentProxy.autocapitalizationType ?? .sentences", controller)

    def test_project_and_ci_run_native_onboarding_ui_tests(self):
        project = (IOS_ROOT / "project.yml").read_text()
        workflow = (IOS_ROOT.parents[1] / ".github/workflows/ci.yml").read_text()
        runner = (IOS_ROOT / "scripts/run_ui_tests.sh").read_text()

        self.assertIn("MetasequoiaImeIOSUITests:", project)
        self.assertIn("platforms/ios/UITests", project)
        self.assertIn("GENERATE_INFOPLIST_FILE: YES", project)
        self.assertIn("MetasequoiaImeIOSUITests", project.split("test:", 1)[1])
        self.assertIn("platforms/ios/scripts/run_ui_tests.sh", workflow)
        self.assertIn("simctl bootstatus", runner)
        self.assertIn('derived_data_path="${2:-build/ios-derived}"', runner)
        self.assertIn('xcrun simctl shutdown "${test_device_id}"', runner)
        self.assertIn('xcrun simctl boot "${test_device_id}"', runner)
        self.assertNotIn("sleep ", runner)

        # Build and run are two actions against one destination. A single `test` action rebuilt
        # everything a separate workflow build step had just produced, because that step targeted
        # `generic/platform=iOS Simulator` while this targets a specific x86_64 device -- different
        # products, so nothing was reused and the job paid for the same compile twice.
        self.assertIn("build-for-testing", runner)
        self.assertIn("test-without-building", runner)
        self.assertNotIn("generic/platform=iOS Simulator", workflow)
        self.assertEqual(workflow.count("xcodebuild"), 0)
        # Booting returns immediately and the build needs no simulator, so the wait belongs after
        # the build rather than before it. Compare the commands rather than the file: prose that
        # names a step would otherwise decide the order this reads.
        commands = "\n".join(line for line in runner.splitlines() if not line.lstrip().startswith("#"))
        order = [commands.index(fragment) for fragment in (
            'xcrun simctl boot "${test_device_id}"', "build-for-testing",
            "simctl bootstatus", "test-without-building")]
        self.assertEqual(order, sorted(order), commands)
        # The scope narrows the run, not the build: a narrower build would skip a target that
        # test-without-building then fails to find.
        build_invocation = commands.split("build-for-testing", 1)[0].rsplit("xcodebuild", 1)[1]
        self.assertNotIn("scope_arguments", build_invocation)

    def test_ui_tests_are_main_actor_isolated_for_swift_6(self):
        ui_tests = (IOS_ROOT / "UITests/OnboardingUITests.swift").read_text()

        self.assertIn(
            "@MainActor\n  func testSettingsPersistAndExposeGuideAndTryout()",
            ui_tests,
        )

    def test_keyboard_action_row_adapts_to_narrow_screens(self):
        controller = (IOS_ROOT / "KeyboardExtension/Sources/KeyboardViewController.swift").read_text()

        self.assertIn(
            "space.widthAnchor.constraint(greaterThanOrEqualToConstant: 44)",
            controller,
        )
        # Presets add bottom-row actions; keep Space's minimum small enough for
        # narrow screens, including when applying a different preset at runtime.
        self.assertIn("standardActionWidths[1].constant = 44", controller)
        self.assertIn(
            "delete.widthAnchor.constraint(equalToConstant: 44)",
            controller,
        )
        self.assertIn(
            "enter.widthAnchor.constraint(equalToConstant: 59.4)",
            controller,
        )
        # Alphabetic Delete lives in the letter row; hiding symbol Delete must not
        # collapse Space/Return or leave a required width on a hidden stack item.
        self.assertIn("symbolDeleteWidth?.isActive = showsSymbols", controller)
        self.assertNotIn("equalTo: delete.widthAnchor", controller)
        self.assertNotIn("layoutToggle.widthAnchor.constraint(equalToConstant: 56)", controller)
        self.assertNotIn("space.widthAnchor.constraint(greaterThanOrEqualToConstant: 110)", controller)
        self.assertNotIn("enter.widthAnchor.constraint(equalToConstant: 72)", controller)
        self.assertIn("actionGlobeButton.isHidden = !needsInputModeSwitchKey", controller)
        self.assertIn("globeWidthConstraint?.isActive = false", controller)

    def test_keyboard_requests_consistent_height_below_system_priority(self):
        controller = (IOS_ROOT / "KeyboardExtension/Sources/KeyboardViewController.swift").read_text()

        self.assertIn("root.bottomAnchor.constraint(equalTo: view.bottomAnchor", controller)
        self.assertIn("height.priority = .init(999)", controller)
        # The composition line added a row to the candidate strip and the keyboard grew by it,
        # rather than taking the space out of the keys.
        self.assertIn("landscape ? 216 + extra : 260 + extra", controller)
        self.assertIn("let extra = Self.compositionRowHeight", controller)

    def test_keyboard_exposes_a_persisted_full_and_double_pinyin_switch(self):
        controller = (IOS_ROOT / "KeyboardExtension/Sources/KeyboardViewController.swift").read_text()
        bridge_header = (IOS_ROOT.parents[1] / "shared/apple-bridge/MetasequoiaInputSessionBridge.h").read_text()
        adapter_header = (IOS_ROOT.parents[1] / "shared/apple-bridge/InputSessionAdapter.h").read_text()

        self.assertIn("schemeButton", controller)
        self.assertIn("selectInputScheme", controller)
        self.assertIn("inputScheme = InputSchemePreference.scheme", controller)
        self.assertIn("InputSchemePreference.scheme = scheme", controller)
        self.assertIn("session.switch(toShuangpin: usesShuangpin)", controller)
        self.assertIn('configuration.image = UIImage(systemName: "keyboard")', controller)
        self.assertIn("schemeButton.accessibilityValue = inputScheme.title", controller)
        self.assertIn('schemeButton.accessibilityIdentifier = "schemeButton"', controller)
        self.assertIn("switchToShuangpin", bridge_header)
        self.assertIn("switch_to_shuangpin", adapter_header)

    def test_globe_key_uses_the_system_input_mode_list(self):
        controller = (IOS_ROOT / "KeyboardExtension/Sources/KeyboardViewController.swift").read_text()

        self.assertIn("#selector(handleInputModeButton(_:event:))", controller)
        self.assertIn("for: .allTouchEvents", controller)
        self.assertIn("touch.phase == .began", controller)
        self.assertIn("render(session.commitRaw())", controller)
        self.assertIn("handleInputModeList(from: sender, with: event)", controller)
        self.assertNotIn("advanceToNextInputMode()", controller)

    def test_bridge_compiles_every_engine_source_directory(self):
        # macOS pulls the engine in with add_subdirectory, so it tracks new engine directories on its own. This target enumerates them by hand, so a directory added upstream silently drops out of the static library and only surfaces as undefined symbols at link time — which is how local_modes broke the keyboard extension.
        engine_root = IOS_ROOT.parents[1] / "vendor/MetasequoiaImeEngine"
        if not (engine_root / "core").is_dir():
            self.skipTest("engine submodule is not checked out")

        project = (IOS_ROOT / "project.yml").read_text()
        not_built = {"tests"}
        missing = []
        for directory in sorted(engine_root.iterdir()):
            if not directory.is_dir() or directory.name.startswith("."):
                continue
            if directory.name in not_built:
                continue
            if not any(directory.glob("*.cpp")):
                continue
            if f"vendor/MetasequoiaImeEngine/{directory.name}" not in project:
                missing.append(directory.name)

        self.assertEqual(missing, [], f"engine directories missing from the bridge target: {missing}")


    def test_chinese_mode_never_sends_uppercase_to_the_session(self):
        controller = (IOS_ROOT / "KeyboardExtension/Sources/KeyboardViewController.swift").read_text()

        # Shift leaves the Engine scheme before enabling English capitalization; uppercase letters
        # are inserted directly rather than being consumed as Engine helpcode input.
        shift_handler = controller.split("private func toggleLetterCase", 1)[1].split("\n  }", 1)[0]
        self.assertIn("if isChineseMode {", shift_handler)
        self.assertIn("toggleInputMode()", shift_handler)
        self.assertIn("let usesUppercase = !isChineseMode && letterCaseState != .lowercase", controller)
        character_handler = controller.split("private func handleCharacter", 1)[1].split("\n  }", 1)[0]
        self.assertIn("render(session.handleCharacter(character))", character_handler)
        self.assertNotIn("uppercased()", character_handler.split("} else {", 1)[0])

    def test_build_number_comes_from_the_release_tag_and_not_the_marketing_version(self):
        # App Store Connect keys Beta App Review to CFBundleShortVersionString and rejects a repeated
        # CFBundleVersion inside it. Both used to carry the release version, which allowed exactly one
        # upload per release: a build that failed review could only be replaced by cutting another.
        scripts = {
            name: (IOS_ROOT / "scripts" / name).read_text()
            for name in ("package_ios_testflight.sh", "package_ios_archive.sh")
        }
        for name, script in scripts.items():
            self.assertIn('CURRENT_PROJECT_VERSION="$build_number"', script, name)
            self.assertNotIn('CURRENT_PROJECT_VERSION="$version"', script, name)
            self.assertIn('MARKETING_VERSION="$version"', script, name)

        # Assert the number the scripts produce, not the shape of the line producing it. A previous
        # change truncated the marketing version to x.y and rewrote the assertions above to match, so
        # the suite stayed green while iOS shipped 0.48 against a 0.48.6 product version -- which
        # sorts below it in TestFlight. Replay each script's own derivation and compare the result
        # with the version the project spec declares.
        spec_version = re.search(r"MARKETING_VERSION:\s*(\S+)", (IOS_ROOT / "project.yml").read_text())
        self.assertIsNotNone(spec_version, "project.yml must declare MARKETING_VERSION")
        product_version = spec_version.group(1)
        for name, script in scripts.items():
            setting = re.search(r'MARKETING_VERSION="\$(\w+)"', script)
            self.assertIsNotNone(setting, name)
            # Walk back from the variable the archive is given, collecting the assignments it is
            # built from. tag_name is the input and comes from the environment below.
            wanted, collected = {setting.group(1)}, []
            for line in reversed(script.splitlines()):
                assignment = re.match(r"^(\w+)=(.*)$", line)
                if not assignment or assignment.group(1) in {"tag_name"}:
                    continue
                if assignment.group(1) in wanted:
                    collected.append(line)
                    wanted |= set(re.findall(r"\$\{?(\w+)", assignment.group(2)))
            derivation = "\n".join(reversed(collected))
            archived = subprocess.run(
                ["bash", "-eu", "-c", derivation + f'\nprintf "%s" "${setting.group(1)}"'],
                env=dict(os.environ, tag_name=f"v{product_version}-build.1002.57.1"),
                text=True, capture_output=True,
            )
            self.assertEqual(archived.returncode, 0, archived.stderr)
            self.assertEqual(archived.stdout, product_version, name)

        # The build number is no longer a commit count: a release tag carries it directly, and a
        # METASEQUOIA_BUILD_NUMBER disagreeing with the tag has to stop the packaging rather than
        # ship a number that contradicts the release it goes out under.
        start = "build_number=${METASEQUOIA_BUILD_NUMBER:-$version}"
        fragments = {}
        for name, script in scripts.items():
            begin = script.index(start)
            fragments[name] = script[begin:script.index("\nfi\n", begin) + len("\nfi\n")]
        self.assertEqual(*fragments.values(), "both release paths must derive the build number alike")

        fragment = next(iter(fragments.values()))
        for tag, supplied, expected in [
            (f"v{product_version}", None, product_version),
            (f"v{product_version}-build.1002.57.1", None, "1002.57.1"),
            (f"ios-v{product_version}-build.1002.57.1", None, "1002.57.1"),
            (f"v{product_version}-build.1002.57.1", "1002.57.1", "1002.57.1"),
            (f"v{product_version}-build.1002.57.1", "1002.58.1", None),
        ]:
            environment = dict(os.environ, tag_name=tag, version=product_version)
            environment.pop("METASEQUOIA_BUILD_NUMBER", None)
            if supplied is not None:
                environment["METASEQUOIA_BUILD_NUMBER"] = supplied
            produced = subprocess.run(
                ["bash", "-eu", "-c", fragment + '\nprintf "%s" "$build_number"'],
                env=environment, text=True, capture_output=True,
            )
            if expected is None:
                self.assertNotEqual(produced.returncode, 0, tag)
                self.assertIn("does not match", produced.stderr)
            else:
                self.assertEqual(produced.returncode, 0, produced.stderr)
                self.assertEqual(produced.stdout, expected, tag)


if __name__ == "__main__":
    unittest.main()
