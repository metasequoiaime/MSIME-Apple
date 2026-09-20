package app.msime.client.home;

import android.content.Context;
import android.graphics.Color;
import android.graphics.Typeface;
import android.view.Gravity;
import android.view.View;
import android.widget.LinearLayout;
import android.widget.TextView;

/** The small building blocks the pages are assembled from. Framework views only, no XML layouts. */
public final class Tiles {
    private Tiles() {}

    public static TextView text(Context context, String value, float sizeDp, int color, boolean bold) {
        TextView view = new TextView(context);
        view.setText(value);
        view.setTextSize(sizeDp);
        view.setTextColor(color);
        if (bold) view.setTypeface(Typeface.DEFAULT_BOLD);
        return view;
    }

    /** A page's heading block: a large line and a quieter one under it. */
    public static LinearLayout heading(Context context, String title, String subtitle) {
        LinearLayout column = new LinearLayout(context);
        column.setOrientation(LinearLayout.VERTICAL);
        column.addView(text(context, title, 26f, Theme.INK, true));
        TextView sub = text(context, subtitle, 14f, Theme.TEXT_SECONDARY, false);
        sub.setPadding(0, Theme.dp(context, 4), 0, 0);
        column.addView(sub);
        return column;
    }

    /** A white card with padding. Callers add their own children. */
    public static LinearLayout card(Context context, int padDp) {
        LinearLayout card = new LinearLayout(context);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setBackground(Theme.card(context, 18f));
        // Elevation needs an outline to cast from; a background drawable alone casts nothing.
        card.setOutlineProvider(android.view.ViewOutlineProvider.BACKGROUND);
        card.setElevation(Theme.dp(context, 1));
        int pad = Theme.dp(context, padDp);
        card.setPadding(pad, pad, pad, pad);
        return card;
    }

    /**
     * One of the feature squares: a tinted round badge, a title and a value.
     *
     * The badge carries a single glyph rather than an icon, for the same reason the tab bar draws its
     * own: this package has no icon set to draw from.
     */
    public static LinearLayout feature(Context context, String glyph, int badge, String title, String value) {
        LinearLayout tile = card(context, 14);
        TextView mark = text(context, glyph, 18f, Theme.INK, false);
        mark.setGravity(Gravity.CENTER);
        int badgeSize = Theme.dp(context, 40);
        mark.setBackground(Theme.filled(context, badge, 12f));
        LinearLayout.LayoutParams markParams = new LinearLayout.LayoutParams(badgeSize, badgeSize);
        markParams.bottomMargin = Theme.dp(context, 10);
        tile.addView(mark, markParams);
        tile.addView(text(context, title, 15f, Theme.INK, true));
        TextView caption = text(context, value, 12f, Theme.TEXT_SECONDARY, false);
        caption.setPadding(0, Theme.dp(context, 2), 0, 0);
        tile.addView(caption);
        return tile;
    }

    /** A row of equal-width children with a gap between them. */
    public static LinearLayout row(Context context, int gapDp, View... children) {
        LinearLayout row = new LinearLayout(context);
        row.setOrientation(LinearLayout.HORIZONTAL);
        for (int i = 0; i < children.length; i++) {
            LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f);
            if (i > 0) params.leftMargin = Theme.dp(context, gapDp);
            row.addView(children[i], params);
        }
        return row;
    }

    /** The full-width accent button that opens the keyboard trial. */
    public static TextView primaryButton(Context context, String label) {
        TextView button = text(context, label, 16f, Color.WHITE, true);
        button.setGravity(Gravity.CENTER_VERTICAL);
        button.setBackground(Theme.filled(context, Theme.FOREST, 14f));
        int padX = Theme.dp(context, 18);
        int padY = Theme.dp(context, 16);
        button.setPadding(padX, padY, padX, padY);
        button.setClickable(true);
        return button;
    }
}
