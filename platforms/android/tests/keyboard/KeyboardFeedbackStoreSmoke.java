package app.msime.client;

import app.msime.client.KeyboardFeedbackPreferences.HapticStrength;

public final class KeyboardFeedbackStoreSmoke {
    static void check(boolean condition) { if (!condition) throw new AssertionError(); }

    public static void main(String[] args) {
        KeyboardFeedbackStore.Settings settings = new KeyboardFeedbackStore.Settings(
            false, true, HapticStrength.STRONG);
        check(!settings.soundEnabled());
        check(settings.hapticsEnabled());
        check(settings.hapticStrength() == HapticStrength.STRONG);

        KeyboardFeedbackStore.Settings defaults = new KeyboardFeedbackStore.Settings(
            true, false, null);
        check(defaults.soundEnabled());
        check(!defaults.hapticsEnabled());
        check(defaults.hapticStrength() == HapticStrength.MEDIUM);
        System.out.println("Android keyboard feedback: shared settings value contract passed");
    }
}
