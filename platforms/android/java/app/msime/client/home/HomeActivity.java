package app.msime.client.home;

import android.os.Bundle;
import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsCompat;
import androidx.fragment.app.Fragment;
import com.google.android.material.bottomnavigation.BottomNavigationView;
import app.msime.client.FirstRunPreparation;
import app.msime.client.R;

/**
 * The host app: four tabs over one fragment container, matching the Apple app's shell.
 *
 * Resource preparation stays in SetupActivity; this screen does not duplicate it and never enables
 * the input method on the user's behalf.
 */
public final class HomeActivity extends AppCompatActivity {

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        WindowCompat.setDecorFitsSystemWindows(getWindow(), false);
        setContentView(R.layout.activity_home);

        BottomNavigationView tabs = findViewById(R.id.home_tabs);
        // Edge-to-edge is enforced from Android 15, so the bars' insets are applied rather than
        // assumed: the tab bar keeps clear of the gesture area and the content of the status bar.
        ViewCompat.setOnApplyWindowInsetsListener(findViewById(R.id.home_root), (view, windowInsets) -> {
            Insets bars = windowInsets.getInsets(WindowInsetsCompat.Type.systemBars());
            view.setPadding(bars.left, bars.top, bars.right, 0);
            tabs.setPadding(0, 0, 0, bars.bottom);
            return windowInsets;
        });

        tabs.setOnItemSelectedListener(item -> {
            show(pageFor(item.getItemId()));
            return true;
        });
        if (state == null) show(new KeyboardFragment());

        // The shipped dictionary is prepared on first run without the user having to find a button
        // for it: a keyboard that cannot reach the Engine is not a state worth making someone opt
        // out of. Existing configurations are reported, never overwritten.
        FirstRunPreparation.startIfNeeded(this);
    }

    private Fragment pageFor(int itemId) {
        if (itemId == R.id.tab_community) return new CommunityFragment();
        if (itemId == R.id.tab_statistics) return new StatisticsFragment();
        if (itemId == R.id.tab_account) return new AccountFragment();
        return new KeyboardFragment();
    }

    private void show(@NonNull Fragment page) {
        getSupportFragmentManager().beginTransaction().replace(R.id.home_content, page).commit();
    }
}
