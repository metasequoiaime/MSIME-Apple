package app.msime.client.home;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.widget.LinearLayout;

/**
 * The bottom tab bar: 键盘, 社区, 统计, 我的.
 *
 * Each tab is one {@link Tab} view that draws its own glyph. There is no icon font and no vector
 * asset to reference -- the native package ships no AndroidX and its drawables are the launcher icon
 * and nothing else -- so four small shapes are cheaper to draw than to import, and they scale with the
 * text size instead of against a density bucket.
 */
public final class TabBar extends LinearLayout {
    /** Which page a tab selects. The order is the Apple app's. */
    public enum Page { KEYBOARD("键盘"), COMMUNITY("社区"), STATISTICS("统计"), ACCOUNT("我的");
        final String title;
        Page(String title) { this.title = title; }
    }

    /** Told which page the user asked for; the host swaps content. */
    public interface OnSelect { void selected(Page page); }

    private final Tab[] tabs = new Tab[Page.values().length];
    private Page current = Page.KEYBOARD;
    private OnSelect listener;

    public TabBar(Context context) {
        super(context);
        setOrientation(HORIZONTAL);
        setGravity(Gravity.CENTER_VERTICAL);
        setBackground(Theme.filled(context, Color.rgb(250, 252, 251), 28f));
        int pad = Theme.dp(context, 6);
        setPadding(pad, pad, pad, pad);
        for (Page page : Page.values()) {
            Tab tab = new Tab(context, page);
            tabs[page.ordinal()] = tab;
            addView(tab, new LayoutParams(0, Theme.dp(context, 52), 1f));
        }
        apply();
    }

    public void setOnSelect(OnSelect listener) { this.listener = listener; }

    public void select(Page page) {
        if (page == current) return;
        current = page;
        apply();
        if (listener != null) listener.selected(page);
    }

    private void apply() {
        for (Tab tab : tabs) tab.setSelectedTab(tab.page == current);
    }

    /** One tab: a drawn glyph over its label, with the selected pill behind both. */
    private final class Tab extends View {
        private final Page page;
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final RectF rect = new RectF();
        private final Path path = new Path();
        private boolean chosen;

        Tab(Context context, Page page) {
            super(context);
            this.page = page;
            setClickable(true);
        }

        void setSelectedTab(boolean chosen) {
            if (this.chosen == chosen) return;
            this.chosen = chosen;
            invalidate();
        }

        @Override public boolean onTouchEvent(MotionEvent event) {
            if (event.getAction() == MotionEvent.ACTION_UP) select(page);
            return super.onTouchEvent(event);
        }

        @Override protected void onDraw(Canvas canvas) {
            int width = getWidth();
            int height = getHeight();
            if (chosen) {
                paint.setColor(Color.rgb(226, 236, 231));
                rect.set(Theme.dp(getContext(), 2), 0, width - Theme.dp(getContext(), 2), height);
                canvas.drawRoundRect(rect, height / 2f, height / 2f, paint);
            }
            int tint = chosen ? Theme.FOREST : Theme.TEXT_SECONDARY;
            float glyph = Theme.dp(getContext(), 20);
            float cx = width / 2f;
            float top = Theme.dp(getContext(), 8);
            paint.setColor(tint);
            drawGlyph(canvas, cx, top, glyph);
            paint.setTextAlign(Paint.Align.CENTER);
            paint.setTextSize(Theme.dp(getContext(), 11));
            paint.setFakeBoldText(chosen);
            canvas.drawText(page.title, cx, height - Theme.dp(getContext(), 8), paint);
        }

        /** Four glyphs, each inside a `size` box whose top-left is (cx - size/2, top). */
        private void drawGlyph(Canvas canvas, float cx, float top, float size) {
            float left = cx - size / 2f;
            float unit = size / 8f;
            paint.setStyle(Paint.Style.FILL);
            switch (page) {
                case KEYBOARD: {
                    paint.setStyle(Paint.Style.STROKE);
                    paint.setStrokeWidth(Math.max(1.5f, unit * 0.55f));
                    rect.set(left, top + unit, left + size, top + size - unit);
                    canvas.drawRoundRect(rect, unit, unit, paint);
                    paint.setStyle(Paint.Style.FILL);
                    for (int row = 0; row < 2; row++) {
                        for (int col = 0; col < 3; col++) {
                            float kx = left + unit * (1.6f + col * 2.4f);
                            float ky = top + unit * (2.6f + row * 1.9f);
                            canvas.drawCircle(kx, ky, unit * 0.42f, paint);
                        }
                    }
                    canvas.drawRoundRect(new RectF(left + unit * 2f, top + size - unit * 2.6f,
                        left + size - unit * 2f, top + size - unit * 1.9f), unit * 0.3f, unit * 0.3f, paint);
                    break;
                }
                case COMMUNITY: {
                    float gap = unit * 0.8f;
                    float box = (size - gap) / 2f;
                    for (int row = 0; row < 2; row++) {
                        for (int col = 0; col < 2; col++) {
                            rect.set(left + col * (box + gap), top + row * (box + gap),
                                left + col * (box + gap) + box, top + row * (box + gap) + box);
                            canvas.drawRoundRect(rect, unit * 0.5f, unit * 0.5f, paint);
                        }
                    }
                    break;
                }
                case STATISTICS: {
                    float[] heights = {0.45f, 0.8f, 0.6f, 1f};
                    float barWidth = size / 6f;
                    for (int i = 0; i < heights.length; i++) {
                        float bx = left + i * (barWidth * 1.35f);
                        rect.set(bx, top + size * (1 - heights[i]), bx + barWidth, top + size);
                        canvas.drawRoundRect(rect, barWidth * 0.3f, barWidth * 0.3f, paint);
                    }
                    break;
                }
                case ACCOUNT: {
                    canvas.drawCircle(cx, top + unit * 2.6f, unit * 2.1f, paint);
                    path.reset();
                    rect.set(left + unit * 0.6f, top + unit * 5f, left + size - unit * 0.6f, top + size + unit * 2.4f);
                    path.addRoundRect(rect, unit * 3f, unit * 3f, Path.Direction.CW);
                    canvas.save();
                    canvas.clipRect(left, top, left + size, top + size);
                    canvas.drawPath(path, paint);
                    canvas.restore();
                    break;
                }
            }
        }
    }
}
