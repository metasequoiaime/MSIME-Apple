import app.msime.client.ChineseOutputPolicy;

public final class ChineseOutputPolicySmoke {
    static void check(boolean condition) { if (!condition) throw new AssertionError(); }

    public static void main(String[] args) {
        check(ChineseOutputPolicy.applies(false, 0, "none"));
        check(ChineseOutputPolicy.applies(false, 2, "unicode"));
        check(!ChineseOutputPolicy.applies(true, 0, "none"));
        check(!ChineseOutputPolicy.applies(false, 3, "none"));
        check(!ChineseOutputPolicy.applies(false, 0, "temporary_japanese"));

        ChineseOutputPolicy.Converter sample = text -> text.replace("输入", "輸入");
        check(ChineseOutputPolicy.output("水杉输入法", false, true, sample).equals("水杉输入法"));
        check(ChineseOutputPolicy.output("水杉输入法", true, false, sample).equals("水杉输入法"));
        check(ChineseOutputPolicy.output("水杉输入法", true, true, sample).equals("水杉輸入法"));
        check(ChineseOutputPolicy.output("", true, true, sample).isEmpty());
        check(ChineseOutputPolicy.output("输入法", true, true, text -> null).equals("输入法"));
        check(ChineseOutputPolicy.output("输入法", true, true, text -> {
            throw new IllegalArgumentException();
        }).equals("输入法"));
        System.out.println("Android Chinese output: boundaries and conversion failure fallback passed");
    }
}
