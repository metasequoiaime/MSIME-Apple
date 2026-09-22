package app.msime.client;

/** Maps the hardware number row to the visible candidate slot. */
public final class NumberRowSelectionPolicy {
    private NumberRowSelectionPolicy() {}

    public static int slotForKeyCode(int keyCode, boolean enabled) {
        if (!enabled || keyCode < 8 || keyCode > 16) return -1;
        return keyCode - 8;
    }
}
