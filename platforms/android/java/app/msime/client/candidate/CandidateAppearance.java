package app.msime.client;

/** Validated candidate presentation values consumed by the Android host. */
public final class CandidateAppearance {
    private CandidateAppearance() {}

    public static boolean isHorizontal(String layout) {
        return "horizontal".equals(layout);
    }

    public static int fontSize(int value) {
        return value >= 12 && value <= 32 ? value : 16;
    }
}
