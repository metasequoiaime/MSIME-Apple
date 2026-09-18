package app.msime.client;

import java.util.List;

/** Display labels and Engine inputs for the Apple-compatible quanpin nine-key grid. */
public final class NineKeyLayout {
    public record Key(String label, char input, String description) {}

    private static final List<List<Key>> ROWS = List.of(
        List.of(new Key("分词", '\'', "拼音分词"), new Key("ABC", '2', "2 ABC"),
            new Key("DEF", '3', "3 DEF")),
        List.of(new Key("GHI", '4', "4 GHI"), new Key("JKL", '5', "5 JKL"),
            new Key("MNO", '6', "6 MNO")),
        List.of(new Key("PQRS", '7', "7 PQRS"), new Key("TUV", '8', "8 TUV"),
            new Key("WXYZ", '9', "9 WXYZ")));
    private static final List<String> PUNCTUATION = List.of("，", "。", "？", "！");

    private NineKeyLayout() {}

    public static List<List<Key>> rows() { return ROWS; }
    public static List<String> punctuation() { return PUNCTUATION; }
}
