package app.msime.client.keyboard;

/** Pure text boundaries for direct English completion in the Android host. */
public final class EnglishSuggestionPolicy {
    private EnglishSuggestionPolicy() {}

    public static String currentWord(CharSequence beforeCursor) {
        if (beforeCursor == null || beforeCursor.length() == 0) return "";
        StringBuilder result = new StringBuilder();
        for (int offset = beforeCursor.length(); offset > 0;) {
            int codePoint = Character.codePointBefore(beforeCursor, offset);
            if (!Character.isLetter(codePoint)) break;
            result.appendCodePoint(codePoint);
            offset -= Character.charCount(codePoint);
        }
        return result.reverse().toString();
    }

    public static Replacement replacement(String typed, String candidate, boolean startedCapitalized) {
        if (typed == null || candidate == null || candidate.isEmpty()) return null;
        String word = candidate;
        if (startedCapitalized) {
            int first = word.codePointAt(0);
            word = new StringBuilder().appendCodePoint(Character.toUpperCase(first))
                .append(word.substring(Character.charCount(first))).toString();
        }
        return word.equals(typed) ? null : new Replacement(typed.length(), word);
    }

    public record Replacement(int deleteCount, String insert) {}
}
