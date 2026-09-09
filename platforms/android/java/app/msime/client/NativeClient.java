package app.msime.client;

import java.nio.charset.StandardCharsets;

/** JNI transport for an Android IME host. Session operations use the creating thread.
 * JSON response ownership is handled inside JNI. The host parses the envelope,
 * maps handled/commit/view to InputConnection and UI, and destroys its session.
 */
public final class NativeClient {
    static { System.loadLibrary("msime_android"); }
    private NativeClient() {}
    private static String text(byte[] value) { return new String(value, StandardCharsets.UTF_8); }
    public static String create(String options) { return text(createRaw(options.getBytes(StandardCharsets.UTF_8))); }
    public static String focus(long session, boolean focused) { return text(focusRaw(session, focused)); }
    public static String character(long session, int ascii, boolean shift) {
        if (ascii < 0 || ascii > 127) throw new IllegalArgumentException("Engine character must be ASCII");
        return text(characterRaw(session, ascii, shift));
    }
    public static String command(long session, int command) { return text(commandRaw(session, command)); }
    public static String select(long session, long generation, long index) { return text(selectRaw(session, generation, index)); }
    public static String view(long session) { return text(viewRaw(session)); }
    public static String destroy(long session) { return text(destroyRaw(session)); }
    private static native byte[] createRaw(byte[] options);
    private static native byte[] focusRaw(long session, boolean focused);
    private static native byte[] characterRaw(long session, int ascii, boolean shift);
    private static native byte[] commandRaw(long session, int command);
    private static native byte[] selectRaw(long session, long generation, long index);
    private static native byte[] viewRaw(long session);
    private static native byte[] destroyRaw(long session);
}
