package app.msime.client;

import android.inputmethodservice.InputMethodService;
import android.os.Handler;
import android.os.Looper;
import android.os.Build;
import android.view.View;
import android.view.KeyEvent;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.HorizontalScrollView;
import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

/** Preview system host. No algorithms, pagination state or persistent input logs live here. */
public final class MSIMEInputService extends InputMethodService {
    private long session;
    private InputConnection connection;
    private EditorBridge bridge = new EditorBridge();
    private JSONObject view;
    private LinearLayout candidates;
    private TextView status;
    private String message = "MSIME Preview";
    private boolean shift;
    private boolean allowLearning;
    private String preferencesNotice = "";
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService preferencesWorker = Executors.newSingleThreadExecutor();
    private final PreferencesReloader preferencesReloader = new PreferencesReloader(
        (task, delay) -> main.postDelayed(task, delay), preferencesWorker, NativeClient::loadPreferences);

    private JSONObject value(String response) throws JSONException {
        JSONObject envelope = new JSONObject(response);
        if (!envelope.getBoolean("ok")) throw new JSONException("Shared runtime rejected operation");
        return envelope.getJSONObject("value");
    }

    private EditorBridge.Sink sink() {
        final InputConnection target = connection;
        return new EditorBridge.Sink() {
            public void begin() { target.beginBatchEdit(); }
            public boolean commit(String text) { return target.commitText(text, 1); }
            public boolean compose(String text) { return target.setComposingText(text, 1); }
            public boolean finish() { return target.finishComposingText(); }
            public void end() { target.endBatchEdit(); }
        };
    }

    @Override public void onStartInput(EditorInfo info, boolean restarting) {
        super.onStartInput(info, restarting);
        stop(false);
        connection = getCurrentInputConnection();
        bridge = new EditorBridge();
        shift = false;
        allowLearning = info != null && EditorPolicy.allowLearning(info.imeOptions);
        preferencesNotice = "";
        message = "直接输入";
        if (info != null && connection != null && EditorPolicy.useEngine(info.inputType)) {
            try {
                File file = new File(getFilesDir(), "runtime-options.json");
                if (file.length() > 16384) throw new IllegalArgumentException("Options too large");
                JSONObject options = new JSONObject(new String(Files.readAllBytes(file.toPath()), StandardCharsets.UTF_8));
                if (!allowLearning) options.getJSONObject("preferences").put("learning", false);
                view = value(NativeClient.create(options.toString()));
                session = view.getLong("session");
                apply(NativeClient.focus(session, true));
                message = "MSIME Preview";
                String directory = options.optString("preferences_directory", "");
                if (!directory.isEmpty() && new File(directory).isAbsolute()) preferencesReloader.start(directory, this::reloadPreferences);
            } catch (Exception | LinkageError error) {
                stop(false);
                message = "共享运行时未就绪：仅直接输入";
            }
        }
        render();
    }

    @Override public void onFinishInput() { stop(true); connection = null; super.onFinishInput(); }
    @Override public void onDestroy() { stop(false); preferencesWorker.shutdown(); connection = null; super.onDestroy(); }
    @Override public boolean onEvaluateFullscreenMode() { return false; }

    private void stop(boolean finish) {
        preferencesReloader.stop();
        if (session != 0) {
            try { if (finish && connection != null) apply(NativeClient.command(session, 9)); }
            catch (Exception | LinkageError ignored) { /* Never log editor text or native responses. */ }
            try { NativeClient.destroy(session); } catch (LinkageError ignored) { }
            session = 0;
        }
        if (connection != null) bridge.abandon(sink());
        view = null;
    }

    private void reloadPreferences(String response) {
        if (session == 0) return;
        String previousView = view == null ? "" : view.toString();
        String previousNotice = preferencesNotice;
        try {
            if (response == null) throw new JSONException("Preferences unavailable");
            JSONObject snapshot = value(response);
            // Editor privacy restrictions apply to every update, not only creation.
            if (!allowLearning) snapshot.getJSONObject("preferences").put("learning", false);
            JSONObject result = value(NativeClient.updatePreferences(session, snapshot.toString()));
            view = result.getJSONObject("view");
            preferencesNotice = result.getBoolean("deferred") ? " · 设置将在组词结束后应用" : "";
        } catch (JSONException | LinkageError error) {
            // Never replace the working session or log preferences/native responses.
            preferencesNotice = " · 设置读取或应用失败，保留当前设置";
        }
        if (!previousNotice.equals(preferencesNotice) || !previousView.equals(view == null ? "" : view.toString())) render();
    }

    private boolean apply(String response) throws JSONException {
        JSONObject result = value(response);
        JSONObject next = result.getJSONObject("view");
        String commit = result.isNull("commit") ? null : result.getString("commit");
        if (connection != null && !bridge.apply(sink(), commit, next.getString("editing_text"))) {
            throw new JSONException("Editor rejected update");
        }
        view = next;
        render();
        return result.getBoolean("handled");
    }

    private void fail() { stop(false); message = "输入连接失败：仅直接输入"; render(); }

    private boolean character(int ascii) {
        if (session == 0) return false;
        try { return apply(NativeClient.character(session, ascii, shift)); }
        catch (JSONException | LinkageError error) { fail(); return true; }
    }

    private boolean command(int code) {
        if (session == 0) return false;
        try { return apply(NativeClient.command(session, code)); }
        catch (JSONException | LinkageError error) { fail(); return true; }
    }

