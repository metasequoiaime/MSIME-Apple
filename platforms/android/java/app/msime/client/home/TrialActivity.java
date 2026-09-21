package app.msime.client.home;

import android.content.Intent;
import android.os.Bundle;
import android.provider.Settings;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.inputmethod.InputMethodInfo;
import android.view.inputmethod.InputMethodManager;
import android.widget.TextView;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsCompat;
import app.msime.client.R;
import com.google.android.material.appbar.MaterialToolbar;
import com.google.android.material.button.MaterialButton;
import com.google.android.material.textfield.TextInputEditText;

/**
 * 试用键盘：一个能打字的地方，外加此刻挡在前面的那一步。
 *
 * <p>Trying the keyboard from inside the app that configures it is the whole point of this screen,
 * and what stops it is never the same thing twice: the input method may not be enabled in system
 * settings, or it may be enabled but not the current one. The card says which of those it is and
 * offers exactly that step, instead of always opening the picker and leaving a user who has not
 * enabled the keyboard yet to find an empty list.
 */
public final class TrialActivity extends AppCompatActivity {
    private static final String SERVICE = "app.msime.client.MSIMEInputService";

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        WindowCompat.setDecorFitsSystemWindows(getWindow(), false);
        setContentView(R.layout.activity_trial);

        ViewCompat.setOnApplyWindowInsetsListener(findViewById(R.id.trial_root),
            (view, windowInsets) -> {
                Insets bars = windowInsets.getInsets(
                    WindowInsetsCompat.Type.systemBars() | WindowInsetsCompat.Type.ime());
                view.setPadding(bars.left, bars.top, bars.right, bars.bottom);
                return windowInsets;
            });

        MaterialToolbar toolbar = findViewById(R.id.trial_toolbar);
        toolbar.setNavigationOnClickListener(ignored -> finish());

        TextInputEditText input = findViewById(R.id.trial_input);
        TextView counter = findViewById(R.id.trial_counter);
        counter.setText("已输入 0 个字符");
        input.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence text, int start, int count,
                    int after) {}

            @Override public void onTextChanged(CharSequence text, int start, int before,
                    int count) {}

            @Override public void afterTextChanged(Editable text) {
                // 只数这一框里的字符，不写入任何地方：真正的统计由键盘自己记。
                counter.setText("已输入 " + text.toString().codePointCount(0, text.length())
                    + " 个字符");
            }
        });
        input.requestFocus();
    }

    @Override protected void onResume() {
        super.onResume();
        renderAvailability();
    }

    private void renderAvailability() {
        TextView hint = findViewById(R.id.trial_hint);
        MaterialButton action = findViewById(R.id.trial_action);
        InputMethodManager manager = getSystemService(InputMethodManager.class);
        if (manager == null) {
            hint.setText("系统没有提供输入法服务，无法在这里试用。");
            action.setVisibility(MaterialButton.GONE);
            return;
        }
        if (!enabled(manager)) {
            hint.setText("水杉输入法还没有在系统设置里启用。启用之后回到这里，长按输入框上的地球键就能切过来。");
            action.setText("去系统设置启用");
            action.setVisibility(MaterialButton.VISIBLE);
            action.setOnClickListener(ignored ->
                startActivity(new Intent(Settings.ACTION_INPUT_METHOD_SETTINGS)));
            return;
        }
        hint.setText("长按地球键切换到水杉输入法，然后试试你的皮肤、输入方案和模糊音。这里输入的内容不会被保存，也不会上传。");
        action.setText("切换输入法");
        action.setVisibility(MaterialButton.VISIBLE);
        action.setOnClickListener(ignored -> manager.showInputMethodPicker());
    }

    /** Whether this host is in the system's enabled list, rather than merely installed. */
    private boolean enabled(InputMethodManager manager) {
        for (InputMethodInfo info : manager.getEnabledInputMethodList()) {
            if (getPackageName().equals(info.getPackageName())
                && SERVICE.equals(info.getServiceName())) return true;
        }
        return false;
    }
}
