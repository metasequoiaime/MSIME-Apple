package app.msime.client;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/** Display-only double-pinyin key hints derived from the Engine profile tables. */
public final class ShuangpinKeyHintPolicy {
    private static final String[] LETTER_KEYS = {
        "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P",
        "A", "S", "D", "F", "G", "H", "J", "K", "L", "Z",
        "X", "C", "V", "B", "N", "M", ";"
    };
    private static final Map<String, Map<String, String>> PROFILES = profiles();

    private ShuangpinKeyHintPolicy() { }

    public static boolean visible(boolean dedicatedEnglish, int scheme, String localMode) {
        return !dedicatedEnglish && scheme == 1 && "none".equals(localMode);
    }

    public static String hint(String profile, String key, boolean dedicatedEnglish,
            int scheme, String localMode) {
        if (!visible(dedicatedEnglish, scheme, localMode) || key == null) return "";
        Map<String, String> hints = PROFILES.get(profile);
        if (hints == null) return "";
        return hints.getOrDefault(key.toUpperCase(Locale.ROOT), "");
    }

    private static Map<String, Map<String, String>> profiles() {
        Map<String, Map<String, String>> profiles = new HashMap<>();
        profiles.put("xiaohe", profile(
            new String[] {"sh=u", "ch=i", "zh=v"},
            new String[] {"iu=q", "ei=w", "e=e", "uan=r", "ue=t", "ve=t", "un=y",
                "u=u", "i=i", "uo=o", "o=o", "ie=p", "a=a", "ong=s", "iong=s",
                "ai=d", "en=f", "eng=g", "ang=h", "an=j", "uai=k", "ing=k", "uang=l", "iang=l",
                "ou=z", "ua=x", "ia=x", "ao=c", "ui=v", "v=v", "in=b", "iao=n", "ian=m"}));
        profiles.put("ziranma", profile(
            new String[] {"sh=u", "ch=i", "zh=v"},
            new String[] {"iu=q", "ia=w", "ua=w", "e=e", "uan=r", "ue=t", "ve=t", "ing=y",
                "uai=y", "u=u", "i=i", "o=o", "uo=o", "un=p", "a=a", "iong=s", "ong=s",
                "iang=d", "uang=d", "en=f", "eng=g", "ang=h", "an=j", "ao=k", "ai=l",
                "ei=z", "ie=x", "iao=c", "ui=v", "v=v", "ou=b", "in=n", "ian=m"}));
        profiles.put("shoudao", profile(
            new String[] {"sh=e", "ch=i", "zh=v"},
            new String[] {"iu=q", "ua=w", "e=e", "ie=r", "uan=t", "ang=y", "u=u", "i=i",
                "o=o", "uo=o", "iao=p", "a=a", "ou=s", "ao=d", "eng=f", "uai=g", "ing=g",
                "ong=h", "iong=h", "an=j", "en=k", "ia=k", "ai=l", "ue=l", "un=z",
                "iang=x", "uang=x", "in=c", "v=v", "ui=v", "ve=b", "ian=n", "ei=m"}));
        profiles.put("microsoft", profile(
            new String[] {"sh=u", "ch=i", "zh=v"},
            new String[] {"iu=q", "ia=w", "ua=w", "e=e", "uan=r", "ue=t", "ve=v", "uai=y",
                "v=y", "u=u", "i=i", "o=o", "uo=o", "un=p", "a=a", "iong=s", "ong=s",
                "iang=d", "uang=d", "en=f", "eng=g", "ang=h", "an=j", "ao=k", "ai=l",
                "ing=;", "ei=z", "ie=x", "iao=c", "ui=v", "ou=b", "in=n", "ian=m"}));
        return Map.copyOf(profiles);
    }

    private static Map<String, String> profile(String[] initials, String[] finals) {
        Map<String, List<String>> initialsByKey = new HashMap<>();
        Map<String, List<String>> finalsByKey = new HashMap<>();
        addUnits(initialsByKey, initials);
        addUnits(finalsByKey, finals);
        Map<String, String> hints = new HashMap<>();
        for (String key : LETTER_KEYS) {
            String initial = join(initialsByKey.get(key));
            String ending = join(finalsByKey.get(key));
            if (initial.isEmpty() && ending.isEmpty()) continue;
            hints.put(key, initial.isEmpty() ? ending
                : ending.isEmpty() ? initial : initial + " / " + ending);
        }
        return Map.copyOf(hints);
    }

    private static void addUnits(Map<String, List<String>> byKey, String[] entries) {
        for (String entry : entries) {
            int separator = entry.indexOf('=');
            String unit = displayUnit(entry.substring(0, separator));
            String key = entry.substring(separator + 1).toUpperCase(Locale.ROOT);
            byKey.computeIfAbsent(key, ignored -> new ArrayList<>()).add(unit);
        }
    }

    private static String displayUnit(String unit) {
        return unit.startsWith("v") ? "ü" + unit.substring(1) : unit;
    }

    private static String join(List<String> units) {
        if (units == null || units.isEmpty()) return "";
        units.sort(String::compareTo);
        return String.join(" ", units);
    }
}
