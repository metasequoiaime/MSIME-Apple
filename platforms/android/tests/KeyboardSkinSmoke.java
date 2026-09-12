import app.msime.client.KeyboardSkin;
import java.util.List;

public final class KeyboardSkinSmoke {
    static void check(boolean condition) { if (!condition) throw new AssertionError(); }

    public static void main(String[] args) {
        KeyboardSkin fluent = KeyboardSkin.from("fluent");
        check(fluent.id().equals("fluent"));
        check(fluent.title().equals("流光白"));
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
        List<KeyboardSkin> choices = KeyboardSkin.builtIns();
        check(choices.stream().map(KeyboardSkin::id).toList().equals(
            List.of("fluent", "wechat", "graphite", "willow_green")));
        check(choices.stream().map(KeyboardSkin::title).toList().equals(
            List.of("流光白", "微信绿", "石墨黑", "柳绿")));
        System.out.println("Android keyboard skins: shared IDs, menu order, palette, geometry and fallback passed");
    }
}
