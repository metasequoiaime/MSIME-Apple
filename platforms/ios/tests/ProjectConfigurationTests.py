import re
import unittest
from pathlib import Path


IOS_ROOT = Path(__file__).resolve().parents[1]


class ProjectConfigurationTests(unittest.TestCase):
    def test_app_and_keyboard_share_the_declared_app_group(self):
        expected = "group.app.msime.ios"
        app = (IOS_ROOT / "App/Resources/MSIMEClientApp.entitlements").read_text()
        keyboard = (IOS_ROOT / "KeyboardExtension/Resources/MSIMEKeyboardExtension.entitlements").read_text()
        self.assertIn(expected, app)
        self.assertIn(expected, keyboard)
        project = (IOS_ROOT / "project.yml").read_text()
        self.assertIn("CODE_SIGN_ENTITLEMENTS: App/Resources/MSIMEClientApp.entitlements", project)
        self.assertIn("CODE_SIGN_ENTITLEMENTS: KeyboardExtension/Resources/MSIMEKeyboardExtension.entitlements", project)

    def test_device_uses_real_handwriting_and_simulator_keeps_buildable_fallback(self):
        project = (IOS_ROOT / "project.yml").read_text()
        self.assertIn("EXCLUDED_SOURCE_FILE_NAMES[sdk=iphoneos*]: HandwritingInputViewFallback.swift", project)
        self.assertIn("EXCLUDED_SOURCE_FILE_NAMES[sdk=iphonesimulator*]: HandwritingInputView.swift HandwritingDownloadSession.m", project)
        self.assertIn("SWIFT_OBJC_BRIDGING_HEADER", project)
        podfile = (IOS_ROOT / "Podfile").read_text()
        self.assertIn("pod 'MLKitDigitalInkRecognition', '8.0.0'", podfile)
        self.assertIn("target 'MSIMEKeyboardExtension'", podfile)

    def test_every_keyboard_scroll_view_turns_off_the_ios26_edge_effect(self):
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


if __name__ == "__main__":
    unittest.main()
