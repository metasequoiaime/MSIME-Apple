import app.msime.client.NineKeyLayout;
import java.util.List;

public final class NineKeyLayoutSmoke {
    static void check(boolean condition) { if (!condition) throw new AssertionError(); }

    public static void main(String[] args) {
        check(NineKeyLayout.rows().size() == 3);
        check(NineKeyLayout.rows().stream().allMatch(row -> row.size() == 3));
        check(NineKeyLayout.rows().stream().flatMap(List::stream)
            .map(NineKeyLayout.Key::label).toList().equals(
                List.of("分词", "ABC", "DEF", "GHI", "JKL", "MNO", "PQRS", "TUV", "WXYZ")));
        check(NineKeyLayout.rows().stream().flatMap(List::stream)
            .map(NineKeyLayout.Key::input).toList().equals(
                List.of('\'', '2', '3', '4', '5', '6', '7', '8', '9')));
        check(NineKeyLayout.punctuation().equals(List.of("，", "。", "？", "！")));
        try {
            NineKeyLayout.rows().get(0).add(new NineKeyLayout.Key("bad", '0', "bad"));
            throw new AssertionError();
        } catch (UnsupportedOperationException expected) { }
        System.out.println("Android nine-key layout: grid inputs, labels and punctuation passed");
    }
}
