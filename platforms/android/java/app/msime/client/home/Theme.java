package app.msime.client.home;

import android.content.Context;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.util.TypedValue;

/**
 * The host app's palette and metrics.
 *
 * The values are the Apple app's `MetasequoiaTheme`, so the two platforms read as one product. The
 * native package links against android.jar alone -- no AndroidX, no Material -- so there is no theme
 * attribute system to hang these on and no `MaterialCardView` to use; a card is a rounded
 * {@link GradientDrawable} built here.
 */
public final class Theme {
    private Theme() {}

    /** Apple `forest`: the accent, and the fill of anything asking to be tapped. */
    public static final int FOREST = Color.rgb(24, 92, 72);
    /** Apple `needle`: secondary marks that still belong to the accent family. */
    public static final int NEEDLE = Color.rgb(77, 138, 114);
    /** Apple `mist`: the page behind the cards. */
    public static final int MIST = Color.rgb(243, 247, 245);
    /** Apple `cone`: the one warm accent, used sparingly. */
    public static final int CONE = Color.rgb(167, 103, 59);
    /** Apple `ink`: primary text. */
    public static final int INK = Color.rgb(20, 35, 29);

    public static final int SURFACE = Color.WHITE;
    public static final int TEXT_SECONDARY = Color.rgb(112, 124, 118);
    public static final int HAIRLINE = Color.rgb(228, 234, 231);

    public static int dp(Context context, float value) {
        return Math.round(TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP, value, context.getResources().getDisplayMetrics()));
    }

    /** A card: one surface, one radius, no border. Shadows need a ViewOutlineProvider, not a drawable. */
    public static GradientDrawable card(Context context, float radiusDp) {
        GradientDrawable shape = new GradientDrawable();
        shape.setShape(GradientDrawable.RECTANGLE);
        shape.setColor(SURFACE);
        shape.setCornerRadius(dp(context, radiusDp));
        return shape;
    }

    public static GradientDrawable filled(Context context, int color, float radiusDp) {
        GradientDrawable shape = new GradientDrawable();
        shape.setShape(GradientDrawable.RECTANGLE);
        shape.setColor(color);
        shape.setCornerRadius(dp(context, radiusDp));
        return shape;
    }
}
