package app.msime.client;

import java.nio.charset.StandardCharsets;

/** Privacy and size bounds for text-only clipboard history entries. */
public final class ClipboardHistoryPolicy {
    public static final int LIMIT = 50;
    public static final int MAX_CHARS = 10_000;
    public static final int MAX_BYTES = 40_000;

    private ClipboardHistoryPolicy() {}

    public static boolean acceptable(String text) {
        return text != null && !text.trim().isEmpty()
            && text.length() <= MAX_CHARS
            && text.getBytes(StandardCharsets.UTF_8).length <= MAX_BYTES;
    }
}
