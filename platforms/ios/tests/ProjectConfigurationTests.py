import re
import unittest
from pathlib import Path


IOS_ROOT = Path(__file__).resolve().parents[1]


def target_blocks(project):
    """Yield (name, body) for each entry under `targets:`, split on its indentation."""
    lines = project.splitlines(keepends=True)
    start = next(i for i, line in enumerate(lines) if line.rstrip() == "targets:")
    blocks, name, body = [], None, []
    for line in lines[start + 1:]:
        if line.strip() and not line.startswith("   ") and not line.startswith("  -"):
            if re.fullmatch(r"  [A-Za-z0-9_]+:\n", line):
                if name:
                    blocks.append((name, "".join(body)))
                name, body = line.strip().rstrip(":"), []
                continue
            if not line.startswith(" "):
                break
        body.append(line)
    if name:
        blocks.append((name, "".join(body)))
    return blocks


def source_path_blocks(body, wanted):
    """Yield the body of every `- path: <wanted>` entry in a sources list."""
    lines = body.splitlines(keepends=True)
    out = []
    for i, line in enumerate(lines):
        if line.strip() != f"- path: {wanted}":
            continue
        indent = len(line) - len(line.lstrip())
        collected = []
        for following in lines[i + 1:]:
            if not following.strip():
                collected.append(following)
                continue
            if len(following) - len(following.lstrip()) <= indent:
                break
            collected.append(following)
        out.append("".join(collected))
    return out


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

    # A `swift build` under shared/backend leaves 2000+ files in .build, and every target that takes
    # that directory as a source path would otherwise compile them into the app: the archive fails
    # with dozens of "Multiple commands produce" errors naming MSIMEBackend.o and precompiled
    # modules.
    def test_every_shared_backend_source_path_excludes_swiftpm_output(self):
        project = (IOS_ROOT / "project.yml").read_text()
        blocks = [
            block
            for _, body in target_blocks(project)
            for block in source_path_blocks(body, "../../shared/backend")
        ]
        self.assertTrue(blocks, "no target takes shared/backend as a source path any more")
        for block in blocks:
            self.assertIn("- .build/**", block)

    # XcodeGen's Info.plist detection ignores source excludes, so it finds the plist inside
    # shared/backend/.build and writes it into INFOPLIST_FILE. No exclude pattern suppresses it and
    # a project-level setting does not override it, because the detected value lands in the target's
    # own build settings. Pinning an empty value there is what keeps the generated plist.
    def test_targets_that_generate_their_plist_pin_the_file_setting(self):
        project = (IOS_ROOT / "project.yml").read_text()
        generated = [
            name
            for name, body in target_blocks(project)
            if "GENERATE_INFOPLIST_FILE: YES" in body
        ]
        self.assertTrue(generated, "no target asks Xcode to generate its Info.plist any more")
        for name, body in target_blocks(project):
            if "GENERATE_INFOPLIST_FILE: YES" in body:
                self.assertIn('INFOPLIST_FILE: ""', body, name)

    # The developer account carries app.msime.ios and app.msime.ios.keyboard with the App Group the
    # entitlements declare. A bundle identifier outside that prefix has no profile that satisfies
    # the App Groups entitlement, and signing fails before anything reaches a device.
    def test_bundle_identifiers_match_the_provisioned_app_ids(self):
        project = (IOS_ROOT / "project.yml").read_text()
        identifiers = re.findall(r"PRODUCT_BUNDLE_IDENTIFIER: (\S+)", project)
        self.assertTrue(identifiers)
        for identifier in identifiers:
            self.assertTrue(identifier == "app.msime.ios" or identifier.startswith("app.msime.ios."),
                            identifier)
        self.assertIn("PRODUCT_BUNDLE_IDENTIFIER: app.msime.ios\n", project)
        self.assertIn("PRODUCT_BUNDLE_IDENTIFIER: app.msime.ios.keyboard\n", project)
        self.assertIn("bundleIdPrefix: app.msime.ios", project)
        self.assertIn("DEVELOPMENT_TEAM: LXCL4Z68GU", project)

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