    private void type(char key) {
        if (connection == null) return;
        char output = shift ? Character.toUpperCase(key) : key;
        if (!character(output)) connection.commitText(String.valueOf(output), 1);
    }

    private void enter() {
        if (connection == null) return;
        command(9);
        EditorInfo info = getCurrentInputEditorInfo();
        int action = info == null ? EditorInfo.IME_ACTION_NONE : info.imeOptions & EditorInfo.IME_MASK_ACTION;
        if (info != null && (info.imeOptions & EditorInfo.IME_FLAG_NO_ENTER_ACTION) == 0
                && action != EditorInfo.IME_ACTION_NONE && action != EditorInfo.IME_ACTION_UNSPECIFIED
                && connection.performEditorAction(action)) return;
        connection.commitText("\n", 1);
    }

    @Override public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (session == 0 || event.isCtrlPressed() || event.isAltPressed() || event.isMetaPressed()) {
            if (session != 0 && connection != null) {
                // Preserve displayed source text before the editor handles a shortcut.
                command(2);
            }
            return super.onKeyDown(keyCode, event);
        }
        if (keyCode == KeyEvent.KEYCODE_DEL) return command(0) || super.onKeyDown(keyCode, event);
        if (keyCode == KeyEvent.KEYCODE_SPACE) return command(1) || super.onKeyDown(keyCode, event);
        if (keyCode == KeyEvent.KEYCODE_ENTER) { enter(); return true; }
        int unicode = event.getUnicodeChar();
        boolean previous = shift;
        shift = event.isShiftPressed();
        boolean handled = unicode >= 32 && unicode <= 126 && character(unicode);
        shift = previous;
        return handled || super.onKeyDown(keyCode, event);
    }

    @Override public void onUpdateSelection(int oldStart, int oldEnd, int newStart, int newEnd, int composingStart, int composingEnd) {
        super.onUpdateSelection(oldStart, oldEnd, newStart, newEnd, composingStart, composingEnd);
        if (session != 0 && view != null && !view.optString("editing_text").isEmpty()
                && (newStart != composingEnd || newEnd != composingEnd)) {
            // Don't apply an empty composition over the editor's newly moved selection.
            try { value(NativeClient.command(session, 3)); } catch (JSONException | LinkageError error) { fail(); }
            if (connection != null) bridge.abandon(sink());
            view = null;
            render();
        }
    }

    private Button button(LinearLayout row, String label, Runnable action) {
        Button button = new Button(this);
        button.setAllCaps(false);
        button.setText(label);
        button.setOnClickListener(ignored -> action.run());
        row.addView(button, new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1));
        return button;
    }

    @Override public View onCreateInputView() {
        LinearLayout keyboard = new LinearLayout(this);
        keyboard.setOrientation(LinearLayout.VERTICAL);
        WindowLayout.fitSystemBars(keyboard);
        status = new TextView(this);
        keyboard.addView(status);
        candidates = new LinearLayout(this);
        HorizontalScrollView candidateScroll = new HorizontalScrollView(this);
        candidateScroll.addView(candidates);
        keyboard.addView(candidateScroll);
        for (String letters : new String[] {"1234567890", "qwertyuiop", "asdfghjkl", "zxcvbnm", ",.'!?"}) {
            LinearLayout row = new LinearLayout(this);
            keyboard.addView(row);
            for (char key : letters.toCharArray()) button(row, String.valueOf(key), () -> type(key));
        }
        LinearLayout controls = new LinearLayout(this);
        keyboard.addView(controls);
        Button shiftButton = button(controls, "Shift", () -> { shift = !shift; render(); });
        shiftButton.setContentDescription("切换大写");
        button(controls, "⌫", () -> { if (connection != null && !command(0)) connection.deleteSurroundingTextInCodePoints(1, 0); });
        button(controls, "空格", () -> { if (connection != null && !command(1)) connection.commitText(" ", 1); });
        button(controls, "回车", this::enter);
        button(controls, "切换", () -> switchToNextInputMethod(false));
        render();
        return keyboard;
    }

    private void render() {
        if (status != null) status.setText(message + preferencesNotice + (shift ? " · Shift" : ""));
        if (candidates == null) return;
        candidates.removeAllViews();
        if (view == null) return;
        JSONArray entries = view.optJSONArray("candidates");
        if (entries == null || entries.length() == 0) return;
        for (int slot = 0; slot < entries.length(); slot++) {
            JSONObject candidate = entries.optJSONObject(slot);
            if (candidate == null) continue;
            JSONObject id = candidate.optJSONObject("id");
            if (id == null) continue;
            Button button = new Button(this);
            String text = candidate.optString("text");
            boolean highlighted = candidate.optBoolean("highlighted");
            button.setText((slot + 1) + ". " + text);
            button.setContentDescription("候选 " + (slot + 1) + "：" + text);
            button.setSelected(highlighted);
            if (Build.VERSION.SDK_INT >= 30)
                button.setStateDescription(highlighted ? "已选中" : "未选中");
            button.setOnClickListener(ignored -> {
                if (session == 0 || id.optLong("session") != session) return;
                try { apply(NativeClient.select(session, id.getLong("generation"), id.getLong("index"))); }
                catch (JSONException | LinkageError error) { fail(); }
            });
            candidates.addView(button);
        }
        LinearLayout paging = new LinearLayout(this);
        candidates.addView(paging);
        button(paging, "上一页", () -> command(101));
        button(paging, "下一页", () -> command(100));
    }
}
