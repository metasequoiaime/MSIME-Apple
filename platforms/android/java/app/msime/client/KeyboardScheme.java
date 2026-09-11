package app.msime.client;

/** Shared-Engine keyboard schemes currently exposed by the Android host. */
public enum KeyboardScheme {
    QUANPIN("quanpin", null, "twenty_six_key", "全拼 26 键", "拼", "26"),
    QUANPIN_NINE_KEY("quanpin", null, "nine_key", "全拼 9 键", "拼", "9"),
    XIAOHE("shuangpin", "xiaohe", "twenty_six_key", "小鹤双拼", "鹤", "双"),
    ZIRANMA("shuangpin", "ziranma", "twenty_six_key", "自然码双拼", "自", "双"),
    MICROSOFT("shuangpin", "microsoft", "twenty_six_key", "微软双拼", "微", "双"),
    SHOUDAO("shuangpin", "shoudao", "twenty_six_key", "首道双拼", "S", "双"),
    WUBI("wubi", null, "twenty_six_key", "86 五笔", "五", "86"),
    JAPANESE("japanese", null, "twenty_six_key", "日语 26 键", "あ", "26");

    /** Complete preference values needed for one compare-and-swap update. */
    public record PreferenceMapping(
        String scheme, String lastChineseScheme, String shuangpinProfile,
        String touchKeyboardLayout) {}

    private final String engineScheme;
    private final String shuangpinProfile;
    private final String touchKeyboardLayout;
    private final String title;
    private final String glyph;
    private final String badge;

    KeyboardScheme(String engineScheme, String shuangpinProfile, String touchKeyboardLayout, String title,
                   String glyph, String badge) {
        this.engineScheme = engineScheme;
        this.shuangpinProfile = shuangpinProfile;
        this.touchKeyboardLayout = touchKeyboardLayout;
        this.title = title;
        this.glyph = glyph;
        this.badge = badge;
    }

    public String engineScheme() { return engineScheme; }
    public String shuangpinProfile() { return shuangpinProfile; }
    public String touchKeyboardLayout() { return touchKeyboardLayout; }
    public String title() { return title; }
    public String glyph() { return glyph; }
    public String badge() { return badge; }

    public static KeyboardScheme fromPreferences(String scheme, String profile, String touchLayout) {
        if ("quanpin".equals(scheme) && "nine_key".equals(touchLayout)) return QUANPIN_NINE_KEY;
        if ("shuangpin".equals(scheme)) {
            for (KeyboardScheme candidate : values()) {
                if (profile != null && profile.equals(candidate.shuangpinProfile)) return candidate;
            }
            return XIAOHE;
        }
        for (KeyboardScheme candidate : values()) {
            if (candidate.shuangpinProfile == null && candidate.engineScheme.equals(scheme)
                    && !"nine_key".equals(candidate.touchKeyboardLayout)) return candidate;
        }
        return QUANPIN;
    }

    public PreferenceMapping mapping(String currentLastChineseScheme, String currentProfile) {
        String profile = normalizedProfile(currentProfile);
        if (shuangpinProfile != null) profile = shuangpinProfile;
        String lastChinese = isChineseScheme(currentLastChineseScheme)
            ? currentLastChineseScheme : "quanpin";
        if (!"japanese".equals(engineScheme)) lastChinese = engineScheme;
        return new PreferenceMapping(engineScheme, lastChinese, profile, touchKeyboardLayout);
    }

    private static boolean isChineseScheme(String value) {
        return "quanpin".equals(value) || "shuangpin".equals(value) || "wubi".equals(value);
    }

    private static String normalizedProfile(String value) {
        if ("ziranma".equals(value) || "microsoft".equals(value) || "shoudao".equals(value)) {
            return value;
        }
        return "xiaohe";
    }
}
