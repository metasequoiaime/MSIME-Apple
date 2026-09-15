import app.msime.client.CandidateTranslationPolicy;
import java.util.List;

public final class CandidateTranslationPolicySmoke {
    public static void main(String[] args) {
        check(CandidateTranslationPolicy.targets("ja", "de").equals(List.of("ja", "de")),
            "primary and secondary languages preserved");
        check(CandidateTranslationPolicy.targets("invalid", "ja").equals(List.of("en", "ja")),
            "invalid primary falls back to English");
        check(CandidateTranslationPolicy.targets("en", "en").equals(List.of("en")),
            "duplicate secondary is not requested twice");
        check(CandidateTranslationPolicy.targets("en", null).equals(List.of("en")),
            "missing secondary preserves legacy behavior");
        check(CandidateTranslationPolicy.joinGlosses(List.of("hello", "こんにちは"))
                .equals("hello\nこんにちは"), "two glosses stay on separate rows");
        System.out.println("Android candidate translation language policy passed");
    }

    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
}
