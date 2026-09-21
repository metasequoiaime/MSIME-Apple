package app.msime.client.home;

import android.content.Context;
import android.content.Intent;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.provider.Settings;
import android.view.Gravity;
import android.view.View;
import android.widget.LinearLayout;
import android.widget.TextView;
import androidx.annotation.DrawableRes;
import androidx.annotation.Nullable;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.content.ContextCompat;
import app.msime.client.R;
import com.google.android.material.button.MaterialButton;
import com.google.android.material.imageview.ShapeableImageView;

/**
 * 新手引导：四页，从「这是什么」走到「键盘已经能用了」。
 *
 * <p>Built from the Apple app's `WelcomeFlowView`, page for page, with its last page being that
 * app's `OnboardingView` -- the steps for turning the keyboard on. Those steps are Android's own:
 * copying 设置 → 通用 → 键盘 across would send people somewhere that does not exist here.
 *
 * <p>Explicit 下一步 rather than a swipeable pager, as the master has it: the second page writes a
 * preference, and a page that changes something should not be something a thumb slides past.
 */
public final class OnboardingActivity extends AppCompatActivity {
    private static final String STORE = "msime_onboarding_v1";
    private static final String SEEN = "seen";
    private static final int PAGES = 4;

    /** Whether the flow has run on this device. */
    public static boolean seen(Context context) {
        return context.getSharedPreferences(STORE, MODE_PRIVATE).getBoolean(SEEN, false);
    }

    private static void markSeen(Context context) {
        context.getSharedPreferences(STORE, MODE_PRIVATE).edit().putBoolean(SEEN, true).apply();
    }

    private int page;
    private String layout = "twenty_six_key";

