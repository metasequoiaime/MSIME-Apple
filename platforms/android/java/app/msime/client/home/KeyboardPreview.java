package app.msime.client.home;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import android.view.View;

/**
 * A still picture of the nine-key layout, drawn for the keyboard card.
 *
 * It is a picture and not the input view: the real one belongs to the InputMethodService, bound to an
 * editor and owning an Engine session, and a second instance of it here would be a second owner. The
 * rows are the nine-key faces the host actually ships, so the two do not drift apart silently -- the
 * labels come from one array that mirrors `KeyboardLayout`'s nine-key layer.
 */
public final class KeyboardPreview extends View {
    private static final String[][] ROWS = {
        {"，", "分词", "ABC", "DEF", "⌫"},
        {"。", "GHI", "JKL", "MNO", "."},
        {"？", "PQRS", "TUV", "WXYZ", "0"},
        {"！", "符", "123", "空格", "中/英", "换行"},
    };

    private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final RectF key = new RectF();

    public KeyboardPreview(Context context) {
        super(context);
        setBackground(Theme.filled(context, Color.rgb(240, 245, 242), 14f));
    }

    @Override protected void onDraw(Canvas canvas) {
        Context context = getContext();
        float pad = Theme.dp(context, 8);
        float gap = Theme.dp(context, 5);
        float stripHeight = Theme.dp(context, 26);
        float radius = Theme.dp(context, 7);

        paint.setColor(Theme.INK);
        paint.setTextSize(Theme.dp(context, 12));
        paint.setTextAlign(Paint.Align.LEFT);
        canvas.drawText("ni hao", pad + Theme.dp(context, 6), pad + stripHeight * 0.66f, paint);
        paint.setColor(Theme.FOREST);
        canvas.drawText("你好", pad + Theme.dp(context, 52), pad + stripHeight * 0.66f, paint);
        paint.setColor(Theme.TEXT_SECONDARY);
        canvas.drawText("你号", pad + Theme.dp(context, 84), pad + stripHeight * 0.66f, paint);
        paint.setTextAlign(Paint.Align.RIGHT);
        canvas.drawText("九键", getWidth() - pad - Theme.dp(context, 6), pad + stripHeight * 0.66f, paint);

        float top = pad + stripHeight;
        float available = getHeight() - top - pad;
        float rowHeight = (available - gap * (ROWS.length - 1)) / ROWS.length;
        paint.setTextAlign(Paint.Align.CENTER);
        for (int r = 0; r < ROWS.length; r++) {
            String[] row = ROWS[r];
            float width = (getWidth() - pad * 2 - gap * (row.length - 1)) / (float) row.length;
            float y = top + r * (rowHeight + gap);
            for (int c = 0; c < row.length; c++) {
                float x = pad + c * (width + gap);
                key.set(x, y, x + width, y + rowHeight);
                boolean accent = "换行".equals(row[c]);
                paint.setColor(accent ? Theme.FOREST : Color.WHITE);
                canvas.drawRoundRect(key, radius, radius, paint);
                paint.setColor(accent ? Color.WHITE : Theme.INK);
                paint.setTextSize(Theme.dp(context, row[c].length() > 2 ? 10 : 12));
                canvas.drawText(row[c], key.centerX(),
                    key.centerY() + paint.getTextSize() * 0.36f, paint);
            }
        }
    }
}
