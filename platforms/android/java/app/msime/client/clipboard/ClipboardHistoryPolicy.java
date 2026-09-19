package app.msime.client;

import java.nio.charset.StandardCharsets;

/** Privacy and size bounds for text-only clipboard history entries. */
public final class ClipboardHistoryPolicy {
    public static final int LIMIT = 50;
    public static final int MAX_CHARS = 10_000;
    public static final int MAX_BYTES = 40_000;

    /**
     * Why one save was refused.
     *
     * <p>Apple names each of these to the user, because they ask for different things: shorten the
     * text, or unpin something. A single "could not save" leaves a full history looking broken.
     */
    public enum Rejection { EMPTY, TOO_LONG, FULL }

    private ClipboardHistoryPolicy() {}

    public static boolean acceptable(String text) {
        return rejection(text) == null;
    }

    /** The reason this text cannot be saved, or null when it can. */
    public static Rejection rejection(String text) {
        if (text == null || text.trim().isEmpty()) return Rejection.EMPTY;
        return text.length() > MAX_CHARS
            || text.getBytes(StandardCharsets.UTF_8).length > MAX_BYTES
            ? Rejection.TOO_LONG : null;
    }

    /** What to tell the user, naming the action that would let the save succeed. */
    public static String message(Rejection rejection) {
        if (rejection == null) throw new IllegalArgumentException("No clipboard rejection");
        return switch (rejection) {
            // Android has no paste permission prompt, so the Apple wording drops that clause.
            case EMPTY -> "剪贴板中没有可保存的文本";
            case TOO_LONG -> "单条最多保存 " + MAX_CHARS + " 字，请缩短后重试";
            case FULL -> LIMIT + " 条历史均已固定，请先取消固定或删除一条";
        };
    }
}
