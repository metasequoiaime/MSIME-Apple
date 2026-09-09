package app.msime.client;

import android.text.InputType;
import android.view.inputmethod.EditorInfo;

public final class EditorPolicy {
    private EditorPolicy() {}
    public static boolean useEngine(int type) {
        if ((type & InputType.TYPE_MASK_CLASS) != InputType.TYPE_CLASS_TEXT) return false;
        int variation = type & InputType.TYPE_MASK_VARIATION;
        return variation != InputType.TYPE_TEXT_VARIATION_PASSWORD
            && variation != InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD
            && variation != InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD
            && (type & InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS) == 0;
    }
    public static boolean allowLearning(int options) {
        return (options & EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING) == 0;
    }
}
