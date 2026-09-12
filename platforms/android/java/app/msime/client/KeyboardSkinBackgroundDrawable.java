package app.msime.client;

import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.ColorFilter;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.PixelFormat;
import android.graphics.drawable.Drawable;

/** Draws Apple's built-in touch-keyboard backdrop patterns without external assets. */
public final class KeyboardSkinBackgroundDrawable extends Drawable {
    private final Paint background = new Paint();
    private final Paint pattern = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final float density;
    private final int patternId;
    private int alpha = 255;

    public KeyboardSkinBackgroundDrawable(KeyboardSkin skin, float density) {
        this.density = density;
        patternId = skin.pattern();
        background.setColor(Color.parseColor(skin.background()));
        int accent = Color.parseColor(skin.accent());
        pattern.setColor(Color.argb(38, Color.red(accent), Color.green(accent), Color.blue(accent)));
        pattern.setStyle(Paint.Style.FILL);
    }

    private float dp(double value) { return (float) value * density; }

    @Override public void draw(Canvas canvas) {
        canvas.drawRect(getBounds(), background);
        if (patternId == 0) return;
        float left = getBounds().left;
        float top = getBounds().top;
        float right = getBounds().right;
        float bottom = getBounds().bottom;
        if (patternId == 1) {
            float diameter = dp(1.5);
            for (float y = top + dp(8); y < bottom; y += dp(16)) {
                for (float x = left + dp(8); x < right; x += dp(16))
                    canvas.drawOval(x, y, x + diameter, y + diameter, pattern);
            }
            return;
        }
        pattern.setStyle(Paint.Style.STROKE);
        if (patternId == 2) {
            pattern.setStrokeWidth(dp(0.5));
            for (float x = left; x < right; x += dp(20))
                canvas.drawLine(x, top, x, bottom, pattern);
            for (float y = top; y < bottom; y += dp(20))
                canvas.drawLine(left, y, right, y, pattern);
            return;
        }
        pattern.setStrokeWidth(dp(2));
        float width = right - left;
        Path wave = new Path();
        for (float offset = top - dp(100); offset < bottom + width; offset += dp(24)) {
            wave.moveTo(left, offset);
            wave.cubicTo(left + width * 0.35f, offset - dp(90),
                left + width * 0.65f, offset + dp(20), right, offset - dp(70));
        }
        canvas.drawPath(wave, pattern);
    }

    @Override public void setAlpha(int value) {
        alpha = Math.max(0, Math.min(255, value));
        background.setAlpha(alpha);
        pattern.setAlpha(Math.round(38 * alpha / 255f));
        invalidateSelf();
    }

    @Override public int getAlpha() { return alpha; }

    @Override public void setColorFilter(ColorFilter filter) {
        background.setColorFilter(filter);
        pattern.setColorFilter(filter);
        invalidateSelf();
    }

    @Deprecated
    @Override public int getOpacity() { return alpha == 255 ? PixelFormat.OPAQUE : PixelFormat.TRANSLUCENT; }
}
