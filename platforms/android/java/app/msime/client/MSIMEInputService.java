package app.msime.client;

import android.inputmethodservice.InputMethodService;
import android.app.AlertDialog;
import android.content.ClipDescription;
import android.content.ClipboardManager;
import android.content.SharedPreferences;
import android.content.res.Configuration;
import android.graphics.Color;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.media.AudioManager;
import android.os.Handler;
import android.os.Looper;
import android.os.Build;
import android.os.SystemClock;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.text.SpannableString;
import android.text.Spanned;
import android.text.style.ForegroundColorSpan;
import android.text.style.RelativeSizeSpan;
import android.view.Gravity;
import android.view.HapticFeedbackConstants;
import android.view.KeyEvent;
import android.view.Menu;
import android.view.MenuItem;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewConfiguration;
import android.util.TypedValue;
import android.widget.PopupMenu;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.GridLayout;
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
import java.nio.file.Path;
import java.time.LocalDate;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
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
    private static final long BACKSPACE_REPEAT_DELAY_MILLIS = 400;
    private static final long BACKSPACE_REPEAT_INTERVAL_MILLIS = 75;
    private static final String SCHEME_HOST_PREFERENCES = "android-keyboard-schemes";
    private static final String SELECTED_HOST_SCHEME = "selected-scheme";
    private static final String THOUGHTFUL_REPLY_ENABLED = "thoughtful-reply-enabled";
    private static final String EMOJI_RECENTS_PREFERENCES = "android-emoji-recents";
    private static final String EMOJI_RECENTS_KEY = "items";
    private static final String SPACE_CURSOR_DESCRIPTION =
        "空格；轻点输入空格或选词，左右滑动移动光标";
    private static final int CAPITALIZATION_CONTEXT_LIMIT = 128;
    private long session;
    private InputConnection connection;
    private EditorBridge bridge = new EditorBridge();
    private JSONObject view;
    private FrameLayout keyboardRoot;
    private LinearLayout candidates;
    private LinearLayout verticalCandidates;
    private HorizontalScrollView horizontalCandidateScroll;
    private ScrollView verticalCandidateScroll;
    private final java.util.List<Button> candidateButtons = new java.util.ArrayList<>();
    private LinearLayout candidatePaging;
    private LinearLayout expandedCandidates;
    private ScrollView expandedCandidateScroll;
    private TextView preedit;
    private TextView candidatePage;
    private LinearLayout nineKeySpellings;
    private HorizontalScrollView nineKeySpellingScroll;
    private final java.util.List<Button> nineKeySpellingButtons = new java.util.ArrayList<>();
    private java.util.List<Integer> nineKeySpellingIndices = java.util.List.of();
    private long nineKeySpellingGeneration = -1;
    private Button expandCandidates;
    private boolean candidatePanelOpen;
    private JSONObject candidatePanelSnapshot;
    private ScrollView clipboardScroll;
    private LinearLayout clipboardPanel;
    private ScrollView schemeScroll;
    private LinearLayout schemePanel;
    private ScrollView layoutSettingsScroll;
    private LinearLayout layoutSettingsPanel;
    private ScrollView moreToolsScroll;
    private LinearLayout moreToolsPanel;
    private boolean localInputToolsOpen;
    private LinearLayout emojiPanel;
    private HorizontalScrollView emojiTabsScroll;
    private LinearLayout emojiTabs;
    private ScrollView emojiGridScroll;
    private GridLayout emojiGrid;
    private TextView emojiStatus;
    private SeekBar keySpacingSlider;
    private SeekBar rowSpacingSlider;
    private SeekBar keyboardHeightSlider;
    private Switch voiceShortcutSwitch;
    private Button resetLayoutSettingsButton;
    private TextView keySpacingValue;
    private TextView rowSpacingValue;
    private TextView keyboardHeightValue;
    private ClipboardHistoryStore clipboardHistory;
    private boolean clipboardHistoryEnabled;
    private boolean candidateEnglishGloss;
    private boolean wubiCodeHint = true;
    private String candidateGlossResources = "";
    private long candidateGlossEpoch;
    private long candidateGlossRequestedSession;
    private long candidateGlossRequestedGeneration = -1;
    private boolean candidateHorizontal;
    private int candidateFontSize = 16;
    private int candidatePreeditFontSize = 16;
    private int touchKeySpacingTenths = KeyboardGeometry.DEFAULT_KEY_SPACING_TENTHS;
    private int touchRowSpacingTenths = KeyboardGeometry.DEFAULT_ROW_SPACING_TENTHS;
    private int touchKeyboardHeightAdjustment = KeyboardGeometry.DEFAULT_HEIGHT_ADJUSTMENT_DP;
    private boolean touchVoiceShortcutEnabled;
    private boolean voiceInputEnabled = true;
    private String voiceLanguage = "zh-CN";
    private KeyboardSkin skin = KeyboardSkin.from("forest", false);
    private JSONObject localModes = new JSONObject();
    private Button moreButton;
    private Button schemeButton;
    private Button skinButton;
    private Button layoutSettingsButton;
    private Button scriptShortcutButton;
    private Button emojiShortcutButton;
    private Button voiceShortcutButton;
    private Button aiPolishShortcutButton;
    private Button replyShortcutButton;
    private Button microsoftFinalKey;
    private KeyboardScheme selectedScheme = KeyboardScheme.QUANPIN;
    private java.util.List<KeyboardScheme> enabledSchemes =
        KeyboardScheme.enabledFromPreferenceIds(null);
    private boolean sharedSchemePreferences;
    private SharedPreferences schemeHostPreferences;
    private SharedPreferences feedbackPreferences;
    private boolean soundEnabled = true;
    private boolean hapticsEnabled;
    private KeyboardFeedbackPreferences.HapticStrength hapticStrength =
        KeyboardFeedbackPreferences.HapticStrength.MEDIUM;
    private Vibrator vibrator;
    private LinearLayout keyRows;
    private HorizontalScrollView keyboardControls;
    private JapaneseFlickPreview japaneseFlickPreview;
    private LinearLayout shortcutBar;
    private HorizontalScrollView shortcutScroll;
    private final java.util.List<Button> symbolKeyButtons = new java.util.ArrayList<>();
    private final java.util.List<String> symbolKeyInputs = new java.util.ArrayList<>();
    private HandwritingCanvas handwritingCanvas;
    private LinearLayout handwritingCandidates;
    private TextView handwritingStatus;
    private Button handwritingDownload;
    private HandwritingRecognizer handwritingRecognizer;
    private Runnable handwritingRecognitionTask;
    private Runnable handwritingAvailabilityTask;
    private boolean handwritingDownloading;
    private java.util.List<String> handwritingResults = java.util.List.of();
    private HandwritingRequestTracker.Token handwritingCandidateToken;
    private final HandwritingRequestTracker handwritingRequests = new HandwritingRequestTracker();
    private final SpaceCursorMovement cursorMovement = new SpaceCursorMovement();
    private Button layerButton;
    private Button quickPunctuationButton;
    private Button shiftButton;
    private Button languageButton;
    private Button enterButton;
    private Button spaceButton;
    private Button japaneseSpaceKey;
    private Button japaneseReturnKey;
    private Button japaneseVariantsButton;
    private TextView status;
    private String message = "MSIME Preview";
    private final EnglishLetterCaseState letterCase = new EnglishLetterCaseState();
    private boolean dedicatedEnglish;
    private boolean traditionalChineseOutput;
    private int editorInputType;
    private long currentDocumentIdentifier;
    private long nextDocumentIdentifier = 1;
    private final KeyboardInputContext inputContext = new KeyboardInputContext();
    private KeyboardLayout.Layer keyboardLayer = KeyboardLayout.Layer.LETTERS;
    private boolean allowLearning;
    private String preferencesNotice = "";
    private String preferencesDirectory = "";
    private String runtimeOptionsForSnapshot = "";
    private JSONObject preferencesSnapshot;
    private long preferenceSaveGeneration;
    private boolean schemeSaving;
    private boolean touchGeometrySaving;
    private boolean skinSaving;
    private boolean traditionalOutputSaving;
    private static final class KeyboardHeightRole {
        final int baseHeight;
        final int rowCount;
        final int rowIndex;
        final boolean includesRowSpacing;

        KeyboardHeightRole(int baseHeight, int rowCount, int rowIndex,
                           boolean includesRowSpacing) {
            this.baseHeight = baseHeight;
            this.rowCount = rowCount;
            this.rowIndex = rowIndex;
            this.includesRowSpacing = includesRowSpacing;
        }
    }
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
    private CommunityReplyLibrary communityReplyLibrary;
    private final ReplyKeyboardModel replyModel = new ReplyKeyboardModel();
    private AiPolishClient.Operation replyOperation;
    private EditorContextSnapshot replyTarget;
    private AiPolishConfiguration replyRequestConfiguration;
    private boolean replySuppressed;
    private boolean statisticsFailureReported;
    private long editorContextRevision;
    private SharedPreferences emojiPreferences;
    private java.util.List<String> emojiRecents = java.util.List.of();
    private java.util.List<EmojiCatalogModel.Item> emojiItems = java.util.List.of();
    private String emojiResources = "";
    private int emojiSelectedCategory = Integer.MIN_VALUE;
    private int emojiNextOffset;
    private boolean emojiComplete;
    private boolean emojiLoading;
    private long emojiLoadGeneration;
    private final Handler main = new Handler(Looper.getMainLooper());
    private Runnable backspaceRepeatTask;
    private Button backspaceRepeatButton;
    private boolean backspaceRepeated;
    private final ExecutorService preferencesWorker = Executors.newSingleThreadExecutor();
    private final ExecutorService typingStatisticsWorker = new ThreadPoolExecutor(
        1, 1, 0, TimeUnit.MILLISECONDS, new ArrayBlockingQueue<>(32),
        new ThreadPoolExecutor.AbortPolicy());
    private final ExecutorService emojiWorker = Executors.newSingleThreadExecutor();
    private final ExecutorService candidateGlossWorker = new ThreadPoolExecutor(
        1, 1, 0, TimeUnit.MILLISECONDS, new ArrayBlockingQueue<>(1),
        new ThreadPoolExecutor.DiscardOldestPolicy());
    private final AiPolishClient aiPolishClient = new AiPolishClient(new AiPolishHttpTransport());
    private final PreferencesReloader preferencesReloader = new PreferencesReloader(
        (task, delay) -> main.postDelayed(task, delay), preferencesWorker, NativeClient::loadPreferences);

    private boolean legacyThoughtfulReplyEnabled() {
        return schemeHostPreferences == null
            || schemeHostPreferences.getBoolean(THOUGHTFUL_REPLY_ENABLED, true);
    }

    private boolean thoughtfulReplyEnabled() {
        return sharedSchemePreferences
            ? enabledSchemes.contains(KeyboardScheme.THOUGHTFUL_REPLY)
            : legacyThoughtfulReplyEnabled();
    }

    private KeyboardScheme hostScheme(KeyboardScheme engineScheme) {
        String stored = schemeHostPreferences == null ? null
            : schemeHostPreferences.getString(SELECTED_HOST_SCHEME, null);
        KeyboardScheme resolved = KeyboardScheme.fromHostSelection(
            stored, legacyThoughtfulReplyEnabled(), engineScheme);
        if (resolved != KeyboardScheme.THOUGHTFUL_REPLY && stored != null
                && !resolved.name().equals(stored)) saveHostScheme(resolved);
        return resolved;
    }

    private void saveHostScheme(KeyboardScheme scheme) {
        if (schemeHostPreferences != null)
            schemeHostPreferences.edit().putString(SELECTED_HOST_SCHEME, scheme.name()).apply();
    }

    private record SchemeConfiguration(
        java.util.List<KeyboardScheme> enabled, KeyboardScheme selected, boolean shared) {}

    private SchemeConfiguration schemeConfiguration(
            JSONObject preferences, KeyboardScheme engineScheme) {
        JSONObject shared = preferences == null ? null
            : preferences.optJSONObject("touch_keyboard_schemes");
        if (shared == null) {
            java.util.List<String> legacyIds = new java.util.ArrayList<>();
            for (KeyboardScheme candidate : KeyboardScheme.values()) {
                if (candidate != KeyboardScheme.THOUGHTFUL_REPLY
                        || legacyThoughtfulReplyEnabled()) {
                    legacyIds.add(candidate.preferenceId());
                }
            }
            return new SchemeConfiguration(
                KeyboardScheme.enabledFromPreferenceIds(legacyIds), hostScheme(engineScheme), false);
        }
        JSONArray values = shared.optJSONArray("enabled");
        java.util.List<String> ids = new java.util.ArrayList<>();
        if (values != null) {
            for (int index = 0; index < values.length(); index++) {
                String value = values.optString(index, null);
                if (value != null) ids.add(value);
            }
        }
        java.util.List<KeyboardScheme> enabled = KeyboardScheme.enabledFromPreferenceIds(ids);
        String selected = shared.has("selected") ? shared.optString("selected", null) : null;
        return new SchemeConfiguration(enabled,
            KeyboardScheme.resolveEnabledSelection(engineScheme, selected, enabled), true);
    }

    private JSONObject value(String response) throws JSONException {
        JSONObject envelope = new JSONObject(response);
        if (!envelope.getBoolean("ok")) throw new JSONException("Shared runtime rejected operation");
        return envelope.getJSONObject("value");
    }

    private EditorBridge.Sink sink(TypingSource source) {
        final InputConnection target = connection;
        return new EditorBridge.Sink() {
            public void begin() { target.beginBatchEdit(); }
            public boolean commit(String text) {
                boolean committed = target.commitText(text, 1);
                if (committed) recordTypingStatistics(text, source);
                return committed;
            }
            public boolean compose(String text) { return target.setComposingText(text, 1); }
            public boolean finish() { return target.finishComposingText(); }
            public void end() { target.endBatchEdit(); }
        };
    }

    private TypingSource typingSource() {
        return TypingSource.resolve(selectedScheme, dedicatedEnglish,
            view == null ? null : view.optString("local_mode", null));
    }

    private String typingStatisticsDirectory() {
        if (!preferencesDirectory.isEmpty()) return preferencesDirectory;
        File files = getFilesDir();
        return files == null ? "" : new File(files, "bootstrap/state").getAbsolutePath();
    }

    private void recordTypingStatistics(String text, TypingSource source) {
        String directory = typingStatisticsDirectory();
        if (directory.isEmpty() || text == null || text.isEmpty()) return;
        final String request;
        try {
            request = new JSONObject().put("directory", directory).put("action",
                new JSONObject().put("operation", "record").put("text", text)
                    .put("source", source.id()).put("day", LocalDate.now().toString()))
                .toString();
        } catch (JSONException error) {
            reportTypingStatisticsFailure();
            return;
        }
        try {
            typingStatisticsWorker.execute(() -> {
                try {
                    JSONObject result = new JSONObject(NativeClient.typingStatistics(request));
                    if (!result.getBoolean("ok")) reportTypingStatisticsFailure();
                } catch (Exception | LinkageError error) {
                    reportTypingStatisticsFailure();
                }
            });
        } catch (RuntimeException error) {
            reportTypingStatisticsFailure();
        }
    }

    private void reportTypingStatisticsFailure() {
        main.post(() -> {
            if (statisticsFailureReported) return;
            statisticsFailureReported = true;
            preferencesNotice = " · 打字统计未能写入";
            render();
        });
    }

    private boolean commitText(String text, TypingSource source) {
        if (connection == null) return false;
        boolean committed;
        try { committed = connection.commitText(text, 1); }
        catch (RuntimeException error) { return false; }
        if (committed) recordTypingStatistics(text, source);
        return committed;
    }

    private boolean commitText(String text) { return commitText(text, typingSource()); }

    @Override public void onStartInput(EditorInfo info, boolean restarting) {
        super.onStartInput(info, restarting);
        if (!restarting || currentDocumentIdentifier == 0) {
            currentDocumentIdentifier = nextDocumentIdentifier++;
        }
        resetSpaceCursor();
        stop(false);
        connection = getCurrentInputConnection();
        editorContextRevision++;
        bridge = new EditorBridge();
        schemeHostPreferences = getSharedPreferences(SCHEME_HOST_PREFERENCES, MODE_PRIVATE);
        sharedSchemePreferences = false;
        enabledSchemes = KeyboardScheme.enabledFromPreferenceIds(null);
        letterCase.reset();
        keyboardLayer = KeyboardLayout.Layer.LETTERS;
        editorInputType = info == null ? 0 : info.inputType;
        Boolean englishOverride = inputContext.englishOverride(
            EditorPolicy.prefersLatin(editorInputType), currentDocumentIdentifier, dedicatedEnglish);
        if (englishOverride != null) dedicatedEnglish = englishOverride;
        allowLearning = info != null && EditorPolicy.allowLearning(info.imeOptions);
        preferencesNotice = "";
        statisticsFailureReported = false;
        message = "直接输入";
        if (info != null && connection != null && EditorPolicy.useEngine(info.inputType)) {
            try {
                File file = new File(getFilesDir(), "runtime-options.json");
                if (file.length() > 16384) throw new IllegalArgumentException("Options too large");
                JSONObject options = new JSONObject(new String(Files.readAllBytes(file.toPath()), StandardCharsets.UTF_8));
                JSONObject preferences = options.optJSONObject("preferences");
                KeyboardScheme engineScheme = KeyboardScheme.fromPreferences(
                    preferences == null ? "quanpin" : preferences.optString("scheme", "quanpin"),
                    preferences == null ? "xiaohe" : preferences.optString("shuangpin_profile", "xiaohe"),
                    preferences == null ? "twenty_six_key"
                        : preferences.optString("touch_keyboard_layout", "twenty_six_key"));
                SchemeConfiguration schemeConfiguration = schemeConfiguration(preferences, engineScheme);
                enabledSchemes = schemeConfiguration.enabled();
                selectedScheme = schemeConfiguration.selected();
                sharedSchemePreferences = schemeConfiguration.shared();
                skin = keyboardSkin(preferences);
                localModes = preferences == null ? new JSONObject()
                    : preferences.optJSONObject("local_modes");
                if (localModes == null) localModes = new JSONObject();
                applyCandidateAppearance(preferences);
                applyTouchGeometry(preferences);
                applyVoicePreferences(preferences);
                applyAiPreferences(preferences);
                applyClipboardPreference(preferences);
                applyChineseOutputPreference(preferences);
                applyCandidateGlossPreference(preferences);
                applyWubiCodeHintPreference(preferences);
                if (!allowLearning) options.getJSONObject("preferences").put("learning", false);
                runtimeOptionsForSnapshot = options.toString();
                // Settings edits are queued in the shared PersonalDictionary
                // journal. There is no live Engine session yet, so this is a
                // safe idle boundary at which to apply a bounded batch and
                // refresh the confirmed page.
                try {
                    JSONObject sync = value(NativeClient.personalDictionarySync(options.toString()));
                    if (sync.optString("snapshot_error", "").length() > 0) {
                        preferencesNotice = " · 个人词库同步稍后重试";
                    }
                } catch (JSONException | LinkageError ignored) {
                    // Personal dictionary maintenance is optional; never make
                    // a new editor session unavailable because it is busy.
                }
                view = value(NativeClient.create(options.toString()));
                session = view.getLong("session");
                String resources = options.optString("resources", "");
                if (new File(resources).isAbsolute()) {
                    emojiResources = resources;
                    candidateGlossResources = resources;
                }
                apply(NativeClient.focus(session, true));
                view = value(NativeClient.setEnglishMode(session, dedicatedEnglish));
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
        updateAutomaticCapitalization();
        rebuildKeyRows();
        render();
        replySuppressed = false;
        synchronizeReplyKeyboard();
    }

    @Override public void onFinishInput() {
        cancelBackspaceRepeat();
        resetSpaceCursor();
        stop(true);
        scheduleDictionarySnapshotProcessing();
        connection = null;
        currentDocumentIdentifier = 0;
        super.onFinishInput();
    }
    @Override public void onConfigurationChanged(Configuration configuration) {
        super.onConfigurationChanged(configuration);
        JSONObject preferences = preferencesSnapshot == null ? null
            : preferencesSnapshot.optJSONObject("preferences");
        KeyboardSkin next = keyboardSkin(preferences);
        if (skin.key().equals(next.key())) return;
        skin = next;
        applySkin();
        render();
    }
    @Override public void onDestroy() {
        cancelBackspaceRepeat();
        stop(false);
        preferencesWorker.shutdown();
        typingStatisticsWorker.shutdown();
        emojiWorker.shutdown();
        candidateGlossWorker.shutdownNow();
        aiPolishClient.close();
        connection = null;
        super.onDestroy();
    }
    @Override public boolean onEvaluateFullscreenMode() { return false; }

    private void stop(boolean finish) {
        cancelBackspaceRepeat();
        deactivateHandwriting();
        invalidateCandidateGlosses();
        preferencesReloader.stop();
        preferenceSaveGeneration++;
        preferencesDirectory = "";
        emojiResources = "";
        candidateGlossResources = "";
        candidateEnglishGloss = false;
        wubiCodeHint = true;
        preferencesSnapshot = null;
        schemeSaving = false;
        touchGeometrySaving = false;
        skinSaving = false;
        traditionalOutputSaving = false;
        if (session != 0) {
            try { if (finish && connection != null) apply(NativeClient.command(session, 9)); }
            catch (Exception | LinkageError ignored) { /* Never log editor text or native responses. */ }
            try { NativeClient.destroy(session); } catch (LinkageError ignored) { }
            session = 0;
        }
        if (connection != null) bridge.abandon(sink(typingSource()));
        view = null;
        closeCandidatePanel();
        closeClipboardHistory();
        closeSchemePicker();
        closeLayoutSettings();
        closeMoreTools();
        closeEmojiPicker();
        closeVoiceResult();
        closeAiPolish();
        closeReplyKeyboard();
    }

    /** The session has been destroyed, so native maintenance may take the exclusive lock. */
    private void scheduleDictionarySnapshotProcessing() {
        if (runtimeOptionsForSnapshot.isEmpty()) return;
        String options = runtimeOptionsForSnapshot;
        Path root = new File(getFilesDir(), "bootstrap/state/dictionary-snapshots").toPath();
        Path staging = root.resolve("staging");
        try {
            preferencesWorker.execute(() -> {
                try { DictionarySnapshotWorker.process(root, staging, options); }
                catch (Exception | LinkageError ignored) { /* Retry at the next idle boundary. */ }
            });
        } catch (RuntimeException ignored) { /* Service shutdown owns the final worker state. */ }
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
        touchKeyboardHeightAdjustment = KeyboardGeometry.heightAdjustment(preferences == null
            ? Integer.MIN_VALUE : preferences.optInt("touch_keyboard_height_adjustment",
                Integer.MIN_VALUE));
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

    private void applyChineseOutputPreference(JSONObject preferences) {
        traditionalChineseOutput = preferences != null
            && preferences.optBoolean("traditional_chinese_output", false);
    }

    private void applyCandidateGlossPreference(JSONObject preferences) {
        boolean next = preferences != null
            && preferences.optBoolean("candidate_english_gloss", false);
        if (candidateEnglishGloss != next) invalidateCandidateGlosses();
        candidateEnglishGloss = next;
    }

    private void applyWubiCodeHintPreference(JSONObject preferences) {
        wubiCodeHint = preferences == null
            || preferences.optBoolean("wubi_code_hint", true);
    }

    private void invalidateCandidateGlosses() {
        candidateGlossEpoch = candidateGlossEpoch == Long.MAX_VALUE ? 0 : candidateGlossEpoch + 1;
        candidateGlossRequestedSession = 0;
        candidateGlossRequestedGeneration = -1;
    }

    private String chineseOutput(String text, JSONObject context) {
        int scheme = context == null
            ? (view == null ? -1 : view.optInt("scheme", -1))
            : context.optInt("scheme", -1);
        String localMode = context == null
            ? (view == null ? "none" : view.optString("local_mode", "none"))
            : context.optString("local_mode", "none");
        return AndroidChineseTextConversion.outputString(
            text, traditionalChineseOutput, dedicatedEnglish, scheme, localMode);
    }

    private String candidateAppearanceKey() {
        return (candidateHorizontal ? "horizontal" : "vertical") + ":"
            + candidateFontSize + ":" + candidatePreeditFontSize;
    }

    private String touchGeometryKey() {
        return touchKeySpacingTenths + ":" + touchRowSpacingTenths + ":"
            + touchKeyboardHeightAdjustment + ":"
            + touchVoiceShortcutEnabled + ":" + voiceInputEnabled + ":" + voiceLanguage;
    }

    private void reloadPreferences(String response) {
        if (session == 0) return;
        boolean previousPreferencesReady = preferencesSnapshot != null;
        String previousView = view == null ? "" : view.toString();
        String previousNotice = preferencesNotice;
        String previousSkin = skin.key();
        String previousAppearance = candidateAppearanceKey();
        String previousGeometry = touchGeometryKey();
        AiPolishConfiguration previousAi = aiPolishConfiguration;
        boolean previousClipboard = clipboardHistoryEnabled;
        boolean previousTraditional = traditionalChineseOutput;
        boolean previousCandidateGloss = candidateEnglishGloss;
        boolean previousWubiCodeHint = wubiCodeHint;
        KeyboardScheme previousScheme = selectedScheme;
        try {
            if (response == null) throw new JSONException("Preferences unavailable");
            JSONObject snapshot = value(response);
            applyPreferencesSnapshot(snapshot);
        } catch (JSONException | LinkageError error) {
            // Never replace the working session or log preferences/native responses.
            preferencesNotice = " · 设置读取或应用失败，保留当前设置";
        }
        if (previousPreferencesReady != (preferencesSnapshot != null)
                || !previousNotice.equals(preferencesNotice) || !previousSkin.equals(skin.key())
                || !previousAppearance.equals(candidateAppearanceKey())
                || !previousGeometry.equals(touchGeometryKey())
                || (previousAi == null ? aiPolishConfiguration != null
                    : !previousAi.equals(aiPolishConfiguration))
                || previousClipboard != clipboardHistoryEnabled
                || previousTraditional != traditionalChineseOutput
                || previousCandidateGloss != candidateEnglishGloss
                || previousWubiCodeHint != wubiCodeHint
                || previousScheme != selectedScheme
                || !previousView.equals(view == null ? "" : view.toString())) render();
    }

    private void applyPreferencesSnapshot(JSONObject snapshot) throws JSONException {
        JSONObject accepted = new JSONObject(snapshot.toString());
        JSONObject preferences = accepted.getJSONObject("preferences");
        KeyboardSkin nextSkin = keyboardSkin(preferences);
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
        int nextHeightAdjustment = KeyboardGeometry.heightAdjustment(
            preferences.optInt("touch_keyboard_height_adjustment", Integer.MIN_VALUE));
        boolean nextVoiceShortcut = preferences.optBoolean("touch_voice_shortcut", false);
        JSONObject nextVoice = preferences.optJSONObject("voice_input");
        boolean nextVoiceEnabled = nextVoice == null || nextVoice.optBoolean("enabled", true);
        String nextVoiceLanguage = nextVoice == null ? "zh-CN"
            : nextVoice.optString("language", "zh-CN");
        boolean nextClipboard = preferences.optBoolean("clipboard_history", false);
        boolean nextTraditional = preferences.optBoolean("traditional_chinese_output", false);
        boolean nextCandidateGloss = preferences.optBoolean("candidate_english_gloss", false);
        boolean nextWubiCodeHint = preferences.optBoolean("wubi_code_hint", true);
        KeyboardScheme nextScheme = KeyboardScheme.fromPreferences(
            preferences.optString("scheme", "quanpin"),
            preferences.optString("shuangpin_profile", "xiaohe"),
            preferences.optString("touch_keyboard_layout", "twenty_six_key"));
        SchemeConfiguration nextSchemeConfiguration = schemeConfiguration(preferences, nextScheme);
        JSONObject sessionSnapshot = new JSONObject(accepted.toString());
        // Keep the accepted disk snapshot intact while enforcing editor privacy in this session.
        if (!allowLearning) sessionSnapshot.getJSONObject("preferences").put("learning", false);
        JSONObject result = value(NativeClient.updatePreferences(session, sessionSnapshot.toString()));
        boolean geometryChanged = touchKeySpacingTenths != nextKeySpacing
            || touchRowSpacingTenths != nextRowSpacing
            || touchKeyboardHeightAdjustment != nextHeightAdjustment;
        skin = nextSkin;
        localModes = nextLocalModes;
        candidateHorizontal = nextHorizontal;
        candidateFontSize = nextFontSize;
        candidatePreeditFontSize = nextPreeditFontSize;
        touchKeySpacingTenths = nextKeySpacing;
        touchRowSpacingTenths = nextRowSpacing;
        touchKeyboardHeightAdjustment = nextHeightAdjustment;
        touchVoiceShortcutEnabled = nextVoiceShortcut;
        voiceInputEnabled = nextVoiceEnabled;
        voiceLanguage = nextVoiceLanguage;
        applyAiPreferences(preferences);
        clipboardHistoryEnabled = nextClipboard;
        traditionalChineseOutput = nextTraditional;
        if (candidateEnglishGloss != nextCandidateGloss) invalidateCandidateGlosses();
        candidateEnglishGloss = nextCandidateGloss;
        wubiCodeHint = nextWubiCodeHint;
        JSONObject nextView = result.getJSONObject("view");
        boolean rebuildLayout = displayedTouchLayout(view) != displayedTouchLayout(nextView);
        enabledSchemes = nextSchemeConfiguration.enabled();
        selectedScheme = nextSchemeConfiguration.selected();
        sharedSchemePreferences = nextSchemeConfiguration.shared();
        preferencesSnapshot = accepted;
        if (!clipboardHistoryEnabled && clipboardHistory != null) {
            clipboardHistory.clear();
            closeClipboardHistory();
        }
        view = nextView;
        if (displayedTouchLayout(view) != STANDARD_TOUCH_LAYOUT) letterCase.reset();
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
        boolean rebuildLayout = displayedTouchLayout(view) != displayedTouchLayout(next);
        String commit = result.isNull("commit") ? null : result.getString("commit");
        if (commit != null) commit = chineseOutput(commit, result.optJSONObject("commit_context"));
        if (connection != null
                && !bridge.apply(sink(typingSource()), commit, next.getString("editing_text"))) {
            throw new JSONException("Editor rejected update");
        }
        view = next;
        if (displayedTouchLayout(view) != STANDARD_TOUCH_LAYOUT) letterCase.reset();
        if (rebuildLayout) rebuildKeyRows();
        render();
        return result.getBoolean("handled");
    }

    /** Copies Engine candidates on the IME thread, then performs only session-free IO off-thread. */
    private void scheduleCandidateGlosses() {
        if (!candidateEnglishGloss || session == 0 || view == null
                || candidateGlossResources.isEmpty()) return;
        long generation = view.optLong("generation", -1);
        if (generation < 0 || (candidateGlossRequestedSession == session
                && candidateGlossRequestedGeneration == generation)) return;
        JSONArray visible = view.optJSONArray("candidates");
        if (visible == null || visible.length() == 0) return;
        final long targetSession = session;
        final long targetEpoch = candidateGlossEpoch;
        final String targetResources = candidateGlossResources;
        final String request;
        try {
            JSONObject snapshot = value(NativeClient.allCandidates(targetSession));
            if (snapshot.optLong("session") != targetSession
                    || snapshot.optLong("generation") != generation) return;
            request = CandidateGlossModel.request(generation,
                snapshot.getJSONArray("candidates"));
        } catch (JSONException | RuntimeException | LinkageError error) {
            candidateGlossRequestedSession = targetSession;
            candidateGlossRequestedGeneration = generation;
            return;
        }
        CandidateGlossPolicy.Token token =
            new CandidateGlossPolicy.Token(targetSession, generation, targetEpoch);
        candidateGlossRequestedSession = targetSession;
        candidateGlossRequestedGeneration = generation;
        try {
            candidateGlossWorker.execute(() -> {
                try {
                    CandidateGlossModel.Result result = CandidateGlossModel.decode(
                        NativeClient.candidateGlosses(request, targetResources));
                    main.post(() -> applyCandidateGlosses(token, result));
                } catch (JSONException | RuntimeException | LinkageError error) {
                    // Display-only lookup failures remain silent and never include candidate text.
                }
            });
        } catch (RuntimeException ignored) {
            // A stopped or saturated host must not affect input.
        }
    }

    private void applyCandidateGlosses(
            CandidateGlossPolicy.Token token, CandidateGlossModel.Result result) {
        long currentGeneration = view == null ? -1 : view.optLong("generation", -1);
        if (!candidateEnglishGloss || result.generation() != token.generation()
                || !token.isCurrent(session, currentGeneration, candidateGlossEpoch)) return;
        try {
            JSONObject applied = value(NativeClient.applyTranslations(
                token.session(), token.generation(), result.translations()));
            if (!applied.optBoolean("applied", false)) return;
            JSONObject next = applied.getJSONObject("view");
            if (next.optLong("session") != token.session()
                    || next.optLong("generation") != token.generation()) return;
            view = next;
            if (candidatePanelOpen) {
                JSONObject snapshot = value(NativeClient.allCandidates(token.session()));
                if (snapshot.optLong("session") == token.session()
                        && snapshot.optLong("generation") == token.generation()) {
                    candidatePanelSnapshot = snapshot;
                }
            }
            render();
        } catch (JSONException | RuntimeException | LinkageError error) {
            // Candidate glosses are optional display state; keep the current Engine view.
        }
    }

    private void fail() { stop(false); message = "输入连接失败：仅直接输入"; render(); }

    private boolean character(int ascii) {
        return character(ascii, letterCase.usesUppercase());
    }

    private boolean character(int ascii, boolean shifted) {
        if (session == 0) return false;
        try { return apply(NativeClient.character(session, ascii, shifted)); }
        catch (JSONException | LinkageError error) { fail(); return true; }
    }

    private boolean helpcodeCompositionEligible() {
        if (view == null) return false;
        return ChineseHelpcodePolicy.eligible(dedicatedEnglish,
            view.optString("editing_text", ""), view.optInt("scheme", -1),
            view.optString("local_mode", "none"));
    }

    private boolean entersHelpcode() {
        if (view == null) return false;
        return ChineseHelpcodePolicy.entersHelpcode(dedicatedEnglish, letterCase.usesUppercase(),
            view.optString("editing_text", ""), view.optInt("scheme", -1),
            view.optString("local_mode", "none"));
    }

    private boolean command(int code) {
        if (session == 0) return false;
        try { return apply(NativeClient.command(session, code)); }
        catch (JSONException | LinkageError error) { fail(); return true; }
    }

    private void type(char key) {
        if (connection == null) return;
        if (dedicatedEnglish && !isAsciiLetter(key)) {
            commitEnglishLiteral(key);
            return;
        }
        if (entersHelpcode() && isAsciiLetter(key)) {
            character(Character.toUpperCase(key), true);
            if (letterCase.consumeLetter()) {
                rebuildKeyRows();
                render();
            }
            return;
        }
        char output = letterCase.usesUppercase() ? Character.toUpperCase(key) : key;
        if (!character(output)) commitText(String.valueOf(output));
        if (letterCase.consumeLetter()) {
            rebuildKeyRows();
            render();
        }
    }

    private static boolean isAsciiLetter(int value) {
        return (value >= 'a' && value <= 'z') || (value >= 'A' && value <= 'Z');
    }

    private void commitEnglishLiteral(int value) {
        if (connection == null || value < 32 || value > 126) return;
        if (session != 0) command(9);
        if (connection != null) commitText(String.valueOf((char) value));
    }

    private void space() {
        if (connection == null) return;
        if (commitFirstHandwritingCandidate()) return;
        if (dedicatedEnglish) {
            if (session != 0) command(1);
            if (connection != null) commitText(" ");
        } else if (!command(1)) {
            commitText(" ");
        }
    }

    private boolean japaneseNineKeyActive() {
        return displayedTouchLayout(view) == JAPANESE_NINE_KEY_LAYOUT;
    }

    private String spaceKeyTitle() {
        return japaneseNineKeyActive()
            ? JapaneseNineKeyActions.spaceTitle(view != null
                && !view.optString("editing_text", "").isEmpty()) : "空格";
    }

    private String spaceKeyDescription() {
        return japaneseNineKeyActive()
            ? spaceKeyTitle() + "；左右滑动移动光标" : SPACE_CURSOR_DESCRIPTION;
    }

    private int displayedTouchLayout(JSONObject value) {
        return dedicatedEnglish ? STANDARD_TOUCH_LAYOUT : touchLayout(value);
    }

    private boolean sendsChinesePunctuation() {
        return view != null && ChineseSymbolFaces.shouldUseChineseFaces(dedicatedEnglish,
            view.optInt("scheme", -1), view.optString("local_mode", "none"));
    }

    private java.util.List<QuickPunctuationPolicy.Entry> quickPunctuationEntries() {
        return QuickPunctuationPolicy.entries(dedicatedEnglish,
            view == null ? -1 : view.optInt("scheme", -1),
            view == null ? "none" : view.optString("local_mode", "none"));
    }

    private boolean quickPunctuationVisible() {
        int layout = displayedTouchLayout(view);
        return keyboardLayer == KeyboardLayout.Layer.LETTERS
            && layout != QUANPIN_NINE_KEY_LAYOUT && layout != JAPANESE_NINE_KEY_LAYOUT
            && selectedScheme != KeyboardScheme.QUANPIN_NINE_KEY
            && selectedScheme != KeyboardScheme.JAPANESE_NINE_KEY;
    }

    private void insertQuickPunctuation() {
        java.util.List<QuickPunctuationPolicy.Entry> entries = quickPunctuationEntries();
        if (!entries.isEmpty()) type(entries.get(0).input());
    }

    private void showQuickPunctuationMenu() {
        if (quickPunctuationButton == null || !quickPunctuationVisible()) return;
        PopupMenu popup = new PopupMenu(this, quickPunctuationButton);
        for (QuickPunctuationPolicy.Entry entry : quickPunctuationEntries()) {
            popup.getMenu().add(entry.face()).setOnMenuItemClickListener(ignored -> {
                playFeedback(quickPunctuationButton);
                type(entry.input());
                return true;
            });
        }
        popup.show();
    }

    private void updateQuickPunctuation() {
        if (quickPunctuationButton == null) return;
        java.util.List<QuickPunctuationPolicy.Entry> entries = quickPunctuationEntries();
        boolean visible = quickPunctuationVisible() && !entries.isEmpty();
        quickPunctuationButton.setVisibility(visible ? View.VISIBLE : View.GONE);
        if (!visible) return;
        String face = entries.get(0).face();
        quickPunctuationButton.setText(face);
        quickPunctuationButton.setContentDescription("常用标点：" + face
            + "；长按选择常用标点");
    }

    private void updateSymbolKeyFaces() {
        boolean chineseMode = sendsChinesePunctuation();
        for (int index = 0; index < symbolKeyButtons.size(); index++) {
            String face = ChineseSymbolFaces.face(symbolKeyInputs.get(index), chineseMode);
            Button button = symbolKeyButtons.get(index);
            button.setText(face);
            button.setContentDescription("按键 " + face);
        }
    }

    private void updateAutomaticCapitalization() {
        if (!dedicatedEnglish) {
            letterCase.reset();
            return;
        }
        CharSequence context = null;
        if (connection != null) {
            try {
                context = connection.getTextBeforeCursor(CAPITALIZATION_CONTEXT_LIMIT, 0);
            } catch (RuntimeException ignored) {
                // Editor context is optional and must never be logged or persisted.
            }
        }
        boolean next = EnglishCapitalizationPolicy.shouldShift(
            EditorPolicy.capitalizationMode(editorInputType), context);
        if (letterCase.applyAutomatic(next)) rebuildKeyRows();
        render();
    }

    private void toggleInputLanguage() {
        if (session == 0) return;
        boolean nextEnglish = !dedicatedEnglish;
        if (dedicatedEnglish) command(3); else command(9);
        if (session == 0) return;
        int previousLayout = displayedTouchLayout(view);
        boolean previousUppercase = letterCase.usesUppercase();
        try {
            JSONObject nextView = value(NativeClient.setEnglishMode(session, nextEnglish));
            dedicatedEnglish = nextEnglish;
            view = nextView;
            keyboardLayer = KeyboardLayout.Layer.LETTERS;
            letterCase.reset();
            if (previousLayout != displayedTouchLayout(view) || previousUppercase) rebuildKeyRows();
            updateAutomaticCapitalization();
        } catch (JSONException | LinkageError error) {
            fail();
        }
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
        if (commitFirstHandwritingCandidate()) return;
        if (command(9)) return;
        EditorInfo info = getCurrentInputEditorInfo();
        int action = info == null ? EditorInfo.IME_ACTION_NONE : info.imeOptions & EditorInfo.IME_MASK_ACTION;
        boolean disabled = info == null
                || (info.imeOptions & EditorInfo.IME_FLAG_NO_ENTER_ACTION) != 0;
        if (ReturnKeyAction.shouldPerformEditorAction(action, disabled, false)
                && connection.performEditorAction(action)) return;
        commitText("\n");
    }

    private void updateReturnKey() {
        EditorInfo info = getCurrentInputEditorInfo();
        int action = info == null ? EditorInfo.IME_ACTION_NONE
                : info.imeOptions & EditorInfo.IME_MASK_ACTION;
        boolean disabled = info == null
                || (info.imeOptions & EditorInfo.IME_FLAG_NO_ENTER_ACTION) != 0;
        String title = ReturnKeyAction.title(action, disabled);
        if (enterButton != null) {
            enterButton.setText(title);
            enterButton.setContentDescription(title);
        }
        if (japaneseReturnKey != null) {
            boolean composing = view != null && !view.optString("editing_text", "").isEmpty();
            String japaneseTitle = JapaneseNineKeyActions.returnTitle(composing);
            japaneseReturnKey.setText(japaneseTitle);
            japaneseReturnKey.setContentDescription(japaneseTitle);
        }
        if (japaneseSpaceKey != null) {
            japaneseSpaceKey.setText(spaceKeyTitle());
            japaneseSpaceKey.setContentDescription(spaceKeyDescription());
        }
        if (japaneseVariantsButton != null) {
            boolean composing = view != null
                && !view.optString("editing_text", "").isEmpty();
            boolean enabled = JapaneseVariantPolicy.enabled(
                japaneseNineKeyActive(), keyboardLayer == KeyboardLayout.Layer.SYMBOLS,
                composing);
            japaneseVariantsButton.setEnabled(enabled);
            japaneseVariantsButton.setContentDescription(
                JapaneseVariantPolicy.accessibilityLabel(enabled));
        }
        if (spaceButton != null && !cursorMovement.isActive()) {
            spaceButton.setText(spaceKeyTitle());
            spaceButton.setContentDescription(spaceKeyDescription());
        }
    }

    private void resetSpaceCursor() {
        cursorMovement.cancel();
        if (spaceButton == null) return;
        spaceButton.setPressed(false);
        spaceButton.setText(spaceKeyTitle());
        spaceButton.setContentDescription(spaceKeyDescription());
    }

    private void moveEditorCursor(int offset) {
        int keyCode = offset < 0 ? KeyEvent.KEYCODE_DPAD_LEFT : KeyEvent.KEYCODE_DPAD_RIGHT;
        for (int index = 0; index < Math.abs(offset); index++) sendDownUpKeyEvents(keyCode);
    }

    private void bindSpaceCursor(Button button) {
        final float[] origin = new float[2];
        final boolean[] dragging = new boolean[1];
        final boolean[] cancelled = new boolean[1];
        final int touchSlop = ViewConfiguration.get(this).getScaledTouchSlop();
        button.setOnTouchListener((ignored, event) -> {
            switch (event.getActionMasked()) {
                case MotionEvent.ACTION_DOWN -> {
                    origin[0] = event.getX();
                    origin[1] = event.getY();
                    dragging[0] = false;
                    cancelled[0] = false;
                    button.setPressed(true);
                    button.getParent().requestDisallowInterceptTouchEvent(true);
                    return true;
                }
                case MotionEvent.ACTION_MOVE -> {
                    if (!dragging[0] && !cancelled[0]) {
                        float horizontal = event.getX() - origin[0];
                        float vertical = event.getY() - origin[1];
                        if (Math.abs(horizontal) <= touchSlop && Math.abs(vertical) <= touchSlop)
                            return true;
                        if (Math.abs(horizontal) <= Math.abs(vertical) || connection == null) {
                            cancelled[0] = true;
                            button.setPressed(false);
                            return true;
                        }
                        command(9);
                        cursorMovement.begin(origin[0], connection);
                        dragging[0] = cursorMovement.isActive();
                        cancelled[0] = !dragging[0];
                        button.setPressed(false);
                        if (dragging[0]) {
                            button.setText("移动光标");
                            button.setContentDescription("正在移动光标");
                            moveEditorCursor(cursorMovement.advance(
                                event.getX(), connection, pixels(12)));
                        }
                        return true;
                    }
                    if (dragging[0]) {
                        moveEditorCursor(cursorMovement.advance(
                            event.getX(), connection, pixels(12)));
                        if (!cursorMovement.isActive()) {
                            dragging[0] = false;
                            cancelled[0] = true;
                            resetSpaceCursor();
                        }
                    }
                    return true;
                }
                case MotionEvent.ACTION_UP -> {
                    button.getParent().requestDisallowInterceptTouchEvent(false);
                    button.setPressed(false);
                    if (dragging[0] || cancelled[0]) resetSpaceCursor();
                    else button.performClick();
                    return true;
                }
                case MotionEvent.ACTION_CANCEL -> {
                    button.getParent().requestDisallowInterceptTouchEvent(false);
                    dragging[0] = false;
                    cancelled[0] = true;
                    resetSpaceCursor();
                    return true;
                }
                default -> { return true; }
            }
        });
    }

    @Override public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_BACK && emojiPickerVisible()) {
            closeEmojiPicker();
            return true;
        }
        if (session == 0 || event.isCtrlPressed() || event.isAltPressed() || event.isMetaPressed()) {
            if (session != 0 && connection != null) {
                // Preserve displayed source text before the editor handles a shortcut.
                command(2);
            }
            return super.onKeyDown(keyCode, event);
        }
        if (keyCode == KeyEvent.KEYCODE_DEL && handwritingActive()) {
            deleteFromHandwriting();
            return true;
        }
        if (keyCode == KeyEvent.KEYCODE_DEL) return command(0) || super.onKeyDown(keyCode, event);
        if (keyCode == KeyEvent.KEYCODE_SPACE && dedicatedEnglish) { space(); return true; }
        if (keyCode == KeyEvent.KEYCODE_SPACE && handwritingActive()) { space(); return true; }
        if (keyCode == KeyEvent.KEYCODE_SPACE) return command(1) || super.onKeyDown(keyCode, event);
        if (keyCode == KeyEvent.KEYCODE_ENTER) { enter(); return true; }
        int unicode = event.getUnicodeChar();
        if (dedicatedEnglish && unicode >= 32 && unicode <= 126 && !isAsciiLetter(unicode)) {
            commitEnglishLiteral(unicode);
            return true;
        }
        boolean handled = unicode >= 32 && unicode <= 126
            && character(unicode, event.isShiftPressed());
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
            if (connection != null) bridge.abandon(sink(typingSource()));
            view = null;
            render();
        }
        updateAutomaticCapitalization();
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

    private Button brandButton(LinearLayout row, Runnable action) {
        KeyboardBrandButton button = new KeyboardBrandButton(this,
            () -> Color.parseColor(skin.accent()));
        button.setAllCaps(false);
        button.setText("更多");
        styleButton(button, true);
        button.setOnClickListener(ignored -> {
            playFeedback(button);
            action.run();
        });
        row.addView(button, new LinearLayout.LayoutParams(0,
            LinearLayout.LayoutParams.WRAP_CONTENT, 1));
        return button;
    }

    private Button borderlessButton(LinearLayout row, String label, Runnable action) {
        Button button = new KeyboardBorderlessButton(this);
        button.setAllCaps(false);
        button.setText(label);
        styleButton(button, true);
        button.setOnClickListener(ignored -> {
            playFeedback(button);
            action.run();
        });
        row.addView(button, new LinearLayout.LayoutParams(0,
            LinearLayout.LayoutParams.WRAP_CONTENT, 1));
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

    /** Matches the Apple delete key: a short tap deletes once, a held press repeats. */
    private void bindBackspaceRepeat(Button button, Runnable action) {
        button.setOnTouchListener((view, event) -> {
            switch (event.getActionMasked()) {
                case MotionEvent.ACTION_DOWN -> {
                    cancelBackspaceRepeat();
                    backspaceRepeatButton = button;
                    backspaceRepeated = false;
                    button.setPressed(true);
                    backspaceRepeatTask = new Runnable() {
                        @Override public void run() {
                            if (backspaceRepeatButton != button || !button.isPressed()) return;
                            backspaceRepeated = true;
                            playFeedback(button);
                            action.run();
                            main.postDelayed(this, BACKSPACE_REPEAT_INTERVAL_MILLIS);
                        }
                    };
                    main.postDelayed(backspaceRepeatTask, BACKSPACE_REPEAT_DELAY_MILLIS);
                    return true;
                }
                case MotionEvent.ACTION_MOVE -> {
                    if (event.getX() < 0 || event.getY() < 0
                            || event.getX() >= button.getWidth()
                            || event.getY() >= button.getHeight()) {
                        cancelBackspaceRepeat();
                        button.setPressed(false);
                    }
                    return true;
                }
                case MotionEvent.ACTION_UP -> {
                    boolean active = backspaceRepeatButton == button;
                    boolean repeated = active && backspaceRepeated;
                    cancelBackspaceRepeat();
                    button.setPressed(false);
                    if (active && !repeated) button.performClick();
                    return true;
                }
                case MotionEvent.ACTION_CANCEL, MotionEvent.ACTION_OUTSIDE -> {
                    cancelBackspaceRepeat();
                    button.setPressed(false);
                    return true;
                }
                default -> { return true; }
            }
        });
    }

    private void cancelBackspaceRepeat() {
        if (backspaceRepeatTask != null) main.removeCallbacks(backspaceRepeatTask);
        backspaceRepeatTask = null;
        if (backspaceRepeatButton != null) backspaceRepeatButton.setPressed(false);
        backspaceRepeatButton = null;
        backspaceRepeated = false;
    }

    private int pixels(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private int pixels(double value) {
        if (value <= 0) return 0;
        return Math.max(1, Math.round((float) value * getResources().getDisplayMetrics().density));
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
        applyKeyboardHeight(keyRows);
        keyRows.requestLayout();
        if (keyboardRoot != null) {
            keyboardRoot.requestLayout();
            keyboardRoot.getRootView().requestLayout();
        }
    }

    private void applyKeyboardHeight(View node) {
        Object tag = node.getTag();
        if (tag instanceof KeyboardHeightRole) {
            KeyboardHeightRole role = (KeyboardHeightRole) tag;
            int height = pixels(KeyboardGeometry.adjustedRowHeight(role.baseHeight,
                touchKeyboardHeightAdjustment, role.rowCount, role.rowIndex));
            if (role.includesRowSpacing)
                height += halfSpacingPixels(touchRowSpacingTenths) * 2;
            if (node.getLayoutParams() != null) {
                android.view.ViewGroup.LayoutParams params = node.getLayoutParams();
                params.height = height;
                node.setLayoutParams(params);
            }
        }
        if (node instanceof android.view.ViewGroup) {
            android.view.ViewGroup group = (android.view.ViewGroup) node;
            for (int index = 0; index < group.getChildCount(); index++)
                applyKeyboardHeight(group.getChildAt(index));
        }
    }

    private void adjustFixedHeight(View view, int baseHeight) {
        view.setTag(new KeyboardHeightRole(baseHeight, 1, 0, false));
    }

    private void styleButton(Button button, boolean action) {
        boolean selected = button.isSelected();
        String background = selected ? skin.accent() : action ? skin.actionBackground() : skin.keyBackground();
        String foreground = selected ? skin.actionForeground() : action ? skin.actionForeground() : skin.keyForeground();
        if ("custom".equals(skin.id())) {
            button.setBackground(new KeyboardSkinKeyDrawable(skin,
                Color.parseColor(background), selected || action,
                getResources().getDisplayMetrics().density));
        } else {
            GradientDrawable drawable = new GradientDrawable();
            drawable.setColor(Color.parseColor(background));
            drawable.setCornerRadius(pixels(skin.cornerRadius()));
            int borderWidth = pixels(skin.borderWidth());
            if (borderWidth > 0)
                drawable.setStroke(borderWidth, Color.parseColor(skin.borderColor()));
            button.setBackground(drawable);
        }
        button.setTextColor(Color.parseColor(foreground));
        button.setTypeface(skin.monospaced() ? Typeface.MONOSPACE : Typeface.DEFAULT);
        int shadowAlpha = (int) Math.round(255 * skin.shadowOpacity());
        int shadowColor = Color.argb(shadowAlpha, 0, 0, 0);
        button.setOutlineAmbientShadowColor(shadowColor);
        button.setOutlineSpotShadowColor(shadowColor);
        button.setElevation(skin.shadowOpacity() > 0
            ? pixels(Math.max(1, skin.shadowRadius() + skin.shadowOffset())) : 0);
    }

    private void applySkinToView(View node) {
        if (node instanceof Button) {
            CharSequence description = node.getContentDescription();
            boolean key = description != null && (description.toString().startsWith("按键 ")
                || description.toString().startsWith("候选 ")
                || description.toString().startsWith("输入方案卡片 "));
            styleButton((Button) node, !key);
            if (description != null && "恢复默认".contentEquals(description))
                ((Button) node).setTextColor(Color.RED);
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
        applySkinBackground(keyboardRoot);
        if (expandedCandidates != null)
            applySkinBackground(expandedCandidates);
        if (clipboardPanel != null)
            applySkinBackground(clipboardPanel);
        if (schemePanel != null)
            applySkinBackground(schemePanel);
        if (layoutSettingsPanel != null)
            applySkinBackground(layoutSettingsPanel);
        if (moreToolsPanel != null)
            applySkinBackground(moreToolsPanel);
        if (emojiPanel != null)
            applySkinBackground(emojiPanel);
        if (voiceResultPanel != null)
            applySkinBackground(voiceResultPanel);
        if (aiPolishPanel != null)
            applySkinBackground(aiPolishPanel);
        if (aiPolishContainer != null)
            applySkinBackground(aiPolishContainer);
        if (replyKeyboard != null)
            applySkinBackground(replyKeyboard);
        if (handwritingCanvas != null) handwritingCanvas.applySkin(skin);
        applySkinToView(keyboardRoot);
    }

    private void applySkinBackground(View node) {
        node.setBackground(new KeyboardSkinBackgroundDrawable(
            skin, getResources().getDisplayMetrics().density));
    }

    private boolean systemDark() {
        int mode = getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK;
        return mode == Configuration.UI_MODE_NIGHT_YES;
    }

    private KeyboardSkin keyboardSkin(JSONObject preferences) {
        String keyboardTheme = preferences == null ? "follow"
            : preferences.optString("screen_keyboard_theme", "follow");
        String globalTheme = preferences == null ? "system"
            : preferences.optString("theme", "system");
        boolean dark = KeyboardSkin.resolveDark(keyboardTheme, globalTheme, systemDark());
        String identifier = preferences == null ? "forest"
            : preferences.optString("touch_keyboard_skin", "forest");
        JSONObject customDesign = preferences == null ? null
            : preferences.optJSONObject("custom_touch_keyboard_skin");
        return KeyboardSkin.from(identifier, dark, customDesign);
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
        return !dedicatedEnglish && scheme != 2 && scheme != 3;
    }

    private void showLocalInputMenu() {
        if (preedit == null || !supportsLocalTools() || view == null
                || !view.optString("editing_text", "").isEmpty()
                || !"none".equals(view.optString("local_mode", "none"))) return;
        PopupMenu popup = new PopupMenu(this, preedit);
        for (LocalInputMode mode : LocalInputMode.values()) {
            MenuItem item = popup.getMenu().add(mode.title());
            item.setEnabled(localModeEnabled(mode));
            item.setOnMenuItemClickListener(ignored -> {
                openLocalInputMode(mode);
                return true;
            });
        }
        popup.show();
    }

    private boolean localModeEnabled(LocalInputMode mode) {
        return localModes.optBoolean(mode.preferenceKey(), true);
    }

    private void openLocalInputMode(LocalInputMode mode) {
        if (session == 0 || !supportsLocalTools() || !localModeEnabled(mode)) return;
        playFeedback(moreButton);
        character(mode.trigger().charAt(0), true);
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

    private void closeMoreTools() {
        localInputToolsOpen = false;
        if (moreToolsScroll != null) moreToolsScroll.setVisibility(View.GONE);
    }

    private void closeEmojiPicker() {
        emojiLoadGeneration++;
        emojiLoading = false;
        emojiSelectedCategory = Integer.MIN_VALUE;
        emojiItems = java.util.List.of();
        if (emojiPanel != null) emojiPanel.setVisibility(View.GONE);
        synchronizeReplyKeyboard();
    }

    private java.util.List<String> loadEmojiRecents() {
        if (emojiPreferences == null) return java.util.List.of();
        String document = emojiPreferences.getString(EMOJI_RECENTS_KEY, "[]");
        if (document == null || document.length() > 16_384) return java.util.List.of();
        try {
            JSONArray values = new JSONArray(document);
            java.util.ArrayList<String> stored = new java.util.ArrayList<>();
            int count = Math.min(values.length(), EmojiCatalogModel.RECENTS_LIMIT * 2);
            for (int index = 0; index < count; index++) {
                Object value = values.opt(index);
                if (value instanceof String) stored.add((String) value);
            }
            return EmojiCatalogModel.normalizeRecents(stored);
        } catch (JSONException error) {
            return java.util.List.of();
        }
    }

    private void saveEmojiRecents() {
        if (emojiPreferences == null) return;
        emojiPreferences.edit().putString(
            EMOJI_RECENTS_KEY, new JSONArray(emojiRecents).toString()).apply();
    }

    private boolean emojiPickerVisible() {
        return emojiPanel != null && emojiPanel.getVisibility() == View.VISIBLE;
    }

    private void selectEmojiCategory(int category) {
        if (!emojiPickerVisible()) return;
        if (category < -1 || category >= EmojiCatalogModel.categories().size()) return;
        emojiLoadGeneration++;
        emojiSelectedCategory = category;
        emojiNextOffset = 0;
        emojiComplete = category == -1;
        emojiLoading = false;
        emojiItems = java.util.List.of();
        renderEmojiTabs();
        if (category == -1) {
            java.util.ArrayList<EmojiCatalogModel.Item> recent = new java.util.ArrayList<>();
            for (String text : emojiRecents)
                recent.add(new EmojiCatalogModel.Item(text, "", "最近"));
            emojiItems = java.util.List.copyOf(recent);
            renderEmojiGrid();
        } else {
            renderEmojiGrid();
            loadEmojiPage();
        }
    }

    private EmojiCatalogModel.Page decodeEmojiPage(
            String response, int offset, EmojiCatalogModel.Category category) throws JSONException {
        JSONObject envelope = new JSONObject(response);
        if (!envelope.getBoolean("ok")) throw new JSONException("Emoji catalog unavailable");
        JSONObject value = envelope.getJSONObject("value");
        JSONArray entries = value.getJSONArray("items");
        if (entries.length() > EmojiCatalogModel.PAGE_SIZE)
            throw new JSONException("Emoji catalog page too large");
        java.util.ArrayList<EmojiCatalogModel.Item> items = new java.util.ArrayList<>();
        for (int index = 0; index < entries.length(); index++) {
            JSONObject entry = entries.getJSONObject(index);
            EmojiCatalogModel.Item item;
            try {
                item = new EmojiCatalogModel.Item(entry.getString("text"),
                    entry.getString("annotation"), entry.getString("group"));
            } catch (IllegalArgumentException error) {
                throw new JSONException("Invalid emoji catalog item");
            }
            if (!category.group().equals(item.group()))
                throw new JSONException("Unexpected emoji catalog group");
            items.add(item);
        }
        try {
            return EmojiCatalogModel.validatePage(items, offset, EmojiCatalogModel.PAGE_SIZE,
                value.getLong("next_offset"), value.getBoolean("complete"));
        } catch (IllegalArgumentException error) {
            throw new JSONException("Invalid emoji catalog cursor");
        }
    }

    private void loadEmojiPage() {
        if (!emojiPickerVisible() || emojiSelectedCategory < 0 || emojiLoading || emojiComplete
                || emojiResources.isEmpty()) return;
        int categoryIndex = emojiSelectedCategory;
        EmojiCatalogModel.Category category = EmojiCatalogModel.categories().get(categoryIndex);
        int offset = emojiNextOffset;
        long generation = ++emojiLoadGeneration;
        String resources = emojiResources;
        String query;
        try {
            query = new JSONObject().put("category", "").put("group", category.group())
                .put("offset", offset).put("limit", EmojiCatalogModel.PAGE_SIZE)
                .put("cursor", true).toString();
        } catch (JSONException error) {
            return;
        }
        emojiLoading = true;
        renderEmojiStatus();
        emojiWorker.execute(() -> {
            EmojiCatalogModel.Page page = null;
            try { page = decodeEmojiPage(NativeClient.emojiCatalog(query, resources), offset, category); }
            catch (JSONException | RuntimeException | LinkageError ignored) {
                // The UI reports a sanitized catalog error; never expose resource paths or rows.
            }
            EmojiCatalogModel.Page result = page;
            main.post(() -> {
                if (!emojiPickerVisible() || generation != emojiLoadGeneration
                        || categoryIndex != emojiSelectedCategory) return;
                emojiLoading = false;
                if (result == null) {
                    emojiComplete = true;
                    if (emojiStatus != null) emojiStatus.setText("表情目录暂时不可用；点分类重试");
                    return;
                }
                java.util.ArrayList<EmojiCatalogModel.Item> combined =
                    new java.util.ArrayList<>(emojiItems);
                combined.addAll(result.items());
                emojiItems = java.util.List.copyOf(combined);
                emojiNextOffset = result.nextOffset();
                emojiComplete = result.complete();
                renderEmojiGrid();
                if (!emojiComplete && result.items().isEmpty()) {
                    loadEmojiPage();
                } else if (!emojiComplete && emojiGridScroll != null) {
                    emojiGridScroll.post(() -> {
                        if (emojiPickerVisible() && generation == emojiLoadGeneration
                                && categoryIndex == emojiSelectedCategory
                                && !emojiGridScroll.canScrollVertically(1)) loadEmojiPage();
                    });
                }
            });
        });
    }

    private void renderEmojiStatus() {
        if (emojiStatus == null) return;
        if (emojiLoading) emojiStatus.setText("正在加载表情…");
        else if (emojiItems.isEmpty()) emojiStatus.setText("暂无表情");
        else if (emojiComplete) emojiStatus.setText(emojiItems.size() + " 个表情");
        else emojiStatus.setText(emojiItems.size() + " 个表情 · 继续滚动加载");
    }

    private void renderEmojiTabs() {
        if (emojiTabs == null) return;
        emojiTabs.removeAllViews();
        if (!emojiRecents.isEmpty()) addEmojiTab("最近", -1);
        for (int index = 0; index < EmojiCatalogModel.categories().size(); index++)
            addEmojiTab(EmojiCatalogModel.categories().get(index).title(), index);
    }

    private void addEmojiTab(String title, int category) {
        Button tab = new Button(this);
        tab.setAllCaps(false);
        tab.setText(title);
        tab.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        tab.setSelected(emojiSelectedCategory == category);
        tab.setContentDescription("表情分类 " + title);
        if (Build.VERSION.SDK_INT >= 30)
            tab.setStateDescription(tab.isSelected() ? "已选中" : "未选中");
        styleButton(tab, true);
        tab.setOnClickListener(ignored -> {
            playFeedback(tab);
            selectEmojiCategory(category);
        });
        emojiTabs.addView(tab, new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT, pixels(38)));
    }

    private void renderEmojiGrid() {
        if (emojiGrid == null) return;
        emojiGrid.removeAllViews();
        for (EmojiCatalogModel.Item item : emojiItems) {
            Button cell = keyboardKey(item.text(), "表情 " + item.text(),
                () -> insertEmoji(item.text()));
            cell.setTextSize(TypedValue.COMPLEX_UNIT_SP, 24);
            cell.setPadding(0, 0, 0, 0);
            GridLayout.LayoutParams params = new GridLayout.LayoutParams(
                GridLayout.spec(GridLayout.UNDEFINED), GridLayout.spec(GridLayout.UNDEFINED, 1f));
            params.width = 0;
            params.height = pixels(48);
            emojiGrid.addView(cell, params);
        }
        renderEmojiStatus();
        applySkin();
    }

    private void insertEmoji(String text) {
        if (!emojiPickerVisible() || connection == null) return;
        if (!commitText(text, TypingSource.LOCAL)) return;
        emojiRecents = EmojiCatalogModel.recordRecent(emojiRecents, text);
        saveEmojiRecents();
    }

    private void deleteFromEmojiPicker() {
        if (connection != null && !command(0))
            connection.deleteSurroundingTextInCodePoints(1, 0);
    }

    private void showEmojiPicker() {
        if (session == 0 || connection == null || emojiPanel == null || emojiResources.isEmpty()) {
            Toast.makeText(this, "表情目录尚未就绪", Toast.LENGTH_SHORT).show();
            return;
        }
        command(9);
        if (session == 0 || connection == null) return;
        closeCandidatePanel();
        closeClipboardHistory();
        closeSchemePicker();
        closeLayoutSettings();
        closeMoreTools();
        closeVoiceResult();
        closeAiPolish();
        closeReplyKeyboard();
        emojiRecents = loadEmojiRecents();
        emojiPanel.setVisibility(View.VISIBLE);
        emojiPanel.requestFocus();
        selectEmojiCategory(emojiRecents.isEmpty() ? 0 : -1);
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
        setReplyKeyboardVisible(false);
    }

    /** Keep the shared candidate/shortcut bar visible while the reply surface owns the key area. */
    private void setReplyKeyboardVisible(boolean visible) {
        if (replyKeyboard != null)
            replyKeyboard.setVisibility(visible ? View.VISIBLE : View.GONE);
        if (keyRows != null)
            keyRows.setVisibility(visible ? View.GONE : View.VISIBLE);
        if (keyboardControls != null)
            keyboardControls.setVisibility(visible ? View.GONE : View.VISIBLE);
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
            setReplyKeyboardVisible(false);
            return;
        }
        renderReplyKeyboard();
        setReplyKeyboardVisible(true);
    }

    private void showReplyKeyboard() {
        if (selectedScheme != KeyboardScheme.THOUGHTFUL_REPLY) return;
        replySuppressed = false;
        closeEmojiPicker();
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
                if (!commitText(value, TypingSource.REPLY)) return false;
            } catch (RuntimeException error) { return false; }
            replySuppressed = true;
            return true;
        });
        clearReplyRequestReferences();
        renderReplyKeyboard();
        if (inserted) setReplyKeyboardVisible(false);
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
        return !skinSaving && !traditionalOutputSaving
            && session != 0 && preferencesSnapshot != null
            && !preferencesDirectory.isEmpty();
    }

    private void showSkinMenu(Button anchor) {
        if (anchor == null || !canSaveKeyboardSkin()) return;
        PopupMenu popup = new PopupMenu(this, anchor);
        JSONObject preferences = preferencesSnapshot == null ? null
            : preferencesSnapshot.optJSONObject("preferences");
        JSONObject customDesign = preferences == null ? null
            : preferences.optJSONObject("custom_touch_keyboard_skin");
        for (KeyboardSkin choice : KeyboardSkin.choices(skin.dark(), customDesign)) {
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
        JSONObject currentPreferences = preferencesSnapshot == null ? null
            : preferencesSnapshot.optJSONObject("preferences");
        JSONObject customDesign = currentPreferences == null ? null
            : currentPreferences.optJSONObject("custom_touch_keyboard_skin");
        KeyboardSkin next = KeyboardSkin.from(identifier, skin.dark(), customDesign);
        if (skin.id().equals(next.id()) || skinSaving || traditionalOutputSaving || session == 0
                || preferencesSnapshot == null || preferencesDirectory.isEmpty()) return;
        final long targetSession = session;
        final String targetDirectory = preferencesDirectory;
        final JSONObject pending;
        final long expectedRevision;
        try {
            pending = new JSONObject(preferencesSnapshot.toString());
            expectedRevision = pending.getLong("revision");
            pending.getJSONObject("preferences").put("touch_keyboard_skin", next.id());
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
            skin = keyboardSkin(accepted);
            showKeyboardSkinStatus("皮肤切换失败，已恢复原皮肤");
        }
        applySkin();
        render();
    }

    /** Finish the Engine composition before handing the input connection to another IME. */
    private void switchToNextInputMethodAfterCommit() {
        if (session != 0) command(2);
        switchToNextInputMethod(false);
    }

    private boolean canSaveChineseOutput() {
        return !traditionalOutputSaving && !schemeSaving && !touchGeometrySaving && !skinSaving
            && session != 0 && preferencesSnapshot != null && !preferencesDirectory.isEmpty();
    }

    private void toggleChineseOutput() {
        if (!AndroidChineseTextConversion.available()) {
            Toast.makeText(this, "简繁转换需要 Android 10 或更高版本", Toast.LENGTH_SHORT).show();
            return;
        }
        if (!canSaveChineseOutput()) {
            Toast.makeText(this, "简繁设置尚未就绪", Toast.LENGTH_SHORT).show();
            return;
        }
        final boolean targetTraditional = !traditionalChineseOutput;
        final long targetSession = session;
        final String targetDirectory = preferencesDirectory;
        final JSONObject pending;
        final long expectedRevision;
        try {
            pending = new JSONObject(preferencesSnapshot.toString());
            expectedRevision = pending.getLong("revision");
            if (expectedRevision < 0) throw new JSONException("Invalid preferences revision");
            pending.getJSONObject("preferences")
                .put("traditional_chinese_output", targetTraditional);
        } catch (JSONException error) {
            preferencesNotice = " · 简繁设置保存失败，保留原设置";
            render();
            return;
        }
        traditionalChineseOutput = targetTraditional;
        traditionalOutputSaving = true;
        preferencesNotice = " · 正在保存简繁设置";
        final long operation = ++preferenceSaveGeneration;
        render();
        try {
            preferencesWorker.execute(() -> {
                String response;
                try {
                    response = NativeClient.savePreferences(
                        targetDirectory, expectedRevision, pending.toString());
                } catch (Exception | LinkageError error) {
                    response = null;
                }
                final String savedResponse = response;
                main.post(() -> finishChineseOutputSave(
                    operation, targetSession, targetDirectory, savedResponse));
            });
        } catch (RuntimeException error) {
            finishChineseOutputSave(operation, targetSession, targetDirectory, null);
        }
    }

    private void finishChineseOutputSave(long operation, long targetSession,
                                         String targetDirectory, String response) {
        if (operation != preferenceSaveGeneration || session != targetSession
                || !targetDirectory.equals(preferencesDirectory)) return;
        traditionalOutputSaving = false;
        try {
            if (response == null) throw new JSONException("Preferences save unavailable");
            JSONObject saved = value(response);
            long savedRevision = saved.getLong("revision");
            if (preferencesSnapshot != null
                    && preferencesSnapshot.optLong("revision", -1) > savedRevision) {
                applyChineseOutputPreference(preferencesSnapshot.optJSONObject("preferences"));
                preferencesNotice = "";
            } else {
                applyPreferencesSnapshot(saved);
                preferencesNotice = traditionalChineseOutput
                    ? " · 已切换为繁体输出" : " · 已切换为简体输出";
            }
        } catch (JSONException | LinkageError error) {
            JSONObject accepted = preferencesSnapshot == null ? null
                : preferencesSnapshot.optJSONObject("preferences");
            applyChineseOutputPreference(accepted);
            preferencesNotice = " · 简繁设置保存失败，已恢复原设置";
            Toast.makeText(this, "简繁设置未能保存", Toast.LENGTH_SHORT).show();
        }
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
        replyTemplateButton = button(header, "模板", this::showReplyTemplates);
        replyTemplateButton.setContentDescription("回复模板");
        View spacer = new View(this);
        header.addView(spacer, new LinearLayout.LayoutParams(0,
            LinearLayout.LayoutParams.MATCH_PARENT, 1));
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
        closeEmojiPicker();
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
        committed = commitText(aiOutputText, TypingSource.AI);
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
            committed = commitText(text, TypingSource.VOICE);
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
        closeEmojiPicker();
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
        if (keySpacingSlider == null || rowSpacingSlider == null || keyboardHeightSlider == null
                || keySpacingValue == null || rowSpacingValue == null || keyboardHeightValue == null
                || voiceShortcutSwitch == null || resetLayoutSettingsButton == null) return;
        keySpacingSlider.setProgress(touchKeySpacingTenths);
        rowSpacingSlider.setProgress(touchRowSpacingTenths);
        keyboardHeightSlider.setProgress(touchKeyboardHeightAdjustment);
        keySpacingSlider.setEnabled(!touchGeometrySaving && !traditionalOutputSaving);
        rowSpacingSlider.setEnabled(!touchGeometrySaving && !traditionalOutputSaving);
        keyboardHeightSlider.setEnabled(!touchGeometrySaving && !traditionalOutputSaving);
        voiceShortcutSwitch.setChecked(touchVoiceShortcutEnabled);
        voiceShortcutSwitch.setEnabled(!touchGeometrySaving && !traditionalOutputSaving);
        resetLayoutSettingsButton.setEnabled(!touchGeometrySaving && !traditionalOutputSaving);
        keySpacingValue.setText(KeyboardGeometry.display(touchKeySpacingTenths) + " dp");
        rowSpacingValue.setText(KeyboardGeometry.display(touchRowSpacingTenths) + " dp");
        keyboardHeightValue.setText(KeyboardGeometry.displayHeight(
            touchKeyboardHeightAdjustment) + " dp");
    }

    private void previewTouchGeometry(boolean keySpacing, int value) {
        if (touchGeometrySaving || traditionalOutputSaving) return;
        if (keySpacing) touchKeySpacingTenths = KeyboardGeometry.keySpacing(value);
        else touchRowSpacingTenths = KeyboardGeometry.rowSpacing(value);
        renderLayoutSettingsState();
        applyKeyboardGeometry();
    }

    private void previewTouchHeight(int value) {
        if (touchGeometrySaving || traditionalOutputSaving) return;
        touchKeyboardHeightAdjustment = KeyboardGeometry.heightAdjustment(value);
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
                if (fromUser) {
                    previewTouchGeometry(keySpacing, progress);
                    if (!source.isPressed()) saveTouchGeometry();
                }
            }
            @Override public void onStartTrackingTouch(SeekBar source) { }
            @Override public void onStopTrackingTouch(SeekBar source) { saveTouchGeometry(); }
        });
    }

    private void configureHeightSlider(SeekBar slider) {
        slider.setMin(KeyboardGeometry.MIN_HEIGHT_ADJUSTMENT_DP);
        slider.setMax(KeyboardGeometry.MAX_HEIGHT_ADJUSTMENT_DP);
        slider.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override public void onProgressChanged(SeekBar source, int progress, boolean fromUser) {
                if (fromUser) {
                    previewTouchHeight(progress);
                    if (!source.isPressed()) saveTouchGeometry();
                }
            }
            @Override public void onStartTrackingTouch(SeekBar source) { }
            @Override public void onStopTrackingTouch(SeekBar source) { saveTouchGeometry(); }
        });
    }

    private void showLayoutSettings() {
        if (touchGeometrySaving || traditionalOutputSaving
                || session == 0 || preferencesSnapshot == null
                || preferencesDirectory.isEmpty()) {
            Toast.makeText(this, "键盘设置尚未就绪", Toast.LENGTH_SHORT).show();
            return;
        }
        closeEmojiPicker();
        closeCandidatePanel();
        closeClipboardHistory();
        closeSchemePicker();
        closeVoiceResult();
        closeAiPolish();
        renderLayoutSettingsState();
        layoutSettingsScroll.setVisibility(View.VISIBLE);
    }

    private void saveTouchGeometry() {
        saveTouchGeometry(false);
    }

    private void resetTouchGeometry() {
        if (touchGeometrySaving || traditionalOutputSaving || session == 0
                || preferencesSnapshot == null || preferencesDirectory.isEmpty()) return;
        touchKeySpacingTenths = KeyboardGeometry.DEFAULT_KEY_SPACING_TENTHS;
        touchRowSpacingTenths = KeyboardGeometry.DEFAULT_ROW_SPACING_TENTHS;
        touchKeyboardHeightAdjustment = KeyboardGeometry.DEFAULT_HEIGHT_ADJUSTMENT_DP;
        touchVoiceShortcutEnabled = false;
        applyKeyboardGeometry();
        saveTouchGeometry(true);
    }

    private void saveTouchGeometry(boolean reset) {
        if (touchGeometrySaving || traditionalOutputSaving
                || session == 0 || preferencesSnapshot == null
                || preferencesDirectory.isEmpty()) return;
        JSONObject acceptedPreferences = preferencesSnapshot.optJSONObject("preferences");
        if (!reset && acceptedPreferences != null
                && KeyboardGeometry.keySpacing(acceptedPreferences.optInt(
                    "touch_key_spacing_tenths", -1)) == touchKeySpacingTenths
                && KeyboardGeometry.rowSpacing(acceptedPreferences.optInt(
                    "touch_row_spacing_tenths", -1)) == touchRowSpacingTenths
                && KeyboardGeometry.heightAdjustment(acceptedPreferences.optInt(
                    "touch_keyboard_height_adjustment", Integer.MIN_VALUE))
                    == touchKeyboardHeightAdjustment
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
            if (reset) {
                preferences.remove("touch_key_spacing_tenths");
                preferences.remove("touch_row_spacing_tenths");
                preferences.remove("touch_keyboard_height_adjustment");
                preferences.remove("touch_voice_shortcut");
            } else {
                preferences.put("touch_key_spacing_tenths", touchKeySpacingTenths);
                preferences.put("touch_row_spacing_tenths", touchRowSpacingTenths);
                preferences.put("touch_keyboard_height_adjustment", touchKeyboardHeightAdjustment);
                preferences.put("touch_voice_shortcut", touchVoiceShortcutEnabled);
            }
        } catch (JSONException error) {
            if (reset && preferencesSnapshot != null) {
                applyTouchGeometry(preferencesSnapshot.optJSONObject("preferences"));
                applyKeyboardGeometry();
            }
            preferencesNotice = reset ? " · 恢复默认失败，保留原设置" : " · 键盘设置保存失败，保留原设置";
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
                reset, savedResponse));
        };
        try {
            preferencesWorker.execute(save);
        } catch (RuntimeException error) {
            if (operation == preferenceSaveGeneration) {
                touchGeometrySaving = false;
                if (reset && preferencesSnapshot != null) {
                    applyTouchGeometry(preferencesSnapshot.optJSONObject("preferences"));
                    applyKeyboardGeometry();
                }
                preferencesNotice = reset ? " · 恢复默认失败，保留原设置" : " · 键盘设置保存失败，保留原设置";
                renderLayoutSettingsState();
                render();
            }
        }
    }

    private void finishTouchGeometrySave(long operation, long targetSession,
                                         String targetDirectory, boolean reset, String response) {
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
                preferencesNotice = reset ? " · 键盘设置已恢复默认" : " · 键盘设置已保存";
            }
        } catch (JSONException | LinkageError error) {
            if (preferencesSnapshot != null)
                applyTouchGeometry(preferencesSnapshot.optJSONObject("preferences"));
            applyKeyboardGeometry();
            preferencesNotice = reset ? " · 恢复默认失败，已恢复原设置" : " · 键盘设置保存失败，已恢复原设置";
            Toast.makeText(this, reset ? "键盘设置未能恢复默认" : "键盘设置未能保存", Toast.LENGTH_SHORT).show();
        }
        renderLayoutSettingsState();
        render();
    }

    private void showSchemePicker() {
        if (touchGeometrySaving || traditionalOutputSaving
                || session == 0 || preferencesSnapshot == null
                || preferencesDirectory.isEmpty()) {
            Toast.makeText(this, "输入方案尚未就绪", Toast.LENGTH_SHORT).show();
            return;
        }
        closeEmojiPicker();
        closeCandidatePanel();
        closeClipboardHistory();
        closeLayoutSettings();
        closeVoiceResult();
        closeAiPolish();
        closeReplyKeyboard();
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
        Button settings = borderlessButton(header, "⚙", this::showLayoutSettings);
        settings.setContentDescription("键盘设置");
        Button close = button(header, "返回键盘", this::closeSchemePicker);
        close.setContentDescription("返回键盘");
        schemePanel.addView(header);
        LinearLayout schemeSurface = new LinearLayout(this);
        schemeSurface.setOrientation(LinearLayout.VERTICAL);
        schemeSurface.setPadding(pixels(8), pixels(6), pixels(8), pixels(6));
        schemeSurface.setContentDescription("输入方案卡片区域");
        schemePanel.addView(schemeSurface, new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, 0, 1));
        java.util.List<KeyboardScheme> schemes = enabledSchemes;
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
            schemeSurface.addView(row);
        }
        if (!sharedSchemePreferences) {
            Button toggleReply = button(schemeSurface, thoughtfulReplyEnabled()
                ? "禁用高情商回复" : "启用高情商回复", this::toggleThoughtfulReplyScheme);
            toggleReply.setLayoutParams(new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT));
            toggleReply.setContentDescription(thoughtfulReplyEnabled()
                ? "禁用高情商回复输入方案" : "启用高情商回复输入方案");
        }
        TextView hint = new TextView(this);
        hint.setText(sharedSchemePreferences
            ? "显示的方案由共享设置管理；切换会先完成当前组词并同步当前方案"
            : "切换会先完成当前组词，并迁移到共享输入方案设置");
        schemeSurface.addView(hint);
        applySkin();
        // Apple keeps the selectable scheme area on a filled key surface, so a short list does not
        // leave a bare keyboard backdrop below the cards. Apply this after the recursive skin pass:
        // the picker itself remains the patterned backdrop while this inner surface follows the
        // selected skin's key material, including custom Android skins.
        schemeSurface.setBackground(new KeyboardSkinKeyDrawable(skin,
            Color.parseColor(skin.keyBackground()), false,
            getResources().getDisplayMetrics().density));
    }

    private void selectKeyboardScheme(KeyboardScheme scheme) {
        if (schemeSaving || touchGeometrySaving || traditionalOutputSaving
                || session == 0 || preferencesSnapshot == null
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
            JSONArray enabled = new JSONArray();
            for (KeyboardScheme candidate : enabledSchemes) {
                enabled.put(candidate.preferenceId());
            }
            preferences.put("touch_keyboard_schemes", new JSONObject()
                .put("enabled", enabled).put("selected", scheme.preferenceId()));
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
        synchronizeReplyKeyboard();
        render();
    }

    private void toggleThoughtfulReplyScheme() {
        if (sharedSchemePreferences || schemeHostPreferences == null
                || schemeSaving || traditionalOutputSaving) return;
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
        commitText(text);
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
        closeEmojiPicker();
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
        if (moreButton == null || moreToolsPanel == null || moreToolsScroll == null) return;
        closeEmojiPicker();
        closeCandidatePanel();
        closeClipboardHistory();
        closeSchemePicker();
        closeLayoutSettings();
        closeVoiceResult();
        closeAiPolish();
        closeReplyKeyboard();
        localInputToolsOpen = false;
        renderMoreTools();
        moreToolsScroll.setVisibility(View.VISIBLE);
        moreToolsScroll.requestFocus();
    }

    private Button moreToolsCard(String title, MoreToolsLayout.Section section, boolean active,
                                 boolean enabled, boolean playBeforeAction, Runnable action) {
        return moreToolsCard(title, section, active, enabled, playBeforeAction, null, action);
    }

    private Button moreToolsCard(String title, MoreToolsLayout.Section section, boolean active,
                                 boolean enabled, boolean playBeforeAction, String caption,
                                 Runnable action) {
        Button card = new Button(this);
        card.setAllCaps(false);
        String state = enabled ? MoreToolsLayout.state(section, active) : "不可用";
        boolean navigates = section == MoreToolsLayout.Section.TOOLS
            || section == MoreToolsLayout.Section.LOCAL_INPUT_BACK;
        if (navigates) card.setText(title + "  ›");
        else if (section == MoreToolsLayout.Section.SETTINGS) {
            card.setText(title + "\n" + (caption == null ? state : caption));
        }
        else card.setText(title);
        card.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
        card.setGravity(navigates
            ? Gravity.CENTER_VERTICAL | Gravity.START : Gravity.CENTER);
        card.setPadding(pixels(12), pixels(5), pixels(12), pixels(5));
        card.setContentDescription(title);
        card.setSelected(active);
        card.setEnabled(enabled);
        if (Build.VERSION.SDK_INT >= 30) card.setStateDescription(state);
        styleButton(card, true);
        card.setOnClickListener(ignored -> {
            if (playBeforeAction) playFeedback(card);
            action.run();
        });
        return card;
    }

    private void appendMoreToolsSection(MoreToolsLayout.Section section, Button... cards) {
        if (!section.title().isEmpty()) {
            TextView label = new TextView(this);
            label.setText(section.title());
            label.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11);
            label.setGravity(Gravity.CENTER_VERTICAL);
            moreToolsPanel.addView(label, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, pixels(20)));
        }
        int columns = section.columns();
        for (int start = 0; start < cards.length; start += columns) {
            LinearLayout row = new LinearLayout(this);
            row.setWeightSum(columns);
            for (int column = 0; column < columns; column++) {
                int index = start + column;
                View child = index < cards.length ? cards[index] : new View(this);
                LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                    0, pixels(MoreToolsLayout.CARD_HEIGHT_DP), 1);
                if (column > 0) params.setMarginStart(pixels(MoreToolsLayout.CARD_SPACING_DP));
                row.addView(child, params);
            }
            LinearLayout.LayoutParams rowParams = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, pixels(MoreToolsLayout.CARD_HEIGHT_DP));
            rowParams.bottomMargin = pixels(MoreToolsLayout.ROW_SPACING_DP);
            moreToolsPanel.addView(row, rowParams);
        }
    }

    private void installShortcutBar(Button dismissButton) {
        shortcutBar.removeAllViews();
        // Keep the Apple shortcut order: more/brand, keyboard settings, reply, emoji, skin,
        // scheme and dismiss. Android keeps its optional voice-result entry as a platform-specific
        // extra beside the content tools rather than moving the deliberate scheme switch forward.
        Button[] buttons = {moreButton, layoutSettingsButton, replyShortcutButton,
            emojiShortcutButton, voiceShortcutButton, skinButton, schemeButton, dismissButton};
        for (Button button : buttons) {
            if (button.getParent() instanceof LinearLayout parent) parent.removeView(button);
            shortcutBar.addView(button, new LinearLayout.LayoutParams(
                pixels(44), pixels(44)));
        }
        // Traditional output and AI are persistent settings/actions in the Apple layout; keep
        // their Android controls detached from the shortcut strip rather than duplicating them.
        scriptShortcutButton.setVisibility(View.GONE);
        aiPolishShortcutButton.setVisibility(View.GONE);
    }

    private void toggleSoundFromMoreTools() {
        soundEnabled = !soundEnabled;
        saveFeedbackPreferences();
        if (soundEnabled) playFeedback(moreButton);
        renderMoreTools();
    }

    private void toggleHapticsFromMoreTools() {
        hapticsEnabled = !hapticsEnabled;
        saveFeedbackPreferences();
        if (hapticsEnabled) playFeedback(moreButton);
        renderMoreTools();
    }

    private void selectHapticStrength(KeyboardFeedbackPreferences.HapticStrength strength) {
        hapticStrength = strength;
        saveFeedbackPreferences();
        if (hapticsEnabled) playFeedback(moreButton);
        renderMoreTools();
    }

    private String hapticStrengthTitle() {
        return switch (hapticStrength) {
            case LIGHT -> "轻";
            case MEDIUM -> "中";
            case STRONG -> "强";
        };
    }

    private void cycleHapticStrength() {
        KeyboardFeedbackPreferences.HapticStrength[] values =
            KeyboardFeedbackPreferences.HapticStrength.values();
        int next = (hapticStrength.ordinal() + 1) % values.length;
        selectHapticStrength(values[next]);
    }

    private boolean traditionalOutputToolAvailable() {
        int scheme = view == null ? -1 : view.optInt("scheme", -1);
        return AndroidChineseTextConversion.available() && scheme != 3
            && canSaveChineseOutput();
    }

    private void renderMoreTools() {
        if (moreToolsPanel == null) return;
        moreToolsPanel.removeAllViews();
        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);
        Button close = button(header, "返回", this::closeMoreTools);
        close.setContentDescription("返回键盘");
        close.setLayoutParams(new LinearLayout.LayoutParams(
            pixels(84), pixels(MoreToolsLayout.HEADER_HEIGHT_DP)));
        TextView title = new TextView(this);
        title.setText("工具");
        title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
        title.setGravity(Gravity.CENTER);
        header.addView(title, new LinearLayout.LayoutParams(
            0, pixels(MoreToolsLayout.HEADER_HEIGHT_DP), 1));
        View balance = new View(this);
        header.addView(balance, new LinearLayout.LayoutParams(
            pixels(84), pixels(MoreToolsLayout.HEADER_HEIGHT_DP)));
        moreToolsPanel.addView(header);

        if (localInputToolsOpen) {
            appendMoreToolsSection(MoreToolsLayout.Section.LOCAL_INPUT_BACK,
                moreToolsCard("返回工具", MoreToolsLayout.Section.LOCAL_INPUT_BACK,
                    false, true, true, () -> {
                        localInputToolsOpen = false;
                        renderMoreTools();
                    }));
            LocalInputMode[] modes = LocalInputMode.values();
            Button[] localCards = new Button[modes.length];
            for (int index = 0; index < modes.length; index++) {
                LocalInputMode mode = modes[index];
                localCards[index] = moreToolsCard(mode.title(), MoreToolsLayout.Section.LOCAL_INPUT,
                    false, supportsLocalTools() && localModeEnabled(mode), false, () -> {
                        closeMoreTools();
                        openLocalInputMode(mode);
                    });
            }
            appendMoreToolsSection(MoreToolsLayout.Section.LOCAL_INPUT, localCards);
            applySkin();
            return;
        }

        appendMoreToolsSection(MoreToolsLayout.Section.TOOLS,
            moreToolsCard("表情", MoreToolsLayout.Section.TOOLS, false,
                session != 0 && !emojiResources.isEmpty(), true, () -> {
                    closeMoreTools();
                    showEmojiPicker();
                }),
            moreToolsCard("剪贴板历史", MoreToolsLayout.Section.TOOLS, false,
                clipboardHistoryEnabled, true, () -> {
                    closeMoreTools();
                    showClipboardHistory();
                }),
            moreToolsCard("AI 润色", MoreToolsLayout.Section.TOOLS, false,
                aiPolishConfiguration != null && aiPolishReady(), true, () -> {
                    closeMoreTools();
                    showAiPolish();
                }),
            moreToolsCard("本地输入", MoreToolsLayout.Section.TOOLS, false,
                supportsLocalTools(), true, () -> {
                    localInputToolsOpen = true;
                    renderMoreTools();
                }),
            moreToolsCard("语音结果", MoreToolsLayout.Section.TOOLS, false,
                true, true, () -> {
                    closeMoreTools();
                    showVoiceResult();
                }));
        appendMoreToolsSection(MoreToolsLayout.Section.SETTINGS,
            moreToolsCard("繁体输出", MoreToolsLayout.Section.SETTINGS, traditionalChineseOutput,
                traditionalOutputToolAvailable(), true, null, this::toggleChineseOutput),
            moreToolsCard("按键音", MoreToolsLayout.Section.SETTINGS, soundEnabled,
                true, false, this::toggleSoundFromMoreTools),
            moreToolsCard("按键振动", MoreToolsLayout.Section.SETTINGS, hapticsEnabled,
                true, false, this::toggleHapticsFromMoreTools),
            moreToolsCard("振动强度", MoreToolsLayout.Section.SETTINGS, hapticsEnabled,
                hapticsEnabled, false, hapticStrengthTitle(), this::cycleHapticStrength));
        applySkin();
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

    private CharSequence candidateLabel(String prefix, String text, String annotation,
                                        boolean highlighted) {
        if (annotation.isEmpty()) return prefix + text;
        String primary = prefix + text;
        SpannableString label = new SpannableString(primary + " " + annotation);
        int annotationStart = primary.length() + 1;
        label.setSpan(new RelativeSizeSpan(0.72f), annotationStart, label.length(),
            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
        int foreground = Color.parseColor(
            highlighted ? skin.actionForeground() : skin.keyForeground());
        int secondary = Color.argb(Math.round(Color.alpha(foreground) * 0.58f),
            Color.red(foreground), Color.green(foreground), Color.blue(foreground));
        label.setSpan(new ForegroundColorSpan(secondary), annotationStart, label.length(),
            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
        return label;
    }

    private String candidateAnnotation(JSONObject candidate) {
        return CandidateGlossPolicy.annotation(candidate.optString("annotation", ""),
            candidate.isNull("translation") ? "" : candidate.optString("translation", ""),
            candidateEnglishGloss);
    }

    private String wubiCodeHint(JSONObject candidate, JSONObject context, String typed) {
        return WubiCodeHintPolicy.hint(candidate.optString("code", ""), typed, wubiCodeHint,
            context == null ? -1 : context.optInt("scheme", -1),
            context == null ? "none" : context.optString("local_mode", "none"),
            context != null && context.optBoolean("answered_by_pinyin_fallback", false));
    }

    private String candidateAnnotation(JSONObject candidate, String typed) {
        String hint = wubiCodeHint(candidate, view, typed);
        return hint.isEmpty() ? candidateAnnotation(candidate) : hint;
    }

    private String candidateAccessibilitySuffix(JSONObject candidate) {
        return CandidateGlossPolicy.accessibilitySuffix(candidate.optString("annotation", ""),
            candidate.isNull("translation") ? "" : candidate.optString("translation", ""),
            candidateEnglishGloss);
    }

    private String candidateAccessibilitySuffix(JSONObject candidate, String typed) {
        String hint = wubiCodeHint(candidate, view, typed);
        return hint.isEmpty() ? candidateAccessibilitySuffix(candidate) : "，还需输入 " + hint;
    }

    private Button makeCandidateButton(int slot) {
        Button button = new Button(this);
        button.setAllCaps(false);
        button.setOnClickListener(ignored -> selectVisibleCandidate(button, slot));
        button.setOnLongClickListener(ignored -> {
            JSONObject current = visibleCandidate(slot);
            JSONObject id = current == null ? null : current.optJSONObject("id");
            if (id == null || !candidateManagementEnabled()) return false;
            String text = chineseOutput(current.optString("text"), view);
            showCandidateMenu(button, id, text);
            return true;
        });
        return button;
    }

    private JSONObject visibleCandidate(int slot) {
        if (view == null || slot < 0) return null;
        JSONArray entries = view.optJSONArray("candidates");
        return entries == null ? null : entries.optJSONObject(slot);
    }

    private void selectVisibleCandidate(Button button, int slot) {
        JSONObject candidate = visibleCandidate(slot);
        JSONObject id = candidate == null ? null : candidate.optJSONObject("id");
        if (id == null) return;
        playFeedback(button);
        if (session == 0 || id.optLong("session") != session) return;
        candidatePanelOpen = false;
        try {
            apply(NativeClient.select(session, id.getLong("generation"), id.getLong("index")));
        } catch (JSONException | LinkageError error) { fail(); }
    }

    private void updateCandidateButton(Button button, JSONObject candidate, int slot) {
        String text = chineseOutput(candidate.optString("text"), view);
        boolean highlighted = candidate.optBoolean("highlighted");
        String typed = view == null ? "" : view.optString("preedit", "");
        String annotation = candidateAnnotation(candidate, typed);
        button.setText(candidateLabel("", text, annotation, highlighted));
        button.setTextSize(TypedValue.COMPLEX_UNIT_SP, candidateFontSize);
        button.setSelected(highlighted);
        styleButton(button, false);
        String description = "候选 " + (slot + 1) + "：" + text
            + candidateAccessibilitySuffix(candidate, typed);
        JSONObject id = candidate.optJSONObject("id");
        button.setContentDescription(id != null && candidateManagementEnabled()
            ? description + "；长按管理" : description);
        if (Build.VERSION.SDK_INT >= 30)
            button.setStateDescription(highlighted ? "已选中" : "未选中");
        button.setEnabled(id != null);
    }

    private Button expandedCandidateButton(JSONObject candidate) {
        JSONObject id = candidate.optJSONObject("id");
        Button button = new Button(this);
        String text = chineseOutput(candidate.optString("text"), view);
        boolean highlighted = candidate.optBoolean("highlighted");
        String typed = candidatePanelSnapshot == null ? ""
            : candidatePanelSnapshot.optString("preedit", "");
        String annotation = candidateAnnotation(candidate, typed);
        button.setAllCaps(false);
        button.setText(candidateLabel("", text, annotation, highlighted));
        button.setTextSize(TypedValue.COMPLEX_UNIT_SP, candidateFontSize);
        styleButton(button, false);
        button.setSelected(highlighted);
        long index = id == null ? -1 : id.optLong("index", -1);
        button.setContentDescription(index < 0 ? "候选" : "候选 " + (index + 1) + "："
            + text + candidateAccessibilitySuffix(candidate, typed));
        if (Build.VERSION.SDK_INT >= 30)
            button.setStateDescription(highlighted ? "已选中" : "未选中");
        if (id == null || index < 0) {
            button.setEnabled(false);
        } else {
            button.setOnClickListener(ignored -> {
                playFeedback(button);
                if (session == 0 || id.optLong("session") != session) return;
                candidatePanelOpen = false;
                candidatePanelSnapshot = null;
                try {
                    apply(NativeClient.selectAnyCandidate(
                        session, id.getLong("generation"), id.getLong("index")));
                } catch (JSONException | LinkageError error) { fail(); }
            });
        }
        return button;
    }

    private void closeCandidatePanel() {
        candidatePanelOpen = false;
        candidatePanelSnapshot = null;
        if (keyboardRoot != null && expandedCandidates != null) {
            expandedCandidates.setVisibility(View.GONE);
            if (expandedCandidateScroll != null)
                expandedCandidateScroll.setVisibility(View.GONE);
        }
    }

    private void openCandidatePanel() {
        if (session == 0 || view == null || view.optInt("page_count", 0) <= 1) return;
        try {
            JSONObject snapshot = value(NativeClient.allCandidates(session));
            if (snapshot.optLong("session") != view.optLong("session")
                    || snapshot.optLong("generation") != view.optLong("generation")) return;
            JSONArray entries = snapshot.optJSONArray("candidates");
            JSONArray visible = view.optJSONArray("candidates");
            if (entries == null || visible == null || entries.length() <= visible.length()) return;
            candidatePanelSnapshot = snapshot;
            candidatePanelOpen = true;
            renderExpandedCandidates();
            applySkin();
        } catch (JSONException | LinkageError error) { fail(); }
    }

    private void renderExpandedCandidates() {
        if (expandedCandidates == null || expandedCandidateScroll == null) return;
        expandedCandidates.removeAllViews();
        if (!candidatePanelOpen || view == null || candidatePanelSnapshot == null
                || candidatePanelSnapshot.optLong("session") != view.optLong("session")
                || candidatePanelSnapshot.optLong("generation") != view.optLong("generation")) {
            candidatePanelOpen = false;
            candidatePanelSnapshot = null;
            expandedCandidates.setVisibility(View.GONE);
            expandedCandidateScroll.setVisibility(View.GONE);
            return;
        }
        expandedCandidateScroll.setVisibility(View.VISIBLE);
        expandedCandidates.setVisibility(View.VISIBLE);
        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);
        TextView composition = new TextView(this);
        String compositionText = candidatePanelSnapshot.optString("preedit", "");
        composition.setText(compositionText);
        composition.setTextSize(TypedValue.COMPLEX_UNIT_SP, candidatePreeditFontSize);
        composition.setContentDescription("当前组合文本：" + compositionText);
        header.addView(composition, new LinearLayout.LayoutParams(
            0, LinearLayout.LayoutParams.WRAP_CONTENT, 1));
        JSONArray entries = candidatePanelSnapshot.optJSONArray("candidates");
        int count = entries == null ? 0 : entries.length();
        TextView countView = new TextView(this);
        countView.setText(count + " 个候选");
        countView.setContentDescription(count + " 个候选");
        header.addView(countView, new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT));
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
        CandidateWrapLayout list = new CandidateWrapLayout(this, pixels(8));
        list.setPadding(0, pixels(8), 0, 0);
        list.setContentDescription("完整候选列表");
        if (entries != null) {
            for (int index = 0; index < entries.length(); index++) {
                JSONObject candidate = entries.optJSONObject(index);
                if (candidate == null) continue;
                Button button = expandedCandidateButton(candidate);
                list.addView(button, new android.view.ViewGroup.LayoutParams(
                    android.view.ViewGroup.LayoutParams.WRAP_CONTENT,
                    android.view.ViewGroup.LayoutParams.WRAP_CONTENT));
            }
        }
        expandedCandidates.addView(list);
    }

    private boolean handwritingActive() {
        return session != 0 && keyboardLayer == KeyboardLayout.Layer.LETTERS
            && displayedTouchLayout(view) == HANDWRITING_LAYOUT && handwritingCanvas != null;
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
        handwritingCandidateToken = null;
    }

    private void showHandwritingStatus(String text) {
        if (handwritingStatus == null) return;
        handwritingStatus.setText(text);
        handwritingStatus.setVisibility(text == null || text.isEmpty() ? View.GONE : View.VISIBLE);
        if (handwritingStatus.getLayoutParams() instanceof FrameLayout.LayoutParams params) {
            boolean downloadVisible = handwritingDownload != null
                && handwritingDownload.getVisibility() == View.VISIBLE;
            params.gravity = downloadVisible
                ? Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL : Gravity.CENTER;
            params.bottomMargin = downloadVisible ? pixels(8) : 0;
            handwritingStatus.setLayoutParams(params);
        }
        if (candidates != null) render();
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
        handwritingCandidateToken = null;
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
                        handwritingCandidateToken = handwritingResults.isEmpty() ? null : token;
                        renderHandwritingCandidates(token);
                    });
                }

                @Override public void onFailure(long revision) {
                    main.post(() -> {
                        if (handwritingRecognizer != expected || revision != token.revision()
                                || !acceptsHandwriting(token)) return;
                        handwritingResults = java.util.List.of();
                        handwritingCandidateToken = null;
                        showHandwritingStatus("识别失败，请撤销或重新书写");
                    });
                }
            });
        } catch (RuntimeException error) {
            if (acceptsHandwriting(token)) showHandwritingStatus("识别失败，请撤销或重新书写");
        }
    }

    private void renderHandwritingCandidates(HandwritingRequestTracker.Token token) {
        render();
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

    private boolean commitFirstHandwritingCandidate() {
        if (!handwritingActive() || handwritingCanvas == null || !handwritingCanvas.hasInk()
                || handwritingCandidateToken == null || handwritingResults.isEmpty()) return false;
        return commitHandwritingCandidate(handwritingCandidateToken, handwritingResults.get(0));
    }

    private boolean commitHandwritingCandidate(HandwritingRequestTracker.Token token, String candidate) {
        if (!acceptsHandwriting(token) || !handwritingResults.contains(candidate)
                || connection == null) return false;
        long targetSession = session;
        command(9);
        if (targetSession != session || !acceptsHandwriting(token) || connection == null) return false;
        if (!commitText(chineseOutput(candidate, view), TypingSource.HANDWRITING)) return false;
        clearHandwriting();
        return true;
    }

    private void rebuildHandwritingRows() {
        handwritingStatus = new TextView(this);
        handwritingStatus.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        handwritingStatus.setGravity(Gravity.CENTER);
        handwritingStatus.setText("在此手写，停笔后选字");
        handwritingStatus.setContentDescription("手写状态");
        handwritingStatus.setClickable(false);
        handwritingStatus.setFocusable(false);

        FrameLayout row = new FrameLayout(this);
        handwritingCanvas = new HandwritingCanvas(this);
        handwritingCanvas.applySkin(skin);
        row.addView(handwritingCanvas, new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));

        FrameLayout cardFrame = new FrameLayout(this);
        cardFrame.setClickable(false);
        cardFrame.setFocusable(false);
        FrameLayout.LayoutParams cardParams = new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT);
        cardParams.rightMargin = pixels(64);
        row.addView(cardFrame, cardParams);
        cardFrame.addOnLayoutChangeListener((view, left, top, right, bottom,
                oldLeft, oldTop, oldRight, oldBottom) -> handwritingCanvas.setCardRect(
                    left, top, right, bottom));
        cardFrame.addView(handwritingStatus, new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.CENTER));

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
        cardFrame.addView(handwritingDownload, downloadParams);

        LinearLayout tools = new LinearLayout(this);
        tools.setOrientation(LinearLayout.VERTICAL);
        addNineKey(tools, keyboardKey("撤销", "撤销最后一笔", () -> {
            if (handwritingCanvas != null) handwritingCanvas.undo();
        }));
        addNineKey(tools, keyboardKey("清空", "清空手写", this::clearHandwriting));
        addNineKey(tools, keyboardKey("⌫", "删除", this::deleteFromHandwriting));
        row.addView(tools, new FrameLayout.LayoutParams(pixels(64),
            FrameLayout.LayoutParams.MATCH_PARENT, Gravity.END));
        adjustFixedHeight(row, KeyboardGeometry.HANDWRITING_BODY_HEIGHT_DP);
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
        hideJapaneseFlickPreview();
        deactivateHandwriting();
        symbolKeyButtons.clear();
        symbolKeyInputs.clear();
        microsoftFinalKey = null;
        japaneseSpaceKey = null;
        japaneseReturnKey = null;
        japaneseVariantsButton = null;
        keyRows.removeAllViews();
        if (displayedTouchLayout(view) == JAPANESE_NINE_KEY_LAYOUT) {
            rebuildJapaneseNineKeyRows();
            applyKeyboardGeometry();
            return;
        }
        if (keyboardLayer == KeyboardLayout.Layer.LETTERS) {
            if (displayedTouchLayout(view) == HANDWRITING_LAYOUT) {
                rebuildHandwritingRows();
                applyKeyboardGeometry();
                return;
            }
            if (displayedTouchLayout(view) == QUANPIN_NINE_KEY_LAYOUT) {
                rebuildNineKeyRows();
                applyKeyboardGeometry();
                return;
            }
        }
        boolean chineseMode = !dedicatedEnglish;
        boolean localMode = view != null
            && !"none".equals(view.optString("local_mode", "none"));
        boolean shifted = letterCase.usesUppercase();
        boolean uppercaseFaces = LetterKeyFacePolicy.displaysUppercase(
            chineseMode, localMode, shifted);
        java.util.List<java.util.List<String>> rows = KeyboardLayout.rows(
            keyboardLayer, uppercaseFaces);
        for (int rowIndex = 0; rowIndex < rows.size(); rowIndex++) {
            java.util.List<String> keys = rows.get(rowIndex);
            LinearLayout row = new LinearLayout(this);
            row.setTag(new KeyboardHeightRole(KeyboardGeometry.STANDARD_ROW_HEIGHT_DP,
                rows.size(), rowIndex, true));
            keyRows.addView(row, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT));
            for (String key : keys) {
                final String input = key;
                String face = keyboardLayer == KeyboardLayout.Layer.SYMBOLS
                    ? ChineseSymbolFaces.face(key, sendsChinesePunctuation())
                    : LetterKeyFacePolicy.face(key, chineseMode, localMode, shifted);
                Button keyButton = keyboardKey(face, face, () -> type(input.charAt(0)));
                if (keyboardLayer == KeyboardLayout.Layer.LETTERS) {
                    keyButton.setContentDescription(LetterKeyFacePolicy.accessibilityLabel(
                        input, chineseMode, localMode, shifted));
                }
                if (keyboardLayer == KeyboardLayout.Layer.SYMBOLS) {
                    symbolKeyButtons.add(keyButton);
                    symbolKeyInputs.add(input);
                }
                row.addView(keyButton, new LinearLayout.LayoutParams(0,
                    LinearLayout.LayoutParams.MATCH_PARENT, 1));
            }
            if (keyboardLayer == KeyboardLayout.Layer.LETTERS && rowIndex == 1) {
                microsoftFinalKey = keyboardKey(";", "微软双拼 ing", () -> type(';'));
                row.addView(microsoftFinalKey, new LinearLayout.LayoutParams(0,
                    LinearLayout.LayoutParams.MATCH_PARENT, 1));
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
        adjustFixedHeight(container, KeyboardGeometry.NINE_KEY_HEIGHT_DP);
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
        Runnable deleteAction = () -> {
            if (connection != null && !command(0)) connection.deleteSurroundingTextInCodePoints(1, 0);
        };
        Button delete = keyboardKey("⌫", "删除", deleteAction);
        bindBackspaceRepeat(delete, deleteAction);
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

    private void showJapaneseFlickPreview(Button button, JapaneseNineKeyLayout.Key key, int direction) {
        if (japaneseFlickPreview != null && keyboardRoot != null)
            japaneseFlickPreview.show(button, key, direction, keyboardRoot);
    }

    private void hideJapaneseFlickPreview() {
        if (japaneseFlickPreview != null) japaneseFlickPreview.hide();
    }

    private void bindJapaneseFlick(Button button, JapaneseNineKeyLayout.Key key) {
        final float[] origin = new float[2];
        final int[] direction = new int[1];
        button.setOnTouchListener((ignored, event) -> {
            switch (event.getActionMasked()) {
                case MotionEvent.ACTION_DOWN -> {
                    origin[0] = event.getX();
                    origin[1] = event.getY();
                    direction[0] = 0;
                    button.setPressed(true);
                    showJapaneseFlickPreview(button, key, 0);
                    return true;
                }
                case MotionEvent.ACTION_MOVE -> {
                    direction[0] = JapaneseNineKeyLayout.direction(
                        event.getX() - origin[0], event.getY() - origin[1], pixels(12));
                    showJapaneseFlickPreview(button, key, direction[0]);
                    return true;
                }
                case MotionEvent.ACTION_UP -> {
                    button.setPressed(false);
                    hideJapaneseFlickPreview();
                    if (direction[0] == 0) button.performClick();
                    else {
                        playFeedback(button);
                        selectJapaneseKey(key, direction[0]);
                    }
                    return true;
                }
                case MotionEvent.ACTION_CANCEL -> {
                    button.setPressed(false);
                    hideJapaneseFlickPreview();
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
            + "；左、上、右、下滑动选择其他假名");
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

    private void showJapaneseDigitVariants(Button anchor) {
        PopupMenu popup = new PopupMenu(this, anchor);
        for (String symbol : new String[] {"（", "）", "「", "」", "『", "』", "【", "】"}) {
            popup.getMenu().add(symbol).setOnMenuItemClickListener(ignored -> {
                playFeedback(anchor);
                commitNineKeyLiteral(symbol);
                return true;
            });
        }
        popup.show();
    }

    private Button japaneseDigitVariantsKey() {
        final Button[] holder = new Button[1];
        holder[0] = keyboardKey("（）", "括号", () -> showJapaneseDigitVariants(holder[0]));
        return holder[0];
    }

    private Button japaneseVariantsKey() {
        Button variants = keyboardKey("小゛゜", "小假名、浊音和半浊音", () -> {});
        japaneseVariantsButton = variants;
        variants.setOnClickListener(ignored -> {
            playFeedback(variants);
            showJapaneseVariants(variants);
        });
        return variants;
    }

    private void rebuildJapaneseNineKeyRows() {
        LinearLayout container = new LinearLayout(this);
        container.setOrientation(LinearLayout.HORIZONTAL);
        adjustFixedHeight(container, KeyboardGeometry.NINE_KEY_HEIGHT_DP);
        keyRows.addView(container, new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, pixels(180)));

        LinearLayout grid = new LinearLayout(this);
        grid.setOrientation(LinearLayout.VERTICAL);
        java.util.List<JapaneseNineKeyLayout.Key> keys = keyboardLayer == KeyboardLayout.Layer.SYMBOLS
            ? JapaneseNineKeyLayout.digitKeys() : JapaneseNineKeyLayout.keys();
        for (int rowIndex = 0; rowIndex < 3; rowIndex++) {
            LinearLayout row = new LinearLayout(this);
            for (int column = 0; column < 3; column++) {
                addNineKey(row, japaneseKey(keys.get(rowIndex * 3 + column)));
            }
            grid.addView(row, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 0, 1));
        }
        LinearLayout finalRow = new LinearLayout(this);
        addNineKey(finalRow, keyboardLayer == KeyboardLayout.Layer.SYMBOLS
            ? japaneseDigitVariantsKey() : japaneseVariantsKey());
        addNineKey(finalRow, japaneseKey(keys.get(9)));
        addNineKey(finalRow, japaneseKey(keys.get(10)));
        grid.addView(finalRow, new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, 0, 1));
        container.addView(grid, new LinearLayout.LayoutParams(0,
            LinearLayout.LayoutParams.MATCH_PARENT, 3));

        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.VERTICAL);
        Runnable deleteAction = () -> {
            if (connection != null && !command(0)) connection.deleteSurroundingTextInCodePoints(1, 0);
        };
        Button delete = keyboardKey("⌫", "删除", deleteAction);
        bindBackspaceRepeat(delete, deleteAction);
        addNineKey(actions, delete);
        japaneseSpaceKey = keyboardKey("空白", "空白", this::space);
        japaneseSpaceKey.setContentDescription("空白；左右滑动移动光标");
        addNineKey(actions, japaneseSpaceKey);
        japaneseReturnKey = keyboardKey("改行", "改行", this::enter);
        japaneseReturnKey.setContentDescription("改行");
        Button enter = japaneseReturnKey;
        actions.addView(enter, new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, 0, 2));
        container.addView(actions, new LinearLayout.LayoutParams(0,
            LinearLayout.LayoutParams.MATCH_PARENT, 0.8f));
    }

    /** Non-interactive overlay showing the five choices while a Japanese key is being flicked. */
    private final class JapaneseFlickPreview extends View {
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private static final int[] X_OFFSETS = {0, -1, 0, 1, 0};
        private static final int[] Y_OFFSETS = {0, 0, -1, 0, 1};
        private String[] labels = new String[5];
        private int selectedDirection;
        private float centerX;
        private float centerY;
        private float cellWidth;
        private float cellHeight;
        private float gap;

        JapaneseFlickPreview(android.content.Context context) {
            super(context);
            setVisibility(View.GONE);
            setClickable(false);
            setFocusable(false);
            setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        }

        void show(Button anchor, JapaneseNineKeyLayout.Key key, int direction, FrameLayout root) {
            labels = key.kana().toArray(String[]::new);
            selectedDirection = Math.max(0, Math.min(direction, labels.length - 1));
            int[] rootLocation = new int[2];
            int[] anchorLocation = new int[2];
            root.getLocationOnScreen(rootLocation);
            anchor.getLocationOnScreen(anchorLocation);
            centerX = anchorLocation[0] - rootLocation[0] + anchor.getWidth() / 2f;
            centerY = anchorLocation[1] - rootLocation[1] + anchor.getHeight() / 2f;
            float density = getResources().getDisplayMetrics().density;
            cellWidth = Math.max(anchor.getWidth(), Math.round(40 * density));
            cellHeight = Math.max(anchor.getHeight(), Math.round(36 * density));
            gap = Math.round(6 * density);
            root.bringChildToFront(this);
            setVisibility(View.VISIBLE);
            invalidate();
        }

        void hide() { setVisibility(View.GONE); }

        @Override protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);
            float textSize = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, 22,
                getResources().getDisplayMetrics());
            float radius = 8 * getResources().getDisplayMetrics().density;
            paint.setTextSize(textSize);
            paint.setTypeface(skin.monospaced() ? Typeface.MONOSPACE : Typeface.DEFAULT);
            Paint.FontMetrics metrics = paint.getFontMetrics();
            float stepX = cellWidth + gap;
            float stepY = cellHeight + gap;
            for (int index = 0; index < labels.length; index++) {
                String label = labels[index];
                if (label == null || label.isEmpty()) continue;
                boolean selected = index == selectedDirection;
                float x = centerX + X_OFFSETS[index] * stepX - cellWidth / 2;
                float y = centerY + Y_OFFSETS[index] * stepY - cellHeight / 2;
                paint.setColor(Color.parseColor(selected ? skin.accent() : skin.keyBackground()));
                canvas.drawRoundRect(x, y, x + cellWidth, y + cellHeight,
                    radius, radius, paint);
                paint.setColor(Color.parseColor(
                    selected ? skin.actionForeground() : skin.keyForeground()));
                float baseline = y + (cellHeight - metrics.bottom - metrics.top) / 2
                    - metrics.top;
                float textWidth = paint.measureText(label);
                canvas.drawText(label, x + (cellWidth - textWidth) / 2, baseline, paint);
            }
        }

        @Override public boolean onTouchEvent(MotionEvent event) { return false; }
    }

    private void commitNineKeyLiteral(String text) {
        if (connection == null) return;
        command(9);
        commitText(text);
    }

    private void chooseNineKeySpelling(long generation, int index) {
        if (session == 0) return;
        try { apply(NativeClient.chooseNineKeySpelling(session, generation, index)); }
        catch (JSONException | LinkageError error) { fail(); }
    }

    private void renderNineKeySpellings() {
        if (nineKeySpellings == null || nineKeySpellingScroll == null) return;
        JSONArray spellings = view == null ? null : view.optJSONArray("nine_key_spellings");
        boolean visible = displayedTouchLayout(view) == QUANPIN_NINE_KEY_LAYOUT
            && spellings != null && spellings.length() > 0;
        nineKeySpellingScroll.setVisibility(visible ? View.VISIBLE : View.GONE);
        if (!visible) {
            nineKeySpellingIndices = java.util.List.of();
            nineKeySpellingGeneration = -1;
            for (Button key : nineKeySpellingButtons) key.setVisibility(View.GONE);
            return;
        }
        nineKeySpellingGeneration = view.optLong("generation", -1);
        java.util.List<String> values = new java.util.ArrayList<>();
        java.util.List<Integer> indices = new java.util.ArrayList<>();
        for (int index = 0; index < spellings.length(); index++) {
            String spelling = spellings.optString(index, "");
            if (!spelling.isEmpty()) {
                values.add(spelling);
                indices.add(index);
            }
        }
        nineKeySpellingIndices = java.util.List.copyOf(indices);
        while (nineKeySpellingButtons.size() < values.size()) {
            int slot = nineKeySpellingButtons.size();
            Button key = button(nineKeySpellings, "", () -> {
                if (slot < nineKeySpellingIndices.size()) {
                    chooseNineKeySpelling(nineKeySpellingGeneration,
                        nineKeySpellingIndices.get(slot));
                }
            });
            key.setContentDescription("选择拼音");
            LinearLayout.LayoutParams params = (LinearLayout.LayoutParams) key.getLayoutParams();
            params.width = LinearLayout.LayoutParams.WRAP_CONTENT;
            params.weight = 0;
            key.setLayoutParams(params);
            nineKeySpellingButtons.add(key);
        }
        for (int slot = 0; slot < nineKeySpellingButtons.size(); slot++) {
            Button key = nineKeySpellingButtons.get(slot);
            boolean slotVisible = slot < values.size();
            key.setVisibility(slotVisible ? View.VISIBLE : View.GONE);
            if (slotVisible) {
                String spelling = values.get(slot);
                key.setText(spelling);
                key.setContentDescription("选择拼音 " + spelling);
            }
        }
    }

    @Override public View onCreateInputView() {
        deactivateHandwriting();
        candidateButtons.clear();
        nineKeySpellingButtons.clear();
        nineKeySpellingIndices = java.util.List.of();
        nineKeySpellingGeneration = -1;
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
        japaneseFlickPreview = new JapaneseFlickPreview(this);
        keyboardRoot.addView(japaneseFlickPreview, new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
        status = new TextView(this);
        keyboard.addView(status);
        LinearLayout candidateRegion = new LinearLayout(this);
        candidateRegion.setOrientation(LinearLayout.VERTICAL);
        LinearLayout candidateHeader = new LinearLayout(this);
        preedit = new TextView(this);
        preedit.setTextSize(TypedValue.COMPLEX_UNIT_SP, candidatePreeditFontSize);
        preedit.setOnClickListener(ignored -> {
            playFeedback(preedit);
            showLocalInputMenu();
        });
        candidateHeader.addView(preedit, new LinearLayout.LayoutParams(0,
            LinearLayout.LayoutParams.WRAP_CONTENT, 1));
        candidatePage = new TextView(this);
        candidateHeader.addView(candidatePage, new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT));
        shortcutBar = new LinearLayout(this);
        shortcutBar.setOrientation(LinearLayout.HORIZONTAL);
        shortcutBar.setGravity(Gravity.CENTER_VERTICAL);
        shortcutBar.setContentDescription("键盘快捷栏");
        shortcutBar.setPadding(pixels(2), 0, pixels(2), 0);
        shortcutScroll = new HorizontalScrollView(this);
        shortcutScroll.setHorizontalScrollBarEnabled(false);
        shortcutScroll.setContentDescription("键盘快捷栏");
        shortcutScroll.addView(shortcutBar, new HorizontalScrollView.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.MATCH_PARENT));
        scriptShortcutButton = button(shortcutBar, "简", this::toggleChineseOutput);
        scriptShortcutButton.setContentDescription("切换到繁体");
        emojiShortcutButton = button(shortcutBar, "☺", this::showEmojiPicker);
        emojiShortcutButton.setContentDescription("打开表情浏览");
        voiceShortcutButton = button(shortcutBar, "语音", this::showVoiceResult);
        voiceShortcutButton.setContentDescription("打开语音结果");
        aiPolishShortcutButton = button(shortcutBar, "AI", this::showAiPolish);
        aiPolishShortcutButton.setContentDescription("打开 AI 润色");
        replyShortcutButton = button(shortcutBar, "回复", this::showReplyKeyboard);
        replyShortcutButton.setContentDescription("生成高情商回复");
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
        candidateRegion.addView(shortcutScroll, new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, pixels(44)));
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
        // Like Apple, keep the shared candidate/shortcut strip above the reply surface. The
        // ordinary key rows and controls are hidden while this weighted child is visible.
        replyKeyboard = createReplyKeyboard();
        replyKeyboard.setVisibility(View.GONE);
        keyboard.addView(replyKeyboard, new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, 0, 1));
        keyRows = new LinearLayout(this);
        keyRows.setOrientation(LinearLayout.VERTICAL);
        keyboard.addView(keyRows);
        rebuildKeyRows();
        LinearLayout controls = new LinearLayout(this);
        keyboardControls = new HorizontalScrollView(this);
        keyboardControls.setHorizontalScrollBarEnabled(false);
        keyboardControls.addView(controls, new HorizontalScrollView.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT));
        keyboard.addView(keyboardControls);
        shiftButton = button(controls, "⇧", () -> {
            if (!dedicatedEnglish && session != 0 && !helpcodeCompositionEligible()) {
                toggleInputLanguage();
                if (!dedicatedEnglish) return;
                // Match Apple: the Shift that entered English starts from lowercase even if the
                // editor would otherwise request automatic capitalization.
                letterCase.reset();
            }
            letterCase.toggle(SystemClock.uptimeMillis());
            rebuildKeyRows();
            render();
        });
        shiftButton.setContentDescription("切换到英文大写");
        languageButton = button(controls, "中/英", this::toggleInputLanguage);
        languageButton.setContentDescription("切换中英文");
        layerButton = button(controls, "符号", () -> {
            keyboardLayer = keyboardLayer == KeyboardLayout.Layer.LETTERS
                ? KeyboardLayout.Layer.SYMBOLS : KeyboardLayout.Layer.LETTERS;
            rebuildKeyRows();
            render();
        });
        layerButton.setContentDescription("切换符号键盘");
        quickPunctuationButton = button(controls, ",", this::insertQuickPunctuation);
        quickPunctuationButton.setOnLongClickListener(ignored -> {
            showQuickPunctuationMenu();
            return true;
        });
        button(controls, "首", () -> command(6));
        button(controls, "←", () -> command(4));
        button(controls, "→", () -> command(5));
        button(controls, "尾", () -> command(7));
        Button delete = button(controls, "⌫", this::deleteFromHandwriting);
        bindBackspaceRepeat(delete, this::deleteFromHandwriting);
        button(controls, "删除", () -> command(8));
        button(controls, "取消", () -> command(3));
        spaceButton = button(controls, "空格", this::space);
        spaceButton.setContentDescription(SPACE_CURSOR_DESCRIPTION);
        bindSpaceCursor(spaceButton);
        enterButton = button(controls, "换行", this::enter);
        enterButton.setContentDescription("换行");
        button(controls, "切换", this::switchToNextInputMethodAfterCommit);
        schemeButton = borderlessButton(controls, "方案", this::showSchemePicker);
        schemeButton.setContentDescription("选择输入方案");
        skinButton = button(controls, "皮肤", () -> showSkinMenu(skinButton));
        skinButton.setContentDescription("切换键盘皮肤");
        layoutSettingsButton = button(controls, "设置", this::showLayoutSettings);
        layoutSettingsButton.setContentDescription("键盘设置");
        moreButton = brandButton(controls, this::showFeedbackMenu);
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
        installShortcutBar(dismissButton);
        expandedCandidates = new LinearLayout(this);
        expandedCandidates.setOrientation(LinearLayout.VERTICAL);
        expandedCandidates.setPadding(24, 16, 24, 16);
        expandedCandidates.setBackgroundColor(0xfff5f5f5);
        expandedCandidates.setContentDescription("候选面板");
        expandedCandidates.setVisibility(View.GONE);
        expandedCandidateScroll = new ScrollView(this);
        expandedCandidateScroll.addView(expandedCandidates);
        expandedCandidateScroll.setVisibility(View.GONE);
        keyboardRoot.addView(expandedCandidateScroll, new FrameLayout.LayoutParams(
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
        schemeScroll.addView(schemePanel, new ScrollView.LayoutParams(
            ScrollView.LayoutParams.MATCH_PARENT, ScrollView.LayoutParams.MATCH_PARENT));
        schemeScroll.setFillViewport(true);
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
        LinearLayout keyboardHeightHeader = new LinearLayout(this);
        TextView keyboardHeightLabel = new TextView(this);
        keyboardHeightLabel.setText("键盘高度");
        keyboardHeightHeader.addView(keyboardHeightLabel, new LinearLayout.LayoutParams(0,
            LinearLayout.LayoutParams.WRAP_CONTENT, 1));
        keyboardHeightValue = new TextView(this);
        keyboardHeightHeader.addView(keyboardHeightValue);
        layoutSettingsPanel.addView(keyboardHeightHeader);
        keyboardHeightSlider = new SeekBar(this);
        keyboardHeightSlider.setContentDescription("键盘高度");
        configureHeightSlider(keyboardHeightSlider);
        layoutSettingsPanel.addView(keyboardHeightSlider);
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
            if (checked == touchVoiceShortcutEnabled
                    || touchGeometrySaving || traditionalOutputSaving) return;
            touchVoiceShortcutEnabled = checked;
            renderLayoutSettingsState();
            render();
            saveTouchGeometry();
        });
        layoutSettingsPanel.addView(voiceShortcutSwitch);
        resetLayoutSettingsButton = button(layoutSettingsPanel, "恢复默认", this::resetTouchGeometry);
        resetLayoutSettingsButton.setContentDescription("恢复默认");
        TextView layoutHint = new TextView(this);
        layoutHint.setText("高度和间距只改变键位外观，不改变输入方案；松手后自动保存。");
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
        moreToolsPanel = new LinearLayout(this);
        moreToolsPanel.setOrientation(LinearLayout.VERTICAL);
        moreToolsPanel.setPadding(pixels(12), 0, pixels(12), pixels(10));
        moreToolsPanel.setBackgroundColor(Color.parseColor(skin.background()));
        moreToolsScroll = new ScrollView(this);
        moreToolsScroll.setFillViewport(true);
        moreToolsScroll.setVerticalScrollBarEnabled(false);
        moreToolsScroll.setContentDescription("更多工具");
        moreToolsScroll.addView(moreToolsPanel);
        moreToolsScroll.setVisibility(View.GONE);
        keyboardRoot.addView(moreToolsScroll, new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
        emojiPreferences = getSharedPreferences(EMOJI_RECENTS_PREFERENCES, MODE_PRIVATE);
        emojiRecents = loadEmojiRecents();
        emojiPanel = new LinearLayout(this);
        emojiPanel.setOrientation(LinearLayout.VERTICAL);
        emojiPanel.setPadding(pixels(8), 0, pixels(8), pixels(6));
        emojiPanel.setBackgroundColor(Color.parseColor(skin.background()));
        emojiPanel.setContentDescription("表情面板");
        emojiPanel.setFocusable(true);
        LinearLayout emojiHeader = new LinearLayout(this);
        emojiHeader.setGravity(Gravity.CENTER_VERTICAL);
        Button closeEmoji = button(emojiHeader, "‹", this::closeEmojiPicker);
        closeEmoji.setContentDescription("返回键盘");
        closeEmoji.setLayoutParams(new LinearLayout.LayoutParams(pixels(56), pixels(40)));
        TextView emojiTitle = new TextView(this);
        emojiTitle.setText("表情");
        emojiTitle.setTextSize(TypedValue.COMPLEX_UNIT_SP, 17);
        emojiTitle.setGravity(Gravity.CENTER);
        emojiHeader.addView(emojiTitle, new LinearLayout.LayoutParams(0, pixels(40), 1));
        Button deleteEmoji = button(emojiHeader, "⌫", this::deleteFromEmojiPicker);
        deleteEmoji.setContentDescription("删除");
        deleteEmoji.setLayoutParams(new LinearLayout.LayoutParams(pixels(56), pixels(40)));
        emojiPanel.addView(emojiHeader);
        emojiTabs = new LinearLayout(this);
        emojiTabs.setOrientation(LinearLayout.HORIZONTAL);
        emojiTabsScroll = new HorizontalScrollView(this);
        emojiTabsScroll.setHorizontalScrollBarEnabled(false);
        emojiTabsScroll.setContentDescription("表情分类");
        emojiTabsScroll.addView(emojiTabs);
        emojiPanel.addView(emojiTabsScroll, new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, pixels(40)));
        emojiStatus = new TextView(this);
        emojiStatus.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11);
        emojiStatus.setGravity(Gravity.CENTER_VERTICAL);
        emojiPanel.addView(emojiStatus, new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, pixels(20)));
        emojiGrid = new GridLayout(this);
        emojiGrid.setColumnCount(EmojiCatalogModel.COLUMNS);
        emojiGrid.setAlignmentMode(GridLayout.ALIGN_BOUNDS);
        emojiGrid.setUseDefaultMargins(false);
        emojiGridScroll = new ScrollView(this);
        emojiGridScroll.setFillViewport(false);
        emojiGridScroll.setVerticalScrollBarEnabled(false);
        emojiGridScroll.setContentDescription("表情网格；每行八个");
        emojiGridScroll.addView(emojiGrid, new ScrollView.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT));
        emojiGridScroll.setOnScrollChangeListener((view, scrollX, scrollY, oldX, oldY) -> {
            if (scrollY > oldY && !view.canScrollVertically(1)) loadEmojiPage();
        });
        emojiPanel.addView(emojiGridScroll, new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, 0, 1));
        emojiPanel.setVisibility(View.GONE);
        keyboardRoot.addView(emojiPanel, new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
        renderLayoutSettingsState();
        render();
        synchronizeReplyKeyboard();
        return keyboardRoot;
    }

    private void render() {
        updateSymbolKeyFaces();
        updateQuickPunctuation();
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
        if (status != null) status.setText(message + preferencesNotice
            + (dedicatedEnglish ? " · 英文输入" : "") + localMode + page
            + switch (letterCase.mode()) {
                case LOWERCASE -> "";
                case SHIFTED -> " · Shift";
                case CAPS_LOCK -> " · Caps Lock";
            });
        if (candidatePage != null) candidatePage.setText(page.isEmpty() ? "" : page.substring(3));
        JSONArray visibleCandidates = view == null ? null : view.optJSONArray("candidates");
        boolean handwriting = handwritingActive();
        boolean hasHandwritingResults = handwriting && !handwritingResults.isEmpty()
            && handwritingCandidateToken != null;
        boolean idle = view == null || (view.optString("editing_text", "").isEmpty()
            && "none".equals(view.optString("local_mode", "none"))
            && (visibleCandidates == null || visibleCandidates.length() == 0)
            && !hasHandwritingResults);
        if (preedit != null) {
            preedit.setTextSize(TypedValue.COMPLEX_UNIT_SP, candidatePreeditFontSize);
            String editingText = view == null ? "" : view.optString("editing_text", "");
            boolean offersLocalModes = idle && supportsLocalTools();
            String localModeKey = view == null ? "none" : view.optString("local_mode", "none");
            String localModeTitle = editingText;
            for (LocalInputMode mode : LocalInputMode.values()) {
                if (mode.preferenceKey().equals(localModeKey)
                        && mode.trigger().equals(editingText)) {
                    localModeTitle = mode.title();
                    break;
                }
            }
            boolean idleTitle = idle && editingText.isEmpty();
            String displayText = idleTitle
                ? (dedicatedEnglish ? "英文输入" : "水杉输入法") : localModeTitle;
            preedit.setText(displayText);
            preedit.setContentDescription(offersLocalModes ? "本地输入模式" : displayText);
            preedit.setClickable(offersLocalModes);
            preedit.setFocusable(offersLocalModes);
        }
        if (shortcutScroll != null)
            shortcutScroll.setVisibility(idle ? View.VISIBLE : View.GONE);
        if (scriptShortcutButton != null) {
            scriptShortcutButton.setVisibility(View.GONE);
            scriptShortcutButton.setText(traditionalChineseOutput ? "繁" : "简");
            scriptShortcutButton.setSelected(traditionalChineseOutput);
            styleButton(scriptShortcutButton, true);
            int scheme = view == null
                ? ((selectedScheme == KeyboardScheme.JAPANESE
                    || selectedScheme == KeyboardScheme.JAPANESE_NINE_KEY) ? 3 : -1)
                : view.optInt("scheme", -1);
            boolean japanese = scheme == 3;
            boolean conversionAvailable = AndroidChineseTextConversion.available();
            scriptShortcutButton.setEnabled(
                conversionAvailable && !japanese && canSaveChineseOutput());
            String label = traditionalChineseOutput ? "切换到简体" : "切换到繁体";
            String outputState = !conversionAvailable ? "需要 Android 10 或更高版本"
                : japanese ? "日语不使用简繁转换"
                : traditionalOutputSaving ? "正在保存"
                : traditionalChineseOutput ? "繁体" : "简体";
            scriptShortcutButton.setContentDescription(
                Build.VERSION.SDK_INT >= 30 ? label : label + "，" + outputState);
            if (Build.VERSION.SDK_INT >= 30)
                scriptShortcutButton.setStateDescription(outputState);
        }
        if (emojiShortcutButton != null) {
            emojiShortcutButton.setVisibility(idle && session != 0 && !emojiResources.isEmpty()
                && selectedScheme != KeyboardScheme.THOUGHTFUL_REPLY ? View.VISIBLE : View.GONE);
            emojiShortcutButton.setEnabled(session != 0 && !emojiResources.isEmpty());
        }
        if (voiceShortcutButton != null) {
            voiceShortcutButton.setVisibility(touchVoiceShortcutEnabled
                && selectedScheme != KeyboardScheme.THOUGHTFUL_REPLY ? View.VISIBLE : View.GONE);
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
        if (microsoftFinalKey != null) {
            String currentLocalMode = view == null ? "none" : view.optString("local_mode", "none");
            boolean visible = MicrosoftShuangpinKeyPolicy.visible(
                dedicatedEnglish, selectedScheme, currentLocalMode);
            microsoftFinalKey.setVisibility(visible ? View.VISIBLE : View.GONE);
            microsoftFinalKey.setEnabled(visible && session != 0);
            microsoftFinalKey.setContentDescription("微软双拼 ing");
        }
        if (layerButton != null) {
            layerButton.setText(keyboardLayer == KeyboardLayout.Layer.LETTERS ? "符号" : "字母");
            layerButton.setContentDescription(keyboardLayer == KeyboardLayout.Layer.LETTERS
                ? "切换符号键盘" : "切换字母键盘");
        }
        updateReturnKey();
        if (shiftButton != null) {
            shiftButton.setVisibility(displayedTouchLayout(view) != STANDARD_TOUCH_LAYOUT
                && keyboardLayer == KeyboardLayout.Layer.LETTERS ? View.GONE : View.VISIBLE);
            shiftButton.setText(letterCase.keyText());
            shiftButton.setSelected(letterCase.usesUppercase());
            shiftButton.setActivated(letterCase.mode() == EnglishLetterCaseState.Mode.CAPS_LOCK);
            styleButton(shiftButton, true);
            String caseLabel = letterCase.accessibilityLabel(dedicatedEnglish || session == 0);
            String caseValue = letterCase.accessibilityValue();
            shiftButton.setContentDescription(Build.VERSION.SDK_INT >= 30
                ? caseLabel : caseLabel + "，" + caseValue);
            if (Build.VERSION.SDK_INT >= 30) shiftButton.setStateDescription(caseValue);
        }
        if (languageButton != null) {
            languageButton.setText(dedicatedEnglish ? "英" : "中");
            languageButton.setEnabled(session != 0);
            languageButton.setContentDescription(
                dedicatedEnglish ? "切换到所选输入方案" : "切换到英文输入");
            if (Build.VERSION.SDK_INT >= 30) {
                languageButton.setStateDescription(dedicatedEnglish ? "英文输入" : "中文输入");
            }
        }
        if (schemeButton != null) {
            schemeButton.setText(selectedScheme.glyph() + selectedScheme.badge());
            schemeButton.setContentDescription("输入方案：" + selectedScheme.title());
            boolean schemeReady = session != 0 && preferencesSnapshot != null
                && !schemeSaving && !touchGeometrySaving && !traditionalOutputSaving;
            schemeButton.setEnabled(schemeReady);
            if (Build.VERSION.SDK_INT >= 30) {
                String schemeState = session == 0 ? "输入会话未就绪"
                    : preferencesSnapshot == null ? "设置加载中"
                    : schemeSaving ? "正在切换输入方案"
                    : touchGeometrySaving || traditionalOutputSaving ? "正在保存其他设置"
                    : "可用";
                schemeButton.setStateDescription(schemeState);
            }
        }
        if (skinButton != null) {
            skinButton.setEnabled(canSaveKeyboardSkin());
            skinButton.setContentDescription("切换键盘皮肤；当前" + skin.title());
            if (Build.VERSION.SDK_INT >= 30) skinButton.setStateDescription(skin.title());
        }
        synchronizeReplyKeyboard();
        if (layoutSettingsButton != null)
            layoutSettingsButton.setEnabled(session != 0 && preferencesSnapshot != null
                && !schemeSaving && !touchGeometrySaving && !traditionalOutputSaving);
        renderNineKeySpellings();
        scheduleCandidateGlosses();
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
        if (handwriting) {
            renderSharedHandwritingCandidates(activeCandidates);
        } else if (entries != null) {
            for (int slot = 0; slot < entries.length(); slot++) {
                JSONObject candidate = entries.optJSONObject(slot);
                if (candidate == null) continue;
                while (candidateButtons.size() <= slot)
                    candidateButtons.add(makeCandidateButton(candidateButtons.size()));
                Button candidateView = candidateButtons.get(slot);
                candidateView.setVisibility(View.VISIBLE);
                updateCandidateButton(candidateView, candidate, slot);
                activeCandidates.addView(candidateView, new LinearLayout.LayoutParams(
                    candidateHorizontal ? LinearLayout.LayoutParams.WRAP_CONTENT
                        : LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT));
            }
            if (view.optInt("page_count", 0) > 1 && expandCandidates != null)
                expandCandidates.setVisibility(View.VISIBLE);
        }
        int visibleSlots = entries == null ? 0 : entries.length();
        for (int slot = visibleSlots; slot < candidateButtons.size(); slot++)
            candidateButtons.get(slot).setVisibility(View.GONE);
        if (!handwriting && candidatePaging != null) {
            button(candidatePaging, "上词", () -> command(103));
            button(candidatePaging, "下词", () -> command(102));
            button(candidatePaging, "上一页", () -> command(101));
            button(candidatePaging, "下一页", () -> command(100));
        }
        renderExpandedCandidates();
        if (moreToolsScroll != null && moreToolsScroll.getVisibility() == View.VISIBLE)
            renderMoreTools();
        applySkin();
    }

    private void renderSharedHandwritingCandidates(LinearLayout activeCandidates) {
        if (handwritingStatus == null) return;
        if (handwritingResults.isEmpty() || handwritingCandidateToken == null) {
            handwritingStatus.setVisibility(View.VISIBLE);
            return;
        }
        handwritingStatus.setVisibility(View.GONE);
        for (int index = 0; index < handwritingResults.size(); index++) {
            String candidate = handwritingResults.get(index);
            HandwritingRequestTracker.Token token = handwritingCandidateToken;
            Button choice = keyboardKey(chineseOutput(candidate, view),
                "手写候选 " + (index + 1), () -> commitHandwritingCandidate(token, candidate));
            choice.setTextSize(TypedValue.COMPLEX_UNIT_SP, candidateFontSize);
            LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                candidateHorizontal ? LinearLayout.LayoutParams.WRAP_CONTENT
                    : LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT);
            activeCandidates.addView(choice, params);
        }
    }
}
