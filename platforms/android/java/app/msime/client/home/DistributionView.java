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
import app.msime.client.TypingStatisticsModel;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * 一组占比：上面一张图，下面每行一个分类。
 *
 * <p>Three shapes, chosen the way the Apple app chooses them (`StatisticsCharts.swift`): a pie for
 * character types, where the question is what share each took; a donut for language modes, whose
 * hole carries the total; and a ranked bar for schemes, because that list runs to fifteen rows and
 * four of them would be slivers in a pie.
 *
 * <p>Drawn rather than charted, for the same reason the trend line is: three small charts are not
 * worth a charting dependency.
 */
public final class DistributionView extends View {
    /** 这一块用哪种图。 */
    public enum Style { PIE, DONUT, RANK }

    private static final int MAX_ROWS = 16;
    /** 梯度的档数，和 Apple 的 `chartRamp(8)` 一致。 */
    private static final int RAMP_STEPS = 8;

    private final Paint fill = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint track = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint title = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint value = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint centre = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint caption = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint empty = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final RectF box = new RectF();
    private final int[] ramp = new int[RAMP_STEPS];
    private final int surface;
    private List<TypingStatisticsModel.Slice> slices = List.of();
    private List<TypingStatisticsModel.Slice> ranked = List.of();
    private Style style = Style.RANK;
    private long total;

    public DistributionView(Context context, AttributeSet attributes) {
        super(context, attributes);
        surface = ContextCompat.getColor(context, R.color.surface);
        int from = ContextCompat.getColor(context, R.color.forest);
        int to = ContextCompat.getColor(context, R.color.chart_ramp_end);
        for (int step = 0; step < RAMP_STEPS; step++) {
            ramp[step] = blend(from, to, step / (float) (RAMP_STEPS - 1));
        }
        track.setColor(ContextCompat.getColor(context, R.color.mist));
        title.setColor(ContextCompat.getColor(context, R.color.ink));
        title.setTextSize(dp(13f));
        value.setColor(ContextCompat.getColor(context, R.color.text_secondary));
        value.setTextSize(dp(12f));
        centre.setColor(ContextCompat.getColor(context, R.color.ink));
        centre.setTextSize(dp(24f));
        centre.setFakeBoldText(true);
        caption.setColor(ContextCompat.getColor(context, R.color.text_secondary));
        caption.setTextSize(dp(11f));
        empty.setColor(ContextCompat.getColor(context, R.color.text_secondary));
        empty.setTextSize(dp(13f));
    }

    /**
     * Show one distribution.
     *
     * <p>The legend keeps the order the categories are declared in, so a category stays the same
     * colour whatever it counts this week; only the ranked bars re-order, which is their point. An
     * empty 历史未分类 is the one row dropped -- it is an artefact of older versions, and printing it
     * at zero explains nothing.
     */
    public void setSlices(List<TypingStatisticsModel.Slice> values, Style chart) {
        style = chart == null ? Style.RANK : chart;
        List<TypingStatisticsModel.Slice> kept = new ArrayList<>();
        for (TypingStatisticsModel.Slice slice : values == null
                ? List.<TypingStatisticsModel.Slice>of() : values) {
            if (slice.count() > 0 || !"unknown".equals(slice.id())) kept.add(slice);
        }
        if (kept.size() > MAX_ROWS) kept = kept.subList(0, MAX_ROWS);
        slices = List.copyOf(kept);
        List<TypingStatisticsModel.Slice> order = new ArrayList<>();
        for (TypingStatisticsModel.Slice slice : slices) if (slice.count() > 0) order.add(slice);
        order.sort((left, right) -> Long.compare(right.count(), left.count()));
        ranked = List.copyOf(order);
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
        if (total <= 0) {
            setContentDescription("这一段时间还没有记录");
            return;
        }
        StringBuilder text = new StringBuilder();
        for (TypingStatisticsModel.Slice slice : slices) {
            if (slice.count() <= 0) continue;
            if (text.length() > 0) text.append('，');
            text.append(slice.title()).append(' ').append(slice.count()).append(" 字符");
            text.append(String.format(Locale.ROOT, "，占 %.1f%%", 100.0 * slice.count() / total));
        }
        setContentDescription(text.toString());
    }

    private float dp(float value) { return value * getResources().getDisplayMetrics().density; }

    private float rowHeight() { return dp(34f); }

    /** The chart above the legend: a fixed square for the two round ones, a row each for the bars. */
    private float chartHeight() {
        if (total <= 0 && style != Style.RANK) return dp(28f);
        return switch (style) {
            case PIE, DONUT -> dp(190f);
            case RANK -> ranked.isEmpty() ? dp(28f) : ranked.size() * dp(30f) + dp(20f);
        };
    }

    @Override protected void onMeasure(int widthSpec, int heightSpec) {
        int width = resolveSize((int) dp(240f), widthSpec);
        float height = chartHeight() + dp(12f) + Math.max(1, slices.size()) * rowHeight();
        setMeasuredDimension(width, resolveSize((int) height, heightSpec));
    }

