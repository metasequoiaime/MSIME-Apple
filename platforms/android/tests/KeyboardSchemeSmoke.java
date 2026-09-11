import app.msime.client.KeyboardScheme;
import java.util.Arrays;
import java.util.List;

public final class KeyboardSchemeSmoke {
    static void check(boolean condition) { if (!condition) throw new AssertionError(); }

    static void mapping(KeyboardScheme scheme, String currentLast, String currentProfile,
                        String expectedScheme, String expectedLast, String expectedProfile) {
        KeyboardScheme.PreferenceMapping value = scheme.mapping(currentLast, currentProfile);
        check(value.scheme().equals(expectedScheme));
        check(value.lastChineseScheme().equals(expectedLast));
        check(value.shuangpinProfile().equals(expectedProfile));
        check(value.touchKeyboardLayout().equals(
            scheme == KeyboardScheme.QUANPIN_NINE_KEY || scheme == KeyboardScheme.JAPANESE_NINE_KEY
                ? "nine_key" : "twenty_six_key"));
    }

    public static void main(String[] args) {
        check(Arrays.stream(KeyboardScheme.values()).map(KeyboardScheme::title).toList().equals(List.of(
            "全拼 26 键", "全拼 9 键", "小鹤双拼", "自然码双拼", "微软双拼", "首道双拼", "86 五笔", "日语 26 键", "日语 9 键")));
        check(Arrays.stream(KeyboardScheme.values()).map(value -> value.glyph() + value.badge()).toList().equals(
            List.of("拼26", "拼9", "鹤双", "自双", "微双", "S双", "五86", "あ26", "あ9")));
        check(KeyboardScheme.fromPreferences("quanpin", "xiaohe", "nine_key") == KeyboardScheme.QUANPIN_NINE_KEY);
        check(KeyboardScheme.fromPreferences("japanese", "xiaohe", "nine_key") == KeyboardScheme.JAPANESE_NINE_KEY);
        check(KeyboardScheme.fromPreferences("shuangpin", "microsoft", "nine_key") == KeyboardScheme.MICROSOFT);
        check(KeyboardScheme.fromPreferences("shuangpin", "unknown", "twenty_six_key") == KeyboardScheme.XIAOHE);
        check(KeyboardScheme.fromPreferences("future", "xiaohe", "nine_key") == KeyboardScheme.QUANPIN);
        mapping(KeyboardScheme.QUANPIN, "wubi", "microsoft", "quanpin", "quanpin", "microsoft");
        mapping(KeyboardScheme.QUANPIN_NINE_KEY, "wubi", "microsoft", "quanpin", "quanpin", "microsoft");
        mapping(KeyboardScheme.XIAOHE, "quanpin", "shoudao", "shuangpin", "shuangpin", "xiaohe");
        mapping(KeyboardScheme.ZIRANMA, "quanpin", "xiaohe", "shuangpin", "shuangpin", "ziranma");
        mapping(KeyboardScheme.WUBI, "shuangpin", "ziranma", "wubi", "wubi", "ziranma");
        mapping(KeyboardScheme.JAPANESE, "wubi", "shoudao", "japanese", "wubi", "shoudao");
        mapping(KeyboardScheme.JAPANESE_NINE_KEY, "wubi", "shoudao", "japanese", "wubi", "shoudao");
        mapping(KeyboardScheme.JAPANESE, "invalid", "invalid", "japanese", "quanpin", "xiaohe");
        System.out.println("Android keyboard schemes: nine labels, glyphs and shared preference mappings passed");
    }
}
