package app.msime.client.home;

import android.os.Bundle;
import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsCompat;
import androidx.fragment.app.Fragment;
import app.msime.client.CommunityRequest;
import app.msime.client.R;
import com.google.android.material.bottomnavigation.BottomNavigationView;

/**
 * The host app: four tabs over one fragment container, matching the Apple app's shell.
 *
 * Resource preparation stays in SetupActivity; this screen does not duplicate it and never enables
 * the input method on the user's behalf.
 */
public final class HomeActivity extends AppCompatActivity {
    private static final String STATE_TAB = "home-tab";

    private BottomNavigationView tabs;
    private int selected = R.id.tab_keyboard;
    private CommunityRequest.Kind pendingKind;

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        WindowCompat.setDecorFitsSystemWindows(getWindow(), false);
        setContentView(R.layout.activity_home);

        tabs = findViewById(R.id.home_tabs);
        // Edge-to-edge is enforced from Android 15, so the bars' insets are applied rather than
        // assumed: the tab bar keeps clear of the gesture area and the content of the status bar.
        ViewCompat.setOnApplyWindowInsetsListener(findViewById(R.id.home_root), (view, windowInsets) -> {
            Insets bars = windowInsets.getInsets(WindowInsetsCompat.Type.systemBars());
            view.setPadding(bars.left, bars.top, bars.right, 0);
            tabs.setPadding(0, 0, 0, bars.bottom);
            return windowInsets;
        });

        tabs.setOnItemSelectedListener(item -> {
            selected = item.getItemId();
            show(pageFor(selected));
            return true;
        });
        if (state != null) selected = state.getInt(STATE_TAB, R.id.tab_keyboard);
        if (state == null) show(pageFor(selected));
        tabs.setSelectedItemId(selected);
    }

    @Override protected void onSaveInstanceState(@NonNull Bundle state) {
        super.onSaveInstanceState(state);
        state.putInt(STATE_TAB, selected);
    }

    /** Switch to one of the four tabs, as a row on another tab can ask to. */
    public void openTab(int itemId) {
        if (tabs != null) tabs.setSelectedItemId(itemId);
    }

    /** Switch to the community tab and open it on one kind of work. */
    public void openCommunity(CommunityRequest.Kind kind) {
        pendingKind = kind;
        if (selected == R.id.tab_community) {
            // Already there, so the tab listener will not fire; replace the page directly.
            show(pageFor(R.id.tab_community));
            return;
        }
        openTab(R.id.tab_community);
    }

    private Fragment pageFor(int itemId) {
        if (itemId == R.id.tab_community) {
            CommunityRequest.Kind kind = pendingKind;
            pendingKind = null;
            return CommunityFragment.forKind(kind);
        }
        if (itemId == R.id.tab_statistics) return new StatisticsFragment();
        if (itemId == R.id.tab_account) return new AccountFragment();
        return new KeyboardFragment();
    }

    private void show(@NonNull Fragment page) {
        getSupportFragmentManager().beginTransaction().replace(R.id.home_content, page).commit();
    }
}
