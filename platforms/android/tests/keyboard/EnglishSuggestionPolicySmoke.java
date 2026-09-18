import app.msime.client.keyboard.EnglishSuggestionPolicy;

public final class EnglishSuggestionPolicySmoke {
    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    public static void main(String[] args) {
        check(EnglishSuggestionPolicy.currentWord("我用iph").equals("iph"), "suffix word");
        check(EnglishSuggestionPolicy.currentWord("hello wor").equals("wor"), "word boundary");
        check(EnglishSuggestionPolicy.currentWord("done. ").isEmpty(), "punctuation boundary");
        check(EnglishSuggestionPolicy.currentWord("don't").equals("t"), "apostrophe boundary");
        var replacement = EnglishSuggestionPolicy.replacement("iph", "iphone", false);
        check(replacement != null && replacement.deleteCount() == 3
            && replacement.insert().equals("iphone"), "replacement span");
        var capitalized = EnglishSuggestionPolicy.replacement("Hel", "hello", true);
        check(capitalized != null && capitalized.insert().equals("Hello"), "capitalized replacement");
        check(EnglishSuggestionPolicy.replacement("hello", "hello", false) == null,
            "identical replacement is omitted");
        System.out.println("Android English suggestion policy: boundaries and replacement passed");
    }
}
