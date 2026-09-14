import re
import unittest
from pathlib import Path


IOS_ROOT = Path(__file__).resolve().parents[1]


class ProjectConfigurationTests(unittest.TestCase):
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
