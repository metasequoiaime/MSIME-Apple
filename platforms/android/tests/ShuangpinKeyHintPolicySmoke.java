import app.msime.client.ShuangpinKeyHintPolicy;

public final class ShuangpinKeyHintPolicySmoke {
    private static void check(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    public static void main(String[] args) {
        check(ShuangpinKeyHintPolicy.hint("xiaohe", "U", false, 1, "none").equals("sh / u"),
            "Xiaohe initial and final hint");
        check(ShuangpinKeyHintPolicy.hint("ziranma", "W", false, 1, "none").equals("ia ua"),
            "Ziranma dual-final hint");
        check(ShuangpinKeyHintPolicy.hint("shoudao", "E", false, 1, "none").equals("sh / e"),
            "Shoudao initial and final hint");
        check(ShuangpinKeyHintPolicy.hint("xiaohe", "K", false, 1, "none")
                .equals("ing uai"), "Xiaohe dual-final hint");
        check(ShuangpinKeyHintPolicy.hint("microsoft", ";", false, 1, "none").equals("ing"),
            "Microsoft semicolon hint");
        check(ShuangpinKeyHintPolicy.hint("microsoft", "V", false, 1, "none")
                .equals("zh / ui üe"), "Microsoft umlaut hint");
        check(ShuangpinKeyHintPolicy.hint("xiaohe", "U", false, 0, "none").isEmpty(),
            "Full pinyin hides hints");
        check(ShuangpinKeyHintPolicy.hint("xiaohe", "U", true, 1, "none").isEmpty(),
            "English mode hides hints");
        check(ShuangpinKeyHintPolicy.hint("xiaohe", "U", false, 1, "emoji").isEmpty(),
            "Local mode hides hints");
        check(ShuangpinKeyHintPolicy.hint("unknown", "U", false, 1, "none").isEmpty(),
            "Unknown profile hides hints");
        System.out.println("Android double-pinyin key hints passed");
    }
}
