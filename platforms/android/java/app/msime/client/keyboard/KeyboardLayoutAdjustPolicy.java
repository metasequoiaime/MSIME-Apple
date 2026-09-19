package app.msime.client;

/** Pure drag math for the transparent keyboard-layout adjustment surface. */
public final class KeyboardLayoutAdjustPolicy {
    public enum Axis { HORIZONTAL, VERTICAL }

    private static final float SPACING_DRAG_SCALE_DP = 18f;

    private KeyboardLayoutAdjustPolicy() { }

    public static Axis chooseAxis(float translationX, float translationY, Axis previous) {
        if (previous != null) return previous;
        if (!Float.isFinite(translationX) || !Float.isFinite(translationY)) return null;
        return Math.abs(translationY) >= Math.abs(translationX)
            ? Axis.VERTICAL : Axis.HORIZONTAL;
    }

    public static int keySpacingFromDrag(int baseTenths, float translationDp) {
        if (!Float.isFinite(translationDp)) return KeyboardGeometry.keySpacing(baseTenths);
        int delta = Math.round(translationDp * 10f / SPACING_DRAG_SCALE_DP);
        return clamp(baseTenths + delta, KeyboardGeometry.MIN_KEY_SPACING_TENTHS,
            KeyboardGeometry.MAX_KEY_SPACING_TENTHS);
    }

    public static int rowSpacingFromDrag(int baseTenths, float translationDp) {
        if (!Float.isFinite(translationDp)) return KeyboardGeometry.rowSpacing(baseTenths);
        int delta = Math.round(translationDp * 10f / SPACING_DRAG_SCALE_DP);
        return clamp(baseTenths + delta, KeyboardGeometry.MIN_ROW_SPACING_TENTHS,
            KeyboardGeometry.MAX_ROW_SPACING_TENTHS);
    }

    public static int heightFromDrag(int baseAdjustment, float translationDp) {
        if (!Float.isFinite(translationDp)) return KeyboardGeometry.heightAdjustment(baseAdjustment);
        int delta = Math.round(translationDp);
        return clamp(KeyboardGeometry.heightAdjustment(baseAdjustment) - delta,
            KeyboardGeometry.MIN_HEIGHT_ADJUSTMENT_DP,
            KeyboardGeometry.MAX_HEIGHT_ADJUSTMENT_DP);
    }

    private static int clamp(int value, int minimum, int maximum) {
        return Math.max(minimum, Math.min(value, maximum));
    }
}
