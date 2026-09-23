package app.msime.client;

public final class HardwareShortcutPolicySmoke {
    public static void main(String[] args) {
        if (HardwareShortcutPolicy.chord(62, true, false, false, 0, true, true, true)
                != HardwareShortcutPolicy.Action.TOGGLE_LANGUAGE) throw new AssertionError("shift space");
        if (HardwareShortcutPolicy.chord(62, false, true, true, 0, true, true, true)
                != HardwareShortcutPolicy.Action.TOGGLE_LANGUAGE) throw new AssertionError("ctrl alt space");
        if (HardwareShortcutPolicy.chord(33, true, true, false, 0, true, true, true)
                != HardwareShortcutPolicy.Action.TOGGLE_CHARACTER_SET) throw new AssertionError("ctrl shift f");
        if (HardwareShortcutPolicy.chord(36, true, false, true, 0, true, true, true)
                != HardwareShortcutPolicy.Action.TOGGLE_FULL_WIDTH) throw new AssertionError("alt shift h");
        if (HardwareShortcutPolicy.chord(62, true, false, false, 0, false, true, true)
                != HardwareShortcutPolicy.Action.NONE) throw new AssertionError("disabled");
        // Ctrl + . is the source's punctuation chord. Asserting against KeyEvent's own constant
        // rather than the number in the policy is the point: the policy carries raw key codes, and
        // a wrong one is invisible until somebody presses the key.
        if (HardwareShortcutPolicy.chord(android.view.KeyEvent.KEYCODE_PERIOD, false, true, false,
                0, true, true, true) != HardwareShortcutPolicy.Action.TOGGLE_PUNCTUATION) {
            throw new AssertionError("ctrl period");
        }
        // The shifted face of that key is a mark the user is entitled to type while composing.
        if (HardwareShortcutPolicy.chord(android.view.KeyEvent.KEYCODE_PERIOD, true, true, false,
                0, true, true, true) != HardwareShortcutPolicy.Action.NONE) {
            throw new AssertionError("ctrl shift period");
        }
        if (HardwareShortcutPolicy.chord(android.view.KeyEvent.KEYCODE_PERIOD, false, false, false,
                0, true, true, true) != HardwareShortcutPolicy.Action.NONE) {
            throw new AssertionError("bare period");
        }
        if (HardwareShortcutPolicy.chord(android.view.KeyEvent.KEYCODE_COMMA, false, true, false,
                0, true, true, true) != HardwareShortcutPolicy.Action.NONE) {
            throw new AssertionError("ctrl comma");
        }
    }
}
