import json
import plistlib
import unittest
from pathlib import Path


TAURI_ROOT = Path(__file__).resolve().parents[1]
APPLE_ROOT = TAURI_ROOT / "gen/apple"


class IOSProjectConfigTests(unittest.TestCase):
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

    def test_keyboard_keeps_device_mlkit_and_simulator_fallback_boundaries(self):
        project = (APPLE_ROOT / "project.yml").read_text()
        self.assertIn("EXCLUDED_SOURCE_FILE_NAMES[sdk=iphoneos*]: HandwritingInputViewFallback.swift", project)
        self.assertIn("EXCLUDED_SOURCE_FILE_NAMES[sdk=iphonesimulator*]: HandwritingInputView.swift HandwritingDownloadSession.m", project)
        self.assertIn("../../../../../target/ios/EngineResources", project)
        self.assertIn('          - "-lmsime_host_api"', project)

        podfile = (APPLE_ROOT / "Podfile").read_text()
        self.assertIn("target 'MSIMEKeyboardExtension'", podfile)
        self.assertIn("pod 'MLKitDigitalInkRecognition', '8.0.0'", podfile)

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
