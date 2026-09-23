package app.msime.client;

/** Chords shared by desktop settings and Android hardware keyboards. */
public final class HardwareShortcutPolicy {
    public enum Action {
        NONE, TOGGLE_LANGUAGE, TOGGLE_CHARACTER_SET, TOGGLE_FULL_WIDTH, TOGGLE_PUNCTUATION
    }
    private HardwareShortcutPolicy() {}

    public static Action chord(int key, boolean shift, boolean ctrl, boolean alt, int repeatCount,
                               boolean language, boolean characterSet, boolean fullWidth) {
        if (repeatCount != 0) return Action.NONE;
        if (key == 62 && language && shift && !ctrl && !alt)
            return Action.TOGGLE_LANGUAGE;
        if (key == 62 && language && ctrl && alt)
            return Action.TOGGLE_LANGUAGE;
        if (key == 33 && characterSet && ctrl && shift && !alt)
            return Action.TOGGLE_CHARACTER_SET;
        if (key == 36 && fullWidth && alt && shift && !ctrl)
            return Action.TOGGLE_FULL_WIDTH;
        // Ctrl + . switches Chinese and English punctuation, as the source does. It is not one of
        // the five shared keybinding switches, so there is no preference gating it: the desktop
        // hosts reserve this chord unconditionally too.
        if (key == 56 && ctrl && !shift && !alt)
            return Action.TOGGLE_PUNCTUATION;
        return Action.NONE;
    }
}
