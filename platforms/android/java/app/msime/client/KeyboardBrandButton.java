package app.msime.client;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.widget.Button;
import java.util.function.IntSupplier;

/** Draws the tintable MSIME brand mark without baking a white square into the shortcut bar. */
public final class KeyboardBrandButton extends Button {
    private final IntSupplier accent;
    private final Paint mark = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Path path = new Path();

    public KeyboardBrandButton(Context context, IntSupplier accent) {
        super(context);
        this.accent = accent;
        path.moveTo(74.7234f, 14f);
        path.lineTo(35.1501f, 29.1727f);
        path.lineTo(74.7234f, 40.5522f);
        path.lineTo(35.1501f, 59.518f);
        path.cubicTo(72.562f, 65.84f, 107.728f, 71.024f, 33f, 95f);
        mark.setStyle(Paint.Style.STROKE);
        mark.setStrokeWidth(8f);
        mark.setStrokeCap(Paint.Cap.ROUND);
        mark.setStrokeJoin(Paint.Join.ROUND);
        setContentDescription("更多快捷设置");
    }

    @Override protected void onDraw(Canvas canvas) {
        // The text remains available to accessibility and device smoke tests, while the visible
        // shortcut is the same mark Apple turns into an accent-tinted template.
        int color;
        try {
            color = accent.getAsInt();
        } catch (RuntimeException error) {
            color = Color.WHITE;
        }
        mark.setColor(color);
        mark.setAlpha(isEnabled() ? 255 : 96);
        int width = Math.max(0, getWidth() - getPaddingLeft() - getPaddingRight());
        int height = Math.max(0, getHeight() - getPaddingTop() - getPaddingBottom());
        float size = Math.min(width, height);
        if (size <= 0) return;
        canvas.save();
        canvas.translate(getPaddingLeft() + (width - size) / 2f,
            getPaddingTop() + (height - size) / 2f);
        canvas.scale(size / 110f, size / 110f);
        canvas.drawPath(path, mark);
        canvas.restore();
    }
}
