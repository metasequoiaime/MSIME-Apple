package app.msime.client.home;

import android.os.Bundle;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.View;
import android.view.inputmethod.InputMethodManager;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsCompat;
import com.google.android.material.appbar.MaterialToolbar;
import com.google.android.material.button.MaterialButton;
import com.google.android.material.textfield.TextInputEditText;
import app.msime.client.R;

/**
 * 试用键盘: an editor that exists only so the keyboard can be raised against it, matching the Apple
 * app's tryout screen.
 *
 * The keyboard here is the real input method bound to this editor, not the still preview on the
 * 键盘 tab. Nothing typed is read, stored or sent anywhere; the field is a scratch surface.
 */
public final class KeyboardTryoutActivity extends AppCompatActivity {

    /** The Apple screen's draft limit, kept so the two platforms bound the same way. */
    private static final int DRAFT_LIMIT = 2000;

    @Override protected void onCreate(@Nullable Bundle state) {
        super.onCreate(state);
        WindowCompat.setDecorFitsSystemWindows(getWindow(), false);
        setContentView(R.layout.activity_keyboard_tryout);

        View root = findViewById(R.id.tryout_root);
        // The keyboard is the point of this screen, so its inset is applied rather than assumed:
        // the field has to stay above the input view as it is raised and dismissed.
        ViewCompat.setOnApplyWindowInsetsListener(root, (view, windowInsets) -> {
            Insets bars = windowInsets.getInsets(WindowInsetsCompat.Type.systemBars());
            Insets ime = windowInsets.getInsets(WindowInsetsCompat.Type.ime());
            view.setPadding(bars.left, bars.top, bars.right, Math.max(bars.bottom, ime.bottom));
            return windowInsets;
        });

        MaterialToolbar bar = findViewById(R.id.tryout_bar);
        bar.setNavigationOnClickListener(ignored -> finish());

        TextInputEditText field = findViewById(R.id.tryout_field);
        MaterialButton dismiss = findViewById(R.id.tryout_dismiss);

        // The system picker belongs here rather than on the 键盘 tab: it is only useful once the
        // user is in front of an editor and finds another keyboard came up.
        MaterialButton switchIme = findViewById(R.id.tryout_switch);
        switchIme.setOnClickListener(ignored ->
            getSystemService(InputMethodManager.class).showInputMethodPicker());

        // 收起键盘 only means something while the keyboard is up, as on Apple.
        dismiss.setVisibility(View.GONE);
        dismiss.setOnClickListener(ignored -> {
            field.clearFocus();
            getSystemService(InputMethodManager.class).hideSoftInputFromWindow(field.getWindowToken(), 0);
        });
        field.setOnFocusChangeListener((view, focused) ->
            dismiss.setVisibility(focused ? View.VISIBLE : View.GONE));

        field.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) { }
            @Override public void onTextChanged(CharSequence s, int start, int before, int count) { }
            @Override public void afterTextChanged(@NonNull Editable text) {
                if (text.length() > DRAFT_LIMIT) text.delete(DRAFT_LIMIT, text.length());
            }
        });

        // Opening the screen is the user asking for the keyboard, so it is raised without a tap.
        field.requestFocus();
        WindowCompat.getInsetsController(getWindow(), field).show(WindowInsetsCompat.Type.ime());
    }
}