    @Override protected void onDraw(Canvas canvas) {
        if (total <= 0 && ranked.isEmpty()) {
            canvas.drawText("这一段时间还没有记录", 0, dp(20f), empty);
            if (slices.isEmpty()) return;
        }
        float top = chartHeight() + dp(12f);
        switch (style) {
            case PIE -> drawSectors(canvas, 0f);
            case DONUT -> drawSectors(canvas, .62f);
            case RANK -> drawRanked(canvas);
        }
        for (int index = 0; index < slices.size(); index++) {
            TypingStatisticsModel.Slice slice = slices.get(index);
            float rowTop = top + index * rowHeight();
            float middle = rowTop + rowHeight() / 2f;
            float baseline = middle + dp(4.5f);
            int colour = ramp[index % RAMP_STEPS];
            // 图例左边那块色是图和名字之间唯一的连线，所以它必须和扇区同色、同顺序。
            float tile = dp(22f);
            box.set(0, middle - tile / 2f, tile, middle + tile / 2f);
            fill.setColor(fade(colour, .18f));
            canvas.drawRoundRect(box, dp(7f), dp(7f), fill);
            box.set(dp(6f), middle - dp(5f), dp(16f), middle + dp(5f));
            fill.setColor(colour);
            canvas.drawRoundRect(box, dp(3f), dp(3f), fill);
            canvas.drawText(slice.title(), tile + dp(10f), baseline, title);
            String share = total <= 0 ? "—"
                : String.format(Locale.ROOT, "%.1f%%", 100.0 * slice.count() / total);
            float shareWidth = value.measureText(share);
            canvas.drawText(share, getWidth() - shareWidth, baseline, value);
            String count = String.valueOf(slice.count());
            canvas.drawText(count, getWidth() - shareWidth - dp(10f) - value.measureText(count),
                baseline, value);
        }
    }

    /** A pie, or a donut when `hole` is more than zero, in declaration order from twelve o'clock. */
    private void drawSectors(Canvas canvas, float hole) {
        float height = dp(190f);
        if (total <= 0) return;
        float diameter = Math.min(height, getWidth());
        float left = (getWidth() - diameter) / 2f;
        box.set(left, 0, left + diameter, diameter);
        float start = -90f;
        for (int index = 0; index < slices.size(); index++) {
            TypingStatisticsModel.Slice slice = slices.get(index);
            if (slice.count() <= 0) continue;
            float sweep = 360f * slice.count() / total;
            fill.setColor(ramp[index % RAMP_STEPS]);
            // 相邻扇区之间留一线：贴在一起时，梯度里相邻的两档几乎看不出分界。
            float inset = Math.min(1.5f, sweep / 4f);
            canvas.drawArc(box, start + inset, Math.max(0f, sweep - inset * 2f), true, fill);
            start += sweep;
        }
        if (hole <= 0) return;
        float radius = diameter / 2f * hole;
        fill.setColor(surface);
        canvas.drawCircle(left + diameter / 2f, diameter / 2f, radius, fill);
        // 环心放总数：这一块要回答的是「一共多少、谁占大头」，总数就在图里，不用往上找。
        String amount = String.valueOf(total);
        canvas.drawText(amount, left + diameter / 2f - centre.measureText(amount) / 2f,
            diameter / 2f + dp(2f), centre);
        canvas.drawText("字符", left + diameter / 2f - caption.measureText("字符") / 2f,
            diameter / 2f + dp(20f), caption);
    }

    /** Ranked bars, largest first, each carrying its count at the end. */
    private void drawRanked(Canvas canvas) {
        if (ranked.isEmpty()) return;
        long peak = ranked.get(0).count();
        float rowHeight = dp(30f);
        float radius = dp(5f);
        for (int index = 0; index < ranked.size(); index++) {
            TypingStatisticsModel.Slice slice = ranked.get(index);
            float middle = dp(10f) + index * rowHeight + rowHeight / 2f;
            String count = String.valueOf(slice.count());
            float countWidth = value.measureText(count) + dp(8f);
            float right = Math.max(dp(24f), getWidth() - countWidth);
            box.set(0, middle - dp(9f), right, middle + dp(9f));
            canvas.drawRoundRect(box, radius, radius, track);
            float width = peak <= 0 ? 0 : (right) * slice.count() / (float) peak;
            box.set(0, middle - dp(9f), Math.max(width, dp(6f)), middle + dp(9f));
            fill.setColor(ramp[position(slice) % RAMP_STEPS]);
            canvas.drawRoundRect(box, radius, radius, fill);
            canvas.drawText(slice.title(), dp(8f), middle + dp(4.5f), title);
            canvas.drawText(count, getWidth() - value.measureText(count), middle + dp(4f), value);
        }
    }

    /** Where this slice sits in the declared order, so bar and legend agree on its colour. */
    private int position(TypingStatisticsModel.Slice slice) {
        for (int index = 0; index < slices.size(); index++) {
            if (slices.get(index).id().equals(slice.id())) return index;
        }
        return 0;
    }

    private static int blend(int from, int to, float amount) {
        return Color.rgb(
            Math.round(Color.red(from) + (Color.red(to) - Color.red(from)) * amount),
            Math.round(Color.green(from) + (Color.green(to) - Color.green(from)) * amount),
            Math.round(Color.blue(from) + (Color.blue(to) - Color.blue(from)) * amount));
    }

    private static int fade(int colour, float alpha) {
        return Color.argb(Math.round(255 * alpha), Color.red(colour), Color.green(colour),
            Color.blue(colour));
    }
}
