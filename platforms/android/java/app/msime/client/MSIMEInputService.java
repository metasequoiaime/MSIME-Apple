package app.msime.client;

import android.inputmethodservice.InputMethodService;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Handler;
import android.os.Looper;
import android.os.Build;
import android.view.View;
import android.view.KeyEvent;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ScrollView;
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
    private FrameLayout keyboardRoot;
    private LinearLayout candidates;
    private LinearLayout candidatePaging;
    private LinearLayout expandedCandidates;
    private TextView preedit;
    private TextView candidatePage;
    private Button expandCandidates;
    private boolean candidatePanelOpen;
    private KeyboardSkin skin = KeyboardSkin.from("fluent");
    private LinearLayout keyRows;
    private Button layerButton;
    private TextView status;
    private String message = "MSIME Preview";
    private boolean shift;
    private KeyboardLayout.Layer keyboardLayer = KeyboardLayout.Layer.LETTERS;
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
        keyboardLayer = KeyboardLayout.Layer.LETTERS;
        allowLearning = info != null && EditorPolicy.allowLearning(info.imeOptions);
        preferencesNotice = "";
        message = "直接输入";
        if (info != null && connection != null && EditorPolicy.useEngine(info.inputType)) {
            try {
                File file = new File(getFilesDir(), "runtime-options.json");
                if (file.length() > 16384) throw new IllegalArgumentException("Options too large");
                JSONObject options = new JSONObject(new String(Files.readAllBytes(file.toPath()), StandardCharsets.UTF_8));
                JSONObject preferences = options.optJSONObject("preferences");
                skin = KeyboardSkin.from(preferences == null ? "fluent"
                    : preferences.optString("candidate_skin", "fluent"));
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
        String previousSkin = skin.id();
        try {
            if (response == null) throw new JSONException("Preferences unavailable");
            JSONObject snapshot = value(response);
            // Editor privacy restrictions apply to every update, not only creation.
            if (!allowLearning) snapshot.getJSONObject("preferences").put("learning", false);
            skin = KeyboardSkin.from(snapshot.getJSONObject("preferences")
                .optString("candidate_skin", "fluent"));
            JSONObject result = value(NativeClient.updatePreferences(session, snapshot.toString()));
            view = result.getJSONObject("view");
            preferencesNotice = result.getBoolean("deferred") ? " · 设置将在组词结束后应用" : "";
        } catch (JSONException | LinkageError error) {
            // Never replace the working session or log preferences/native responses.
            preferencesNotice = " · 设置读取或应用失败，保留当前设置";
        }
        if (!previousNotice.equals(preferencesNotice) || !previousSkin.equals(skin.id())
                || !previousView.equals(view == null ? "" : view.toString())) render();
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
        styleButton(button, true);
        button.setOnClickListener(ignored -> action.run());
        row.addView(button, new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1));
        return button;
    }

    private int pixels(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private void styleButton(Button button, boolean action) {
        boolean selected = button.isSelected();
        String background = selected ? skin.accent() : action ? skin.actionBackground() : skin.keyBackground();
        String foreground = selected ? skin.actionForeground() : action ? skin.actionForeground() : skin.keyForeground();
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(Color.parseColor(background));
        drawable.setCornerRadius(pixels(skin.cornerRadius()));
        drawable.setStroke(pixels(1), Color.parseColor(skin.accent()));
        button.setBackground(drawable);
        button.setTextColor(Color.parseColor(foreground));
        button.setTypeface(skin.monospaced() ? Typeface.MONOSPACE : Typeface.DEFAULT);
    }

    private void applySkinToView(View node) {
        if (node instanceof Button) {
            CharSequence description = node.getContentDescription();
            boolean key = description != null && (description.toString().startsWith("按键 ")
                || description.toString().startsWith("候选 "));
            styleButton((Button) node, !key);
        } else if (node instanceof TextView) {
            TextView text = (TextView) node;
            text.setTextColor(Color.parseColor(skin.keyForeground()));
            text.setTypeface(skin.monospaced() ? Typeface.MONOSPACE : Typeface.DEFAULT);
        }
        if (node instanceof android.view.ViewGroup) {
            android.view.ViewGroup group = (android.view.ViewGroup) node;
            for (int index = 0; index < group.getChildCount(); index++)
                applySkinToView(group.getChildAt(index));
        }
    }

    private void applySkin() {
        if (keyboardRoot == null) return;
        keyboardRoot.setBackgroundColor(Color.parseColor(skin.background()));
        if (expandedCandidates != null)
            expandedCandidates.setBackgroundColor(Color.parseColor(skin.background()));
        applySkinToView(keyboardRoot);
    }

    private Button candidateButton(JSONObject candidate, int slot) {
        JSONObject id = candidate.optJSONObject("id");
        Button button = new Button(this);
        String text = candidate.optString("text");
        boolean highlighted = candidate.optBoolean("highlighted");
        button.setAllCaps(false);
        button.setText((slot + 1) + ". " + text);
        styleButton(button, false);
        button.setContentDescription("候选 " + (slot + 1) + "：" + text);
        button.setSelected(highlighted);
        if (Build.VERSION.SDK_INT >= 30)
            button.setStateDescription(highlighted ? "已选中" : "未选中");
        if (id == null) {
            button.setEnabled(false);
        } else {
            button.setOnClickListener(ignored -> {
                if (session == 0 || id.optLong("session") != session) return;
                candidatePanelOpen = false;
                try { apply(NativeClient.select(session, id.getLong("generation"), id.getLong("index"))); }
                catch (JSONException | LinkageError error) { fail(); }
            });
        }
        return button;
    }

    private void closeCandidatePanel() {
        candidatePanelOpen = false;
        if (keyboardRoot != null && expandedCandidates != null)
            expandedCandidates.setVisibility(View.GONE);
    }

    private void openCandidatePanel() {
        if (view == null || view.optJSONArray("candidates") == null) return;
        candidatePanelOpen = true;
        renderExpandedCandidates();
    }

    private void renderExpandedCandidates() {
        if (expandedCandidates == null) return;
        expandedCandidates.removeAllViews();
        if (!candidatePanelOpen || view == null) {
            expandedCandidates.setVisibility(View.GONE);
            return;
        }
        expandedCandidates.setVisibility(View.VISIBLE);
        LinearLayout header = new LinearLayout(this);
        TextView title = new TextView(this);
        title.setText("候选面板 · 当前页");
        title.setTextSize(18);
        header.addView(title, new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1));
        Button close = new Button(this);
        close.setAllCaps(false);
        close.setText("收起");
        close.setContentDescription("收起候选面板");
        close.setOnClickListener(ignored -> closeCandidatePanel());
        header.addView(close, new LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT));
        expandedCandidates.addView(header);
        TextView spelling = new TextView(this);
        spelling.setText("正在输入：" + view.optString("editing_text", ""));
        spelling.setContentDescription("当前组合文本：" + view.optString("editing_text", ""));
        expandedCandidates.addView(spelling);
        LinearLayout list = new LinearLayout(this);
        list.setOrientation(LinearLayout.VERTICAL);
        JSONArray entries = view.optJSONArray("candidates");
        if (entries != null) {
            for (int slot = 0; slot < entries.length(); slot++) {
                JSONObject candidate = entries.optJSONObject(slot);
                if (candidate == null) continue;
                Button button = candidateButton(candidate, slot);
                list.addView(button, new LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT));
            }
        }
        expandedCandidates.addView(list);
        LinearLayout panelPaging = new LinearLayout(this);
        panelPaging.setOrientation(LinearLayout.HORIZONTAL);
        button(panelPaging, "上词", () -> command(103));
        button(panelPaging, "下词", () -> command(102));
        button(panelPaging, "上一页", () -> command(101));
        button(panelPaging, "下一页", () -> command(100));
        expandedCandidates.addView(panelPaging);
        TextView hint = new TextView(this);
        hint.setText("可在此面板直接翻页或选择候选");
        expandedCandidates.addView(hint);
    }

    private void rebuildKeyRows() {
        if (keyRows == null) return;
        keyRows.removeAllViews();
        for (java.util.List<String> keys : KeyboardLayout.rows(keyboardLayer, shift)) {
            LinearLayout row = new LinearLayout(this);
            keyRows.addView(row);
            for (String key : keys) {
                final String input = key;
                Button keyButton = new Button(this);
                keyButton.setAllCaps(false);
                keyButton.setText(key);
                styleButton(keyButton, false);
                keyButton.setOnClickListener(ignored -> type(input.charAt(0)));
                row.addView(keyButton, new LinearLayout.LayoutParams(0,
                    LinearLayout.LayoutParams.WRAP_CONTENT, 1));
                keyButton.setContentDescription("按键 " + key);
            }
        }
    }

    @Override public View onCreateInputView() {
        keyboardRoot = new FrameLayout(this);
        LinearLayout keyboard = new LinearLayout(this);
        keyboard.setOrientation(LinearLayout.VERTICAL);
        WindowLayout.fitSystemBars(keyboard);
        keyboardRoot.addView(keyboard, new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
        status = new TextView(this);
        keyboard.addView(status);
        LinearLayout candidateRegion = new LinearLayout(this);
        candidateRegion.setOrientation(LinearLayout.VERTICAL);
        LinearLayout candidateHeader = new LinearLayout(this);
        preedit = new TextView(this);
        preedit.setTextSize(16);
        candidateHeader.addView(preedit, new LinearLayout.LayoutParams(0,
            LinearLayout.LayoutParams.WRAP_CONTENT, 1));
        candidatePage = new TextView(this);
        candidateHeader.addView(candidatePage, new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT));
        expandCandidates = new Button(this);
        expandCandidates.setAllCaps(false);
        expandCandidates.setText("展开");
        expandCandidates.setContentDescription("展开候选面板");
        expandCandidates.setOnClickListener(ignored -> openCandidatePanel());
        candidateHeader.addView(expandCandidates, new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT));
        candidateRegion.addView(candidateHeader);
        candidates = new LinearLayout(this);
        candidates.setOrientation(LinearLayout.HORIZONTAL);
        HorizontalScrollView candidateScroll = new HorizontalScrollView(this);
        candidateScroll.addView(candidates);
        candidateRegion.addView(candidateScroll);
        candidatePaging = new LinearLayout(this);
        candidatePaging.setOrientation(LinearLayout.HORIZONTAL);
        candidateRegion.addView(candidatePaging);
        keyboard.addView(candidateRegion);
        keyRows = new LinearLayout(this);
        keyRows.setOrientation(LinearLayout.VERTICAL);
        keyboard.addView(keyRows);
        rebuildKeyRows();
        LinearLayout controls = new LinearLayout(this);
        HorizontalScrollView controlScroll = new HorizontalScrollView(this);
        controlScroll.setHorizontalScrollBarEnabled(false);
        controlScroll.addView(controls, new HorizontalScrollView.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT));
        keyboard.addView(controlScroll);
        final Button[] shiftButtonRef = new Button[1];
        Button shiftButton = button(controls, "Shift", () -> {
            shift = !shift;
            shiftButtonRef[0].setSelected(shift);
            shiftButtonRef[0].setContentDescription(shift ? "大写已开启" : "切换大写");
            rebuildKeyRows();
            render();
        });
        shiftButtonRef[0] = shiftButton;
        shiftButton.setContentDescription("切换大写");
        layerButton = button(controls, "符号", () -> {
            keyboardLayer = keyboardLayer == KeyboardLayout.Layer.LETTERS
                ? KeyboardLayout.Layer.SYMBOLS : KeyboardLayout.Layer.LETTERS;
            shift = false;
            rebuildKeyRows();
            render();
        });
        layerButton.setContentDescription("切换符号键盘");
        button(controls, "首", () -> command(6));
        button(controls, "←", () -> command(4));
        button(controls, "→", () -> command(5));
        button(controls, "尾", () -> command(7));
        button(controls, "⌫", () -> { if (connection != null && !command(0)) connection.deleteSurroundingTextInCodePoints(1, 0); });
        button(controls, "删除", () -> command(8));
        button(controls, "取消", () -> command(3));
        button(controls, "空格", () -> { if (connection != null && !command(1)) connection.commitText(" ", 1); });
        button(controls, "回车", this::enter);
        button(controls, "切换", () -> switchToNextInputMethod(false));
        for (int index = 0; index < controls.getChildCount(); index++) {
            View child = controls.getChildAt(index);
            LinearLayout.LayoutParams params = (LinearLayout.LayoutParams) child.getLayoutParams();
            params.width = LinearLayout.LayoutParams.WRAP_CONTENT;
            params.weight = 0;
            child.setLayoutParams(params);
        }
        expandedCandidates = new LinearLayout(this);
        expandedCandidates.setOrientation(LinearLayout.VERTICAL);
        expandedCandidates.setPadding(24, 16, 24, 16);
        expandedCandidates.setBackgroundColor(0xfff5f5f5);
        expandedCandidates.setContentDescription("候选面板");
        expandedCandidates.setVisibility(View.GONE);
        ScrollView expandedScroll = new ScrollView(this);
        expandedScroll.addView(expandedCandidates);
        keyboardRoot.addView(expandedScroll, new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
        render();
        return keyboardRoot;
    }

    private void render() {
        String page = "";
        if (view != null && view.optInt("page_count", 0) > 0)
            page = " · " + (view.optInt("page", 0) + 1) + "/" + view.optInt("page_count");
        if (status != null) status.setText(message + preferencesNotice + page + (shift ? " · Shift" : ""));
        if (preedit != null) preedit.setText(view == null ? "" : view.optString("editing_text", ""));
        if (candidatePage != null) candidatePage.setText(page.isEmpty() ? "" : page.substring(3));
        if (layerButton != null) {
            layerButton.setText(keyboardLayer == KeyboardLayout.Layer.LETTERS ? "符号" : "字母");
            layerButton.setContentDescription(keyboardLayer == KeyboardLayout.Layer.LETTERS
                ? "切换符号键盘" : "切换字母键盘");
        }
        if (candidates == null) {
            applySkin();
            return;
        }
        candidates.removeAllViews();
        if (candidatePaging != null) candidatePaging.removeAllViews();
        if (expandCandidates != null) expandCandidates.setVisibility(View.GONE);
        if (view == null) {
            closeCandidatePanel();
            applySkin();
            return;
        }
        JSONArray entries = view.optJSONArray("candidates");
        if (entries != null) {
            for (int slot = 0; slot < entries.length(); slot++) {
                JSONObject candidate = entries.optJSONObject(slot);
                if (candidate == null) continue;
                Button candidateView = candidateButton(candidate, slot);
                candidates.addView(candidateView, new LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT));
            }
            if (entries.length() > 1 && expandCandidates != null) expandCandidates.setVisibility(View.VISIBLE);
        }
        if (candidatePaging != null) {
            button(candidatePaging, "上词", () -> command(103));
            button(candidatePaging, "下词", () -> command(102));
            button(candidatePaging, "上一页", () -> command(101));
            button(candidatePaging, "下一页", () -> command(100));
        }
        renderExpandedCandidates();
        applySkin();
    }
}
