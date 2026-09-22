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
    }
}
