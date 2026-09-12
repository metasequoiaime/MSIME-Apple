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
import android.widget.Switch;
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
    private static final String SCHEME_HOST_PREFERENCES = "android-keyboard-schemes";
    private static final String SELECTED_HOST_SCHEME = "selected-scheme";
    private static final String THOUGHTFUL_REPLY_ENABLED = "thoughtful-reply-enabled";
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
    private Switch voiceShortcutSwitch;
    private TextView keySpacingValue;
    private TextView rowSpacingValue;
    private ClipboardHistoryStore clipboardHistory;
    private boolean clipboardHistoryEnabled;
    private boolean candidateHorizontal;
    private int candidateFontSize = 16;
    private int candidatePreeditFontSize = 16;
    private int touchKeySpacingTenths = KeyboardGeometry.DEFAULT_KEY_SPACING_TENTHS;
    private int touchRowSpacingTenths = KeyboardGeometry.DEFAULT_ROW_SPACING_TENTHS;
    private boolean touchVoiceShortcutEnabled;
    private boolean voiceInputEnabled = true;
    private String voiceLanguage = "zh-CN";
    private KeyboardSkin skin = KeyboardSkin.from("fluent");
    private JSONObject localModes = new JSONObject();
    private Button moreButton;
    private Button schemeButton;
    private Button skinButton;
    private Button layoutSettingsButton;
    private Button voiceShortcutButton;
    private Button aiPolishShortcutButton;
    private Button replyShortcutButton;
    private KeyboardScheme selectedScheme = KeyboardScheme.QUANPIN;
    private KeyboardScheme schemeSaveTarget;
    private SharedPreferences schemeHostPreferences;
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
    private Button enterButton;
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
    private boolean skinSaving;
    private ScrollView voiceResultScroll;
    private LinearLayout voiceResultPanel;
    private VoiceResultStore voiceResultStore;
    private VoiceResultStore.Entry voiceResultEntry;
    private EditorContextSnapshot voiceTarget;
    private ScrollView aiPolishScroll;
    private LinearLayout aiPolishContainer;
    private LinearLayout aiPolishPanel;
    private LinearLayout aiPolishActions;
    private AiPolishConfiguration aiPolishConfiguration;
    private AiPolishConfiguration aiRequestConfiguration;
    private AiPolishClient.Operation aiOperation;
    private EditorContextSnapshot aiTarget;
    private String aiSourceText = "";
    private String aiOutputText = "";
    private String aiError = "";
    private boolean aiBusy;
    private LinearLayout replyKeyboard;
    private LinearLayout replyMain;
    private LinearLayout replyActions;
    private TextView replyStatus;
    private Button replyReplyModeButton;
    private Button replyPolishModeButton;
    private Button replySourceButton;
    private Button replyTemplateButton;
    private Button replySkinButton;
    private CommunityReplyLibrary communityReplyLibrary;
    private final ReplyKeyboardModel replyModel = new ReplyKeyboardModel();
    private AiPolishClient.Operation replyOperation;
    private EditorContextSnapshot replyTarget;
    private AiPolishConfiguration replyRequestConfiguration;
    private boolean replySuppressed;
    private long editorContextRevision;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService preferencesWorker = Executors.newSingleThreadExecutor();
    private final AiPolishClient aiPolishClient = new AiPolishClient(new AiPolishHttpTransport());
    private final PreferencesReloader preferencesReloader = new PreferencesReloader(
        (task, delay) -> main.postDelayed(task, delay), preferencesWorker, NativeClient::loadPreferences);

    private boolean thoughtfulReplyEnabled() {
        return schemeHostPreferences == null
            || schemeHostPreferences.getBoolean(THOUGHTFUL_REPLY_ENABLED, true);
    }

    private KeyboardScheme hostScheme(KeyboardScheme engineScheme) {
        String stored = schemeHostPreferences == null ? null
            : schemeHostPreferences.getString(SELECTED_HOST_SCHEME, null);
        KeyboardScheme resolved = KeyboardScheme.fromHostSelection(
            stored, thoughtfulReplyEnabled(), engineScheme);
        if (resolved != KeyboardScheme.THOUGHTFUL_REPLY && stored != null
                && !resolved.name().equals(stored)) saveHostScheme(resolved);
        return resolved;
    }

    private void saveHostScheme(KeyboardScheme scheme) {
        if (schemeHostPreferences != null)
            schemeHostPreferences.edit().putString(SELECTED_HOST_SCHEME, scheme.name()).apply();
    }

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
        editorContextRevision++;
        bridge = new EditorBridge();
        schemeHostPreferences = getSharedPreferences(SCHEME_HOST_PREFERENCES, MODE_PRIVATE);
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
                selectedScheme = hostScheme(KeyboardScheme.fromPreferences(
                    preferences == null ? "quanpin" : preferences.optString("scheme", "quanpin"),
                    preferences == null ? "xiaohe" : preferences.optString("shuangpin_profile", "xiaohe"),
                    preferences == null ? "twenty_six_key"
                        : preferences.optString("touch_keyboard_layout", "twenty_six_key")));
                skin = KeyboardSkin.from(preferences == null ? "fluent"
                    : preferences.optString("candidate_skin", "fluent"));
                localModes = preferences == null ? new JSONObject()
                    : preferences.optJSONObject("local_modes");
                if (localModes == null) localModes = new JSONObject();
                applyCandidateAppearance(preferences);
                applyTouchGeometry(preferences);
                applyVoicePreferences(preferences);
                applyAiPreferences(preferences);
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
        replySuppressed = false;
        synchronizeReplyKeyboard();
    }

    @Override public void onFinishInput() { stop(true); connection = null; super.onFinishInput(); }
    @Override public void onDestroy() {
        stop(false);
        preferencesWorker.shutdown();
        aiPolishClient.close();
        connection = null;
        super.onDestroy();
    }
    @Override public boolean onEvaluateFullscreenMode() { return false; }

    private void stop(boolean finish) {
        deactivateHandwriting();
        preferencesReloader.stop();
        preferenceSaveGeneration++;
        preferencesDirectory = "";
        preferencesSnapshot = null;
        schemeSaving = false;
        schemeSaveTarget = null;
        touchGeometrySaving = false;
        skinSaving = false;
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
        closeVoiceResult();
        closeAiPolish();
        closeReplyKeyboard();
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
        touchVoiceShortcutEnabled = preferences != null
            && preferences.optBoolean("touch_voice_shortcut", false);
    }

    private void applyVoicePreferences(JSONObject preferences) {
        JSONObject voice = preferences == null ? null : preferences.optJSONObject("voice_input");
        voiceInputEnabled = voice == null || voice.optBoolean("enabled", true);
        voiceLanguage = voice == null ? "zh-CN" : voice.optString("language", "zh-CN");
    }

    private void applyAiPreferences(JSONObject preferences) {
        AiPolishConfiguration next = null;
        JSONObject ai = preferences == null ? null : preferences.optJSONObject("ai_assistant");
        if (ai != null && ai.optBoolean("enabled", false)) {
            try {
                String endpoint = ai.optString("endpoint", "");
                String origin = AiPolishConfiguration.credentialOrigin(endpoint);
                JSONObject tokens = ai.optJSONObject("tokens");
                String token = tokens == null ? "" : tokens.optString(origin, "");
                String prompt = ai.optString("prompt", "");
                if (prompt.trim().isEmpty()) prompt = AiPolishConfiguration.DEFAULT_PROMPT;
                next = new AiPolishConfiguration(endpoint, ai.optString("model", ""), prompt, token);
            } catch (IllegalArgumentException ignored) {
                // Invalid settings disable this entry; never log endpoints, models or credentials.
            }
        }
        AiPolishConfiguration previous = aiPolishConfiguration;
        aiPolishConfiguration = next;
        if (aiPolishContainer != null && aiPolishContainer.getVisibility() == View.VISIBLE
                && aiRequestConfiguration != null && !aiRequestConfiguration.equals(next)) {
            cancelAiRequest();
            aiError = "AI 配置已变化，请返回键盘后重新打开。";
            renderAiPolish();
        }
        if (replyRequestConfiguration != null && !replyRequestConfiguration.equals(next)) {
            invalidateReplyContext("AI 配置已变化，请重新选择回复方式");
        }
        if (previous != null && !previous.equals(next)) render();
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
        return touchKeySpacingTenths + ":" + touchRowSpacingTenths + ":"
            + touchVoiceShortcutEnabled + ":" + voiceInputEnabled + ":" + voiceLanguage;
    }

    private void reloadPreferences(String response) {
        if (session == 0) return;
        String previousView = view == null ? "" : view.toString();
        String previousNotice = preferencesNotice;
        String previousSkin = skin.id();
        String previousAppearance = candidateAppearanceKey();
        String previousGeometry = touchGeometryKey();
        AiPolishConfiguration previousAi = aiPolishConfiguration;
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
                || (previousAi == null ? aiPolishConfiguration != null
                    : !previousAi.equals(aiPolishConfiguration))
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
        boolean nextVoiceShortcut = preferences.optBoolean("touch_voice_shortcut", false);
        JSONObject nextVoice = preferences.optJSONObject("voice_input");
        boolean nextVoiceEnabled = nextVoice == null || nextVoice.optBoolean("enabled", true);
        String nextVoiceLanguage = nextVoice == null ? "zh-CN"
            : nextVoice.optString("language", "zh-CN");
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
        touchVoiceShortcutEnabled = nextVoiceShortcut;
        voiceInputEnabled = nextVoiceEnabled;
        voiceLanguage = nextVoiceLanguage;
        applyAiPreferences(preferences);
        clipboardHistoryEnabled = nextClipboard;
        JSONObject nextView = result.getJSONObject("view");
        boolean rebuildLayout = touchLayout(view) != touchLayout(nextView);
        selectedScheme = hostScheme(nextScheme);
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
        if (voiceResultScroll != null && voiceResultScroll.getVisibility() == View.VISIBLE)
            renderVoiceResult();
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
        boolean disabled = info == null
                || (info.imeOptions & EditorInfo.IME_FLAG_NO_ENTER_ACTION) != 0;
        if (ReturnKeyAction.performsEditorAction(action, disabled)
                && connection.performEditorAction(action)) return;
        connection.commitText("\n", 1);
    }

    private void updateReturnKey() {
        if (enterButton == null) return;
        EditorInfo info = getCurrentInputEditorInfo();
        int action = info == null ? EditorInfo.IME_ACTION_NONE
                : info.imeOptions & EditorInfo.IME_MASK_ACTION;
        boolean disabled = info == null
                || (info.imeOptions & EditorInfo.IME_FLAG_NO_ENTER_ACTION) != 0;
        String title = ReturnKeyAction.title(action, disabled);
        enterButton.setText(title);
        enterButton.setContentDescription(title);
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
        if (oldStart != newStart || oldEnd != newEnd) editorContextRevision++;
        if (aiPolishContainer != null && aiPolishContainer.getVisibility() == View.VISIBLE
                && aiTarget != null && !aiTargetMatches()) {
            cancelAiRequest();
            aiError = "输入位置已变化，请返回键盘后重新选择文字。";
            renderAiPolish();
        }
        if (selectedScheme == KeyboardScheme.THOUGHTFUL_REPLY && replyTarget != null
                && !replyTargetMatches()) {
            invalidateReplyContext("输入位置已变化，请重新选择回复方式");
        }
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
        if (voiceResultPanel != null)
            voiceResultPanel.setBackgroundColor(Color.parseColor(skin.background()));
        if (aiPolishPanel != null)
            aiPolishPanel.setBackgroundColor(Color.parseColor(skin.background()));
        if (aiPolishContainer != null)
            aiPolishContainer.setBackgroundColor(Color.parseColor(skin.background()));
        if (replyKeyboard != null)
            replyKeyboard.setBackgroundColor(Color.parseColor(skin.background()));
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
        synchronizeReplyKeyboard();
    }

    private void closeLayoutSettings() {
        if (layoutSettingsScroll != null) layoutSettingsScroll.setVisibility(View.GONE);
    }

    private void closeVoiceResult() {
        if (voiceResultScroll != null) voiceResultScroll.setVisibility(View.GONE);
        voiceResultEntry = null;
        voiceTarget = null;
    }

    private void cancelAiRequest() {
        if (aiOperation != null) aiOperation.cancel();
        aiOperation = null;
        aiBusy = false;
    }

    private void closeAiPolish() {
        cancelAiRequest();
        if (aiPolishContainer != null) aiPolishContainer.setVisibility(View.GONE);
        aiTarget = null;
        aiRequestConfiguration = null;
        aiSourceText = "";
        aiOutputText = "";
        aiError = "";
    }

    private void clearReplyRequestReferences() {
        replyOperation = null;
        replyTarget = null;
        replyRequestConfiguration = null;
    }

    private void closeReplyKeyboard() {
        replyModel.resetResults();
        clearReplyRequestReferences();
        if (replyKeyboard != null) replyKeyboard.setVisibility(View.GONE);
    }

    private void invalidateReplyContext(String message) {
        replyModel.invalidate(message);
        clearReplyRequestReferences();
        renderReplyKeyboard();
    }

    private boolean replyTargetMatches() {
        return replyTarget != null && replyTarget.matches(connection, editorContextRevision,
            editorContext(true), selectedEditorText(), editorContext(false));
    }

    private boolean replyReady() {
        return selectedScheme == KeyboardScheme.THOUGHTFUL_REPLY && thoughtfulReplyEnabled()
            && aiPolishReady();
    }

    private void synchronizeReplyKeyboard() {
        if (replyKeyboard == null) return;
        if (selectedScheme != KeyboardScheme.THOUGHTFUL_REPLY || !thoughtfulReplyEnabled()) {
            closeReplyKeyboard();
            replySuppressed = false;
            return;
        }
        if (replySuppressed) {
            replyKeyboard.setVisibility(View.GONE);
            return;
        }
        renderReplyKeyboard();
        replyKeyboard.setVisibility(View.VISIBLE);
    }

    private void showReplyKeyboard() {
        if (selectedScheme != KeyboardScheme.THOUGHTFUL_REPLY) return;
        replySuppressed = false;
        closeCandidatePanel();
        closeClipboardHistory();
        closeSchemePicker();
        closeLayoutSettings();
        closeVoiceResult();
        closeAiPolish();
        synchronizeReplyKeyboard();
    }

    private void pasteReplySource() {
        try {
            ClipboardManager manager = getSystemService(ClipboardManager.class);
            if (manager == null || !manager.hasPrimaryClip() || manager.getPrimaryClip() == null
                    || manager.getPrimaryClip().getItemCount() == 0
                    || manager.getPrimaryClipDescription() == null
                    || !(manager.getPrimaryClipDescription().hasMimeType(ClipDescription.MIMETYPE_TEXT_PLAIN)
                        || manager.getPrimaryClipDescription().hasMimeType(ClipDescription.MIMETYPE_TEXT_HTML))) {
                replyModel.setSource("");
            } else {
                CharSequence value = manager.getPrimaryClip().getItemAt(0).getText();
                replyModel.setSource(value == null ? "" : value.toString());
            }
        } catch (SecurityException | IllegalStateException error) {
            replyModel.invalidate("无法读取剪贴板，请重试");
        }
        clearReplyRequestReferences();
        renderReplyKeyboard();
    }

    private void generateReply(String style) {
        if (aiPolishConfiguration == null) {
            replyModel.showStatus("请先在共享设置中启用并配置 AI 辅助");
            renderReplyKeyboard();
            return;
        }
        if (!replyReady()) {
            replyModel.showStatus("请先完成输入，再选择回复方式");
            renderReplyKeyboard();
            return;
        }
        java.util.List<CommunityReplyLibrary.Template> templates = java.util.List.of();
        if (style != null && style.startsWith("community:")) {
            try { templates = communityReplyLibrary == null ? java.util.List.of() : communityReplyLibrary.read(); }
            catch (java.io.IOException error) {
                replyModel.showStatus("回复模板无法读取，请重试");
                renderReplyKeyboard();
                return;
            }
        }
        ReplyKeyboardModel.Request request = replyModel.begin(style, templates);
        if (request == null) {
            renderReplyKeyboard();
            return;
        }
        replyRequestConfiguration = aiPolishConfiguration;
        replyTarget = new EditorContextSnapshot(connection, editorContextRevision, editorContext(true),
            selectedEditorText(), editorContext(false));
        renderReplyKeyboard();
        try {
            AiPolishConfiguration requestConfiguration = aiPolishConfiguration.withPrompt(request.prompt());
            replyOperation = aiPolishClient.request(requestConfiguration, request.source(),
                (generation, result, failure) -> main.post(
                    () -> finishReply(request.generation(), generation, result, failure)));
            replyModel.attachCancellation(request.generation(), replyOperation::cancel);
        } catch (AiPolishClient.Failure | IllegalArgumentException error) {
            replyModel.fail(request.generation(), "无法启动 AI 请求，请检查配置");
            clearReplyRequestReferences();
            renderReplyKeyboard();
        }
    }

    private void finishReply(long modelGeneration, long operationGeneration, String result,
                             AiPolishClient.Failure failure) {
        if (replyOperation == null || replyOperation.generation() != operationGeneration) return;
        replyOperation = null;
        if (!replyTargetMatches() || replyRequestConfiguration == null
                || !replyRequestConfiguration.equals(aiPolishConfiguration)
                || selectedScheme != KeyboardScheme.THOUGHTFUL_REPLY) {
            invalidateReplyContext("输入位置或 AI 配置已变化，请重新选择回复方式");
            return;
        }
        if (failure == null) replyModel.finish(modelGeneration, result);
        else replyModel.fail(modelGeneration, failure.reason() == AiPolishClient.Reason.INVALID
            ? "服务返回的文字为空或超过一万字" : "AI 请求失败，请检查网络、地址、模型和密钥");
        if (!replyModel.busy()) replyOperation = null;
        renderReplyKeyboard();
    }

    private void useReply(String text) {
        boolean inserted = replyModel.use(text, value -> {
            if (!replyReady() || !replyTargetMatches() || replyRequestConfiguration == null
                    || !replyRequestConfiguration.equals(aiPolishConfiguration)
                    || connection == null) return false;
            try {
                if (!connection.commitText(value, 1)) return false;
            } catch (RuntimeException error) { return false; }
            replySuppressed = true;
            return true;
        });
        clearReplyRequestReferences();
        renderReplyKeyboard();
        if (inserted) replyKeyboard.setVisibility(View.GONE);
    }

    private void showReplyTemplates() {
        if (replyTemplateButton == null || replyModel.busy()) return;
        final java.util.List<CommunityReplyLibrary.Template> templates;
        try { templates = communityReplyLibrary == null ? java.util.List.of() : communityReplyLibrary.read(); }
        catch (java.io.IOException error) {
            replyModel.showStatus("回复模板无法读取，请重试");
            renderReplyKeyboard();
            return;
        }
        if (templates.isEmpty()) {
            Toast.makeText(this, "请先在 App 社区收藏并添加回复模板", Toast.LENGTH_SHORT).show();
            return;
        }
        PopupMenu popup = new PopupMenu(this, replyTemplateButton);
        for (CommunityReplyLibrary.Template template : templates) {
            popup.getMenu().add(template.name()).setOnMenuItemClickListener(ignored -> {
                generateReply("community:" + template.id());
                return true;
            });
        }
        popup.show();
    }

    private boolean canSaveKeyboardSkin() {
        return !skinSaving && session != 0 && preferencesSnapshot != null
            && !preferencesDirectory.isEmpty();
    }

    private void showSkinMenu(Button anchor) {
        if (anchor == null || !canSaveKeyboardSkin()) return;
        PopupMenu popup = new PopupMenu(this, anchor);
        for (KeyboardSkin choice : KeyboardSkin.builtIns()) {
            MenuItem item = popup.getMenu().add(choice.title());
            item.setCheckable(true).setChecked(skin.id().equals(choice.id()));
            item.setOnMenuItemClickListener(ignored -> {
                saveKeyboardSkin(choice.id());
                return true;
            });
        }
        popup.show();
    }

    private void showKeyboardSkinStatus(String value) {
        if (replyKeyboard != null && replyKeyboard.getVisibility() == View.VISIBLE) {
            replyModel.showStatus(value);
            renderReplyKeyboard();
        } else {
            Toast.makeText(this, value, Toast.LENGTH_SHORT).show();
        }
    }

    private void saveKeyboardSkin(String identifier) {
        KeyboardSkin next = KeyboardSkin.from(identifier);
        if (skin.id().equals(next.id()) || skinSaving || session == 0
                || preferencesSnapshot == null || preferencesDirectory.isEmpty()) return;
        final long targetSession = session;
        final String targetDirectory = preferencesDirectory;
        final JSONObject pending;
        final long expectedRevision;
        try {
            pending = new JSONObject(preferencesSnapshot.toString());
            expectedRevision = pending.getLong("revision");
            pending.getJSONObject("preferences").put("candidate_skin", next.id());
        } catch (JSONException error) {
            showKeyboardSkinStatus("皮肤切换失败，保留当前皮肤");
            return;
        }
        skin = next;
        skinSaving = true;
        final long operation = ++preferenceSaveGeneration;
        applySkin();
        render();
        try {
            preferencesWorker.execute(() -> {
                String response;
                try { response = NativeClient.savePreferences(targetDirectory, expectedRevision, pending.toString()); }
                catch (Exception | LinkageError error) { response = null; }
                final String savedResponse = response;
                main.post(() -> finishKeyboardSkinSave(operation, targetSession, targetDirectory, savedResponse));
            });
        } catch (RuntimeException error) {
            finishKeyboardSkinSave(operation, targetSession, targetDirectory, null);
        }
    }

    private void finishKeyboardSkinSave(long operation, long targetSession, String targetDirectory,
                                        String response) {
        if (operation != preferenceSaveGeneration || session != targetSession
                || !targetDirectory.equals(preferencesDirectory)) return;
        skinSaving = false;
        try {
            if (response == null) throw new JSONException("Preferences save unavailable");
            applyPreferencesSnapshot(value(response));
            showKeyboardSkinStatus("皮肤已切换");
        } catch (JSONException | LinkageError error) {
            JSONObject accepted = preferencesSnapshot == null ? null
                : preferencesSnapshot.optJSONObject("preferences");
            skin = KeyboardSkin.from(accepted == null ? "fluent"
                : accepted.optString("candidate_skin", "fluent"));
            showKeyboardSkinStatus("皮肤切换失败，已恢复原皮肤");
        }
        applySkin();
        render();
    }

    private LinearLayout createReplyKeyboard() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(pixels(6), pixels(5), pixels(6), pixels(5));
        root.setBackgroundColor(Color.parseColor(skin.background()));
        root.setContentDescription("高情商回复键盘");

        LinearLayout header = new LinearLayout(this);
        replyReplyModeButton = button(header, "帮你回", () -> {
            replyModel.setMode(ReplyKeyboardModel.Mode.REPLY);
            clearReplyRequestReferences();
            renderReplyKeyboard();
        });
        replyReplyModeButton.setContentDescription("帮你回模式");
        replyPolishModeButton = button(header, "帮润色", () -> {
            replyModel.setMode(ReplyKeyboardModel.Mode.POLISH);
            clearReplyRequestReferences();
            renderReplyKeyboard();
        });
        replyPolishModeButton.setContentDescription("帮润色模式");
        Button schemes = button(header, "⌨", this::showSchemePicker);
        schemes.setContentDescription("选择输入方案");
        replyTemplateButton = button(header, "模板", this::showReplyTemplates);
        replyTemplateButton.setContentDescription("回复模板");
        replySkinButton = button(header, "皮肤", () -> showSkinMenu(replySkinButton));
        replySkinButton.setContentDescription("切换皮肤");
        Button dismiss = button(header, "⌄", () -> requestHideSelf(0));
        dismiss.setContentDescription("收起键盘");
        root.addView(header, new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, pixels(42)));

        LinearLayout sourceRow = new LinearLayout(this);
        replySourceButton = button(sourceRow, "+ 粘贴 TA 的话帮你回", this::pasteReplySource);
        replySourceButton.setSingleLine(true);
        replySourceButton.setEllipsize(android.text.TextUtils.TruncateAt.END);
        replySourceButton.setContentDescription("回复源文字");
        Button paste = button(sourceRow, "粘贴", this::pasteReplySource);
        paste.setContentDescription("粘贴回复源文字");
        paste.setLayoutParams(new LinearLayout.LayoutParams(pixels(64),
            LinearLayout.LayoutParams.MATCH_PARENT));
        root.addView(sourceRow, new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, pixels(44)));

        LinearLayout body = new LinearLayout(this);
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        replyMain = new LinearLayout(this);
        replyMain.setOrientation(LinearLayout.VERTICAL);
        replyMain.setContentDescription("回复风格与候选");
        scroll.addView(replyMain);
        body.addView(scroll, new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, 1));
        replyActions = new LinearLayout(this);
        replyActions.setOrientation(LinearLayout.VERTICAL);
        body.addView(replyActions, new LinearLayout.LayoutParams(pixels(68),
            LinearLayout.LayoutParams.MATCH_PARENT));
        root.addView(body, new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, 0, 1));

        LinearLayout footer = new LinearLayout(this);
        replyStatus = new TextView(this);
        replyStatus.setSingleLine(true);
        replyStatus.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11);
        replyStatus.setContentDescription("回复键盘状态");
        footer.addView(replyStatus, new LinearLayout.LayoutParams(0,
            LinearLayout.LayoutParams.WRAP_CONTENT, 1));
        Button styles = button(footer, "选风格", () -> {
            replyModel.chooseStyle();
            clearReplyRequestReferences();
            renderReplyKeyboard();
        });
        styles.setContentDescription("重新选择回复风格");
        root.addView(footer, new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, pixels(36)));
        return root;
    }

    private void renderReplyKeyboard() {
        if (replyKeyboard == null || replyMain == null || replyActions == null) return;
        replyMain.removeAllViews();
        replyActions.removeAllViews();
        replyReplyModeButton.setSelected(replyModel.mode() == ReplyKeyboardModel.Mode.REPLY);
        replyPolishModeButton.setSelected(replyModel.mode() == ReplyKeyboardModel.Mode.POLISH);
        styleButton(replyReplyModeButton, true);
        styleButton(replyPolishModeButton, true);
        replyTemplateButton.setEnabled(!replyModel.busy());
        replySkinButton.setEnabled(canSaveKeyboardSkin());
        replySourceButton.setText(replyModel.source().isEmpty()
            ? "+ 粘贴 TA 的话帮你回" : replyModel.source());
        if (replyModel.replies().isEmpty()) {
            for (int start = 0; start < ReplyKeyboardModel.STYLES.size(); start += 3) {
                LinearLayout row = new LinearLayout(this);
                for (int column = 0; column < 3; column++) {
                    int index = start + column;
                    ReplyKeyboardModel.Style style = ReplyKeyboardModel.STYLES.get(index);
                    Button choice = button(row, style.emoji() + " " + style.label(),
                        () -> generateReply(style.label()));
                    choice.setContentDescription("回复风格 " + style.label());
                    choice.setEnabled(!replyModel.busy());
                }
                replyMain.addView(row, new LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT, pixels(52)));
            }
        } else {
            for (String reply : replyModel.replies()) {
                Button candidate = button(replyMain, reply, () -> useReply(reply));
                candidate.setGravity(Gravity.START | Gravity.CENTER_VERTICAL);
                candidate.setContentDescription("回复候选，点按插入");
                candidate.setMinHeight(pixels(48));
                candidate.setLayoutParams(new LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT));
            }
        }
        Button delete = button(replyActions, "⌫", () -> {
            replyModel.deleteLastCodePoint();
            clearReplyRequestReferences();
            renderReplyKeyboard();
        });
        delete.setLayoutParams(new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, 0, 1));
        delete.setContentDescription("删除源文字");
        Button clear = button(replyActions, "清空", () -> {
            replyModel.setSource("");
            clearReplyRequestReferences();
            renderReplyKeyboard();
        });
        clear.setLayoutParams(new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, 0, 1));
        clear.setContentDescription("清空源文字");
        if (replyModel.busy()) {
            Button cancel = button(replyActions, "取消", () -> {
                replyModel.cancel();
                clearReplyRequestReferences();
                renderReplyKeyboard();
            });
            cancel.setLayoutParams(new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 0, 1));
            cancel.setContentDescription("取消回复生成");
        } else if (replyModel.replies().isEmpty()) {
            Button generate = button(replyActions, "生成", () -> generateReply(replyModel.style()));
            generate.setLayoutParams(new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 0, 1));
            generate.setContentDescription("生成回复");
        } else {
            Button regenerate = button(replyActions, "换一句", () -> generateReply(replyModel.style()));
            regenerate.setLayoutParams(new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 0, 1));
            regenerate.setContentDescription("换一句回复");
        }
        replyStatus.setText(replyModel.status());
        applySkinToView(replyKeyboard);
    }

    private boolean voiceInsertionReady() {
        return session != 0 && connection != null && view != null
            && view.optString("editing_text", "").isEmpty()
            && view.optString("local_mode", "none").equals("none");
    }

    private boolean aiPolishReady() { return voiceInsertionReady(); }

    private String editorContext(boolean before) {
        if (connection == null) return null;
        CharSequence text = before ? connection.getTextBeforeCursor(64, 0)
            : connection.getTextAfterCursor(64, 0);
        return text == null ? null : text.toString();
    }

    private String selectedEditorText() {
        if (connection == null) return null;
        CharSequence text = connection.getSelectedText(0);
        return text == null ? null : text.toString();
    }

    private void captureVoiceTarget() {
        voiceTarget = new EditorContextSnapshot(connection, editorContextRevision, editorContext(true),
            selectedEditorText(), editorContext(false));
    }

    private boolean voiceTargetMatches() {
        return voiceTarget != null && voiceTarget.matches(connection, editorContextRevision,
            editorContext(true), selectedEditorText(), editorContext(false));
    }

    private boolean aiTargetMatches() {
        return aiTarget != null && aiTarget.matches(connection, editorContextRevision,
            editorContext(true), selectedEditorText(), editorContext(false));
    }

    private void showAiPolish() {
        if (aiPolishConfiguration == null) {
            Toast.makeText(this, "请先在共享设置中启用并配置 AI 辅助", Toast.LENGTH_SHORT).show();
            return;
        }
        String selected = selectedEditorText();
        if (!aiPolishReady() || !AiPolishConfiguration.acceptableText(selected)) {
            Toast.makeText(this, "请先完成当前输入，再选择一万字以内的文字", Toast.LENGTH_SHORT).show();
            return;
        }
        closeCandidatePanel();
        closeClipboardHistory();
        closeSchemePicker();
        closeLayoutSettings();
        closeVoiceResult();
        closeAiPolish();
        closeReplyKeyboard();
        aiRequestConfiguration = aiPolishConfiguration;
        aiSourceText = selected;
        aiTarget = new EditorContextSnapshot(connection, editorContextRevision, editorContext(true),
            selected, editorContext(false));
        renderAiPolish();
        aiPolishContainer.setVisibility(View.VISIBLE);
    }

    private void sendAiPolish() {
        if (aiBusy || aiRequestConfiguration == null || !aiTargetMatches()
                || !aiRequestConfiguration.equals(aiPolishConfiguration)) {
            aiError = "输入位置或 AI 配置已变化，请返回键盘后重试。";
            renderAiPolish();
            return;
        }
        aiBusy = true;
        aiError = "";
        renderAiPolish();
        try {
            aiOperation = aiPolishClient.request(aiRequestConfiguration, aiSourceText,
                (generation, result, failure) -> main.post(
                    () -> finishAiPolish(generation, result, failure)));
        } catch (AiPolishClient.Failure error) {
            aiBusy = false;
            aiError = error.reason() == AiPolishClient.Reason.BUSY
                ? "已有 AI 请求正在处理，请稍后重试。" : "无法启动 AI 请求，请检查配置。";
            renderAiPolish();
        }
    }

    private void finishAiPolish(long generation, String result, AiPolishClient.Failure failure) {
        if (aiOperation == null || aiOperation.generation() != generation
                || aiPolishContainer == null
                || aiPolishContainer.getVisibility() != View.VISIBLE) return;
        aiOperation = null;
        aiBusy = false;
        if (!aiTargetMatches() || aiRequestConfiguration == null
                || !aiRequestConfiguration.equals(aiPolishConfiguration)) {
            aiError = "输入位置或 AI 配置已变化，请返回键盘后重试。";
        } else if (failure != null) {
            aiError = failure.reason() == AiPolishClient.Reason.INVALID
                ? "服务返回的文字为空或超过一万字。"
                : "AI 请求失败，请检查网络、地址、模型和密钥。";
        } else {
            aiOutputText = result;
            aiError = "";
        }
        renderAiPolish();
    }

    private void replaceAiSelection() {
        if (aiOutputText.isEmpty() || !aiPolishReady() || !aiTargetMatches()
                || aiRequestConfiguration == null
                || !aiRequestConfiguration.equals(aiPolishConfiguration)) {
            aiError = "输入位置或 AI 配置已变化，请返回键盘后重试。";
            renderAiPolish();
            return;
        }
        boolean committed;
        try { committed = connection.commitText(aiOutputText, 1); }
        catch (RuntimeException error) { committed = false; }
        if (committed) closeAiPolish();
        else {
            aiError = "编辑器拒绝替换，请返回键盘后重试。";
            renderAiPolish();
        }
    }

    private void renderAiPolish() {
        if (aiPolishPanel == null || aiPolishActions == null) return;
        aiPolishPanel.removeAllViews();
        aiPolishActions.removeAllViews();
        LinearLayout header = new LinearLayout(this);
        TextView title = new TextView(this);
        title.setText("AI 润色");
        title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 18);
        header.addView(title, new LinearLayout.LayoutParams(0,
            LinearLayout.LayoutParams.WRAP_CONTENT, 1));
        button(header, "返回键盘", this::closeAiPolish);
        aiPolishPanel.addView(header);
        if (!aiError.isEmpty()) {
            TextView error = new TextView(this);
            error.setText(aiError);
            error.setTextColor(Color.RED);
            error.setContentDescription("AI 润色状态");
            aiPolishPanel.addView(error);
        }
        if (aiRequestConfiguration != null) {
            TextView destination = new TextView(this);
            destination.setText("发送到 " + aiRequestConfiguration.destination() + " · "
                + aiRequestConfiguration.model());
            destination.setContentDescription("AI 请求目标和模型");
            aiPolishPanel.addView(destination);
        }
        TextView label = new TextView(this);
        label.setText(aiOutputText.isEmpty() ? "待发送的选中文字" : "润色结果");
        aiPolishPanel.addView(label);
        TextView content = new TextView(this);
        content.setText(aiOutputText.isEmpty() ? aiSourceText : aiOutputText);
        content.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16);
        content.setContentDescription(aiOutputText.isEmpty() ? "待润色文字" : "AI 润色结果");
        aiPolishPanel.addView(content);
        if (aiBusy) {
            TextView progress = new TextView(this);
            progress.setText("正在请求…");
            aiPolishPanel.addView(progress);
            Button cancel = button(aiPolishActions, "取消请求", () -> {
                cancelAiRequest();
                renderAiPolish();
            });
            cancel.setLayoutParams(new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT));
        } else if (aiOutputText.isEmpty()) {
            Button send = button(aiPolishActions, "发送选中文字", this::sendAiPolish);
            send.setEnabled(aiTargetMatches() && aiRequestConfiguration != null
                && aiRequestConfiguration.equals(aiPolishConfiguration));
            send.setLayoutParams(new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT));
        } else {
            Button replace = button(aiPolishActions, "替换选中文字", this::replaceAiSelection);
            replace.setEnabled(aiTargetMatches() && aiRequestConfiguration != null
                && aiRequestConfiguration.equals(aiPolishConfiguration));
            replace.setLayoutParams(new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT));
        }
        applySkin();
    }

    private void startVoiceRecognition() {
        if (!voiceInputEnabled) {
            Toast.makeText(this, "请先在共享设置中启用语音输入", Toast.LENGTH_SHORT).show();
            return;
        }
        if (!VoiceRecognitionActivity.available(this)) {
            Toast.makeText(this, "设备没有可用的系统语音识别服务", Toast.LENGTH_SHORT).show();
            return;
        }
        closeVoiceResult();
        try { VoiceRecognitionActivity.launch(this, voiceLanguage); }
        catch (RuntimeException error) {
            Toast.makeText(this, "系统语音识别服务无法启动", Toast.LENGTH_SHORT).show();
        }
    }

    private void insertVoiceResult() {
        VoiceResultStore.Entry entry = voiceResultEntry;
        if (entry == null || voiceResultStore == null) return;
        if (!voiceInsertionReady() || !voiceTargetMatches()) {
            Toast.makeText(this, "输入位置已变化，请关闭后重新打开语音结果", Toast.LENGTH_SHORT).show();
            return;
        }
        try {
            String text = voiceResultStore.consume(entry.id(), System.currentTimeMillis());
            boolean committed;
            try { committed = connection.commitText(text, 1); }
            catch (RuntimeException error) { committed = false; }
            closeVoiceResult();
            if (!committed)
                Toast.makeText(this, "编辑器拒绝插入；结果已安全清除", Toast.LENGTH_SHORT).show();
        } catch (VoiceResultStore.Failure error) {
            voiceResultEntry = null;
            renderVoiceResult();
            Toast.makeText(this, error.reason() == VoiceResultStore.Reason.BUSY
                ? "语音结果正在更新，请稍后重试" : "语音结果已过期、已使用或不可读取",
                Toast.LENGTH_SHORT).show();
        }
    }

    private void showVoiceResult() {
        if (!voiceInsertionReady()) {
            Toast.makeText(this, "请先完成当前输入，再插入语音结果", Toast.LENGTH_SHORT).show();
            return;
        }
        if (voiceResultStore == null || voiceResultScroll == null) {
            Toast.makeText(this, "语音结果存储尚未就绪", Toast.LENGTH_SHORT).show();
            return;
        }
        try { voiceResultEntry = voiceResultStore.read(System.currentTimeMillis()); }
        catch (VoiceResultStore.Failure error) {
            Toast.makeText(this, error.reason() == VoiceResultStore.Reason.BUSY
                ? "语音结果正在更新，请稍后重试" : "语音结果无法读取",
                Toast.LENGTH_SHORT).show();
            return;
        }
        captureVoiceTarget();
        closeCandidatePanel();
        closeClipboardHistory();
        closeSchemePicker();
        closeLayoutSettings();
        closeAiPolish();
        renderVoiceResult();
        voiceResultScroll.setVisibility(View.VISIBLE);
    }

    private void renderVoiceResult() {
        if (voiceResultPanel == null) return;
        voiceResultPanel.removeAllViews();
        LinearLayout header = new LinearLayout(this);
        TextView title = new TextView(this);
        title.setText("语音结果");
        title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 18);
        header.addView(title, new LinearLayout.LayoutParams(0,
            LinearLayout.LayoutParams.WRAP_CONTENT, 1));
        button(header, "返回键盘", this::closeVoiceResult);
        voiceResultPanel.addView(header);
        if (voiceResultEntry == null) {
            TextView empty = new TextView(this);
            empty.setText("暂无待插入结果。点击下方按钮使用系统语音识别；只保留最新一条，10 分钟内有效。");
            voiceResultPanel.addView(empty);
        } else {
            TextView recognized = new TextView(this);
            recognized.setText(voiceResultEntry.text());
            recognized.setContentDescription("待插入语音结果");
            voiceResultPanel.addView(recognized);
            TextView hint = new TextView(this);
            hint.setText("点击插入后清除待插入结果；输入位置变化时会拒绝插入。");
            voiceResultPanel.addView(hint);
            Button insert = button(voiceResultPanel, "插入语音结果", this::insertVoiceResult);
            insert.setContentDescription("插入并清除语音结果");
            insert.setLayoutParams(new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT));
        }
        Button recognize = button(voiceResultPanel, "开始系统语音识别",
            this::startVoiceRecognition);
        recognize.setLayoutParams(new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT));
        recognize.setEnabled(voiceInputEnabled && VoiceRecognitionActivity.available(this));
        applySkin();
    }

    private void renderLayoutSettingsState() {
        if (keySpacingSlider == null || rowSpacingSlider == null
                || keySpacingValue == null || rowSpacingValue == null
                || voiceShortcutSwitch == null) return;
        keySpacingSlider.setProgress(touchKeySpacingTenths);
        rowSpacingSlider.setProgress(touchRowSpacingTenths);
        keySpacingSlider.setEnabled(!touchGeometrySaving);
        rowSpacingSlider.setEnabled(!touchGeometrySaving);
        voiceShortcutSwitch.setChecked(touchVoiceShortcutEnabled);
        voiceShortcutSwitch.setEnabled(!touchGeometrySaving);
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
        closeVoiceResult();
        closeAiPolish();
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
                    "touch_row_spacing_tenths", -1)) == touchRowSpacingTenths
                && acceptedPreferences.optBoolean("touch_voice_shortcut", false)
                    == touchVoiceShortcutEnabled) return;
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
            preferences.put("touch_voice_shortcut", touchVoiceShortcutEnabled);
        } catch (JSONException error) {
            preferencesNotice = " · 键盘设置保存失败，保留原设置";
            render();
            return;
        }
        touchGeometrySaving = true;
        preferencesNotice = " · 正在保存键盘设置";
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
                preferencesNotice = " · 键盘设置保存失败，保留原设置";
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
                preferencesNotice = " · 键盘设置已保存";
            }
        } catch (JSONException | LinkageError error) {
            if (preferencesSnapshot != null)
                applyTouchGeometry(preferencesSnapshot.optJSONObject("preferences"));
            applyKeyboardGeometry();
            preferencesNotice = " · 键盘设置保存失败，已恢复原设置";
            Toast.makeText(this, "键盘设置未能保存", Toast.LENGTH_SHORT).show();
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
        closeVoiceResult();
        closeAiPolish();
        if (replyKeyboard != null) replyKeyboard.setVisibility(View.GONE);
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
        java.util.List<KeyboardScheme> schemes = java.util.Arrays.stream(KeyboardScheme.values())
            .filter(value -> value != KeyboardScheme.THOUGHTFUL_REPLY || thoughtfulReplyEnabled()).toList();
        for (int start = 0; start < schemes.size(); start += 4) {
            LinearLayout row = new LinearLayout(this);
            row.setOrientation(LinearLayout.HORIZONTAL);
            for (int slot = 0; slot < 4; slot++) {
                int index = start + slot;
                if (index >= schemes.size()) {
                    View spacer = new View(this);
                    row.addView(spacer, new LinearLayout.LayoutParams(0, pixels(72), 1));
                    continue;
                }
                KeyboardScheme scheme = schemes.get(index);
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
        Button toggleReply = button(schemePanel, thoughtfulReplyEnabled()
            ? "禁用高情商回复" : "启用高情商回复", this::toggleThoughtfulReplyScheme);
        toggleReply.setLayoutParams(new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT));
        toggleReply.setContentDescription(thoughtfulReplyEnabled()
            ? "禁用高情商回复输入方案" : "启用高情商回复输入方案");
        TextView hint = new TextView(this);
        hint.setText("切换会先完成当前组词，并同步到共享设置；高情商回复只保存宿主展示状态");
        schemePanel.addView(hint);
        applySkin();
    }

    private void selectKeyboardScheme(KeyboardScheme scheme) {
        if (schemeSaving || touchGeometrySaving || session == 0 || preferencesSnapshot == null
                || preferencesDirectory.isEmpty()) return;
        if (scheme == selectedScheme) {
            closeSchemePicker();
            if (scheme == KeyboardScheme.THOUGHTFUL_REPLY) showReplyKeyboard();
            return;
        }
        replyModel.resetResults();
        clearReplyRequestReferences();
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
        schemeSaveTarget = scheme;
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
                schemeSaveTarget = null;
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
                if (schemeSaveTarget != null) {
                    saveHostScheme(schemeSaveTarget);
                    selectedScheme = schemeSaveTarget;
                }
                preferencesNotice = " · 输入方案已切换";
            }
        } catch (JSONException | LinkageError error) {
            // A conflict or storage failure leaves the working session unchanged.
            preferencesNotice = " · 输入方案切换失败，保留当前设置";
            Toast.makeText(this, "输入方案未能保存", Toast.LENGTH_SHORT).show();
        }
        schemeSaveTarget = null;
        synchronizeReplyKeyboard();
        render();
    }

    private void toggleThoughtfulReplyScheme() {
        if (schemeHostPreferences == null || schemeSaving) return;
        boolean enabled = thoughtfulReplyEnabled();
        schemeHostPreferences.edit().putBoolean(THOUGHTFUL_REPLY_ENABLED, !enabled).apply();
        if (enabled && selectedScheme == KeyboardScheme.THOUGHTFUL_REPLY) {
            selectedScheme = KeyboardScheme.QUANPIN;
            saveHostScheme(selectedScheme);
            replySuppressed = false;
            closeReplyKeyboard();
        }
        renderSchemePicker();
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
        closeVoiceResult();
        closeAiPolish();
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
        MenuItem voiceInput = menu.add("语音输入");
        voiceInput.setEnabled(voiceInputEnabled && VoiceRecognitionActivity.available(this));
        MenuItem voiceResult = menu.add("语音结果");
        MenuItem aiPolish = menu.add("AI 润色");
        aiPolish.setEnabled(aiPolishConfiguration != null && aiPolishReady());
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
            if (item == voiceInput) {
                startVoiceRecognition();
                return true;
            }
            if (item == voiceResult) {
                showVoiceResult();
                return true;
            }
            if (item == aiPolish) {
                showAiPolish();
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

    private void editCandidate(JSONObject id, CandidateManagementAction action) {
        if (session == 0 || id == null || id.optLong("session") != session) return;
        try {
            long generation = id.getLong("generation");
            long index = id.getLong("index");
            String result = switch (action) {
                case PROMOTE -> NativeClient.pinCandidate(session, generation, index);
                case FIX_FIRST -> NativeClient.fixCandidatePosition(
                    session, generation, index, action.fixedPosition());
                case CLEAR_POSITION -> NativeClient.clearCandidatePosition(
                    session, generation, index);
                case REMOVE -> NativeClient.removeCandidate(session, generation, index);
            };
            if (!apply(result)) {
                Toast.makeText(this, "当前候选不支持此操作", Toast.LENGTH_SHORT).show();
            } else if (keyboardRoot != null) {
                keyboardRoot.announceForAccessibility(action.announcement());
            }
        } catch (JSONException | LinkageError error) { fail(); }
    }

    private void confirmCandidateRemoval(JSONObject id, String text) {
        new AlertDialog.Builder(this)
            .setTitle("删除词条")
            .setMessage("确认删除“" + text + "”？")
            .setNegativeButton("取消", null)
            .setPositiveButton("删除", (dialog, which) -> {
                playFeedback(moreButton);
                editCandidate(id, CandidateManagementAction.REMOVE);
            })
            .show();
    }

    private void showCandidateMenu(Button button, JSONObject id, String text) {
        if (!candidateManagementEnabled()) return;
        PopupMenu popup = new PopupMenu(this, button);
        for (CandidateManagementAction action : CandidateManagementAction.values()) {
            popup.getMenu().add(Menu.NONE, action.menuItemId(), action.ordinal(), action.title());
        }
        popup.setOnMenuItemClickListener(item -> {
            playFeedback(button);
            CandidateManagementAction action;
            try {
                action = CandidateManagementAction.fromMenuItemId(item.getItemId());
            } catch (IllegalArgumentException error) {
                return false;
            }
            if (action.confirmationRequired()) {
                confirmCandidateRemoval(id, text);
                return true;
            }
            editCandidate(id, action);
            return true;
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
        File files = getFilesDir();
        voiceResultStore = files == null ? null
            : new VoiceResultStore(files.toPath().resolve("voice-handoff"));
        communityReplyLibrary = files == null ? null : new CommunityReplyLibrary(files.toPath());
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
        voiceShortcutButton = button(candidateHeader, "语音", this::showVoiceResult);
        voiceShortcutButton.setContentDescription("打开语音结果");
        voiceShortcutButton.setLayoutParams(new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT));
        aiPolishShortcutButton = button(candidateHeader, "AI", this::showAiPolish);
        aiPolishShortcutButton.setContentDescription("打开 AI 润色");
        aiPolishShortcutButton.setLayoutParams(new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT));
        replyShortcutButton = button(candidateHeader, "回复", this::showReplyKeyboard);
        replyShortcutButton.setContentDescription("生成高情商回复");
        replyShortcutButton.setLayoutParams(new LinearLayout.LayoutParams(
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
        enterButton = button(controls, "换行", this::enter);
        enterButton.setContentDescription("换行");
        button(controls, "切换", () -> switchToNextInputMethod(false));
        schemeButton = button(controls, "方案", this::showSchemePicker);
        schemeButton.setContentDescription("选择输入方案");
        skinButton = button(controls, "皮肤", () -> showSkinMenu(skinButton));
        skinButton.setContentDescription("切换键盘皮肤");
        layoutSettingsButton = button(controls, "设置", this::showLayoutSettings);
        layoutSettingsButton.setContentDescription("键盘设置");
        moreButton = button(controls, "更多", this::showFeedbackMenu);
        moreButton.setContentDescription("更多快捷设置");
        Button dismissButton = button(controls, "收起", () -> requestHideSelf(0));
        dismissButton.setContentDescription("收起键盘");
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
        voiceShortcutSwitch = new Switch(this);
        voiceShortcutSwitch.setText("顶部语音入口");
        voiceShortcutSwitch.setContentDescription("顶部语音入口");
        voiceShortcutSwitch.setOnCheckedChangeListener((button, checked) -> {
            if (checked == touchVoiceShortcutEnabled || touchGeometrySaving) return;
            touchVoiceShortcutEnabled = checked;
            renderLayoutSettingsState();
            render();
            saveTouchGeometry();
        });
        layoutSettingsPanel.addView(voiceShortcutSwitch);
        TextView layoutHint = new TextView(this);
        layoutHint.setText("间距只改变键位外观，不改变输入方案；松手后自动保存。");
        layoutSettingsPanel.addView(layoutHint);
        layoutSettingsScroll = new ScrollView(this);
        layoutSettingsScroll.addView(layoutSettingsPanel);
        layoutSettingsScroll.setVisibility(View.GONE);
        keyboardRoot.addView(layoutSettingsScroll, new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
        voiceResultPanel = new LinearLayout(this);
        voiceResultPanel.setOrientation(LinearLayout.VERTICAL);
        voiceResultPanel.setPadding(24, 16, 24, 16);
        voiceResultPanel.setBackgroundColor(Color.parseColor(skin.background()));
        voiceResultPanel.setContentDescription("语音结果面板");
        voiceResultScroll = new ScrollView(this);
        voiceResultScroll.addView(voiceResultPanel);
        voiceResultScroll.setVisibility(View.GONE);
        keyboardRoot.addView(voiceResultScroll, new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
        aiPolishContainer = new LinearLayout(this);
        aiPolishContainer.setOrientation(LinearLayout.VERTICAL);
        aiPolishContainer.setBackgroundColor(Color.parseColor(skin.background()));
        aiPolishPanel = new LinearLayout(this);
        aiPolishPanel.setOrientation(LinearLayout.VERTICAL);
        aiPolishPanel.setPadding(24, 16, 24, 16);
        aiPolishPanel.setBackgroundColor(Color.parseColor(skin.background()));
        aiPolishPanel.setContentDescription("AI 润色面板");
        aiPolishScroll = new ScrollView(this);
        aiPolishScroll.setFillViewport(true);
        aiPolishScroll.addView(aiPolishPanel);
        aiPolishContainer.addView(aiPolishScroll, new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, 0, 1));
        aiPolishActions = new LinearLayout(this);
        aiPolishActions.setOrientation(LinearLayout.VERTICAL);
        aiPolishActions.setPadding(24, 0, 24, 16);
        aiPolishContainer.addView(aiPolishActions, new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT));
        aiPolishContainer.setVisibility(View.GONE);
        keyboardRoot.addView(aiPolishContainer, new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
        replyKeyboard = createReplyKeyboard();
        replyKeyboard.setVisibility(View.GONE);
        keyboardRoot.addView(replyKeyboard, new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
        renderLayoutSettingsState();
        render();
        synchronizeReplyKeyboard();
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
        if (voiceShortcutButton != null) {
            voiceShortcutButton.setVisibility(touchVoiceShortcutEnabled ? View.VISIBLE : View.GONE);
            voiceShortcutButton.setEnabled(voiceInsertionReady());
        }
        if (aiPolishShortcutButton != null) {
            aiPolishShortcutButton.setVisibility(
                aiPolishConfiguration == null ? View.GONE : View.VISIBLE);
            aiPolishShortcutButton.setEnabled(aiPolishReady());
        }
        if (replyShortcutButton != null) {
            replyShortcutButton.setVisibility(selectedScheme == KeyboardScheme.THOUGHTFUL_REPLY
                ? View.VISIBLE : View.GONE);
            replyShortcutButton.setEnabled(replyReady());
        }
        if (layerButton != null) {
            layerButton.setText(keyboardLayer == KeyboardLayout.Layer.LETTERS ? "符号" : "字母");
            layerButton.setContentDescription(keyboardLayer == KeyboardLayout.Layer.LETTERS
                ? "切换符号键盘" : "切换字母键盘");
        }
        updateReturnKey();
        if (shiftButton != null)
            shiftButton.setVisibility(touchLayout(view) != STANDARD_TOUCH_LAYOUT
                && keyboardLayer == KeyboardLayout.Layer.LETTERS ? View.GONE : View.VISIBLE);
        if (schemeButton != null) {
            schemeButton.setText(selectedScheme.glyph() + selectedScheme.badge());
            schemeButton.setContentDescription("输入方案：" + selectedScheme.title());
            schemeButton.setEnabled(session != 0 && preferencesSnapshot != null
                && !schemeSaving && !touchGeometrySaving);
        }
        if (skinButton != null) {
            skinButton.setEnabled(canSaveKeyboardSkin());
            skinButton.setContentDescription("切换键盘皮肤；当前" + skin.title());
            if (Build.VERSION.SDK_INT >= 30) skinButton.setStateDescription(skin.title());
        }
        synchronizeReplyKeyboard();
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
