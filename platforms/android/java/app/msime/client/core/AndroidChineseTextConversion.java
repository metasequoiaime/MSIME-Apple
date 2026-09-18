package app.msime.client;

import android.annotation.TargetApi;
import android.icu.text.Transliterator;
import android.os.Build;

/**
 * Android platform conversion matching Apple's Simplified-Traditional host boundary.
 * Android exposes Transliterator from API 29; older systems safely preserve Engine text.
 */
public final class AndroidChineseTextConversion {
    private AndroidChineseTextConversion() {}

    public static boolean available() {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q;
    }

    public static String outputString(String text, boolean traditional, boolean dedicatedEnglish,
                                      int scheme, String localMode) {
        boolean applies = ChineseOutputPolicy.applies(dedicatedEnglish, scheme, localMode);
        if (!available()) return text;
        return ChineseOutputPolicy.output(text, traditional, applies, Api29::convert);
    }

    @TargetApi(Build.VERSION_CODES.Q)
    private static final class Api29 {
        private static final Transliterator SIMPLIFIED_TO_TRADITIONAL =
            Transliterator.getInstance("Simplified-Traditional");

        private static String convert(String text) {
            return SIMPLIFIED_TO_TRADITIONAL.transliterate(text);
        }
    }
}
