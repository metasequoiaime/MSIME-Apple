package app.msime.client;

import android.inputmethodservice.InputMethodService;
import android.app.AlertDialog;
import android.content.ClipDescription;
import android.content.ClipboardManager;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.media.AudioManager;
import android.os.Handler;
import android.os.Looper;
import android.os.Build;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.view.View;
import android.view.HapticFeedbackConstants;
import android.view.KeyEvent;
import android.view.Menu;
import android.view.MenuItem;
import android.util.TypedValue;
import android.widget.PopupMenu;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.HorizontalScrollView;
import android.widget.Toast;
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
    private LinearLayout verticalCandidates;
    private HorizontalScrollView horizontalCandidateScroll;
    private ScrollView verticalCandidateScroll;
    private LinearLayout candidatePaging;
    private LinearLayout expandedCandidates;
    private TextView preedit;
    private TextView candidatePage;
    private Button expandCandidates;
    private boolean candidatePanelOpen;
    private ScrollView clipboardScroll;
    private LinearLayout clipboardPanel;
    private ClipboardHistoryStore clipboardHistory;
    private boolean clipboardHistoryEnabled;
    private boolean candidateHorizontal;
    private int candidateFontSize = 16;
    private int candidatePreeditFontSize = 16;
    private KeyboardSkin skin = KeyboardSkin.from("fluent");
    private JSONObject localModes = new JSONObject();
    private Button moreButton;
    private SharedPreferences feedbackPreferences;
    private boolean soundEnabled = true;
    private boolean hapticsEnabled;
    private KeyboardFeedbackPreferences.HapticStrength hapticStrength =
        KeyboardFeedbackPreferences.HapticStrength.MEDIUM;
    private Vibrator vibrator;
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
                localModes = preferences == null ? new JSONObject()
                    : preferences.optJSONObject("local_modes");
                if (localModes == null) localModes = new JSONObject();
                applyCandidateAppearance(preferences);
                applyClipboardPreference(preferences);
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
        closeCandidatePanel();
        closeClipboardHistory();
    }

    private void applyCandidateAppearance(JSONObject preferences) {
        if (preferences == null) {
            candidateHorizontal = false;
            candidateFontSize = 16;
            candidatePreeditFontSize = 16;
            return;
        }
        String layout = preferences.optString("candidate_layout",
            preferences.optString("candidate_orientation", "vertical"));
        candidateHorizontal = CandidateAppearance.isHorizontal(layout);
        candidateFontSize = CandidateAppearance.fontSize(preferences.optInt("candidate_font_size", 16));
        candidatePreeditFontSize = CandidateAppearance.fontSize(
            preferences.optInt("candidate_preedit_font_size", candidateFontSize));
    }

    private void applyClipboardPreference(JSONObject preferences) {
        clipboardHistoryEnabled = preferences != null
            && preferences.optBoolean("clipboard_history", false);
        if (!clipboardHistoryEnabled && clipboardHistory != null) clipboardHistory.clear();
    }

    private String candidateAppearanceKey() {
        return (candidateHorizontal ? "horizontal" : "vertical") + ":"
            + candidateFontSize + ":" + candidatePreeditFontSize;
    }

    private void reloadPreferences(String response) {
        if (session == 0) return;
        String previousView = view == null ? "" : view.toString();
        String previousNotice = preferencesNotice;
        String previousSkin = skin.id();
        String previousAppearance = candidateAppearanceKey();
        boolean previousClipboard = clipboardHistoryEnabled;
        try {
            if (response == null) throw new JSONException("Preferences unavailable");
            JSONObject snapshot = value(response);
            // Editor privacy restrictions apply to every update, not only creation.
            if (!allowLearning) snapshot.getJSONObject("preferences").put("learning", false);
            KeyboardSkin nextSkin = KeyboardSkin.from(snapshot.getJSONObject("preferences")
                .optString("candidate_skin", "fluent"));
            JSONObject nextLocalModes = snapshot.getJSONObject("preferences").optJSONObject("local_modes");
            if (nextLocalModes == null) nextLocalModes = new JSONObject();
            JSONObject preferences = snapshot.getJSONObject("preferences");
            String nextLayout = preferences.optString("candidate_layout",
                preferences.optString("candidate_orientation", "vertical"));
            boolean nextHorizontal = CandidateAppearance.isHorizontal(nextLayout);
            int nextFontSize = CandidateAppearance.fontSize(preferences.optInt("candidate_font_size", 16));
            int nextPreeditFontSize = CandidateAppearance.fontSize(
                preferences.optInt("candidate_preedit_font_size", nextFontSize));
            boolean nextClipboard = preferences.optBoolean("clipboard_history", false);
            JSONObject result = value(NativeClient.updatePreferences(session, snapshot.toString()));
            skin = nextSkin;
            localModes = nextLocalModes;
            candidateHorizontal = nextHorizontal;
            candidateFontSize = nextFontSize;
            candidatePreeditFontSize = nextPreeditFontSize;
            clipboardHistoryEnabled = nextClipboard;
            if (!clipboardHistoryEnabled && clipboardHistory != null) {
                clipboardHistory.clear();
                closeClipboardHistory();
            }
            view = result.getJSONObject("view");
            preferencesNotice = result.getBoolean("deferred") ? " · 设置将在组词结束后应用" : "";
        } catch (JSONException | LinkageError error) {
            // Never replace the working session or log preferences/native responses.
            preferencesNotice = " · 设置读取或应用失败，保留当前设置";
        }
        if (!previousNotice.equals(preferencesNotice) || !previousSkin.equals(skin.id())
                || !previousAppearance.equals(candidateAppearanceKey())
                || previousClipboard != clipboardHistoryEnabled
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
        button.setOnClickListener(ignored -> {
            playFeedback(button);
            action.run();
        });
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

    private void loadFeedbackPreferences() {
        feedbackPreferences = getSharedPreferences("keyboard-feedback", MODE_PRIVATE);
        soundEnabled = feedbackPreferences.getBoolean(KeyboardFeedbackPreferences.SOUND_KEY, true);
        hapticsEnabled = feedbackPreferences.getBoolean(KeyboardFeedbackPreferences.HAPTICS_KEY, false);
        hapticStrength = KeyboardFeedbackPreferences.strength(feedbackPreferences.getString(
            KeyboardFeedbackPreferences.STRENGTH_KEY, "medium"));
        vibrator = getSystemService(Vibrator.class);
    }

    private void saveFeedbackPreferences() {
        if (feedbackPreferences == null) return;
        feedbackPreferences.edit()
            .putBoolean(KeyboardFeedbackPreferences.SOUND_KEY, soundEnabled)
            .putBoolean(KeyboardFeedbackPreferences.HAPTICS_KEY, hapticsEnabled)
            .putString(KeyboardFeedbackPreferences.STRENGTH_KEY, hapticStrength.id())
            .apply();
    }

    private void playFeedback(View source) {
        if (soundEnabled) {
            AudioManager audio = (AudioManager) getSystemService(AUDIO_SERVICE);
            if (audio != null) audio.playSoundEffect(AudioManager.FX_KEYPRESS_STANDARD);
        }
        if (!hapticsEnabled) return;
        if (Build.VERSION.SDK_INT >= 26 && vibrator != null && vibrator.hasVibrator()) {
            vibrator.vibrate(VibrationEffect.createOneShot(10, hapticStrength.amplitude()));
        } else {
            source.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP);
        }
    }

    private boolean supportsLocalTools() {
        if (view == null) return false;
        int scheme = view.optInt("scheme", 0);
        return scheme != 2 && scheme != 3;
    }

    private boolean localModeEnabled(LocalInputMode mode) {
        return localModes.optBoolean(mode.preferenceKey(), true);
    }

    private void openLocalInputMode(LocalInputMode mode) {
        if (session == 0 || !supportsLocalTools() || !localModeEnabled(mode)) return;
        playFeedback(moreButton);
        boolean previousShift = shift;
        shift = true;
        character(mode.trigger().charAt(0));
        shift = previousShift;
    }

    private void closeClipboardHistory() {
        if (clipboardScroll != null) clipboardScroll.setVisibility(View.GONE);
    }

    private void insertClipboardText(String text) {
        if (connection == null || !ClipboardHistoryPolicy.acceptable(text)) return;
        command(9);
        connection.commitText(text, 1);
        closeClipboardHistory();
    }

    private void captureClipboardText() {
        if (!clipboardHistoryEnabled || clipboardHistory == null) return;
        try {
            ClipboardManager manager = getSystemService(ClipboardManager.class);
            if (manager == null || !manager.hasPrimaryClip() || manager.getPrimaryClip() == null
                    || manager.getPrimaryClip().getItemCount() == 0
                    || manager.getPrimaryClipDescription() == null
                    || !(manager.getPrimaryClipDescription().hasMimeType(ClipDescription.MIMETYPE_TEXT_PLAIN)
                        || manager.getPrimaryClipDescription().hasMimeType(ClipDescription.MIMETYPE_TEXT_HTML))) {
                Toast.makeText(this, "剪贴板中没有可保存的文本", Toast.LENGTH_SHORT).show();
                return;
            }
            CharSequence value = manager.getPrimaryClip().getItemAt(0).getText();
            if (value == null || !ClipboardHistoryPolicy.acceptable(value.toString())) {
                Toast.makeText(this, "剪贴板文本为空或过长", Toast.LENGTH_SHORT).show();
                return;
            }
            clipboardHistory.add(value.toString());
            renderClipboardHistory();
        } catch (IllegalArgumentException | IllegalStateException | SecurityException error) {
            Toast.makeText(this, "无法保存当前剪贴板", Toast.LENGTH_SHORT).show();
        }
    }

    private void manageClipboardItem(Button anchor, ClipboardHistory.Item item) {
        PopupMenu popup = new PopupMenu(this, anchor);
        MenuItem pin = popup.getMenu().add(item.pinned() ? "取消固定" : "固定");
        MenuItem remove = popup.getMenu().add("删除");
        popup.setOnMenuItemClickListener(selected -> {
            if (clipboardHistory == null) return false;
            if (selected == pin) clipboardHistory.togglePinned(item.id());
            else if (selected == remove) clipboardHistory.remove(item.id());
            else return false;
            renderClipboardHistory();
            return true;
        });
        popup.show();
    }

    private void confirmClearClipboardHistory() {
        new AlertDialog.Builder(this)
            .setTitle("清空剪贴板历史")
            .setMessage("将删除全部历史，包括固定项。")
            .setNegativeButton("取消", null)
            .setPositiveButton("清空", (dialog, which) -> {
                if (clipboardHistory != null) clipboardHistory.clear();
                renderClipboardHistory();
            })
            .show();
    }

    private void showClipboardHistory() {
        if (!clipboardHistoryEnabled || clipboardScroll == null) return;
        closeCandidatePanel();
        renderClipboardHistory();
        clipboardScroll.setVisibility(View.VISIBLE);
    }

    private void renderClipboardHistory() {
        if (clipboardPanel == null || clipboardHistory == null) return;
        clipboardPanel.removeAllViews();
        LinearLayout header = new LinearLayout(this);
        TextView title = new TextView(this);
        title.setText("剪贴板历史");
        title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 18);
        header.addView(title, new LinearLayout.LayoutParams(0,
            LinearLayout.LayoutParams.WRAP_CONTENT, 1));
        button(header, "清空", this::confirmClearClipboardHistory);
        button(header, "返回", this::closeClipboardHistory);
        clipboardPanel.addView(header);
        Button capture = button(clipboardPanel, "保存当前剪贴板", this::captureClipboardText);
        capture.setContentDescription("保存当前剪贴板文本");
        try {
            java.util.List<ClipboardHistory.Item> items = clipboardHistory.load();
            TextView status = new TextView(this);
            status.setText(items.isEmpty() ? "暂无历史 · 记录仅保存在本机"
                : items.size() + "/" + ClipboardHistoryPolicy.LIMIT + " 条 · 点按插入");
            clipboardPanel.addView(status);
            for (ClipboardHistory.Item item : items) {
                LinearLayout row = new LinearLayout(this);
                Button insert = button(row, item.text(), () -> insertClipboardText(item.text()));
                insert.setContentDescription((item.pinned() ? "已固定；" : "") + "点按插入剪贴板记录");
                Button manage = button(row, item.pinned() ? "已固定" : "管理", () -> {});
                manage.setOnClickListener(ignored -> manageClipboardItem(manage, item));
                row.getChildAt(0).setLayoutParams(new LinearLayout.LayoutParams(0,
                    LinearLayout.LayoutParams.WRAP_CONTENT, 1));
                row.getChildAt(1).setLayoutParams(new LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT));
                clipboardPanel.addView(row);
            }
        } catch (IllegalStateException error) {
            TextView status = new TextView(this);
            status.setText("历史记录无法读取，请清空后重试");
            clipboardPanel.addView(status);
        }
        applySkin();
    }

    private void showFeedbackMenu() {
        if (moreButton == null) return;
        PopupMenu popup = new PopupMenu(this, moreButton);
        Menu menu = popup.getMenu();
        MenuItem clipboard = menu.add("剪贴板历史");
        clipboard.setEnabled(clipboardHistoryEnabled);
        MenuItem sound = menu.add("按键音");
        sound.setCheckable(true).setChecked(soundEnabled);
        MenuItem haptics = menu.add("按键振动");
        haptics.setCheckable(true).setChecked(hapticsEnabled);
        menu.setGroupCheckable(1, true, true);
        MenuItem light = menu.add(1, 1, Menu.NONE, "振动强度：轻");
        MenuItem medium = menu.add(1, 2, Menu.NONE, "振动强度：中");
        MenuItem strong = menu.add(1, 3, Menu.NONE, "振动强度：强");
        light.setCheckable(true).setChecked(hapticStrength == KeyboardFeedbackPreferences.HapticStrength.LIGHT);
        medium.setCheckable(true).setChecked(hapticStrength == KeyboardFeedbackPreferences.HapticStrength.MEDIUM);
        strong.setCheckable(true).setChecked(hapticStrength == KeyboardFeedbackPreferences.HapticStrength.STRONG);
        android.view.SubMenu local = menu.addSubMenu("本地输入");
        for (LocalInputMode mode : LocalInputMode.values()) {
            MenuItem item = local.add(2, 100 + mode.ordinal(), Menu.NONE, mode.title());
            item.setEnabled(supportsLocalTools() && localModeEnabled(mode));
        }
        popup.setOnMenuItemClickListener(item -> {
            if (item == clipboard) {
                showClipboardHistory();
                return true;
            }
            if (item == sound) soundEnabled = !soundEnabled;
            else if (item == haptics) hapticsEnabled = !hapticsEnabled;
            else if (item == light) hapticStrength = KeyboardFeedbackPreferences.HapticStrength.LIGHT;
            else if (item == medium) hapticStrength = KeyboardFeedbackPreferences.HapticStrength.MEDIUM;
            else if (item == strong) hapticStrength = KeyboardFeedbackPreferences.HapticStrength.STRONG;
            else if (item.getGroupId() == 2 && item.getItemId() >= 100
                    && item.getItemId() < 100 + LocalInputMode.values().length) {
                openLocalInputMode(LocalInputMode.values()[item.getItemId() - 100]);
                return true;
            }
            else return false;
            saveFeedbackPreferences();
            return true;
        });
        popup.show();
    }

    private boolean candidateManagementEnabled() {
        if (view == null || !view.optString("local_mode", "none").equals("none")) return false;
        int scheme = view.optInt("scheme", 0);
        return scheme != 2 && scheme != 3;
    }

    private void editCandidate(JSONObject id, boolean remove) {
        if (session == 0 || id == null || id.optLong("session") != session) return;
        try {
            String result = remove
                ? NativeClient.removeCandidate(session, id.getLong("generation"), id.getLong("index"))
                : NativeClient.pinCandidate(session, id.getLong("generation"), id.getLong("index"));
            if (!apply(result)) Toast.makeText(this, "当前候选不支持此操作", Toast.LENGTH_SHORT).show();
        } catch (JSONException | LinkageError error) { fail(); }
    }

    private void confirmCandidateRemoval(JSONObject id, String text) {
        new AlertDialog.Builder(this)
            .setTitle("删除词条")
            .setMessage("确认删除“" + text + "”？")
            .setNegativeButton("取消", null)
            .setPositiveButton("删除", (dialog, which) -> {
                playFeedback(moreButton);
                editCandidate(id, true);
            })
            .show();
    }

    private void showCandidateMenu(Button button, JSONObject id, String text) {
        if (!candidateManagementEnabled()) return;
        PopupMenu popup = new PopupMenu(this, button);
        MenuItem promote = popup.getMenu().add("优先显示");
        MenuItem remove = popup.getMenu().add("删除词条…");
        popup.setOnMenuItemClickListener(item -> {
            playFeedback(button);
            if (item == promote) {
                editCandidate(id, false);
                return true;
            }
            if (item == remove) {
                confirmCandidateRemoval(id, text);
                return true;
            }
            return false;
        });
        popup.show();
    }

    private Button candidateButton(JSONObject candidate, int slot) {
        JSONObject id = candidate.optJSONObject("id");
        Button button = new Button(this);
        String text = candidate.optString("text");
        boolean highlighted = candidate.optBoolean("highlighted");
        button.setAllCaps(false);
        button.setText((slot + 1) + ". " + text);
        button.setTextSize(TypedValue.COMPLEX_UNIT_SP, candidateFontSize);
        styleButton(button, false);
        button.setContentDescription("候选 " + (slot + 1) + "：" + text);
        button.setSelected(highlighted);
        if (Build.VERSION.SDK_INT >= 30)
            button.setStateDescription(highlighted ? "已选中" : "未选中");
        if (id != null && candidateManagementEnabled()) {
            button.setContentDescription("候选 " + (slot + 1) + "：" + text + "；长按管理");
            button.setOnLongClickListener(ignored -> {
                showCandidateMenu(button, id, text);
                return true;
            });
        }
        if (id == null) {
            button.setEnabled(false);
        } else {
            button.setOnClickListener(ignored -> {
                playFeedback(button);
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
        close.setOnClickListener(ignored -> {
            playFeedback(close);
            closeCandidatePanel();
        });
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
                keyButton.setOnClickListener(ignored -> {
                    playFeedback(keyButton);
                    type(input.charAt(0));
                });
                row.addView(keyButton, new LinearLayout.LayoutParams(0,
                    LinearLayout.LayoutParams.WRAP_CONTENT, 1));
                keyButton.setContentDescription("按键 " + key);
            }
        }
    }

    @Override public View onCreateInputView() {
        loadFeedbackPreferences();
        clipboardHistory = new ClipboardHistoryStore(this);
        if (!clipboardHistoryEnabled) clipboardHistory.clear();
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
        preedit.setTextSize(TypedValue.COMPLEX_UNIT_SP, candidatePreeditFontSize);
        candidateHeader.addView(preedit, new LinearLayout.LayoutParams(0,
            LinearLayout.LayoutParams.WRAP_CONTENT, 1));
        candidatePage = new TextView(this);
        candidateHeader.addView(candidatePage, new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT));
        expandCandidates = new Button(this);
        expandCandidates.setAllCaps(false);
        expandCandidates.setText("展开");
        expandCandidates.setContentDescription("展开候选面板");
        expandCandidates.setOnClickListener(ignored -> {
            playFeedback(expandCandidates);
            openCandidatePanel();
        });
        candidateHeader.addView(expandCandidates, new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT));
        candidateRegion.addView(candidateHeader);
        candidates = new LinearLayout(this);
        candidates.setOrientation(LinearLayout.HORIZONTAL);
        horizontalCandidateScroll = new HorizontalScrollView(this);
        horizontalCandidateScroll.addView(candidates);
        verticalCandidates = new LinearLayout(this);
        verticalCandidates.setOrientation(LinearLayout.VERTICAL);
        verticalCandidateScroll = new ScrollView(this);
        verticalCandidateScroll.addView(verticalCandidates);
        FrameLayout candidateViewport = new FrameLayout(this);
        candidateViewport.addView(horizontalCandidateScroll, new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT));
        candidateViewport.addView(verticalCandidateScroll, new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT));
        candidateRegion.addView(candidateViewport);
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
        moreButton = button(controls, "更多", this::showFeedbackMenu);
        moreButton.setContentDescription("更多快捷设置");
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
        clipboardPanel = new LinearLayout(this);
        clipboardPanel.setOrientation(LinearLayout.VERTICAL);
        clipboardPanel.setPadding(24, 16, 24, 16);
        clipboardPanel.setBackgroundColor(Color.parseColor(skin.background()));
        clipboardPanel.setContentDescription("剪贴板历史");
        clipboardScroll = new ScrollView(this);
        clipboardScroll.addView(clipboardPanel);
        clipboardScroll.setVisibility(View.GONE);
        keyboardRoot.addView(clipboardScroll, new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
        render();
        return keyboardRoot;
    }

    private void render() {
        String page = "";
        if (view != null && view.optInt("page_count", 0) > 0)
            page = " · " + (view.optInt("page", 0) + 1) + "/" + view.optInt("page_count");
        String localMode = "";
        if (view != null) {
            String modeKey = view.optString("local_mode", "none");
            for (LocalInputMode mode : LocalInputMode.values()) {
                if (mode.preferenceKey().equals(modeKey)) {
                    localMode = " · " + mode.title();
                    break;
                }
            }
        }
        if (status != null) status.setText(message + preferencesNotice + localMode + page
            + (shift ? " · Shift" : ""));
        if (preedit != null) {
            preedit.setTextSize(TypedValue.COMPLEX_UNIT_SP, candidatePreeditFontSize);
            preedit.setText(view == null ? "" : view.optString("editing_text", ""));
        }
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
        if (horizontalCandidateScroll != null)
            horizontalCandidateScroll.setVisibility(candidateHorizontal ? View.VISIBLE : View.GONE);
        if (verticalCandidateScroll != null)
            verticalCandidateScroll.setVisibility(candidateHorizontal ? View.GONE : View.VISIBLE);
        LinearLayout activeCandidates = candidateHorizontal ? candidates : verticalCandidates;
        candidates.removeAllViews();
        if (verticalCandidates != null) verticalCandidates.removeAllViews();
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
                activeCandidates.addView(candidateView, new LinearLayout.LayoutParams(
                    candidateHorizontal ? LinearLayout.LayoutParams.WRAP_CONTENT
                        : LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT));
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
