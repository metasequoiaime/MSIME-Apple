package app.msime.client;

import java.util.Arrays;
import java.util.List;

public final class KeyboardSkinSmoke {
    static void check(boolean condition) { if (!condition) throw new AssertionError(); }

    public static void main(String[] args) {
        List<KeyboardSkin> light = KeyboardSkin.builtIns(false);
        check(light.stream().map(KeyboardSkin::id).toList().equals(Arrays.asList(
            "forest", "ocean", "rose", "porcelain", "typewriter", "candy",
            "midnight", "blueprint")));
        check(light.stream().map(KeyboardSkin::title).toList().equals(Arrays.asList(
            "水杉绿", "海盐蓝", "浅蔷薇", "素白瓷", "纸上时光", "奶油桃桃",
            "霓虹夜航", "工程蓝图")));

        KeyboardSkin forest = light.get(0);
        check("#E8F0EB".equals(forest.background()));
        check("#FFFFFF".equals(forest.keyBackground()));
        check("#000000".equals(forest.keyForeground()));
        check("#185C47".equals(forest.accent()));
        check(forest.cornerRadius() == 8 && forest.borderWidth() == 0);
        check("forest:false".equals(forest.key()));

        KeyboardSkin darkForest = KeyboardSkin.from("forest", true);
        check("#17211C".equals(darkForest.background()));
        check("#303D36".equals(darkForest.keyBackground()));
        check("#73CCA6".equals(darkForest.accent()));
        check("forest:true".equals(darkForest.key()));

        KeyboardSkin porcelain = KeyboardSkin.from("porcelain", false);
        check(porcelain.cornerRadius() == 3 && porcelain.borderWidth() == 0.5);
        check("#47333D47".equals(porcelain.borderColor()));

        KeyboardSkin typewriter = KeyboardSkin.from("typewriter", false);
        check(typewriter.pattern() == 1 && typewriter.monospaced());
        check(typewriter.borderWidth() == 1 && typewriter.shadowOpacity() == 0.30);
        check(typewriter.shadowRadius() == 0 && typewriter.shadowOffset() == 3);

        KeyboardSkin candy = KeyboardSkin.from("candy", true);
        check("#4D333D".equals(candy.keyBackground()));
        check(candy.pattern() == 3 && candy.cornerRadius() == 18);
        check(candy.shadowOpacity() == 0.16);

        KeyboardSkin midnight = KeyboardSkin.from("midnight", false);
        check("#130F24".equals(midnight.background()));
        check("#291F40".equals(midnight.keyBackground()));
        check("#A6C7B0FF".equals(midnight.borderColor()));
        check(midnight.pattern() == 1 && midnight.borderWidth() == 1);
        check(KeyboardSkin.from("midnight", true).background().equals(midnight.background()));

        KeyboardSkin blueprint = KeyboardSkin.from("blueprint", false);
        check("#0E2138".equals(blueprint.background()));
        check(blueprint.pattern() == 2 && blueprint.monospaced());

        KeyboardSkin fallback = KeyboardSkin.from("untrusted-value", true);
        check("forest".equals(fallback.id()) && fallback.dark());
        check(KeyboardSkin.resolveDark("dark", "light", false));
        check(!KeyboardSkin.resolveDark("light", "dark", true));
        check(KeyboardSkin.resolveDark("follow", "dark", false));
        check(!KeyboardSkin.resolveDark("follow", "light", true));
        check(KeyboardSkin.resolveDark("follow", "system", true));
        check(!KeyboardSkin.resolveDark("follow", "system", false));
        CustomKeyboardSkin design = CustomKeyboardSkin.fixture(0x151022, 0x291E40, 0xFFFFFF,
            0xD4BBFF, 0xFFFFFF, 17, 1.5, .25, 3, true, "pebble", "glass", .45,
            0x30224A, true, .2, 0xA987E8,
            new byte[] {(byte) 0xFF, (byte) 0xD8, (byte) 0xFF, 0}, .8, 1);
        KeyboardSkin custom = KeyboardSkin.customFixture(design, false);
        check("custom".equals(custom.id()) && "我的皮肤".equals(custom.title()));
        check("#151022".equals(custom.background()) && "#30224A".equals(custom.gradientEnd()));
        check(custom.gradientHorizontal() && custom.patternOpacity() == .2);
        check("pebble".equals(custom.keyShape()) && "glass".equals(custom.keyMaterial()));
        check(custom.keyOpacity() == .45 && custom.cornerRadius() == 17);
        check("#A987E8".equals(custom.borderColor()) && "#000000".equals(custom.actionForeground()));
        check(custom.photo().length == 4 && custom.photoShade() == .8 && custom.photoPosition() == 1);
        check(KeyboardSkin.choices(false, null).stream().map(KeyboardSkin::id).toList().equals(
            Arrays.asList("forest", "ocean", "rose", "porcelain", "typewriter", "candy",
                "midnight", "blueprint", "custom")));
        System.out.println("Android keyboard skins: Apple order, adaptive palettes, geometry, "
            + "patterns, custom materials, photos, theme resolution and fallback passed");
    }
}
