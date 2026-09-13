import app.msime.client.JapaneseNineKeyLayout;
import java.util.List;

public final class JapaneseNineKeyLayoutSmoke {
    static void check(boolean condition) { if (!condition) throw new AssertionError(); }

    public static void main(String[] args) {
        List<JapaneseNineKeyLayout.Key> keys = JapaneseNineKeyLayout.keys();
        check(keys.size() == 10);
        check(keys.stream().map(key -> key.kana().get(0)).toList().equals(
            List.of("あ", "か", "さ", "た", "な", "は", "ま", "や", "ら", "わ")));
        check(keys.get(2).kana().equals(List.of("さ", "し", "す", "せ", "そ")));
        check(keys.get(2).strokes().equals(List.of("sa", "shi", "su", "se", "so")));
        check(keys.get(7).kana().equals(List.of("や", "（", "ゆ", "）", "よ")));
        check(keys.get(7).strokes().equals(List.of("ya", "", "yu", "", "yo")));
        check(keys.get(9).kana().equals(List.of("わ", "を", "ん", "ー", "〜")));
        check(keys.get(9).strokes().equals(List.of("wa", "wo", "n'", "-", "")));
        List<JapaneseNineKeyLayout.Key> digitKeys = JapaneseNineKeyLayout.digitKeys();
        check(digitKeys.size() == 10);
        check(digitKeys.stream().map(key -> key.kana().get(0)).toList().equals(
            List.of("1", "2", "3", "4", "5", "6", "7", "8", "9", "0")));
        check(digitKeys.get(0).kana().equals(List.of("1", "☆", "♪", "→", "")));
        check(digitKeys.get(9).kana().equals(List.of("0", "〜", "…", "ー", "")));
        check(digitKeys.stream().allMatch(key -> key.strokes().stream().allMatch(String::isEmpty)));
        check(JapaneseNineKeyLayout.digitBrackets().equals(
            List.of("（", "）", "「", "」", "『", "』", "【", "】")));
        check(JapaneseNineKeyLayout.variants().stream().map(
            JapaneseNineKeyLayout.VariantGroup::title).toList().equals(
                List.of("小假名", "浊音", "半浊音")));
        check(JapaneseNineKeyLayout.variants().stream().mapToInt(
            group -> group.kana().size()).sum() == 36);
        check(JapaneseNineKeyLayout.direction(0, 0, 12) == 0);
        check(JapaneseNineKeyLayout.direction(-13, 2, 12) == 1);
        check(JapaneseNineKeyLayout.direction(1, -13, 12) == 2);
        check(JapaneseNineKeyLayout.direction(13, 2, 12) == 3);
        check(JapaneseNineKeyLayout.direction(1, 13, 12) == 4);
        try {
            keys.get(0).kana().add("bad");
            throw new AssertionError();
        } catch (UnsupportedOperationException expected) { }
        System.out.println("Android Japanese nine-key: kana, strokes, variants and flick directions passed");
    }
}
