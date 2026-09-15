import json
import plistlib
import unittest
from pathlib import Path


TAURI_ROOT = Path(__file__).resolve().parents[1]
APPLE_ROOT = TAURI_ROOT / "gen/apple"


class IOSProjectConfigTests(unittest.TestCase):
    def test_tauri_app_declares_export_compliance_without_non_exempt_encryption(self):
        project = (APPLE_ROOT / "project.yml").read_text()
        self.assertIn("ITSAppUsesNonExemptEncryption: false", project)
        with (APPLE_ROOT / "msime-desktop_iOS/Info.plist").open("rb") as file:
            info = plistlib.load(file)
        self.assertIs(info["ITSAppUsesNonExemptEncryption"], False)

    def test_privacy_manifest_is_shared_by_tauri_app_and_keyboard(self):
        privacy_path = TAURI_ROOT / "../../../platforms/ios/SharedResources/PrivacyInfo.xcprivacy"
        with privacy_path.resolve().open("rb") as file:
            privacy = plistlib.load(file)
        self.assertFalse(privacy["NSPrivacyTracking"])
        self.assertEqual(privacy["NSPrivacyCollectedDataTypes"], [])
        project = (APPLE_ROOT / "project.yml").read_text()
        reference = "path: ../../../../../platforms/ios/SharedResources/PrivacyInfo.xcprivacy"
        self.assertEqual(project.count(reference), 2)
        generated = (APPLE_ROOT / "msime-desktop.xcodeproj/project.pbxproj").read_text()
        self.assertIn("path = PrivacyInfo.xcprivacy", generated)
        self.assertEqual(generated.count("PrivacyInfo.xcprivacy in Resources"), 4)

    def test_platform_config_uses_the_shipping_identity_and_supported_version(self):
        config = json.loads((TAURI_ROOT / "tauri.ios.conf.json").read_text())
        self.assertEqual(config["identifier"], "com.metasequoiaime.client")
        self.assertEqual(config["productName"], "水杉输入法")
        self.assertEqual(config["bundle"]["iOS"]["minimumSystemVersion"], "16.0")

    def test_native_entry_and_entitlement_share_keyboard_state_without_private_data(self):
        entry = (APPLE_ROOT / "Sources/msime-desktop/main.mm").read_text()
        self.assertIn("group.app.msime.ios", entry)
        self.assertIn('setenv("MSIME_CLIENT_STATE_DIR"', entry)
        with (APPLE_ROOT / "msime-desktop_iOS/msime-desktop_iOS.entitlements").open("rb") as file:
            entitlements = plistlib.load(file)
        self.assertEqual(
            entitlements["com.apple.security.application-groups"],
            ["group.app.msime.ios"],
        )

    def test_generated_project_builds_the_shared_rust_mobile_entry(self):
        project = (APPLE_ROOT / "project.yml").read_text()
        self.assertIn("PRODUCT_BUNDLE_IDENTIFIER: com.metasequoiaime.client", project)
        self.assertIn("iOS: 16.0", project)
        self.assertIn("pnpm tauri ios xcode-script", project)
        self.assertIn("framework: libapp.a", project)
        self.assertIn("../../../../../target/ios/EngineResources", project)
        self.assertIn('          - "-lsqlite3"', project)

    def test_tauri_app_embeds_the_native_keyboard_extension(self):
        project = (APPLE_ROOT / "project.yml").read_text()
        self.assertIn("  MSIMEKeyboardExtension:\n    type: app-extension", project)
        self.assertIn("PRODUCT_BUNDLE_IDENTIFIER: com.metasequoiaime.client.keyboard", project)
        self.assertIn("CODE_SIGN_ENTITLEMENTS: ../../../../../platforms/ios/KeyboardExtension/Resources/MSIMEKeyboardExtension.entitlements", project)
        self.assertIn("SWIFT_OBJC_BRIDGING_HEADER: $(SRCROOT)/../../../../../platforms/ios/KeyboardExtension/Sources/MetasequoiaKeyboard-Bridging-Header.h", project)
        self.assertIn("SWIFT_VERSION: 5.0", project)
        self.assertIn("path: MSIMEKeyboardExtension/Info.plist", project)
        self.assertIn("      - target: MSIMEKeyboardExtension", project)

        info_path = APPLE_ROOT / "MSIMEKeyboardExtension/Info.plist"
        with info_path.resolve().open("rb") as file:
            info = plistlib.load(file)
        extension = info["NSExtension"]
        self.assertEqual(extension["NSExtensionPointIdentifier"], "com.apple.keyboard-service")
        self.assertTrue(extension["NSExtensionAttributes"]["RequestsOpenAccess"])

        entitlement_path = APPLE_ROOT / "../../../../../platforms/ios/KeyboardExtension/Resources/MSIMEKeyboardExtension.entitlements"
        with entitlement_path.resolve().open("rb") as file:
            entitlements = plistlib.load(file)
        self.assertEqual(
            entitlements["com.apple.security.application-groups"],
            ["group.app.msime.ios"],
        )

    def test_tauri_app_packages_and_registers_ios_alternate_icons(self):
        project = (APPLE_ROOT / "project.yml").read_text()
        generated_project = (APPLE_ROOT / "msime-desktop.xcodeproj/project.pbxproj").read_text()
        alternate_names = [
            "AppIconForest",
            "AppIconSky",
            "AppIconDusk",
            "AppIconVermilion",
        ]
        self.assertIn("ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon", project)
        self.assertIn(
            "ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES: " + " ".join(alternate_names),
            project,
        )
        self.assertIn("ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS: true", project)
        self.assertIn('- "**/libapp.a"', project)
        self.assertIn("ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES", generated_project)
        self.assertNotIn("libapp.a in Resources", generated_project)
        for name in alternate_names:
            icon_set = APPLE_ROOT / f"Assets.xcassets/{name}.appiconset"
            self.assertTrue((icon_set / "Contents.json").is_file())
            self.assertTrue((icon_set / "Icon.png").is_file())

        manifest = (TAURI_ROOT / "Cargo.toml").read_text()
        rust_entry = (TAURI_ROOT / "src/lib.rs").read_text()
        desktop_entry = (TAURI_ROOT.parent / "src/main.tsx").read_text()
        plugin = TAURI_ROOT / "../../../crates/tauri-mobile-platform"
        swift = (plugin / "ios/Sources/MobilePlatformPlugin.swift").read_text()
        self.assertIn("msime-tauri-mobile-platform", manifest)
        self.assertIn("builder.plugin(msime_tauri_mobile_platform::init())", rust_entry)
        self.assertIn("open_system_keyboard_settings", rust_entry)
        self.assertIn("app_icon_info", rust_entry)
        self.assertIn("app_icon_set", rust_entry)
        self.assertIn('invoke("open_system_keyboard_settings")', desktop_entry)
        self.assertIn("UIApplication.openSettingsURLString", swift)
        self.assertIn("openSystemKeyboardSettings", swift)
        self.assertIn("application.supportsAlternateIcons", swift)
        self.assertIn("application.setAlternateIconName(requestedName)", swift)
        self.assertIn("application.alternateIconName != requestedName", swift)
        self.assertIn('invoke.reject("app_icon", code: "app_icon")', swift)

    def test_keyboard_keeps_device_mlkit_and_simulator_fallback_boundaries(self):
        project = (APPLE_ROOT / "project.yml").read_text()
        self.assertIn("EXCLUDED_SOURCE_FILE_NAMES[sdk=iphoneos*]: HandwritingInputViewFallback.swift", project)
        self.assertIn("EXCLUDED_SOURCE_FILE_NAMES[sdk=iphonesimulator*]: HandwritingInputView.swift HandwritingDownloadSession.m", project)
        self.assertIn("../../../../../target/ios/EngineResources", project)
        self.assertIn('          - "-lmsime_host_api"', project)

        podfile = (APPLE_ROOT / "Podfile").read_text()
        self.assertIn("target 'MSIMEKeyboardExtension'", podfile)
        self.assertIn("pod 'MLKitDigitalInkRecognition', '8.0.0'", podfile)

    def test_mobile_platform_keeps_account_sessions_in_the_ios_keychain(self):
        plugin = TAURI_ROOT / "../../../crates/tauri-mobile-platform"
        rust = (plugin / "src/lib.rs").read_text()
        swift = (plugin / "ios/Sources/MobilePlatformPlugin.swift").read_text()

        self.assertIn('run_mobile_plugin::<AccountSessionResponse>("loadSession", ())', rust)
        self.assertIn('run_mobile_plugin("saveSession", AccountSessionRequest { value })', rust)
        self.assertIn('run_mobile_plugin("clearSession", ())', rust)
        self.assertIn('kSecAttrService as String: "app.msime.backend.account"', swift)
        self.assertIn('kSecAttrAccount as String: "https://api.msime.app"', swift)
        self.assertIn("kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly", swift)
        self.assertIn('kSecAttrService as String: "app.msime.ios.community"', swift)
        self.assertIn("static let maximumPayloadBytes = 16 * 1024", swift)
        self.assertIn("@objc public func loadSession", swift)
        self.assertIn("@objc public func saveSession", swift)
        self.assertIn("@objc public func clearSession", swift)

    def test_ios_registers_shared_account_commands_and_ui(self):
        rust_entry = (TAURI_ROOT / "src/lib.rs").read_text()
        account = (TAURI_ROOT / "src/ios_account.rs").read_text()
        desktop_entry = (TAURI_ROOT.parent / "src/main.tsx").read_text()

        self.assertIn('mod ios_account;', rust_entry)
        self.assertIn('ios_account::setup(app.handle())?', rust_entry)
        for command in [
            "account_status",
            "account_providers",
            "account_request_code",
            "account_login",
            "account_profile",
            "account_chat_models",
            "account_chat",
            "account_rename",
            "account_logout",
            "account_delete",
            "account_forget",
            "account_preferences_schema",
            "account_preferences_load",
            "account_preferences_upload",
            "account_preferences_apply",
        ]:
            self.assertIn(f"ios_account::{command}", rust_entry)
            self.assertIn(f"pub async fn {command}", account)
        self.assertIn("BackendAccountSession::new", account)
        self.assertIn("IosAccountStorage(platform.clone())", account)
        self.assertIn('account: { ...basicAccount, settingsSync: accountSettingsSync }', desktop_entry)
        self.assertIn('invoke("account_chat_models")', desktop_entry)
        self.assertIn('invoke<{ content: string }>("account_chat", { messages, model })', desktop_entry)

    def test_ios_account_settings_sync_bridges_app_group_keyboard_preferences(self):
        plugin = TAURI_ROOT / "../../../crates/tauri-mobile-platform"
        rust = (plugin / "src/lib.rs").read_text()
        swift = (plugin / "ios/Sources/MobilePlatformPlugin.swift").read_text()
        account = (TAURI_ROOT / "src/ios_account.rs").read_text()
        mapping = (TAURI_ROOT / "src/ios_account_preferences.rs").read_text()
        desktop_entry = (TAURI_ROOT.parent / "src/main.tsx").read_text()

        self.assertIn('run_mobile_plugin::<IosKeyboardPreferences>("loadKeyboardPreferences", ())', rust)
        self.assertIn('run_mobile_plugin::<IosKeyboardPreferences>("saveKeyboardPreferences", preferences)', rust)
        self.assertIn('UserDefaults(suiteName: "group.app.msime.ios")', swift)
        for key in [
            "chineseInputScheme",
            "chineseOutputUsesTraditional",
            "keyboardSoundEnabled",
            "keyboardHapticsEnabled",
            "keyboardHapticStrength",
            "dictionaryLearningEnabled",
            "keyboardSkin",
            "customKeyboardSkin.v1",
        ]:
            self.assertIn(key, swift)
        self.assertIn("merge_account_preferences", account)
        self.assertIn("platform.save_keyboard_preferences(&previous_native)", account)
        self.assertIn('"platform.ios.nine_key"', mapping)
        self.assertIn('"platform.ios.custom_keyboard_skin"', mapping)
        self.assertIn("settingsSync: accountSettingsSync", desktop_entry)

    def test_ios_cloud_clipboard_uses_the_shared_account_and_native_copy_boundaries(self):
        plugin = TAURI_ROOT / "../../../crates/tauri-mobile-platform"
        plugin_rust = (plugin / "src/lib.rs").read_text()
        swift = (plugin / "ios/Sources/MobilePlatformPlugin.swift").read_text()
        rust_entry = (TAURI_ROOT / "src/lib.rs").read_text()
        account = (TAURI_ROOT / "src/ios_account.rs").read_text()
        desktop_entry = (TAURI_ROOT.parent / "src/main.tsx").read_text()

        self.assertIn("ios_account::cloud_clipboard_request(state, action).await", rust_entry)
        self.assertIn("pub async fn cloud_clipboard_request", account)
        self.assertIn("session.clipboard(&search)", account)
        self.assertIn(".set_clipboard_enabled(enabled)", account)
        self.assertIn("session.add_clipboard(&text)", account)
        self.assertIn(".delete_clipboard(Some(&id))", account)
        self.assertIn('run_mobile_plugin("copyText", CopyTextRequest { text })', plugin_rust)
        self.assertIn("@objc public func copyText", swift)
        self.assertIn("UIPasteboard.general.string = args.text", swift)
        self.assertEqual(
            desktop_entry.count(
                'openCloudClipboard: async () => setMobilePanel("cloud-clipboard")'
            ),
            2,
        )

    def test_ios_cloud_dictionary_uses_shared_account_without_snapshot_state(self):
        rust_entry = (TAURI_ROOT / "src/lib.rs").read_text()
        account = (TAURI_ROOT / "src/ios_account.rs").read_text()
        desktop_entry = (TAURI_ROOT.parent / "src/main.tsx").read_text()

        self.assertIn("ios_account::cloud_dictionary_request(state, action).await", rust_entry)
        self.assertIn("pub async fn cloud_dictionary_request", account)
        for method in [
            "session.dictionary(kind, &search, offset)",
            "dictionary_catalog(kind, &code, offset, &scheme, &profile)",
            ".add_dictionary(",
            ".update_dictionary(",
            ".personal_candidates(",
            ".rank_candidate(",
            ".remove_candidate(",
            ".import_dictionary(",
            ".export_dictionary(",
        ]:
            self.assertIn(method, account)
        self.assertIn(
            'openCloudDictionary: async () => setMobilePanel("cloud-dictionary")',
            desktop_entry,
        )
        self.assertIn('code: "invalid_cloud_dictionary"', account)

    def test_ios_community_services_use_shared_backend_and_tauri_ui(self):
        rust_entry = (TAURI_ROOT / "src/lib.rs").read_text()
        account = (TAURI_ROOT / "src/ios_account.rs").read_text()
        desktop_entry = (TAURI_ROOT.parent / "src/main.tsx").read_text()

        for symbol in [
            "ios_account::community_skin_list",
            "ios_account::community_skin_download",
            "ios_account::ai_skin_generate",
            "ios_account::community_resource_list",
            "ios_account::community_resource_apply",
        ]:
            self.assertIn(symbol, rust_entry)
        for symbol in [
            "BackendCommunitySkinService",
            "BackendCommunityResourceService",
            "BackendAiSkinService",
            "pub async fn community_skin_list",
            "pub async fn ai_skin_generate",
            "pub async fn community_resource_list",
            "CommunityResourceLibraryStore",
        ]:
            self.assertIn(symbol, account)
        self.assertIn("communitySkins:", desktop_entry)
        self.assertIn("communityResources:", desktop_entry)
        self.assertIn("aiSkins:", desktop_entry)

    def test_xcode27_runtime_exports_are_built_before_the_rust_mobile_library(self):
        project = (APPLE_ROOT / "project.yml").read_text()
        self.assertIn("revision: a83e2b2f196e3fa9605cb21c7d3b82652205c279", project)
        self.assertIn("  MSIMESwiftRsRuntimeExports:\n    type: library.static", project)
        self.assertIn("      - target: MSIMESwiftRsRuntimeExports", project)
        build_script = (TAURI_ROOT / "build.rs").read_text()
        self.assertIn("CONFIGURATION_BUILD_DIR", build_script)
        self.assertIn("cargo:rustc-link-lib=static=MSIMESwiftRsRuntimeExports", build_script)


if __name__ == "__main__":
    unittest.main()
