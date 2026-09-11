import app.msime.client.KeyboardLayout;
import java.util.List;

public final class KeyboardLayoutSmoke {
    static void check(boolean condition) { if (!condition) throw new AssertionError(); }

    public static void main(String[] args) {
        List<List<String>> letters = KeyboardLayout.rows(KeyboardLayout.Layer.LETTERS, false);
        check(letters.size() == 3);
        check(letters.get(0).equals(List.of("q", "w", "e", "r", "t", "y", "u", "i", "o", "p")));
        check(letters.get(2).equals(List.of("z", "x", "c", "v", "b", "n", "m")));

        List<List<String>> shifted = KeyboardLayout.rows(KeyboardLayout.Layer.LETTERS, true);
        check(shifted.get(0).get(0).equals("Q"));
        check(shifted.get(1).get(8).equals("L"));

        List<List<String>> symbols = KeyboardLayout.rows(KeyboardLayout.Layer.SYMBOLS, false);
        check(symbols.size() == 3);
        check(symbols.get(0).equals(List.of("1", "2", "3", "4", "5", "6", "7", "8", "9", "0")));
        check(symbols.get(1).contains("\""));
        check(symbols.get(2).equals(List.of("(", ")", "[", "]", "<", ">", "\\", "-", "_", "=")));
        check(KeyboardLayout.rows(KeyboardLayout.Layer.SYMBOLS, true).equals(symbols));

        System.out.println("Android keyboard layers: letter, shift and symbol layouts passed");
    }
}
