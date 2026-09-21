package app.msime.client.home;

import android.annotation.SuppressLint;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import android.util.AttributeSet;
import android.view.MotionEvent;
import android.view.View;
import androidx.annotation.Nullable;
import androidx.core.content.ContextCompat;
import app.msime.client.R;
import java.util.List;
import java.util.function.Consumer;

/**
 * One cell per day, one column per week, matching the Apple app's calendar.
 *
 * A cell can be tapped to scope the page to that one day. That is the only way to read a single
 * day's mix of character kinds and schemes: the distributions below otherwise cover the whole
 * record, where one day's shape is lost in the total.
 */
public final class HeatmapView extends View {
    private static final int ROWS = 7;

    private final Paint cell = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint outline = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final RectF box = new RectF();
    private int[] daily = new int[0];
    private List<String> days = List.of();
    @Nullable private Consumer<String> onDayPicked;
    @Nullable private String selected;
    /**
     * Where the finger went down, so {@link #performClick} knows which cell was meant.
     *
     * <p>The tap is not resolved at touch time. Consuming the gesture would take it away from the
     * scrolling page this calendar sits in, and a drag that started on the calendar would fail to
     * scroll; leaving it to the clickable View's own handling keeps that distinction where the
     * framework already makes it correctly.
     */
    private float downX;
    private float downY;

    public HeatmapView(Context context, AttributeSet attributes) {
        super(context, attributes);
        outline.setStyle(Paint.Style.STROKE);
        outline.setStrokeWidth(dp(1.5f));
        outline.setColor(ContextCompat.getColor(context, R.color.ink));
    }

    public void setDaily(int[] daily) {
        this.daily = daily == null ? new int[0] : daily;
        invalidate();
    }

    /** The day key behind each cell, in the same order as {@link #setDaily}. */
    public void setDays(List<String> days) {
        this.days = days == null ? List.of() : days;
        invalidate();
    }

    /** Called with the tapped day, or with null when the tapped cell holds no record. */
    public void setOnDayPicked(@Nullable Consumer<String> listener) {
        onDayPicked = listener;
        setClickable(listener != null);
    }

    public void setSelected(@Nullable String day) {
        selected = day;
        invalidate();
    }

    private float dp(float value) { return value * getResources().getDisplayMetrics().density; }

    private float cellSize() { return (getHeight() - dp(3f) * (ROWS - 1)) / ROWS; }

    private int columns() {
        float gap = dp(3f);
        return Math.max(1, (int) ((getWidth() + gap) / (cellSize() + gap)));
    }

    /** The index into {@link #daily} drawn at one cell, or -1 when that cell is before the record. */
    private int offsetAt(int column, int row) {
        int index = column * ROWS + row;
        int offset = daily.length - columns() * ROWS + index;
        return offset >= 0 && offset < daily.length ? offset : -1;
    }

    // Lint wants this override to call performClick itself. It is super.onTouchEvent that decides a
    // tap happened and calls it -- doing it here as well would fire the selection on a drag that
    // was only passing through on its way to scrolling the page.
    @SuppressLint("ClickableViewAccessibility")
    @Override public boolean onTouchEvent(MotionEvent event) {
        if (event.getActionMasked() == MotionEvent.ACTION_DOWN) {
            downX = event.getX();
            downY = event.getY();
        }
        return super.onTouchEvent(event);
    }

    @Override public boolean performClick() {
        boolean handled = super.performClick();
        if (onDayPicked == null) return handled;
        float gap = dp(3f);
        float size = cellSize();
        if (size <= 0) return handled;
        int column = (int) (downX / (size + gap));
        int row = (int) (downY / (size + gap));
        if (column < 0 || column >= columns() || row < 0 || row >= ROWS) return handled;
        int offset = offsetAt(column, row);
        onDayPicked.accept(offset >= 0 && offset < days.size() ? days.get(offset) : null);
        return true;
    }

    @Override protected void onDraw(Canvas canvas) {
        float gap = dp(3f);
        float size = cellSize();
        int columns = columns();
        int peak = 0;
        for (int value : daily) peak = Math.max(peak, value);
        int forest = ContextCompat.getColor(getContext(), R.color.forest);
        int empty = ContextCompat.getColor(getContext(), R.color.hairline);

        for (int index = 0; index < columns * ROWS; index++) {
            int column = index / ROWS;
            int row = index % ROWS;
            float x = column * (size + gap);
            float y = row * (size + gap);
            int offset = offsetAt(column, row);
            int value = offset >= 0 ? daily[offset] : 0;
            // The lightest step still has to be visible, or a quiet day reads as no day at all.
            float weight = peak == 0 || value == 0 ? 0f : Math.max(0.2f, value / (float) peak);
            cell.setColor(weight == 0f ? empty
                : Color.argb(Math.round(255 * weight), Color.red(forest), Color.green(forest), Color.blue(forest)));
            box.set(x, y, x + size, y + size);
            canvas.drawRoundRect(box, dp(2f), dp(2f), cell);
            if (selected != null && offset >= 0 && offset < days.size()
                    && selected.equals(days.get(offset))) {
                // Outlined rather than recoloured: the fill is the day's own count, and replacing
                // it would hide the one number the selection is there to read.
                box.inset(dp(0.75f), dp(0.75f));
                canvas.drawRoundRect(box, dp(2f), dp(2f), outline);
            }
        }
    }
}
