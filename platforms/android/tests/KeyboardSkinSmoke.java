import app.msime.client.KeyboardSkin;

public final class KeyboardSkinSmoke {
    static void check(boolean condition) { if (!condition) throw new AssertionError(); }

    public static void main(String[] args) {
        KeyboardSkin fluent = KeyboardSkin.from("fluent");
        check(fluent.id().equals("fluent"));
        check(fluent.keyBackground().equals("#FFFFFF"));
        check(fluent.cornerRadius() == 8);
        check(!fluent.monospaced());

        KeyboardSkin wechat = KeyboardSkin.from("wechat");
        check(wechat.accent().equals("#32B76A"));
        check(wechat.actionBackground().equals("#D7F5E2"));

        KeyboardSkin graphite = KeyboardSkin.from("graphite");
        check(graphite.keyForeground().equals("#F1F1F1"));
        check(graphite.cornerRadius() == 3);
        check(graphite.monospaced());

        KeyboardSkin willow = KeyboardSkin.from("willow_green");
        check(willow.cornerRadius() == 18);
        check(!willow.id().equals(fluent.id()));

        KeyboardSkin fallback = KeyboardSkin.from("untrusted-value");
        check(fallback.id().equals("fluent"));
        System.out.println("Android keyboard skins: shared IDs, palette, geometry and fallback passed");
    }
}
