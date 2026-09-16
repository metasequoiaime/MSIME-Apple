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
        check(CandidateTranslationPolicy.glossLines(List.of("en"), true, false) == 1,
            "offline English keeps its row when online translation is off");
        check(CandidateTranslationPolicy.glossLines(List.of("ja"), true, false) == 0,
            "non-English has no row without online translation");
        check(CandidateTranslationPolicy.glossLines(List.of("en", "ja"), true, false) == 1,
            "only offline-capable targets reserve rows");
        check(CandidateTranslationPolicy.glossLines(List.of("en", "ja"), false, true) == 2,
            "online translation reserves every target row");
        System.out.println("Android candidate translation language policy passed");
    }

    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
}
