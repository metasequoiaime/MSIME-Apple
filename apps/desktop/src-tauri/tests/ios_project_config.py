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


if __name__ == "__main__":
    unittest.main()
