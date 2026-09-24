package app.msime.client;

import java.nio.charset.StandardCharsets;
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

    /** Return the bounded, user-visible gloss rows that a long press may insert. */
    public static List<String> insertionGlosses(String translation) {
        if (translation == null || translation.isEmpty()) return List.of();
        ArrayList<String> result = new ArrayList<>(2);
        for (String value : translation.split("\\R", -1)) {
            String gloss = value.trim();
            if (gloss.isEmpty() || result.contains(gloss)
                    || gloss.getBytes(StandardCharsets.UTF_8).length > 4096
                    || gloss.codePoints().anyMatch(Character::isISOControl)) continue;
            result.add(gloss);
            if (result.size() == 2) break;
        }
        return List.copyOf(result);
    }

    /**
     * Whether candidate words may be sent to the MSIME account endpoint (api.msime.app).
     *
     * <p>Only an explicit `translation_account` choice selects it, and a user's own NiuTrans or custom service always wins over it, so nothing is sent when the user never chose. This mirrors the `translation_account` rule in the shared core (`msime_client_translation_query` in `crates/host-api/src/ffi/providers.rs`) except for the Tencent clause: this host has no Tencent client and neither Android settings surface can enter Tencent credentials. The shared settings page also writes Tencent's `enabled` to false when the account is chosen; the native feature switch writes only `translation_account`. Plain booleans because the JVM smokes cannot load org.json.
     */
    public static boolean accountSelected(boolean candidateTranslations,
            boolean translationAccount, boolean niutransEnabled, boolean customEnabled) {
        return candidateTranslations && translationAccount && !niutransEnabled && !customEnabled;
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

    /** Number of rows needed by one rendered candidate label, based on actual annotation text. */
    public static int renderedGlossLines(String annotation) {
        return annotation != null && annotation.indexOf('\n') >= 0 ? 2 : 1;
    }

    private static String normalize(String value) {
        return value == null ? "" : value.trim().toLowerCase(Locale.ROOT);
    }
}
