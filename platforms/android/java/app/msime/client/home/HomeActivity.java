package app.msime.client.home;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.provider.Settings;
import android.view.Gravity;
import android.view.View;
import android.view.inputmethod.InputMethodManager;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import app.msime.client.SetupActivity;
import app.msime.client.WindowLayout;

/**
 * The host app: four tabs over one content area, matching the Apple app's shell.
 *
 * Resource preparation still belongs to {@link SetupActivity}; this screen does not duplicate it and
 * does not enable the input method. The remaining three tabs land in later changes, so they say so
 * rather than showing an empty page -- an empty page reads as a failure.
 */
public final class HomeActivity extends Activity {
    private FrameLayout content;
    private TabBar tabs;

    @Override protected void onCreate(Bundle state) {
        WindowLayout.theme(this);
        super.onCreate(state);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Theme.MIST);
        WindowLayout.fitSystemBars(root);

        ScrollView scroller = new ScrollView(this);
        scroller.setFillViewport(true);
        content = new FrameLayout(this);
        // Room for the floating tab bar, which overlaps the scroller's last child otherwise.
        content.setClipToPadding(false);
        content.setPadding(0, 0, 0, Theme.dp(this, 76));
        scroller.addView(content, new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT));
        root.addView(scroller, new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f));

        tabs = new TabBar(this);
        tabs.setOnSelect(this::show);
        LinearLayout.LayoutParams tabParams = new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        int side = Theme.dp(this, 12);
        tabParams.setMargins(side, 0, side, Theme.dp(this, 10));
        root.addView(tabs, tabParams);

        setContentView(root);
        show(TabBar.Page.KEYBOARD);
    }

    private void show(TabBar.Page page) {
        content.removeAllViews();
        content.addView(page == TabBar.Page.KEYBOARD ? keyboardPage() : placeholder(page));
    }

    private View keyboardPage() {
        // The names the card shows come from the prepared preferences once that reader lands; until
        // then they are the shipped defaults rather than invented values.
        return KeyboardPage.create(this, "水杉绿", "全拼 9 键", new KeyboardPage.Actions() {
            @Override public void tryKeyboard() {
                ((InputMethodManager) getSystemService(INPUT_METHOD_SERVICE)).showInputMethodPicker();
            }
            @Override public void openSystemSettings() {
                startActivity(new Intent(Settings.ACTION_INPUT_METHOD_SETTINGS));
            }
        });
    }

    private View placeholder(TabBar.Page page) {
        LinearLayout column = new LinearLayout(this);
        column.setOrientation(LinearLayout.VERTICAL);
        column.setGravity(Gravity.CENTER);
        int pad = Theme.dp(this, 32);
        column.setPadding(pad, pad, pad, pad);
        column.addView(Tiles.text(this, page.title, 22f, Theme.INK, true));
        column.addView(Tiles.text(this, "这一页还没有搬到 Android，先在这里占位。", 14f, Theme.TEXT_SECONDARY, false));
        return column;
    }

    /** Resource preparation and the input-method pickers stay where they were. */
    public void openSetup() { startActivity(new Intent(this, SetupActivity.class)); }
}
