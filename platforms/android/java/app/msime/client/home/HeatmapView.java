package app.msime.client.home;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import android.util.AttributeSet;
import android.view.View;
import androidx.core.content.ContextCompat;
import app.msime.client.R;

/** One cell per day, one column per week, matching the Apple app's calendar. */
public final class HeatmapView extends View {
    private static final int ROWS = 7;

    private final Paint cell = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final RectF box = new RectF();
    private int[] daily = new int[0];

    public HeatmapView(Context context, AttributeSet attributes) { super(context, attributes); }

    public void setDaily(int[] daily) {
        this.daily = daily == null ? new int[0] : daily;
        invalidate();
    }

    private float dp(float value) { return value * getResources().getDisplayMetrics().density; }

    @Override protected void onDraw(Canvas canvas) {
        float gap = dp(3f);
        float size = (getHeight() - gap * (ROWS - 1)) / ROWS;
        int columns = Math.max(1, (int) ((getWidth() + gap) / (size + gap)));
        int peak = 0;
        for (int value : daily) peak = Math.max(peak, value);
        int forest = ContextCompat.getColor(getContext(), R.color.forest);
        int empty = ContextCompat.getColor(getContext(), R.color.hairline);

        for (int index = 0; index < columns * ROWS; index++) {
            int column = index / ROWS;
            int row = index % ROWS;
            float x = column * (size + gap);
            float y = row * (size + gap);
            int offset = daily.length - columns * ROWS + index;
            int value = offset >= 0 && offset < daily.length ? daily[offset] : 0;
            // The lightest step still has to be visible, or a quiet day reads as no day at all.
            float weight = peak == 0 || value == 0 ? 0f : Math.max(0.2f, value / (float) peak);
            cell.setColor(weight == 0f ? empty
                : Color.argb(Math.round(255 * weight), Color.red(forest), Color.green(forest), Color.blue(forest)));
            box.set(x, y, x + size, y + size);
            canvas.drawRoundRect(box, dp(2f), dp(2f), cell);
        }
    }
}
