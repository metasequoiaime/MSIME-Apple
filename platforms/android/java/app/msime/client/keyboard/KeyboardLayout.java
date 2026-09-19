package app.msime.client;

import java.util.List;

/** The two keyboard layers shared by the Android view and its host-side tests. */
public final class KeyboardLayout {
    public enum Layer { LETTERS, SYMBOLS }

    public static final int STANDARD_TOUCH_LAYOUT = 0;
    public static final int QUANPIN_NINE_KEY_LAYOUT = 1;
    public static final int JAPANESE_NINE_KEY_LAYOUT = 2;
    public static final int HANDWRITING_LAYOUT = 3;

    private static final List<List<String>> LETTER_ROWS = List.of(
        List.of("q", "w", "e", "r", "t", "y", "u", "i", "o", "p"),
        List.of("a", "s", "d", "f", "g", "h", "j", "k", "l"),
        List.of("z", "x", "c", "v", "b", "n", "m")
    );
    private static final List<List<String>> SYMBOL_ROWS = List.of(
        List.of("1", "2", "3", "4", "5", "6", "7", "8", "9", "0"),
        List.of(",", ".", "?", "!", ";", ":", "'", "\"", "@", "/"),
        List.of("(", ")", "[", "]", "<", ">", "\\", "-", "_", "=")
    );

    private KeyboardLayout() {}

    /** Resolves the host surface from the Engine view without conflating Japanese nine-key. */
    public static int resolveTouchLayout(boolean handwriting, boolean nineKey, int scheme,
                                         String touchLayout) {
        if (handwriting || "handwriting".equals(touchLayout)) return HANDWRITING_LAYOUT;
        if (scheme == 3 && "nine_key".equals(touchLayout)) return JAPANESE_NINE_KEY_LAYOUT;
        if (nineKey) return QUANPIN_NINE_KEY_LAYOUT;
        return STANDARD_TOUCH_LAYOUT;
    }

    public static List<List<String>> rows(Layer layer, boolean shifted) {
        List<List<String>> source = layer == Layer.SYMBOLS ? SYMBOL_ROWS : LETTER_ROWS;
        if (!shifted || layer == Layer.SYMBOLS) return source;
        return source.stream().map(row -> row.stream()
            .map(key -> key.toUpperCase(java.util.Locale.ROOT))
            .toList()).toList();
    }
}
