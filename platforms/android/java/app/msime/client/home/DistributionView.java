package app.msime.client.home;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.RectF;
import android.util.AttributeSet;
import android.view.View;
import androidx.core.content.ContextCompat;
import app.msime.client.R;
import app.msime.client.TypingStatisticsModel;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * 一组占比：每行一个分类，名字、条、计数和百分比。
 *
 * <p>Drawn rather than charted, for the same reason the trend line is: one bar chart is not worth a
 * charting dependency. A ranked bar rather than a pie because the lists here run to fifteen rows --
 * the four smallest schemes are a sliver each in a pie and a readable row here.
 *
 * <p>Empty categories are dropped rather than drawn at zero. Fifteen scheme rows of which two have
 * counts is a list you have to search; the two that happened are the answer.
 */
public final class DistributionView extends View {
    private static final int MAX_ROWS = 16;

    private final Paint bar = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint track = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint title = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint value = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint empty = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final RectF box = new RectF();
    private List<TypingStatisticsModel.Slice> slices = List.of();
    private long total;

    public DistributionView(Context context, AttributeSet attributes) {
        super(context, attributes);
        bar.setColor(ContextCompat.getColor(context, R.color.forest));
        track.setColor(ContextCompat.getColor(context, R.color.mist));
        title.setColor(ContextCompat.getColor(context, R.color.ink));
        title.setTextSize(dp(13f));
        value.setColor(ContextCompat.getColor(context, R.color.text_secondary));
        value.setTextSize(dp(12f));
        empty.setColor(ContextCompat.getColor(context, R.color.text_secondary));
        empty.setTextSize(dp(13f));
    }

    /** Show one distribution, largest first; categories with no characters are left out. */
    public void setSlices(List<TypingStatisticsModel.Slice> values) {
        List<TypingStatisticsModel.Slice> kept = new ArrayList<>();
        for (TypingStatisticsModel.Slice slice : values == null ? List.<TypingStatisticsModel.Slice>of() : values) {
            if (slice.count() > 0) kept.add(slice);
        }
        kept.sort((left, right) -> Long.compare(right.count(), left.count()));
        if (kept.size() > MAX_ROWS) kept = kept.subList(0, MAX_ROWS);
        slices = List.copyOf(kept);
        total = TypingStatisticsModel.sum(slices);
        describe();
        requestLayout();
        invalidate();
    }

    /**
     * Say the rows out loud.
     *
     * <p>Everything this view shows is drawn, so without this there is nothing here for a screen
     * reader to read -- the chart would be a blank rectangle between two headings.
     */
    private void describe() {
        if (slices.isEmpty()) {
            setContentDescription("这一段时间还没有记录");
            return;
        }
        StringBuilder text = new StringBuilder();
        for (TypingStatisticsModel.Slice slice : slices) {
            if (text.length() > 0) text.append('，');
            text.append(slice.title()).append(' ').append(slice.count()).append(" 字符");
            if (total > 0) {
                text.append(String.format(Locale.ROOT, "，占 %.1f%%", 100.0 * slice.count() / total));
            }
        }
        setContentDescription(text.toString());
    }

    private float dp(float value) { return value * getResources().getDisplayMetrics().density; }

    private float rowHeight() { return dp(34f); }

    @Override protected void onMeasure(int widthSpec, int heightSpec) {
        int width = resolveSize((int) dp(240f), widthSpec);
        int rows = Math.max(1, slices.size());
        setMeasuredDimension(width, resolveSize((int) (rows * rowHeight()), heightSpec));
    }

    @Override protected void onDraw(Canvas canvas) {
        if (slices.isEmpty()) {
            canvas.drawText("这一段时间还没有记录", 0, dp(20f), empty);
            return;
        }
        long peak = 0;
        for (TypingStatisticsModel.Slice slice : slices) peak = Math.max(peak, slice.count());
        float labelWidth = dp(76f);
        float valueWidth = dp(96f);
        float trackLeft = labelWidth;
        float trackRight = Math.max(trackLeft + dp(8f), getWidth() - valueWidth);
        float radius = dp(4f);
        for (int index = 0; index < slices.size(); index++) {
            TypingStatisticsModel.Slice slice = slices.get(index);
            float top = index * rowHeight();
            float centre = top + rowHeight() / 2f;
            float baseline = centre + dp(4.5f);
            canvas.drawText(slice.title(), 0, baseline, title);
            box.set(trackLeft, centre - dp(5f), trackRight, centre + dp(5f));
            canvas.drawRoundRect(box, radius, radius, track);
            if (peak > 0) {
                float width = (trackRight - trackLeft) * slice.count() / (float) peak;
                box.set(trackLeft, centre - dp(5f), trackLeft + Math.max(width, dp(3f)),
                    centre + dp(5f));
                canvas.drawRoundRect(box, radius, radius, bar);
            }
            String share = total <= 0 ? ""
                : String.format(Locale.ROOT, "  %.1f%%", 100.0 * slice.count() / total);
            String text = slice.count() + share;
            canvas.drawText(text, getWidth() - value.measureText(text), baseline, value);
        }
    }
}
