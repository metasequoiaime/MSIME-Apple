package app.msime.client;

import android.provider.Settings;
import android.view.animation.DecelerateInterpolator;
import android.view.animation.OvershootInterpolator;
import android.widget.Button;

/** Matches Apple's key press feedback without changing the button's layout or input timing. */
public class KeyboardPressButton extends Button {
    private static final float PRESSED_SCALE = 0.94f;
    private static final float PRESSED_TRANSLATION_DP = 1f;
    private static final long PRESS_DURATION_MILLIS = 60L;
    private static final long RELEASE_DURATION_MILLIS = 180L;

    private KeyboardKeyRole role;

    public KeyboardPressButton(android.content.Context context) {
        super(context);
    }

    /**
     * The face the shared style pass should give this button.
     *
     * <p>It is carried on the view rather than decided at style time because that pass re-walks the
     * whole tree on every render and has no other way to tell a toolbar glyph from a key cap. Left
     * unset, the button keeps following the accessibility description the pass has always read, so
     * only the controls that asked for a role change appearance.
     */
    public void setKeyboardRole(KeyboardKeyRole value) { role = value; }

    /** The requested role, or {@code null} to follow the shared derivation. */
    public KeyboardKeyRole keyboardRole() { return role; }

    @Override public void setPressed(boolean pressed) {
        boolean changed = pressed != isPressed();
        super.setPressed(pressed);
        if (changed) updatePressFeedback();
    }

    @Override public void setEnabled(boolean enabled) {
        super.setEnabled(enabled);
        if (!enabled) updatePressFeedback();
    }

    @Override protected void onDetachedFromWindow() {
        animate().cancel();
        resetPressFeedback();
        super.onDetachedFromWindow();
    }

    private void updatePressFeedback() {
        animate().cancel();
        if (!isAttachedToWindow() || !isEnabled() || !animationsEnabled()) {
            resetPressFeedback();
            return;
        }
        if (isPressed()) {
            animate().translationY(dp(PRESSED_TRANSLATION_DP))
                .scaleX(PRESSED_SCALE).scaleY(PRESSED_SCALE)
                .setDuration(PRESS_DURATION_MILLIS)
                .setInterpolator(new DecelerateInterpolator()).start();
        } else {
            animate().translationY(0f).scaleX(1f).scaleY(1f)
                .setDuration(RELEASE_DURATION_MILLIS)
                .setInterpolator(new OvershootInterpolator(1.1f)).start();
        }
    }

    private boolean animationsEnabled() {
        try {
            float animatorScale = Settings.Global.getFloat(getContext().getContentResolver(),
                Settings.Global.ANIMATOR_DURATION_SCALE, 1f);
            float transitionScale = Settings.Global.getFloat(getContext().getContentResolver(),
                Settings.Global.TRANSITION_ANIMATION_SCALE, 1f);
            return animatorScale > 0f && transitionScale > 0f;
        } catch (RuntimeException error) {
            return true;
        }
    }

    private void resetPressFeedback() {
        setTranslationY(0f);
        setScaleX(1f);
        setScaleY(1f);
    }

    private float dp(float value) {
        return value * getResources().getDisplayMetrics().density;
    }
}
