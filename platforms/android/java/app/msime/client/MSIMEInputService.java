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
import android.view.Gravity;
import android.view.HapticFeedbackConstants;
import android.view.KeyEvent;
import android.view.Menu;
import android.view.MenuItem;
import android.view.MotionEvent;
import android.view.View;
import android.util.TypedValue;
import android.widget.PopupMenu;
import android.view.ViewConfiguration;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.SeekBar;
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
    private static final int STANDARD_TOUCH_LAYOUT = 0;
    private static final int QUANPIN_NINE_KEY_LAYOUT = 1;
    private static final int JAPANESE_NINE_KEY_LAYOUT = 2;
    private static final int HANDWRITING_LAYOUT = 3;
    private static final long HANDWRITING_DEBOUNCE_MILLIS = 550;
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
    private LinearLayout nineKeySpellings;
    private HorizontalScrollView nineKeySpellingScroll;
    private Button expandCandidates;
    private boolean candidatePanelOpen;
    private ScrollView clipboardScroll;
    private LinearLayout clipboardPanel;
    private ScrollView schemeScroll;
    private LinearLayout schemePanel;
    private ScrollView layoutSettingsScroll;
    private LinearLayout layoutSettingsPanel;
    private SeekBar keySpacingSlider;
    private SeekBar rowSpacingSlider;
    private TextView keySpacingValue;
    private TextView rowSpacingValue;
    private ClipboardHistoryStore clipboardHistory;
    private boolean clipboardHistoryEnabled;
    private boolean candidateHorizontal;
    private int candidateFontSize = 16;
    private int candidatePreeditFontSize = 16;
    private int touchKeySpacingTenths = KeyboardGeometry.DEFAULT_KEY_SPACING_TENTHS;
    private int touchRowSpacingTenths = KeyboardGeometry.DEFAULT_ROW_SPACING_TENTHS;
    private KeyboardSkin skin = KeyboardSkin.from("fluent");
    private JSONObject localModes = new JSONObject();
    private Button moreButton;
    private Button schemeButton;
    private Button layoutSettingsButton;
    private KeyboardScheme selectedScheme = KeyboardScheme.QUANPIN;
    private SharedPreferences feedbackPreferences;
    private boolean soundEnabled = true;
    private boolean hapticsEnabled;
    private KeyboardFeedbackPreferences.HapticStrength hapticStrength =
        KeyboardFeedbackPreferences.HapticStrength.MEDIUM;
    private Vibrator vibrator;
    private LinearLayout keyRows;
    private HandwritingCanvas handwritingCanvas;
    private LinearLayout handwritingCandidates;
    private TextView handwritingStatus;
    private Button handwritingDownload;
    private HandwritingRecognizer handwritingRecognizer;
    private Runnable handwritingRecognitionTask;
    private Runnable handwritingAvailabilityTask;
    private boolean handwritingDownloading;
    private java.util.List<String> handwritingResults = java.util.List.of();
    private final HandwritingRequestTracker handwritingRequests = new HandwritingRequestTracker();
    private Button layerButton;
    private Button shiftButton;
    private TextView status;
    private String message = "MSIME Preview";
    private boolean shift;
    private KeyboardLayout.Layer keyboardLayer = KeyboardLayout.Layer.LETTERS;
    private boolean allowLearning;
    private String preferencesNotice = "";
    private String preferencesDirectory = "";
    private JSONObject preferencesSnapshot;
    private long preferenceSaveGeneration;
    private boolean schemeSaving;
    private boolean touchGeometrySaving;
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
                selectedScheme = KeyboardScheme.fromPreferences(
                    preferences == null ? "quanpin" : preferences.optString("scheme", "quanpin"),
                    preferences == null ? "xiaohe" : preferences.optString("shuangpin_profile", "xiaohe"),
                    preferences == null ? "twenty_six_key"
                        : preferences.optString("touch_keyboard_layout", "twenty_six_key"));
                skin = KeyboardSkin.from(preferences == null ? "fluent"
                    : preferences.optString("candidate_skin", "fluent"));
                localModes = preferences == null ? new JSONObject()
                    : preferences.optJSONObject("local_modes");
                if (localModes == null) localModes = new JSONObject();
                applyCandidateAppearance(preferences);
                applyTouchGeometry(preferences);
                applyClipboardPreference(preferences);
                if (!allowLearning) options.getJSONObject("preferences").put("learning", false);
                view = value(NativeClient.create(options.toString()));
                session = view.getLong("session");
                apply(NativeClient.focus(session, true));
                message = "MSIME Preview";
                String directory = options.optString("preferences_directory", "");
                if (!directory.isEmpty() && new File(directory).isAbsolute()) {
                    preferencesDirectory = directory;
                    preferencesReloader.start(directory, this::reloadPreferences);
                }
            } catch (Exception | LinkageError error) {
                stop(false);
                message = "共享运行时未就绪：仅直接输入";
            }
        }
        rebuildKeyRows();
        render();
    }

    @Override public void onFinishInput() { stop(true); connection = null; super.onFinishInput(); }
    @Override public void onDestroy() { stop(false); preferencesWorker.shutdown(); connection = null; super.onDestroy(); }
    @Override public boolean onEvaluateFullscreenMode() { return false; }

    private void stop(boolean finish) {
        deactivateHandwriting();
        preferencesReloader.stop();
        preferenceSaveGeneration++;
        preferencesDirectory = "";
        preferencesSnapshot = null;
        schemeSaving = false;
        touchGeometrySaving = false;
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
        closeSchemePicker();
        closeLayoutSettings();
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

    private void applyTouchGeometry(JSONObject preferences) {
        touchKeySpacingTenths = KeyboardGeometry.keySpacing(preferences == null ? -1
            : preferences.optInt("touch_key_spacing_tenths", -1));
        touchRowSpacingTenths = KeyboardGeometry.rowSpacing(preferences == null ? -1
            : preferences.optInt("touch_row_spacing_tenths", -1));
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

    private String touchGeometryKey() {
        return touchKeySpacingTenths + ":" + touchRowSpacingTenths;
    }

    private void reloadPreferences(String response) {
        if (session == 0) return;
        String previousView = view == null ? "" : view.toString();
        String previousNotice = preferencesNotice;
        String previousSkin = skin.id();
        String previousAppearance = candidateAppearanceKey();
        String previousGeometry = touchGeometryKey();
        boolean previousClipboard = clipboardHistoryEnabled;
        KeyboardScheme previousScheme = selectedScheme;
        try {
            if (response == null) throw new JSONException("Preferences unavailable");
            JSONObject snapshot = value(response);
            applyPreferencesSnapshot(snapshot);
        } catch (JSONException | LinkageError error) {
            // Never replace the working session or log preferences/native responses.
            preferencesNotice = " · 设置读取或应用失败，保留当前设置";
        }
        if (!previousNotice.equals(preferencesNotice) || !previousSkin.equals(skin.id())
                || !previousAppearance.equals(candidateAppearanceKey())
                || !previousGeometry.equals(touchGeometryKey())
                || previousClipboard != clipboardHistoryEnabled
                || previousScheme != selectedScheme
                || !previousView.equals(view == null ? "" : view.toString())) render();
    }

    private void applyPreferencesSnapshot(JSONObject snapshot) throws JSONException {
        JSONObject accepted = new JSONObject(snapshot.toString());
        JSONObject preferences = accepted.getJSONObject("preferences");
        KeyboardSkin nextSkin = KeyboardSkin.from(preferences.optString("candidate_skin", "fluent"));
        JSONObject nextLocalModes = preferences.optJSONObject("local_modes");
        if (nextLocalModes == null) nextLocalModes = new JSONObject();
        String nextLayout = preferences.optString("candidate_layout",
            preferences.optString("candidate_orientation", "vertical"));
        boolean nextHorizontal = CandidateAppearance.isHorizontal(nextLayout);
        int nextFontSize = CandidateAppearance.fontSize(preferences.optInt("candidate_font_size", 16));
        int nextPreeditFontSize = CandidateAppearance.fontSize(
            preferences.optInt("candidate_preedit_font_size", nextFontSize));
        int nextKeySpacing = KeyboardGeometry.keySpacing(
            preferences.optInt("touch_key_spacing_tenths", -1));
        int nextRowSpacing = KeyboardGeometry.rowSpacing(
            preferences.optInt("touch_row_spacing_tenths", -1));
        boolean nextClipboard = preferences.optBoolean("clipboard_history", false);
        KeyboardScheme nextScheme = KeyboardScheme.fromPreferences(
            preferences.optString("scheme", "quanpin"),
            preferences.optString("shuangpin_profile", "xiaohe"),
            preferences.optString("touch_keyboard_layout", "twenty_six_key"));
        JSONObject sessionSnapshot = new JSONObject(accepted.toString());
        // Keep the accepted disk snapshot intact while enforcing editor privacy in this session.
        if (!allowLearning) sessionSnapshot.getJSONObject("preferences").put("learning", false);
        JSONObject result = value(NativeClient.updatePreferences(session, sessionSnapshot.toString()));
        boolean geometryChanged = touchKeySpacingTenths != nextKeySpacing
            || touchRowSpacingTenths != nextRowSpacing;
        skin = nextSkin;
        localModes = nextLocalModes;
        candidateHorizontal = nextHorizontal;
        candidateFontSize = nextFontSize;
        candidatePreeditFontSize = nextPreeditFontSize;
        touchKeySpacingTenths = nextKeySpacing;
        touchRowSpacingTenths = nextRowSpacing;
        clipboardHistoryEnabled = nextClipboard;
        JSONObject nextView = result.getJSONObject("view");
        boolean rebuildLayout = touchLayout(view) != touchLayout(nextView);
        selectedScheme = nextScheme;
        preferencesSnapshot = accepted;
        if (!clipboardHistoryEnabled && clipboardHistory != null) {
            clipboardHistory.clear();
            closeClipboardHistory();
        }
        view = nextView;
        if (touchLayout(view) != STANDARD_TOUCH_LAYOUT) shift = false;
        if (rebuildLayout) rebuildKeyRows();
        else if (geometryChanged) applyKeyboardGeometry();
        renderLayoutSettingsState();
        preferencesNotice = result.getBoolean("deferred") ? " · 设置将在组词结束后应用" : "";
    }

    private boolean apply(String response) throws JSONException {
        JSONObject result = value(response);
        JSONObject next = result.getJSONObject("view");
        boolean rebuildLayout = touchLayout(view) != touchLayout(next);
        String commit = result.isNull("commit") ? null : result.getString("commit");
        if (connection != null && !bridge.apply(sink(), commit, next.getString("editing_text"))) {
            throw new JSONException("Editor rejected update");
        }
        view = next;
        if (touchLayout(view) != STANDARD_TOUCH_LAYOUT) shift = false;
        if (rebuildLayout) rebuildKeyRows();
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

    private static int touchLayout(JSONObject value) {
        if (value == null) return STANDARD_TOUCH_LAYOUT;
        if ("handwriting".equals(value.optString("touch_keyboard_layout"))) {
            return HANDWRITING_LAYOUT;
        }
        if (value.optBoolean("nine_key", false)) return QUANPIN_NINE_KEY_LAYOUT;
        if (value.optInt("scheme", -1) == 3
                && "nine_key".equals(value.optString("touch_keyboard_layout"))) {
            return JAPANESE_NINE_KEY_LAYOUT;
        }
        return STANDARD_TOUCH_LAYOUT;
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

    private Button keyboardKey(String label, String description, Runnable action) {
        Button button = new Button(this);
        button.setAllCaps(false);
        button.setText(label);
        button.setContentDescription("按键 " + description);
        styleButton(button, false);
        button.setOnClickListener(ignored -> {
            playFeedback(button);
            action.run();
        });
        return button;
    }

    private int pixels(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private int halfSpacingPixels(int tenths) {
        return KeyboardGeometry.halfGapPixels(tenths,
            getResources().getDisplayMetrics().density);
    }

    private void applyKeyboardGeometry(View node) {
        CharSequence description = node.getContentDescription();
        if (node instanceof Button && description != null
                && description.toString().startsWith("按键 ")
                && node.getLayoutParams() instanceof android.view.ViewGroup.MarginLayoutParams) {
            android.view.ViewGroup.MarginLayoutParams params =
                (android.view.ViewGroup.MarginLayoutParams) node.getLayoutParams();
            int horizontal = halfSpacingPixels(touchKeySpacingTenths);
            int vertical = halfSpacingPixels(touchRowSpacingTenths);
            params.setMargins(horizontal, vertical, horizontal, vertical);
            node.setLayoutParams(params);
        }
        if (node instanceof android.view.ViewGroup) {
            android.view.ViewGroup group = (android.view.ViewGroup) node;
            for (int index = 0; index < group.getChildCount(); index++)
                applyKeyboardGeometry(group.getChildAt(index));
        }
    }

    private void applyKeyboardGeometry() {
        if (keyRows == null) return;
        applyKeyboardGeometry(keyRows);
        keyRows.requestLayout();
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
                || description.toString().startsWith("候选 ")
                || description.toString().startsWith("输入方案卡片 "));
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
        if (schemePanel != null)
            schemePanel.setBackgroundColor(Color.parseColor(skin.background()));
        if (layoutSettingsPanel != null)
            layoutSettingsPanel.setBackgroundColor(Color.parseColor(skin.background()));
        if (handwritingCanvas != null) handwritingCanvas.applySkin(skin);
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

    private void closeSchemePicker() {
        if (schemeScroll != null) schemeScroll.setVisibility(View.GONE);
    }

    private void closeLayoutSettings() {
        if (layoutSettingsScroll != null) layoutSettingsScroll.setVisibility(View.GONE);
    }

    private void renderLayoutSettingsState() {
        if (keySpacingSlider == null || rowSpacingSlider == null
                || keySpacingValue == null || rowSpacingValue == null) return;
        keySpacingSlider.setProgress(touchKeySpacingTenths);
        rowSpacingSlider.setProgress(touchRowSpacingTenths);
        keySpacingSlider.setEnabled(!touchGeometrySaving);
        rowSpacingSlider.setEnabled(!touchGeometrySaving);
        keySpacingValue.setText(KeyboardGeometry.display(touchKeySpacingTenths) + " dp");
        rowSpacingValue.setText(KeyboardGeometry.display(touchRowSpacingTenths) + " dp");
    }

    private void previewTouchGeometry(boolean keySpacing, int value) {
        if (touchGeometrySaving) return;
        if (keySpacing) touchKeySpacingTenths = KeyboardGeometry.keySpacing(value);
        else touchRowSpacingTenths = KeyboardGeometry.rowSpacing(value);
        renderLayoutSettingsState();
        applyKeyboardGeometry();
    }

    private void configureSpacingSlider(SeekBar slider, boolean keySpacing) {
        slider.setMin(keySpacing ? KeyboardGeometry.MIN_KEY_SPACING_TENTHS
            : KeyboardGeometry.MIN_ROW_SPACING_TENTHS);
        slider.setMax(keySpacing ? KeyboardGeometry.MAX_KEY_SPACING_TENTHS
            : KeyboardGeometry.MAX_ROW_SPACING_TENTHS);
        slider.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override public void onProgressChanged(SeekBar source, int progress, boolean fromUser) {
                if (fromUser) previewTouchGeometry(keySpacing, progress);
            }
            @Override public void onStartTrackingTouch(SeekBar source) { }
            @Override public void onStopTrackingTouch(SeekBar source) { saveTouchGeometry(); }
        });
    }

    private void showLayoutSettings() {
        if (touchGeometrySaving || session == 0 || preferencesSnapshot == null
                || preferencesDirectory.isEmpty()) {
            Toast.makeText(this, "键盘设置尚未就绪", Toast.LENGTH_SHORT).show();
            return;
        }
        closeCandidatePanel();
        closeClipboardHistory();
        closeSchemePicker();
        renderLayoutSettingsState();
        layoutSettingsScroll.setVisibility(View.VISIBLE);
    }

    private void saveTouchGeometry() {
        if (touchGeometrySaving || session == 0 || preferencesSnapshot == null
                || preferencesDirectory.isEmpty()) return;
        JSONObject acceptedPreferences = preferencesSnapshot.optJSONObject("preferences");
        if (acceptedPreferences != null
                && KeyboardGeometry.keySpacing(acceptedPreferences.optInt(
                    "touch_key_spacing_tenths", -1)) == touchKeySpacingTenths
                && KeyboardGeometry.rowSpacing(acceptedPreferences.optInt(
                    "touch_row_spacing_tenths", -1)) == touchRowSpacingTenths) return;
        final long targetSession = session;
        final String targetDirectory = preferencesDirectory;
        final JSONObject pending;
        final long expectedRevision;
        try {
            pending = new JSONObject(preferencesSnapshot.toString());
            expectedRevision = pending.getLong("revision");
            if (expectedRevision < 0) throw new JSONException("Invalid preferences revision");
            JSONObject preferences = pending.getJSONObject("preferences");
            preferences.put("touch_key_spacing_tenths", touchKeySpacingTenths);
            preferences.put("touch_row_spacing_tenths", touchRowSpacingTenths);
        } catch (JSONException error) {
            preferencesNotice = " · 键盘间距保存失败，保留原设置";
            render();
            return;
        }
        touchGeometrySaving = true;
        preferencesNotice = " · 正在保存键盘间距";
        final long operation = ++preferenceSaveGeneration;
        renderLayoutSettingsState();
        render();
        Runnable save = () -> {
            String response;
            try {
                response = NativeClient.savePreferences(targetDirectory, expectedRevision,
                    pending.toString());
            } catch (Exception | LinkageError error) {
                response = null;
            }
            final String savedResponse = response;
            main.post(() -> finishTouchGeometrySave(operation, targetSession, targetDirectory,
                savedResponse));
        };
        try {
            preferencesWorker.execute(save);
        } catch (RuntimeException error) {
            if (operation == preferenceSaveGeneration) {
                touchGeometrySaving = false;
                preferencesNotice = " · 键盘间距保存失败，保留原设置";
                renderLayoutSettingsState();
                render();
            }
        }
    }

    private void finishTouchGeometrySave(long operation, long targetSession,
                                         String targetDirectory, String response) {
        if (operation != preferenceSaveGeneration || session != targetSession
                || !targetDirectory.equals(preferencesDirectory)) return;
        touchGeometrySaving = false;
        try {
            if (response == null) throw new JSONException("Preferences save unavailable");
            JSONObject saved = value(response);
            long savedRevision = saved.getLong("revision");
            if (preferencesSnapshot != null
                    && preferencesSnapshot.optLong("revision", -1) > savedRevision) {
                applyTouchGeometry(preferencesSnapshot.optJSONObject("preferences"));
                applyKeyboardGeometry();
                preferencesNotice = "";
            } else {
                applyPreferencesSnapshot(saved);
                preferencesNotice = " · 键盘间距已保存";
            }
        } catch (JSONException | LinkageError error) {
            if (preferencesSnapshot != null)
                applyTouchGeometry(preferencesSnapshot.optJSONObject("preferences"));
            applyKeyboardGeometry();
            preferencesNotice = " · 键盘间距保存失败，已恢复原设置";
            Toast.makeText(this, "键盘间距未能保存", Toast.LENGTH_SHORT).show();
        }
        renderLayoutSettingsState();
        render();
    }

    private void showSchemePicker() {
        if (touchGeometrySaving || session == 0 || preferencesSnapshot == null
                || preferencesDirectory.isEmpty()) {
            Toast.makeText(this, "输入方案尚未就绪", Toast.LENGTH_SHORT).show();
            return;
        }
        closeCandidatePanel();
        closeClipboardHistory();
        closeLayoutSettings();
        renderSchemePicker();
        schemeScroll.setVisibility(View.VISIBLE);
    }

    private void renderSchemePicker() {
        if (schemePanel == null) return;
        schemePanel.removeAllViews();
        LinearLayout header = new LinearLayout(this);
        TextView title = new TextView(this);
        title.setText("输入方案");
        title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 18);
        header.addView(title, new LinearLayout.LayoutParams(0,
            LinearLayout.LayoutParams.WRAP_CONTENT, 1));
        Button close = button(header, "返回键盘", this::closeSchemePicker);
        close.setContentDescription("返回键盘");
        schemePanel.addView(header);
        KeyboardScheme[] schemes = KeyboardScheme.values();
        for (int start = 0; start < schemes.length; start += 4) {
            LinearLayout row = new LinearLayout(this);
            row.setOrientation(LinearLayout.HORIZONTAL);
            for (int slot = 0; slot < 4; slot++) {
                int index = start + slot;
                if (index >= schemes.length) {
                    View spacer = new View(this);
                    row.addView(spacer, new LinearLayout.LayoutParams(0, pixels(72), 1));
                    continue;
                }
                KeyboardScheme scheme = schemes[index];
                Button card = button(row, scheme.glyph() + " " + scheme.badge() + "\n" + scheme.title(),
                    () -> selectKeyboardScheme(scheme));
                card.setSelected(scheme == selectedScheme);
                card.setEnabled(!schemeSaving);
                card.setContentDescription("输入方案卡片 " + scheme.title());
                if (Build.VERSION.SDK_INT >= 30)
                    card.setStateDescription(scheme == selectedScheme ? "已选中" : "未选中");
                LinearLayout.LayoutParams params = (LinearLayout.LayoutParams) card.getLayoutParams();
                params.height = pixels(72);
                card.setLayoutParams(params);
                styleButton(card, true);
            }
            schemePanel.addView(row);
        }
        TextView hint = new TextView(this);
        hint.setText("切换会先完成当前组词，并同步到共享设置");
        schemePanel.addView(hint);
        applySkin();
    }

    private void selectKeyboardScheme(KeyboardScheme scheme) {
        if (schemeSaving || touchGeometrySaving || session == 0 || preferencesSnapshot == null
                || preferencesDirectory.isEmpty()) return;
        if (scheme == selectedScheme) {
            closeSchemePicker();
            return;
        }
        final long targetSession = session;
        final String targetDirectory = preferencesDirectory;
        final JSONObject pending;
        final long expectedRevision;
        try {
            // Scheme replacement is never deferred: complete Engine composition first.
            apply(NativeClient.command(targetSession, 9));
            if (session != targetSession || preferencesSnapshot == null
                    || !targetDirectory.equals(preferencesDirectory)) return;
            pending = new JSONObject(preferencesSnapshot.toString());
            expectedRevision = pending.getLong("revision");
            if (expectedRevision < 0) throw new JSONException("Invalid preferences revision");
            JSONObject preferences = pending.getJSONObject("preferences");
            String currentScheme = preferences.optString("scheme", "quanpin");
            String lastChinese = preferences.optString("last_chinese_scheme", currentScheme);
            KeyboardScheme.PreferenceMapping mapping = scheme.mapping(lastChinese,
                preferences.optString("shuangpin_profile", "xiaohe"));
            preferences.put("scheme", mapping.scheme());
            preferences.put("last_chinese_scheme", mapping.lastChineseScheme());
            preferences.put("shuangpin_profile", mapping.shuangpinProfile());
            preferences.put("touch_keyboard_layout", mapping.touchKeyboardLayout());
        } catch (JSONException | LinkageError error) {
            preferencesNotice = " · 输入方案切换失败，保留当前设置";
            closeSchemePicker();
            render();
            return;
        }
        closeSchemePicker();
        schemeSaving = true;
        preferencesNotice = " · 正在切换输入方案";
        final long operation = ++preferenceSaveGeneration;
        render();
        Runnable save = () -> {
            String response;
            try {
                response = NativeClient.savePreferences(targetDirectory, expectedRevision, pending.toString());
            } catch (Exception | LinkageError error) {
                response = null;
            }
            final String savedResponse = response;
            main.post(() -> finishSchemeSave(operation, targetSession, targetDirectory, savedResponse));
        };
        try {
            preferencesWorker.execute(save);
        } catch (RuntimeException error) {
            if (operation == preferenceSaveGeneration) {
                schemeSaving = false;
                preferencesNotice = " · 输入方案切换失败，保留当前设置";
                render();
            }
        }
    }

    private void finishSchemeSave(long operation, long targetSession, String targetDirectory,
                                  String response) {
        if (operation != preferenceSaveGeneration || session != targetSession
                || !targetDirectory.equals(preferencesDirectory)) return;
        schemeSaving = false;
        try {
            if (response == null) throw new JSONException("Preferences save unavailable");
            JSONObject saved = value(response);
            long savedRevision = saved.getLong("revision");
            if (preferencesSnapshot != null
                    && preferencesSnapshot.optLong("revision", -1) > savedRevision) {
                preferencesNotice = "";
            } else {
                applyPreferencesSnapshot(saved);
                preferencesNotice = " · 输入方案已切换";
            }
        } catch (JSONException | LinkageError error) {
            // A conflict or storage failure leaves the working session unchanged.
            preferencesNotice = " · 输入方案切换失败，保留当前设置";
            Toast.makeText(this, "输入方案未能保存", Toast.LENGTH_SHORT).show();
        }
        render();
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
        closeSchemePicker();
        closeLayoutSettings();
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

    private boolean handwritingActive() {
        return session != 0 && keyboardLayer == KeyboardLayout.Layer.LETTERS
            && touchLayout(view) == HANDWRITING_LAYOUT && handwritingCanvas != null;
    }

    private void deactivateHandwriting() {
        if (handwritingRecognitionTask != null) main.removeCallbacks(handwritingRecognitionTask);
        if (handwritingAvailabilityTask != null) main.removeCallbacks(handwritingAvailabilityTask);
        handwritingRecognitionTask = null;
        handwritingAvailabilityTask = null;
        handwritingRequests.invalidate();
        if (handwritingRecognizer != null) {
            try { handwritingRecognizer.cancelPending(); } catch (RuntimeException ignored) { }
            try { handwritingRecognizer.close(); } catch (RuntimeException ignored) { }
        }
        handwritingRecognizer = null;
        handwritingCanvas = null;
        handwritingCandidates = null;
        handwritingStatus = null;
        handwritingDownload = null;
        handwritingDownloading = false;
        handwritingResults = java.util.List.of();
    }

    private void showHandwritingStatus(String text) {
        if (handwritingCandidates == null || handwritingStatus == null) return;
        handwritingCandidates.removeAllViews();
        handwritingStatus.setText(text);
        handwritingCandidates.addView(handwritingStatus);
    }

    private void refreshHandwritingAvailability() {
        if (!handwritingActive() || handwritingRecognizer == null || handwritingDownload == null) return;
        if (handwritingAvailabilityTask != null) {
            main.removeCallbacks(handwritingAvailabilityTask);
            handwritingAvailabilityTask = null;
        }
        HandwritingRecognizer.Availability availability = handwritingRecognizer.availability();
        switch (availability) {
            case UNAVAILABLE -> {
                handwritingCanvas.setAcceptsInk(false);
                handwritingDownload.setVisibility(View.GONE);
                showHandwritingStatus("此构建不含手写识别");
            }
            case DOWNLOAD_REQUIRED -> {
                handwritingCanvas.setAcceptsInk(false);
                handwritingDownload.setText("下载中文手写模型");
                handwritingDownload.setContentDescription("下载中文手写模型；完成后可离线识别");
                handwritingDownload.setEnabled(true);
                handwritingDownload.setVisibility(View.VISIBLE);
                if (!handwritingDownloading) showHandwritingStatus("首次下载后可离线手写");
            }
            case DOWNLOADING -> {
                handwritingCanvas.setAcceptsInk(false);
                handwritingDownload.setText(handwritingDownloading ? "正在下载…" : "正在检查模型…");
                handwritingDownload.setEnabled(false);
                handwritingDownload.setVisibility(View.VISIBLE);
                showHandwritingStatus(handwritingDownloading
                    ? "正在下载中文手写模型…" : "正在检查中文手写模型…");
                HandwritingRecognizer expected = handwritingRecognizer;
                handwritingAvailabilityTask = () -> {
                    if (handwritingRecognizer == expected) refreshHandwritingAvailability();
                };
                main.postDelayed(handwritingAvailabilityTask, 250);
            }
            case READY -> {
                handwritingDownloading = false;
                handwritingCanvas.setAcceptsInk(true);
                handwritingDownload.setVisibility(View.GONE);
                if (!handwritingCanvas.hasInk() && handwritingResults.isEmpty()) {
                    showHandwritingStatus("在此手写，停笔后选字");
                }
            }
        }
    }

    private void downloadHandwritingModel() {
        if (!handwritingActive() || handwritingRecognizer == null
                || handwritingRecognizer.availability() != HandwritingRecognizer.Availability.DOWNLOAD_REQUIRED) {
            return;
        }
        HandwritingRecognizer expected = handwritingRecognizer;
        handwritingDownloading = true;
        try {
            handwritingRecognizer.download(new HandwritingRecognizer.DownloadListener() {
                @Override public void onProgress(int percent) {
                    main.post(() -> {
                        if (handwritingRecognizer != expected || !handwritingActive()) return;
                        showHandwritingStatus(percent > 0
                            ? "模型下载中 " + percent + "%" : "正在连接模型服务…");
                    });
                }

                @Override public void onComplete() {
                    main.post(() -> {
                        if (handwritingRecognizer != expected || !handwritingActive()) return;
                        handwritingDownloading = false;
                        refreshHandwritingAvailability();
                    });
                }

                @Override public void onFailure() {
                    main.post(() -> {
                        if (handwritingRecognizer != expected || !handwritingActive()) return;
                        handwritingDownloading = false;
                        refreshHandwritingAvailability();
                        showHandwritingStatus("下载失败，请检查网络后重试");
                    });
                }
            });
        } catch (RuntimeException error) {
            handwritingDownloading = false;
            showHandwritingStatus("下载失败，请检查网络后重试");
        }
        refreshHandwritingAvailability();
    }

    private void invalidateHandwritingRecognition() {
        if (handwritingRecognitionTask != null) main.removeCallbacks(handwritingRecognitionTask);
        handwritingRecognitionTask = null;
        handwritingRequests.invalidate();
        handwritingResults = java.util.List.of();
        if (handwritingRecognizer != null) {
            try { handwritingRecognizer.cancelPending(); } catch (RuntimeException ignored) { }
        }
    }

    private void handwritingInkChanged(long revision,
                                       java.util.List<java.util.List<HandwritingInk.Point>> strokes) {
        invalidateHandwritingRecognition();
        if (!handwritingActive() || handwritingCanvas == null) return;
        if (strokes.isEmpty()) {
            showHandwritingStatus("在此手写，停笔后选字");
            return;
        }
        if (handwritingRecognizer == null
                || handwritingRecognizer.availability() != HandwritingRecognizer.Availability.READY) {
            refreshHandwritingAvailability();
            return;
        }
        showHandwritingStatus("停笔后识别…");
        HandwritingRequestTracker.Token token = handwritingRequests.begin(session, revision);
        handwritingRecognitionTask = () -> recognizeHandwriting(token, strokes);
        main.postDelayed(handwritingRecognitionTask, HANDWRITING_DEBOUNCE_MILLIS);
    }

    private boolean acceptsHandwriting(HandwritingRequestTracker.Token token) {
        return handwritingCanvas != null && handwritingRequests.accepts(token, session,
            handwritingCanvas.revision(), handwritingActive());
    }

    private void recognizeHandwriting(HandwritingRequestTracker.Token token,
                                      java.util.List<java.util.List<HandwritingInk.Point>> strokes) {
        handwritingRecognitionTask = null;
        if (!acceptsHandwriting(token) || handwritingRecognizer == null
                || handwritingRecognizer.availability() != HandwritingRecognizer.Availability.READY) {
            return;
        }
        final HandwritingRecognizer expected = handwritingRecognizer;
        final HandwritingRecognizer.Request request;
        try {
            request = new HandwritingRecognizer.Request(token.revision(), strokes,
                handwritingCanvas.getWidth(), handwritingCanvas.getHeight());
        } catch (IllegalArgumentException error) {
            showHandwritingStatus("书写区域不可用，请重试");
            return;
        }
        showHandwritingStatus("正在识别…");
        try {
            handwritingRecognizer.recognize(request, new HandwritingRecognizer.RecognitionListener() {
                @Override public void onResult(long revision, java.util.List<String> values) {
                    main.post(() -> {
                        if (handwritingRecognizer != expected || revision != token.revision()
                                || !acceptsHandwriting(token)) return;
                        handwritingResults = HandwritingRecognizer.sanitizeCandidates(values);
                        renderHandwritingCandidates(token);
                    });
                }

                @Override public void onFailure(long revision) {
                    main.post(() -> {
                        if (handwritingRecognizer != expected || revision != token.revision()
                                || !acceptsHandwriting(token)) return;
                        handwritingResults = java.util.List.of();
                        showHandwritingStatus("识别失败，请撤销或重新书写");
                    });
                }
            });
        } catch (RuntimeException error) {
            if (acceptsHandwriting(token)) showHandwritingStatus("识别失败，请撤销或重新书写");
        }
    }

    private void renderHandwritingCandidates(HandwritingRequestTracker.Token token) {
        if (handwritingCandidates == null || handwritingStatus == null) return;
        handwritingCandidates.removeAllViews();
        if (handwritingResults.isEmpty()) {
            showHandwritingStatus("未识别，请撤销或重新书写");
            return;
        }
        for (int index = 0; index < handwritingResults.size(); index++) {
            String candidate = handwritingResults.get(index);
            Button choice = keyboardKey(candidate, "手写候选 " + (index + 1),
                () -> commitHandwritingCandidate(token, candidate));
            choice.setTextSize(TypedValue.COMPLEX_UNIT_SP, 21);
            handwritingCandidates.addView(choice, new LinearLayout.LayoutParams(
                pixels(48), LinearLayout.LayoutParams.MATCH_PARENT));
        }
        applySkin();
    }

    private void clearHandwriting() {
        invalidateHandwritingRecognition();
        if (handwritingCanvas != null) handwritingCanvas.clear();
        showHandwritingStatus("在此手写，停笔后选字");
    }

    private void deleteFromHandwriting() {
        if (handwritingCanvas != null && handwritingCanvas.hasInk()) {
            handwritingCanvas.undo();
        } else if (connection != null && !command(0)) {
            connection.deleteSurroundingTextInCodePoints(1, 0);
        }
    }

    private void commitHandwritingCandidate(HandwritingRequestTracker.Token token, String candidate) {
        if (!acceptsHandwriting(token) || !handwritingResults.contains(candidate)
                || connection == null) return;
        long targetSession = session;
        command(9);
        if (targetSession != session || !acceptsHandwriting(token) || connection == null) return;
        if (connection.commitText(candidate, 1)) clearHandwriting();
    }

    private void rebuildHandwritingRows() {
        handwritingCandidates = new LinearLayout(this);
        handwritingCandidates.setOrientation(LinearLayout.HORIZONTAL);
        handwritingStatus = new TextView(this);
        handwritingStatus.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        HorizontalScrollView candidateScroll = new HorizontalScrollView(this);
        candidateScroll.setHorizontalScrollBarEnabled(false);
        candidateScroll.setContentDescription("手写候选");
        candidateScroll.addView(handwritingCandidates);
        keyRows.addView(candidateScroll, new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, pixels(48)));

        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        FrameLayout canvasFrame = new FrameLayout(this);
        handwritingCanvas = new HandwritingCanvas(this);
        handwritingCanvas.applySkin(skin);
        canvasFrame.addView(handwritingCanvas, new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
        handwritingDownload = new Button(this);
        handwritingDownload.setAllCaps(false);
        handwritingDownload.setOnClickListener(ignored -> {
            playFeedback(handwritingDownload);
            downloadHandwritingModel();
        });
        FrameLayout.LayoutParams downloadParams = new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, pixels(48));
        downloadParams.gravity = Gravity.CENTER;
        downloadParams.leftMargin = pixels(16);
        downloadParams.rightMargin = pixels(16);
        canvasFrame.addView(handwritingDownload, downloadParams);
        row.addView(canvasFrame, new LinearLayout.LayoutParams(0, pixels(220), 1));

        LinearLayout tools = new LinearLayout(this);
        tools.setOrientation(LinearLayout.VERTICAL);
        addNineKey(tools, keyboardKey("撤销", "撤销最后一笔", () -> {
            if (handwritingCanvas != null) handwritingCanvas.undo();
        }));
        addNineKey(tools, keyboardKey("清空", "清空手写", this::clearHandwriting));
        addNineKey(tools, keyboardKey("⌫", "删除", this::deleteFromHandwriting));
        row.addView(tools, new LinearLayout.LayoutParams(pixels(64), pixels(220)));
        keyRows.addView(row);

        handwritingRecognizer = HandwritingRecognizerFactory.create(this);
        handwritingCanvas.setListener(new HandwritingCanvas.Listener() {
            @Override public void onStrokeBegan() {
                invalidateHandwritingRecognition();
                showHandwritingStatus("书写中…");
            }

            @Override public void onInkChanged(long revision,
                    java.util.List<java.util.List<HandwritingInk.Point>> strokes) {
                handwritingInkChanged(revision, strokes);
            }
        });
        refreshHandwritingAvailability();
    }

    private void rebuildKeyRows() {
        if (keyRows == null) return;
        deactivateHandwriting();
        keyRows.removeAllViews();
        if (keyboardLayer == KeyboardLayout.Layer.LETTERS) {
            if (touchLayout(view) == HANDWRITING_LAYOUT) {
                rebuildHandwritingRows();
                applyKeyboardGeometry();
                return;
            }
            if (touchLayout(view) == QUANPIN_NINE_KEY_LAYOUT) {
                rebuildNineKeyRows();
                applyKeyboardGeometry();
                return;
            }
            if (touchLayout(view) == JAPANESE_NINE_KEY_LAYOUT) {
                rebuildJapaneseNineKeyRows();
                applyKeyboardGeometry();
                return;
            }
        }
        for (java.util.List<String> keys : KeyboardLayout.rows(keyboardLayer, shift)) {
            LinearLayout row = new LinearLayout(this);
            keyRows.addView(row);
            for (String key : keys) {
                final String input = key;
                Button keyButton = keyboardKey(key, key, () -> type(input.charAt(0)));
                row.addView(keyButton, new LinearLayout.LayoutParams(0,
                    LinearLayout.LayoutParams.WRAP_CONTENT, 1));
            }
        }
        applyKeyboardGeometry();
    }

    private void addNineKey(LinearLayout parent, Button key) {
        boolean horizontal = parent.getOrientation() == LinearLayout.HORIZONTAL;
        parent.addView(key, new LinearLayout.LayoutParams(
            horizontal ? 0 : LinearLayout.LayoutParams.MATCH_PARENT,
            horizontal ? LinearLayout.LayoutParams.MATCH_PARENT : 0, 1));
    }

    private void rebuildNineKeyRows() {
        LinearLayout container = new LinearLayout(this);
        container.setOrientation(LinearLayout.HORIZONTAL);
        keyRows.addView(container, new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, pixels(180)));

        LinearLayout punctuation = new LinearLayout(this);
        punctuation.setOrientation(LinearLayout.VERTICAL);
        for (String symbol : NineKeyLayout.punctuation()) {
            Button key = keyboardKey(symbol, "符号 " + symbol, () -> commitNineKeyLiteral(symbol));
            punctuation.addView(key, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 0, 1));
        }
        container.addView(punctuation, new LinearLayout.LayoutParams(0,
            LinearLayout.LayoutParams.MATCH_PARENT, 0.7f));

        LinearLayout grid = new LinearLayout(this);
        grid.setOrientation(LinearLayout.VERTICAL);
        for (java.util.List<NineKeyLayout.Key> keys : NineKeyLayout.rows()) {
            LinearLayout row = new LinearLayout(this);
            for (NineKeyLayout.Key key : keys) {
                addNineKey(row, keyboardKey(key.label(), key.description(),
                    () -> character(key.input())));
            }
            grid.addView(row, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 0, 1));
        }
        container.addView(grid, new LinearLayout.LayoutParams(0,
            LinearLayout.LayoutParams.MATCH_PARENT, 3));

        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.VERTICAL);
        Button delete = keyboardKey("⌫", "删除", () -> {
            if (connection != null && !command(0)) connection.deleteSurroundingTextInCodePoints(1, 0);
        });
        addNineKey(actions, delete);
        addNineKey(actions, keyboardKey("重输", "清空当前拼音重新输入", () -> command(3)));
        addNineKey(actions, keyboardKey("0", "数字 0", () -> commitNineKeyLiteral("0")));
        container.addView(actions, new LinearLayout.LayoutParams(0,
            LinearLayout.LayoutParams.MATCH_PARENT, 0.8f));
    }

    private static String japaneseKeyLabel(JapaneseNineKeyLayout.Key key) {
        return key.kana().get(0) + "\n" + String.join(" ", key.kana().subList(1, 5));
    }

    private void inputJapaneseStroke(String input) {
        if (session == 0 || input.isEmpty()) return;
        for (int index = 0; index < input.length(); index++) character(input.charAt(index));
    }

    private void selectJapaneseKey(JapaneseNineKeyLayout.Key key, int direction) {
        if (direction < 0 || direction >= key.kana().size()) return;
        String stroke = key.strokes().get(direction);
        if (stroke.isEmpty()) commitNineKeyLiteral(key.kana().get(direction));
        else inputJapaneseStroke(stroke);
    }

    private void showJapaneseKeyChoices(Button anchor, JapaneseNineKeyLayout.Key key) {
        PopupMenu popup = new PopupMenu(this, anchor);
        for (int index = 0; index < key.kana().size(); index++) {
            final int direction = index;
            popup.getMenu().add(key.kana().get(index)).setOnMenuItemClickListener(ignored -> {
                playFeedback(anchor);
                selectJapaneseKey(key, direction);
                return true;
            });
        }
        popup.show();
    }

    private void bindJapaneseFlick(Button button, JapaneseNineKeyLayout.Key key) {
        final float[] origin = new float[2];
        final int[] direction = new int[1];
        final boolean[] longPressed = new boolean[1];
        final String label = japaneseKeyLabel(key);
        button.setOnLongClickListener(ignored -> {
            playFeedback(button);
            showJapaneseKeyChoices(button, key);
            return true;
        });
        Runnable longPress = () -> {
            if (!button.isAttachedToWindow() || !button.isPressed()) return;
            longPressed[0] = true;
            button.setPressed(false);
            button.performLongClick();
        };
        button.setOnTouchListener((ignored, event) -> {
            switch (event.getActionMasked()) {
                case MotionEvent.ACTION_DOWN -> {
                    origin[0] = event.getX();
                    origin[1] = event.getY();
                    direction[0] = 0;
                    longPressed[0] = false;
                    button.setPressed(true);
                    main.postDelayed(longPress, ViewConfiguration.getLongPressTimeout());
                    return true;
                }
                case MotionEvent.ACTION_MOVE -> {
                    direction[0] = JapaneseNineKeyLayout.direction(
                        event.getX() - origin[0], event.getY() - origin[1], pixels(12));
                    if (direction[0] != 0) main.removeCallbacks(longPress);
                    button.setText(key.kana().get(direction[0]));
                    return true;
                }
                case MotionEvent.ACTION_UP -> {
                    main.removeCallbacks(longPress);
                    button.setPressed(false);
                    button.setText(label);
                    if (longPressed[0]) return true;
                    if (direction[0] == 0) button.performClick();
                    else {
                        playFeedback(button);
                        selectJapaneseKey(key, direction[0]);
                    }
                    return true;
                }
                case MotionEvent.ACTION_CANCEL -> {
                    main.removeCallbacks(longPress);
                    button.setPressed(false);
                    button.setText(label);
                    return true;
                }
                default -> {
                    return true;
                }
            }
        });
    }

    private Button japaneseKey(JapaneseNineKeyLayout.Key key) {
        Button button = keyboardKey(japaneseKeyLabel(key), String.join("、", key.kana()),
            () -> selectJapaneseKey(key, 0));
        button.setContentDescription("轻点输入" + key.kana().get(0)
            + "；左、上、右、下滑动选择其他假名；长按显示全部选项");
        bindJapaneseFlick(button, key);
        return button;
    }

    private void showJapaneseVariants(Button anchor) {
        PopupMenu popup = new PopupMenu(this, anchor);
        for (JapaneseNineKeyLayout.VariantGroup group : JapaneseNineKeyLayout.variants()) {
            android.view.SubMenu submenu = popup.getMenu().addSubMenu(group.title());
            for (int index = 0; index < group.kana().size(); index++) {
                final String input = group.strokes().get(index);
                submenu.add(group.kana().get(index)).setOnMenuItemClickListener(ignored -> {
                    playFeedback(anchor);
                    inputJapaneseStroke(input);
                    return true;
                });
            }
        }
        popup.show();
    }

    private void rebuildJapaneseNineKeyRows() {
        LinearLayout container = new LinearLayout(this);
        container.setOrientation(LinearLayout.HORIZONTAL);
        keyRows.addView(container, new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, pixels(180)));

        LinearLayout grid = new LinearLayout(this);
        grid.setOrientation(LinearLayout.VERTICAL);
        java.util.List<JapaneseNineKeyLayout.Key> keys = JapaneseNineKeyLayout.keys();
        for (int rowIndex = 0; rowIndex < 3; rowIndex++) {
            LinearLayout row = new LinearLayout(this);
            for (int column = 0; column < 3; column++) {
                addNineKey(row, japaneseKey(keys.get(rowIndex * 3 + column)));
            }
            grid.addView(row, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 0, 1));
        }
        container.addView(grid, new LinearLayout.LayoutParams(0,
            LinearLayout.LayoutParams.MATCH_PARENT, 3));

        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.VERTICAL);
        addNineKey(actions, japaneseKey(keys.get(9)));
        Button variants = keyboardKey("小゛゜", "小假名、浊音和半浊音", () -> {});
        variants.setOnClickListener(ignored -> {
            playFeedback(variants);
            showJapaneseVariants(variants);
        });
        addNineKey(actions, variants);
        addNineKey(actions, keyboardKey("⌫", "删除", () -> {
            if (connection != null && !command(0)) connection.deleteSurroundingTextInCodePoints(1, 0);
        }));
        container.addView(actions, new LinearLayout.LayoutParams(0,
            LinearLayout.LayoutParams.MATCH_PARENT, 0.8f));
    }

    private void commitNineKeyLiteral(String text) {
        if (connection == null) return;
        command(9);
        connection.commitText(text, 1);
    }

    private void chooseNineKeySpelling(long generation, int index) {
        if (session == 0) return;
        try { apply(NativeClient.chooseNineKeySpelling(session, generation, index)); }
        catch (JSONException | LinkageError error) { fail(); }
    }

    private void renderNineKeySpellings() {
        if (nineKeySpellings == null || nineKeySpellingScroll == null) return;
        nineKeySpellings.removeAllViews();
        JSONArray spellings = view == null ? null : view.optJSONArray("nine_key_spellings");
        boolean visible = touchLayout(view) == QUANPIN_NINE_KEY_LAYOUT
            && spellings != null && spellings.length() > 0;
        nineKeySpellingScroll.setVisibility(visible ? View.VISIBLE : View.GONE);
        if (!visible) return;
        long generation = view.optLong("generation", -1);
        for (int index = 0; index < spellings.length(); index++) {
            String spelling = spellings.optString(index, "");
            if (spelling.isEmpty()) continue;
            final int choice = index;
            Button key = button(nineKeySpellings, spelling,
                () -> chooseNineKeySpelling(generation, choice));
            key.setContentDescription("选择拼音 " + spelling);
            LinearLayout.LayoutParams params = (LinearLayout.LayoutParams) key.getLayoutParams();
            params.width = LinearLayout.LayoutParams.WRAP_CONTENT;
            params.weight = 0;
            key.setLayoutParams(params);
        }
    }

    @Override public View onCreateInputView() {
        deactivateHandwriting();
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
        nineKeySpellings = new LinearLayout(this);
        nineKeySpellings.setOrientation(LinearLayout.HORIZONTAL);
        nineKeySpellingScroll = new HorizontalScrollView(this);
        nineKeySpellingScroll.setHorizontalScrollBarEnabled(false);
        nineKeySpellingScroll.setContentDescription("九键拼音选择");
        nineKeySpellingScroll.addView(nineKeySpellings);
        nineKeySpellingScroll.setVisibility(View.GONE);
        candidateRegion.addView(nineKeySpellingScroll);
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
        shiftButton = button(controls, "Shift", () -> {
            shift = !shift;
            shiftButton.setSelected(shift);
            shiftButton.setContentDescription(shift ? "大写已开启" : "切换大写");
            rebuildKeyRows();
            render();
        });
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
        schemeButton = button(controls, "方案", this::showSchemePicker);
        schemeButton.setContentDescription("选择输入方案");
        layoutSettingsButton = button(controls, "设置", this::showLayoutSettings);
        layoutSettingsButton.setContentDescription("键盘设置");
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
        schemePanel = new LinearLayout(this);
        schemePanel.setOrientation(LinearLayout.VERTICAL);
        schemePanel.setPadding(24, 16, 24, 16);
        schemePanel.setBackgroundColor(Color.parseColor(skin.background()));
        schemePanel.setContentDescription("输入方案选择器");
        schemeScroll = new ScrollView(this);
        schemeScroll.addView(schemePanel);
        schemeScroll.setVisibility(View.GONE);
        keyboardRoot.addView(schemeScroll, new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
        layoutSettingsPanel = new LinearLayout(this);
        layoutSettingsPanel.setOrientation(LinearLayout.VERTICAL);
        layoutSettingsPanel.setPadding(24, 16, 24, 16);
        layoutSettingsPanel.setBackgroundColor(Color.parseColor(skin.background()));
        layoutSettingsPanel.setContentDescription("键盘设置");
        LinearLayout layoutHeader = new LinearLayout(this);
        TextView layoutTitle = new TextView(this);
        layoutTitle.setText("键盘设置");
        layoutTitle.setTextSize(TypedValue.COMPLEX_UNIT_SP, 18);
        layoutHeader.addView(layoutTitle, new LinearLayout.LayoutParams(0,
            LinearLayout.LayoutParams.WRAP_CONTENT, 1));
        Button closeLayout = button(layoutHeader, "返回键盘", this::closeLayoutSettings);
        closeLayout.setContentDescription("返回键盘");
        layoutSettingsPanel.addView(layoutHeader);
        LinearLayout keySpacingHeader = new LinearLayout(this);
        TextView keySpacingLabel = new TextView(this);
        keySpacingLabel.setText("按键间距");
        keySpacingHeader.addView(keySpacingLabel, new LinearLayout.LayoutParams(0,
            LinearLayout.LayoutParams.WRAP_CONTENT, 1));
        keySpacingValue = new TextView(this);
        keySpacingHeader.addView(keySpacingValue);
        layoutSettingsPanel.addView(keySpacingHeader);
        keySpacingSlider = new SeekBar(this);
        keySpacingSlider.setContentDescription("按键间距");
        configureSpacingSlider(keySpacingSlider, true);
        layoutSettingsPanel.addView(keySpacingSlider);
        LinearLayout rowSpacingHeader = new LinearLayout(this);
        TextView rowSpacingLabel = new TextView(this);
        rowSpacingLabel.setText("行间距");
        rowSpacingHeader.addView(rowSpacingLabel, new LinearLayout.LayoutParams(0,
            LinearLayout.LayoutParams.WRAP_CONTENT, 1));
        rowSpacingValue = new TextView(this);
        rowSpacingHeader.addView(rowSpacingValue);
        layoutSettingsPanel.addView(rowSpacingHeader);
        rowSpacingSlider = new SeekBar(this);
        rowSpacingSlider.setContentDescription("行间距");
        configureSpacingSlider(rowSpacingSlider, false);
        layoutSettingsPanel.addView(rowSpacingSlider);
        TextView layoutHint = new TextView(this);
        layoutHint.setText("间距只改变键位外观，不改变输入方案；松手后自动保存。");
        layoutSettingsPanel.addView(layoutHint);
        layoutSettingsScroll = new ScrollView(this);
        layoutSettingsScroll.addView(layoutSettingsPanel);
        layoutSettingsScroll.setVisibility(View.GONE);
        keyboardRoot.addView(layoutSettingsScroll, new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
        renderLayoutSettingsState();
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
        if (shiftButton != null)
            shiftButton.setVisibility(touchLayout(view) != STANDARD_TOUCH_LAYOUT
                && keyboardLayer == KeyboardLayout.Layer.LETTERS ? View.GONE : View.VISIBLE);
        if (schemeButton != null) {
            schemeButton.setText(selectedScheme.glyph() + selectedScheme.badge());
            schemeButton.setContentDescription("输入方案：" + selectedScheme.title());
            schemeButton.setEnabled(session != 0 && preferencesSnapshot != null
                && !schemeSaving && !touchGeometrySaving);
        }
        if (layoutSettingsButton != null)
            layoutSettingsButton.setEnabled(session != 0 && preferencesSnapshot != null
                && !schemeSaving && !touchGeometrySaving);
        renderNineKeySpellings();
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
