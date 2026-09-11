import app.msime.client.LocalInputMode;

public final class LocalInputModeSmoke {
    static void check(boolean condition) { if (!condition) throw new AssertionError(); }

    public static void main(String[] args) {
        check(LocalInputMode.values().length == 8);
        check(LocalInputMode.UNICODE.trigger().equals("U"));
        check(LocalInputMode.UNICODE.preferenceKey().equals("unicode"));
        check(LocalInputMode.DATE_TIME.trigger().equals("T"));
        check(LocalInputMode.QUICK_PHRASE.trigger().equals("K"));
        check(LocalInputMode.EMOJI.trigger().equals("E"));
        check(LocalInputMode.KAOMOJI.trigger().equals("M"));
        check(LocalInputMode.SUPER_JIANPIN.trigger().equals("J"));
        check(LocalInputMode.TEMPORARY_ENGLISH.trigger().equals("Y"));
        check(LocalInputMode.TEMPORARY_JAPANESE.trigger().equals("R"));
        System.out.println("Android local input modes: Apple triggers and preference keys passed");
    }
}
