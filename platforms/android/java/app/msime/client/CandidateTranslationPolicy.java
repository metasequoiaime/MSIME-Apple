package app.msime.client;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Set;

/** Validates and presents the one-or-two language candidate gloss configuration. */
public final class CandidateTranslationPolicy {
    private static final Set<String> SUPPORTED = Set.of("en", "fr", "ja", "es", "ru", "de", "ko");

    private CandidateTranslationPolicy() {}

    /** Primary always falls back to English; a malformed or duplicate secondary is ignored. */
    public static List<String> targets(String primary, String secondary) {
        ArrayList<String> result = new ArrayList<>(2);
        String first = normalize(primary);
        result.add(SUPPORTED.contains(first) ? first : "en");
        String second = normalize(secondary);
        if (SUPPORTED.contains(second) && !result.contains(second)) result.add(second);
        return List.copyOf(result);
    }

    /** Keep the two language rows readable in a single Android candidate annotation. */
    public static String joinGlosses(List<String> glosses) {
        if (glosses == null || glosses.isEmpty()) return "";
        return String.join("\n", glosses);
    }

    /** Count rows that can actually be filled by the enabled offline/online paths. */
    public static int glossLines(List<String> targets, boolean offlineEnglish, boolean online) {
        if (targets == null || targets.isEmpty()) return 0;
        int lines = 0;
        for (String target : targets) {
            if (online || (offlineEnglish && "en".equals(normalize(target)))) lines++;
        }
        return lines;
    }

    private static String normalize(String value) {
        return value == null ? "" : value.trim().toLowerCase(Locale.ROOT);
    }
}