    @Override protected void onCreate(@Nullable Bundle state) {
        super.onCreate(state);
        setContentView(R.layout.activity_onboarding);
        findViewById(R.id.onboarding_skip).setOnClickListener(ignored -> finishFlow());
        findViewById(R.id.onboarding_next).setOnClickListener(ignored -> {
            if (page == PAGES - 1) finishFlow();
            else { page++; render(); }
        });
        findViewById(R.id.onboarding_previous).setOnClickListener(ignored -> {
            if (page > 0) { page--; render(); }
        });
        render();
        offMainThread(() -> {
            org.json.JSONObject snapshot = HostStore.loadPreferences(getApplicationContext());
            org.json.JSONObject preferences =
                snapshot == null ? null : snapshot.optJSONObject("preferences");
            String value = preferences == null ? "twenty_six_key"
                : preferences.optString("touch_keyboard_layout", "twenty_six_key");
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed()) return;
                layout = value;
                render();
            });
        });
    }

    private void finishFlow() {
        markSeen(this);
        finish();
    }

    private void render() {
        LinearLayout column = findViewById(R.id.onboarding_page);
        column.removeAllViews();
        ((TextView) findViewById(R.id.onboarding_progress))
            .setText(getString(R.string.onboarding_progress, page + 1, PAGES));
        ((MaterialButton) findViewById(R.id.onboarding_next))
            .setText(page == PAGES - 1 ? R.string.onboarding_done : R.string.onboarding_next);
        findViewById(R.id.onboarding_previous).setVisibility(page == 0 ? View.GONE : View.VISIBLE);
        ((androidx.core.widget.NestedScrollView) findViewById(R.id.onboarding_scroll)).scrollTo(0, 0);
        switch (page) {
            case 0 -> welcome(column);
            case 1 -> choices(column);
            case 2 -> intelligence(column);
            default -> steps(column);
        }
    }

    private void welcome(LinearLayout column) {
        ShapeableImageView mark = new ShapeableImageView(this);
        mark.setImageResource(R.drawable.app_icon_classic);
        mark.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        LinearLayout.LayoutParams markParams =
            new LinearLayout.LayoutParams(pixels(88), pixels(88));
        markParams.topMargin = pixels(12);
        column.addView(mark, markParams);
        title(column, "水杉输入法", 30);
        subtitle(column, "让输入更自然，\n让表达更自在。");
        feature(column, R.drawable.ic_tab_keyboard, "熟悉的键盘，自由的选择",
            "全拼、九键、双拼、五笔与日语，按你的习惯开启。");
        feature(column, R.drawable.ic_feature_skin, "把键盘变成你的风格",
            "挑选皮肤、设计配色，也可以去社区发现更多作品。");
        feature(column, R.drawable.ic_about_feedback, "从打字到更好的表达",
            "AI 对话、高情商回复和语音服务，按需配置。");
        footnote(column, "日常输入无需登录。");
    }

    private void choices(LinearLayout column) {
        title(column, "从你熟悉的键盘开始", 24);
        subtitle(column, "先选一种，稍后可以在输入方案里调整全部方案。");
        choice(column, "twenty_six_key", "全拼 26 键", "完整字母，熟悉的输入手感");
        choice(column, "nine_key", "全拼 9 键", "大按键，单手输入更方便");
    }

    private void intelligence(LinearLayout column) {
        title(column, "输入之外，多一点灵感", 24);
        feature(column, R.drawable.ic_feature_ai, "高情商回复",
            "复制对方的话，在回复键盘中粘贴并选择回复风格，点选结果插入。");
        feature(column, R.drawable.ic_about_feedback, "边试键盘，边看效果",
            "试用键盘里可以直接打字，换皮肤和输入方案都能立刻看到。");
        action(column, "先试试键盘", R.drawable.ic_tab_keyboard,
            () -> startActivity(new Intent(this, KeyboardTryoutActivity.class)));
        footnote(column, "这些功能可以稍后设置。日常拼音输入保持离线，联网的功能由你主动触发。");
    }

    private void steps(LinearLayout column) {
        title(column, "启用水杉输入法", 24);
        subtitle(column, "三步就好，之后随时可以切回来。");
        step(column, 1, "打开键盘设置", "前往「设置 → 系统 → 语言和输入法 → 屏幕键盘」，或用下面那颗按钮。", true);
        step(column, 2, "启用水杉输入法", "在屏幕键盘列表里打开水杉输入法的开关，按提示确认。", true);
        step(column, 3, "切换并开始输入", "点任意输入框，再点右下角的键盘图标选择水杉输入法。", false);
        action(column, "打开系统键盘设置", R.drawable.ic_feature_system, () -> {
            try {
                startActivity(new Intent(Settings.ACTION_INPUT_METHOD_SETTINGS));
            } catch (RuntimeException error) {
                // 系统没有这一页就算了，上面三步已经写明了路径。
            }
        });
        footnote(column, "键盘默认离线。打字统计只保存在本机；AI 和语音可以在设置里单独配置。");
    }

    /** 两张卡二选一，选中的那张写进偏好——这一页是会改东西的，所以立刻生效。 */
    private void choice(LinearLayout column, String value, String name, String detail) {
        boolean selected = value.equals(layout);
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.HORIZONTAL);
        card.setGravity(Gravity.CENTER_VERTICAL);
        card.setPadding(pixels(18), pixels(16), pixels(18), pixels(16));
        GradientDrawable face = new GradientDrawable();
        face.setCornerRadius(pixels(20));
        face.setColor(ContextCompat.getColor(this, R.color.surface));
        if (selected) face.setStroke(pixels(2), ContextCompat.getColor(this, R.color.forest));
        card.setBackground(face);

        LinearLayout text = new LinearLayout(this);
        text.setOrientation(LinearLayout.VERTICAL);
        TextView heading = new TextView(this);
        heading.setText(name);
        heading.setTextSize(16);
        heading.setTypeface(heading.getTypeface(), Typeface.BOLD);
        heading.setTextColor(ContextCompat.getColor(this, R.color.ink));
        text.addView(heading);
        TextView body = new TextView(this);
        body.setText(detail);
        body.setTextSize(12);
        body.setTextColor(ContextCompat.getColor(this, R.color.text_secondary));
        text.addView(body);
        card.addView(text, new LinearLayout.LayoutParams(0,
            LinearLayout.LayoutParams.WRAP_CONTENT, 1));

        TextView tick = new TextView(this);
        tick.setText(selected ? "✓" : "");
        tick.setTextSize(18);
        tick.setTextColor(ContextCompat.getColor(this, R.color.forest));
        card.addView(tick);

        card.setContentDescription(name + "，" + detail + (selected ? "，已选择" : "，未选择"));
        card.setOnClickListener(ignored -> {
            layout = value;
            render();
            offMainThread(() ->
                HostStore.putPreference(getApplicationContext(), "touch_keyboard_layout", value));
        });
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        params.topMargin = pixels(12);
        column.addView(card, params);
    }

    /** 序号、标题、说明，序号之间连一条竖线，和母版一样。 */
    private void step(LinearLayout column, int number, String name, String detail, boolean line) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);

        LinearLayout rail = new LinearLayout(this);
        rail.setOrientation(LinearLayout.VERTICAL);
        rail.setGravity(Gravity.CENTER_HORIZONTAL);
        TextView badge = new TextView(this);
        badge.setText(String.valueOf(number));
        badge.setGravity(Gravity.CENTER);
        badge.setTextSize(15);
        badge.setTypeface(badge.getTypeface(), Typeface.BOLD);
        badge.setTextColor(ContextCompat.getColor(this, R.color.surface));
        GradientDrawable disc = new GradientDrawable();
        disc.setShape(GradientDrawable.OVAL);
        disc.setColor(ContextCompat.getColor(this, R.color.cone));
        badge.setBackground(disc);
        rail.addView(badge, new LinearLayout.LayoutParams(pixels(34), pixels(34)));
        if (line) {
            View thread = new View(this);
            thread.setBackgroundColor(ContextCompat.getColor(this, R.color.hairline));
            rail.addView(thread, new LinearLayout.LayoutParams(pixels(2), pixels(46)));
        }
        row.addView(rail);

        LinearLayout text = new LinearLayout(this);
        text.setOrientation(LinearLayout.VERTICAL);
        TextView heading = new TextView(this);
        heading.setText(name);
        heading.setTextSize(16);
        heading.setTypeface(heading.getTypeface(), Typeface.BOLD);
        heading.setTextColor(ContextCompat.getColor(this, R.color.ink));
        text.addView(heading);
        TextView body = new TextView(this);
        body.setText(detail);
        body.setTextSize(13);
        body.setTextColor(ContextCompat.getColor(this, R.color.text_secondary));
        LinearLayout.LayoutParams bodyParams = new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        bodyParams.topMargin = pixels(4);
        text.addView(body, bodyParams);
        LinearLayout.LayoutParams textParams = new LinearLayout.LayoutParams(0,
            LinearLayout.LayoutParams.WRAP_CONTENT, 1);
        textParams.leftMargin = pixels(14);
        row.addView(text, textParams);

        row.setContentDescription("第 " + number + " 步，" + name + "。" + detail);
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        params.topMargin = pixels(14);
        column.addView(row, params);
    }

    private void feature(LinearLayout column, @DrawableRes int icon, String name, String detail) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        ShapeableImageView badge = new ShapeableImageView(this);
        badge.setImageResource(icon);
        badge.setPadding(pixels(8), pixels(8), pixels(8), pixels(8));
        badge.setBackground(rounded(ContextCompat.getColor(this, R.color.badge_field), pixels(12)));
        badge.setImageTintList(android.content.res.ColorStateList.valueOf(
            ContextCompat.getColor(this, R.color.forest)));
        row.addView(badge, new LinearLayout.LayoutParams(pixels(36), pixels(36)));

        LinearLayout text = new LinearLayout(this);
        text.setOrientation(LinearLayout.VERTICAL);
        TextView heading = new TextView(this);
        heading.setText(name);
        heading.setTextSize(15);
        heading.setTypeface(heading.getTypeface(), Typeface.BOLD);
        heading.setTextColor(ContextCompat.getColor(this, R.color.ink));
        text.addView(heading);
        TextView body = new TextView(this);
        body.setText(detail);
        body.setTextSize(13);
        body.setTextColor(ContextCompat.getColor(this, R.color.text_secondary));
        LinearLayout.LayoutParams bodyParams = new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        bodyParams.topMargin = pixels(3);
        text.addView(body, bodyParams);
        LinearLayout.LayoutParams textParams = new LinearLayout.LayoutParams(0,
            LinearLayout.LayoutParams.WRAP_CONTENT, 1);
        textParams.leftMargin = pixels(14);
        row.addView(text, textParams);

        row.setContentDescription(name + "。" + detail);
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        params.topMargin = pixels(18);
        column.addView(row, params);
    }

    private void action(LinearLayout column, String label, @DrawableRes int icon, Runnable run) {
        MaterialButton button = new MaterialButton(this);
        button.setText(label);
        button.setIconResource(icon);
        button.setCornerRadius(pixels(16));
        button.setOnClickListener(ignored -> run.run());
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        params.topMargin = pixels(22);
        column.addView(button, params);
    }

    private void title(LinearLayout column, String text, int size) {
        TextView view = new TextView(this);
        view.setText(text);
        view.setTextSize(size);
        view.setTypeface(view.getTypeface(), Typeface.BOLD);
        view.setTextColor(ContextCompat.getColor(this, R.color.ink));
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        params.topMargin = pixels(18);
        column.addView(view, params);
    }

    private void subtitle(LinearLayout column, String text) {
        TextView view = new TextView(this);
        view.setText(text);
        view.setTextSize(16);
        view.setTextColor(ContextCompat.getColor(this, R.color.text_secondary));
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        params.topMargin = pixels(8);
        column.addView(view, params);
    }

    private void footnote(LinearLayout column, String text) {
        TextView view = new TextView(this);
        view.setText(text);
        view.setTextSize(12);
        view.setTextColor(ContextCompat.getColor(this, R.color.text_secondary));
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        params.topMargin = pixels(22);
        column.addView(view, params);
    }

    private static GradientDrawable rounded(int colour, int radius) {
        GradientDrawable shape = new GradientDrawable();
        shape.setCornerRadius(radius);
        shape.setColor(colour);
        return shape;
    }

    /**
     * 这一页的磁盘读写。
     *
     * <p>{@link HostTask} 只收 Fragment，而这是一个 Activity；这里要的只是「别在主线程上读盘」，
     * 所以起一条一次性的线程，回来前先看这一页还在不在。
     */
    private void offMainThread(Runnable work) {
        new Thread(() -> {
            try {
                work.run();
            } catch (RuntimeException | LinkageError error) {
                // 读不到偏好就按默认那张卡显示，这一页不该因此打不开。
            }
        }, "msime-onboarding").start();
    }

    private int pixels(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }
}
