package app.msime.client;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import android.provider.Settings;
import android.view.inputmethod.InputMethodManager;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;
import java.lang.ref.WeakReference;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Development launcher for first resource preparation, never auto-enables this IME. */
public final class SetupActivity extends Activity {
    private static final ExecutorService WORKER = Executors.newSingleThreadExecutor();
    @Override public void onCreate(Bundle state) {
        WindowLayout.theme(this);
        super.onCreate(state);
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        WindowLayout.fitSystemBars(layout);
        TextView status = new TextView(this);
        status.setText("MSIME 开发预览：先准备内置词库，再由你手动启用输入法。现有配置不会被覆盖。");
        layout.addView(status);
        Button prepare = new Button(this);
        prepare.setText("准备词库");
        layout.addView(prepare);
        Context context = getApplicationContext();
        WeakReference<SetupActivity> owner = new WeakReference<>(this);
        prepare.setOnClickListener(ignored -> {
            prepare.setEnabled(false);
            status.setText("正在校验与准备词库，请稍候…");
            WORKER.execute(() -> {
                String outcome;
                try { outcome = Bootstrap.prepare(context) ? "资源准备完成。可手动启用并选择 MSIME Preview。" : "检测到已有配置，未覆盖；如输入异常，请保留数据并检查配置。"; }
                catch (Exception | LinkageError error) {
                    // Bootstrap has no editor/session input; never use this logging for keystrokes.
                    android.util.Log.e("MSIMEBootstrap", "First-install resource preparation failed", error);
                    outcome = "准备失败，未发布新配置；请检查存储空间与开发包。可重试。";
                }
                final String result = outcome;
                SetupActivity activity = owner.get();
                if (activity != null) activity.runOnUiThread(() -> {
                    if (activity.isDestroyed()) return;
                    status.setText(result);
                    prepare.setEnabled(true);
                });
            });
        });
        Button settings = new Button(this);
        settings.setText("打开系统输入法设置");
        settings.setOnClickListener(ignored -> startActivity(new Intent(Settings.ACTION_INPUT_METHOD_SETTINGS)));
        layout.addView(settings);
        Button picker = new Button(this);
        picker.setText("选择输入法");
        picker.setOnClickListener(ignored -> ((InputMethodManager)getSystemService(INPUT_METHOD_SERVICE)).showInputMethodPicker());
        layout.addView(picker);
        Intent sharedSettings = new Intent().setClassName(getPackageName(), getPackageName() + ".MainActivity");
        if (sharedSettings.resolveActivity(getPackageManager()) != null) {
            Button settingsPage = new Button(this);
            settingsPage.setText("打开共享设置");
            settingsPage.setOnClickListener(ignored -> { startActivity(sharedSettings); finish(); });
            layout.addView(settingsPage);
        }
        setContentView(layout);
    }
}
