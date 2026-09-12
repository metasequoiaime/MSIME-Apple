package app.msime.client.test;

import android.app.Activity;
import android.content.Intent;
import android.os.ParcelFileDescriptor;
import android.os.SystemClock;
import android.util.AtomicFile;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.WebView;
import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import org.json.JSONObject;

/** Drive the actual React DOM and Tauri IPC, then observe a separate system editor. */
public final class SettingsDeviceSmoke extends DeviceSmoke {
    private static final String PUNCTUATION_CHECKBOX =
        "Array.from(document.querySelectorAll('label')).find(label => "
        + "label.textContent?.includes('中文标点'))?.querySelector('input[type=checkbox]')";
    private static final String RELOAD_BUTTON =
        "Array.from(document.querySelectorAll('button')).find(button => "
        + "button.textContent?.trim() === '重新读取')";
    private static final String QUANPIN_TOGGLE =
        "document.querySelector('[aria-label=\"显示输入方案 全拼 26 键\"]')";
    private static final String NINE_KEY_TOGGLE =
        "document.querySelector('[aria-label=\"显示输入方案 全拼 9 键\"]')";
    private static final String QUANPIN_SELECT =
        "document.querySelector('[aria-label=\"设为当前输入方案 全拼 26 键\"]')";
    private static final String NINE_KEY_SELECT =
        "document.querySelector('[aria-label=\"设为当前输入方案 全拼 9 键\"]')";
    private WebView web;
    @Override protected String successDescription() { return "React save, scheme visibility fallback, persistence and cross-process IME application"; }
    @Override protected void runChecks() throws Exception {
        File root = getTargetContext().getFilesDir();
        JSONObject options = new JSONObject(new String(Files.readAllBytes(new File(root, "runtime-options.json").toPath()), StandardCharsets.UTF_8));
        File directory = new File(options.getString("preferences_directory")).getCanonicalFile();
        if (!directory.toPath().startsWith(root.getCanonicalFile().toPath())) throw new AssertionError("Preferences escaped the preview sandbox");
        File preferences = new File(directory, "preferences.json");
        byte[] original = preferences.exists() ? Files.readAllBytes(preferences.toPath()) : null;
        long revision = original == null ? 0 : new JSONObject(new String(original, StandardCharsets.UTF_8)).getLong("revision");
        Activity activity = null;
        try {
            stage = "React settings load";
            Intent intent = new Intent().setClassName(getTargetContext(), "app.msime.client.preview.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            activity = startActivitySync(intent);
            Activity owner = activity;
            long deadline = SystemClock.uptimeMillis() + 15000;
            do {
                runOnMainSync(() -> web = findWebView(owner.getWindow().getDecorView()));
                if (web != null) break;
                SystemClock.sleep(100);
            } while (SystemClock.uptimeMillis() < deadline);
            if (web == null) throw new AssertionError("Tauri WebView not created");
            awaitJs("!!(" + PUNCTUATION_CHECKBOX + ")");
            boolean before = "true".equals(js("(" + PUNCTUATION_CHECKBOX + ").checked"));
            stage = "React touch scheme settings";
            js("Array.from(document.querySelectorAll('button')).find(button => button.textContent?.trim() === '输入').click(); true");
            awaitJs("!!(" + NINE_KEY_TOGGLE + ")");
            awaitJs("JSON.stringify(Array.from(document.querySelectorAll('.touch-keyboard-scheme-select')).map(button => button.textContent.replace('✓', '')))"
                + " === JSON.stringify(['全拼 26 键','全拼 9 键','小鹤双拼','自然码双拼','微软双拼','首道双拼','86 五笔','日语 9 键','日语 26 键','手写','高情商回复'])");
            if (!"true".equals(js("(" + QUANPIN_TOGGLE + ").checked")))
                js("(" + QUANPIN_TOGGLE + ").click(); true");
            if (!"true".equals(js("(" + NINE_KEY_TOGGLE + ").checked")))
                js("(" + NINE_KEY_TOGGLE + ").click(); true");
            js("(" + NINE_KEY_SELECT + ").click(); true");
            awaitJs("(" + NINE_KEY_SELECT + ").getAttribute('aria-pressed') === 'true'");
            js("(" + NINE_KEY_TOGGLE + ").click(); true");
            awaitJs("!(" + NINE_KEY_TOGGLE + ").checked && (" + NINE_KEY_SELECT
                + ").disabled && (" + QUANPIN_SELECT + ").getAttribute('aria-pressed') === 'true'");
            stage = "React save through Tauri";
            js("(" + PUNCTUATION_CHECKBOX + ").click(); true");
            awaitJs("!document.querySelector('button[type=submit]').disabled");
            js("document.querySelector('button[type=submit]').click(); true");
            awaitJs("document.querySelector('[role=status]')?.textContent === '设置已保存。'");
            JSONObject saved = new JSONObject(new String(Files.readAllBytes(preferences.toPath()), StandardCharsets.UTF_8));
            if (saved.getLong("revision") != revision + 1 || saved.getJSONObject("preferences").getBoolean("chinese_punctuation") == before) throw new AssertionError("React save did not reach shared storage");
            JSONObject savedPreferences = saved.getJSONObject("preferences");
            JSONObject touchSchemes = savedPreferences.getJSONObject("touch_keyboard_schemes");
            if (!"quanpin".equals(touchSchemes.getString("selected")))
                throw new AssertionError("Shared selected scheme did not use the fallback");
            for (int index = 0; index < touchSchemes.getJSONArray("enabled").length(); index++) {
                if ("nine_key".equals(touchSchemes.getJSONArray("enabled").getString(index)))
                    throw new AssertionError("Hidden scheme remained enabled in shared storage");
            }
            if (!"quanpin".equals(savedPreferences.getString("scheme")))
                throw new AssertionError("Engine scheme did not use the fallback");
            if (!"twenty_six_key".equals(savedPreferences.getString("touch_keyboard_layout")))
                throw new AssertionError("Touch layout did not use the fallback");
            stage = "React reload";
            js("(" + RELOAD_BUTTON + ").click(); true");
            awaitJs("!(" + RELOAD_BUTTON + ").disabled && ("
                + PUNCTUATION_CHECKBOX + ").checked === " + !before);
            stage = "cross-process system input uses saved preferences";
            shell("ime disable app.msime.client.preview/app.msime.client.MSIMEInputService");
            shell("ime enable app.msime.client.preview/app.msime.client.MSIMEInputService");
            shell("ime set app.msime.client.preview/app.msime.client.MSIMEInputService");
            SystemClock.sleep(1000);
            shell("am start -W -f 0x10008000 -n app.msime.client.test/app.msime.client.test.EditorActivity");
            tap(field("msime-test-plain"));
            for (String key : new String[] {"n", "i", "h", "a", "o"}) tap(key(key));
            tapSymbol(",");
            String expected = before ? "你好," : "你好，";
            await(field("msime-test-plain").and(node -> equalsText(expected, node.getText())));
            stage = "cross-process scheme picker uses shared visibility";
            assertSharedSchemePicker();
            stage = "scheme visibility survives IME restart";
            shell("am start -W -n app.msime.client.preview/app.msime.client.SetupActivity");
            shell("ime disable app.msime.client.preview/app.msime.client.MSIMEInputService");
            shell("ime enable app.msime.client.preview/app.msime.client.MSIMEInputService");
            shell("ime set app.msime.client.preview/app.msime.client.MSIMEInputService");
            SystemClock.sleep(1000);
            shell("am start -W -f 0x10008000 -n app.msime.client.test/app.msime.client.test.EditorActivity");
            tap(field("msime-test-plain"));
            assertSharedSchemePicker();
        } finally {
            shell("am start -W -n app.msime.client.preview/app.msime.client.SetupActivity");
            if (original == null) Files.deleteIfExists(preferences.toPath()); else publish(preferences, original);
        }
    }
    private void assertSharedSchemePicker() throws Exception {
        String prefix = stage;
        stage = prefix + ": open picker";
        tap(node -> equalsText("app.msime.client.preview", node.getPackageName())
            && equalsText("输入方案：全拼 26 键", node.getContentDescription()));
        stage = prefix + ": selected fallback card";
        await(node -> equalsText("app.msime.client.preview", node.getPackageName())
            && equalsText("输入方案卡片 全拼 26 键", node.getContentDescription())
            && equalsText("已选中", node.getStateDescription()));
        stage = prefix + ": hidden card absence";
        for (var window : automation.getWindows()) {
            if (find(window.getRoot(), node -> equalsText("app.msime.client.preview", node.getPackageName())
                    && equalsText("输入方案卡片 全拼 9 键", node.getContentDescription())) != null) {
                throw new AssertionError("Hidden scheme remained in the keyboard picker");
            }
        }
        stage = prefix + ": return to keyboard";
        tap(node -> equalsText("app.msime.client.preview", node.getPackageName())
            && equalsText("返回键盘", node.getContentDescription()));
    }
    private WebView findWebView(View view) {
        if (view instanceof WebView) return (WebView) view;
        if (view instanceof ViewGroup) {
            ViewGroup group = (ViewGroup) view;
            for (int index = 0; index < group.getChildCount(); index++) {
                WebView found = findWebView(group.getChildAt(index));
                if (found != null) return found;
            }
        }
        return null;
    }
    private String js(String expression) throws Exception {
        CountDownLatch completed = new CountDownLatch(1);
        AtomicReference<String> result = new AtomicReference<>();
        runOnMainSync(() -> web.evaluateJavascript(expression, value -> { result.set(value); completed.countDown(); }));
        if (!completed.await(15, TimeUnit.SECONDS)) throw new AssertionError("WebView response timed out");
        return result.get();
    }
    private void awaitJs(String condition) throws Exception {
        long deadline = SystemClock.uptimeMillis() + 15000;
        do { if ("true".equals(js(condition))) return; SystemClock.sleep(100); } while (SystemClock.uptimeMillis() < deadline);
        throw new AssertionError("Expected React state was not observed");
    }
    private void shell(String command) throws Exception {
        try (var input = new ParcelFileDescriptor.AutoCloseInputStream(automation.executeShellCommand(command))) {
            byte[] buffer = new byte[1024];
            while (input.read(buffer) != -1) { }
        }
    }
    private void publish(File file, byte[] contents) throws Exception {
        AtomicFile target = new AtomicFile(file);
        FileOutputStream output = target.startWrite();
        try { output.write(contents); target.finishWrite(output); }
        catch (Exception error) { target.failWrite(output); throw error; }
    }
}
