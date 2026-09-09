package app.msime.client.test;

import android.app.Activity;
import android.os.Bundle;
import android.text.InputType;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;
import app.msime.client.WindowLayout;

/** Separate synthetic editor app: tests the system InputConnection, not a mock. */
public final class EditorActivity extends Activity {
    @Override public void onCreate(Bundle state) {
        WindowLayout.theme(this);
        super.onCreate(state);
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        WindowLayout.fitSystemBars(layout);
        TextView title = new TextView(this);
        title.setText("MSIME synthetic editor fixture");
        layout.addView(title);
        EditText plain = new EditText(this);
        plain.setInputType(InputType.TYPE_CLASS_TEXT);
        plain.setContentDescription("msime-test-plain");
        plain.setHint("Plain editor");
        layout.addView(plain);
        EditText password = new EditText(this);
        password.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
        password.setContentDescription("msime-test-password");
        password.setHint("Password editor");
        layout.addView(password);
        setContentView(layout);
    }
}
