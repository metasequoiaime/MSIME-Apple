package app.msime.client.home;

import android.os.Bundle;
import androidx.activity.OnBackPressedCallback;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsCompat;
import androidx.fragment.app.Fragment;
import androidx.fragment.app.FragmentManager;
import androidx.fragment.app.FragmentTransaction;
import app.msime.client.CommunityRequest;
import app.msime.client.R;
import com.google.android.material.bottomnavigation.BottomNavigationView;

/**
 * The host app: four tabs over one fragment container, matching the Apple app's shell.
 *
 * Resource preparation stays in SetupActivity; this screen does not duplicate it and never enables
 * the input method on the user's behalf.
 *
 * Each tab is created once and then hidden rather than replaced. Replacing tore the page down on
 * every switch: coming back to 社区 re-fetched the listing over the network and threw away how far
 * the user had scrolled, and 统计 forgot which of its four segments was open.
 */
public final class HomeActivity extends AppCompatActivity {
    private static final String STATE_TAB = "home-tab";
    private static final int FIRST_TAB = R.id.tab_keyboard;
    private static final int[] TAB_IDS = {
        R.id.tab_keyboard, R.id.tab_community, R.id.tab_statistics, R.id.tab_account,
    };

    private BottomNavigationView tabs;
    private OnBackPressedCallback back;
    private int selected = FIRST_TAB;
    @Nullable private CommunityRequest.Kind pendingKind;
    /** A tab whose kept instance is stale and has to be built again on the next switch to it. */
    private int rebuild;

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

        // Back returns to the first tab before it leaves the app, which is what a bottom bar leads
        // the user to expect. On the first tab the callback is off and the system default runs, so
        // leaving still gets the platform's own back animation rather than a bare finish().
        back = new OnBackPressedCallback(false) {
            @Override public void handleOnBackPressed() { tabs.setSelectedItemId(FIRST_TAB); }
        };
        getOnBackPressedDispatcher().addCallback(this, back);

        if (state != null) selected = state.getInt(STATE_TAB, FIRST_TAB);
        tabs.setOnItemSelectedListener(item -> {
            show(item.getItemId());
            return true;
        });
        show(selected);
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

    /**
     * Switch to the community tab and open it on one kind of work.
     *
     * <p>The kept instance is discarded for this: which kind the tab opens on is an argument, and
     * the one on screen is showing another.
     */
    public void openCommunity(CommunityRequest.Kind kind) {
        pendingKind = kind;
        rebuild = R.id.tab_community;
        if (selected == R.id.tab_community) show(R.id.tab_community);
        else openTab(R.id.tab_community);
    }

    private void show(int itemId) {
        selected = itemId;
        back.setEnabled(itemId != FIRST_TAB);
        FragmentManager manager = getSupportFragmentManager();
        FragmentTransaction transaction = manager.beginTransaction();
        for (int id : TAB_IDS) {
            Fragment page = manager.findFragmentByTag(tag(id));
            if (id != itemId) {
                if (page != null && !page.isHidden()) transaction.hide(page);
                continue;
            }
            // Removing and adding in one transaction rather than committing the removal on its own:
            // a synchronous commit here can land on top of a tab switch that has not run yet.
            if (page != null && rebuild == id) {
                transaction.remove(page);
                page = null;
            }
            if (page == null) transaction.add(R.id.home_content, create(id), tag(id));
            else transaction.show(page);
        }
        rebuild = 0;
        transaction.commit();
    }

    private Fragment create(int itemId) {
        if (itemId == R.id.tab_community) {
            CommunityRequest.Kind kind = pendingKind;
            pendingKind = null;
            return CommunityFragment.forKind(kind);
        }
        if (itemId == R.id.tab_statistics) return new StatisticsFragment();
        if (itemId == R.id.tab_account) return new AccountFragment();
        return new KeyboardFragment();
    }

    private static String tag(int itemId) { return "home-tab-" + itemId; }
}
