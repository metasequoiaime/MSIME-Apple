package app.msime.client.home;

import android.content.Context;
import android.graphics.Color;
import android.view.Gravity;
import android.view.View;
import android.widget.LinearLayout;
import android.widget.TextView;

/**
 * The 键盘 tab: what the keyboard currently is, a way to try it, and the way in to each setting group.
 *
 * Mirrors the Apple app's keyboard home. The preview is a static picture of the live layout rather
 * than the real input view -- the input view only exists inside an InputMethodService bound to an
 * editor, and lifting it out of that would mean a second owner for the Engine session.
 */
public final class KeyboardPage {
    private KeyboardPage() {}

    /** Told the user asked to try the keyboard, or to open a group. */
    public interface Actions {
        void tryKeyboard();
        void openSystemSettings();
    }

    public static View create(Context context, String skinName, String schemeName, Actions actions) {
        LinearLayout page = new LinearLayout(context);
        page.setOrientation(LinearLayout.VERTICAL);
        int gutter = Theme.dp(context, 16);
        page.setPadding(gutter, gutter, gutter, gutter);

        page.addView(Tiles.heading(context, "让输入，更像你", "从一次顺手的表达开始"));

        LinearLayout keyboardCard = Tiles.card(context, 16);
        LinearLayout.LayoutParams cardParams = new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        cardParams.topMargin = Theme.dp(context, 20);
        page.addView(keyboardCard, cardParams);

        LinearLayout header = new LinearLayout(context);
        header.setOrientation(LinearLayout.HORIZONTAL);
        header.setGravity(Gravity.CENTER_VERTICAL);
        LinearLayout titles = new LinearLayout(context);
        titles.setOrientation(LinearLayout.VERTICAL);
        titles.addView(Tiles.text(context, "我的键盘", 18f, Theme.INK, true));
        titles.addView(Tiles.text(context, skinName + " · " + schemeName, 13f, Theme.TEXT_SECONDARY, false));
        header.addView(titles, new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f));
        TextView badge = Tiles.text(context, "当前外观", 12f, Theme.TEXT_SECONDARY, false);
        badge.setBackground(Theme.filled(context, Theme.MIST, 12f));
        badge.setPadding(Theme.dp(context, 10), Theme.dp(context, 6), Theme.dp(context, 10), Theme.dp(context, 6));
        header.addView(badge);
        keyboardCard.addView(header);

        KeyboardPreview preview = new KeyboardPreview(context);
        LinearLayout.LayoutParams previewParams = new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, Theme.dp(context, 210));
        previewParams.topMargin = Theme.dp(context, 14);
        keyboardCard.addView(preview, previewParams);

        TextView trial = Tiles.primaryButton(context, "试用键盘");
        trial.setOnClickListener(ignored -> actions.tryKeyboard());
        LinearLayout.LayoutParams trialParams = new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        trialParams.topMargin = Theme.dp(context, 14);
        keyboardCard.addView(trial, trialParams);

        LinearLayout firstRow = Tiles.row(context, 12,
            Tiles.feature(context, "✿", Color.rgb(252, 231, 236), "皮肤", skinName),
            Tiles.feature(context, "⌨", Color.rgb(226, 236, 231), "输入方案", schemeName),
            Tiles.feature(context, "⚙", Color.rgb(233, 232, 248), "按键", "间距与语音"));
        LinearLayout.LayoutParams rowParams = new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        rowParams.topMargin = Theme.dp(context, 16);
        page.addView(firstRow, rowParams);

        View systemTile = Tiles.feature(context, "☷", Color.rgb(238, 240, 239), "系统设置", "启用与完全访问");
        systemTile.setOnClickListener(ignored -> actions.openSystemSettings());
        LinearLayout secondRow = Tiles.row(context, 12,
            Tiles.feature(context, "▤", Color.rgb(245, 235, 226), "词库", "个人词与同步"),
            Tiles.feature(context, "✦", Color.rgb(255, 240, 224), "AI", "回复与润色"),
            systemTile);
        LinearLayout.LayoutParams secondParams = new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        secondParams.topMargin = Theme.dp(context, 12);
        page.addView(secondRow, secondParams);

        return page;
    }
}
