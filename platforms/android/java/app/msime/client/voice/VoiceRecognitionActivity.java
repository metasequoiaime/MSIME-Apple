package app.msime.client;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.speech.RecognitionListener;
import android.speech.RecognizerIntent;
import android.speech.SpeechRecognizer;
import android.widget.Toast;
import java.io.File;
import java.lang.ref.WeakReference;
import java.util.ArrayList;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Voice capture, by whichever engine the user's settings call for.
 *
 * <p>Two of them. Android's SpeechRecognizer owns the microphone itself and needs no account, no
 * token and no network of the user's choosing; it is what this activity uses when nothing has been
 * configured, and it stays the default. A user who configured a transcription provider has chosen
 * a different transcriber, and reaching it means holding the audio here and uploading it - that is
 * {@link HttpAsrRecognizer}.
 *
 * <p>Either way this activity persists only the bounded text result for the isolated IME process.
 */
public final class VoiceRecognitionActivity extends Activity {
    private static final int REQUEST_RECORD_AUDIO = 1;
    private static final String EXTRA_LANGUAGE = "app.msime.client.voice.LANGUAGE";
    private static final String EXTRA_REQUEST_ID = "app.msime.client.voice.REQUEST_ID";
    private static final String EXTRA_PROVIDER = "app.msime.client.voice.PROVIDER";
    private static final String EXTRA_ENDPOINT = "app.msime.client.voice.ENDPOINT";
    private static final String EXTRA_MODEL = "app.msime.client.voice.MODEL";
    private static final String EXTRA_TOKEN = "app.msime.client.voice.TOKEN";
    private static final String EXTRA_POLISH_ENDPOINT = "app.msime.client.voice.POLISH_ENDPOINT";
    private static final String EXTRA_POLISH_MODEL = "app.msime.client.voice.POLISH_MODEL";
    private static final String EXTRA_POLISH_TOKEN = "app.msime.client.voice.POLISH_TOKEN";
    private static final String EXTRA_POLISH_PROMPT = "app.msime.client.voice.POLISH_PROMPT";
    private static volatile WeakReference<VoiceRecognitionActivity> active =
        new WeakReference<>(null);
    private static volatile String activeRequestId;
    private SpeechRecognizer recognizer;
    private HttpAsrRecognizer provider;
    private ExecutorService providerWorker;
    private boolean stopping;
    private boolean finished;

    public static boolean available(Context context) {
        return SpeechRecognizer.isRecognitionAvailable(context);
    }

    public static void markLaunched(String requestId) {
        activeRequestId = requestId;
    }

    public static void clearRequest(String requestId) {
        if (requestId != null && requestId.equals(activeRequestId)) activeRequestId = null;
    }

    public static boolean isRequestActive(String requestId) {
        return requestId != null && requestId.equals(activeRequestId);
    }

    /** The optional rewrite, already resolved: the prompt is text here, not a slot to look up. */
    public record Polish(String endpoint, String model, String token, String prompt) {}

    public static void launch(Context context, String requestId, String language) {
        launch(context, requestId, language, null, null, null, null, null);
    }

    /**
     * Launch with a configured transcription provider, or without one to use the platform
     * recognizer. The three provider values are resolved and validated by the shared layer; this
     * activity only checks that it can speak that protocol before using them.
     */
    public static void launch(Context context, String requestId, String language,
                              String provider, String endpoint, String model, String token,
                              Polish polish) {
        markLaunched(requestId);
        Intent intent = new Intent(context, VoiceRecognitionActivity.class);
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        intent.putExtra(EXTRA_REQUEST_ID, requestId);
        intent.putExtra(EXTRA_LANGUAGE, safeLanguage(language));
        if (provider != null) intent.putExtra(EXTRA_PROVIDER, provider);
        if (endpoint != null) intent.putExtra(EXTRA_ENDPOINT, endpoint);
        if (model != null) intent.putExtra(EXTRA_MODEL, model);
        if (token != null) intent.putExtra(EXTRA_TOKEN, token);
        if (polish != null) {
            intent.putExtra(EXTRA_POLISH_ENDPOINT, polish.endpoint());
            intent.putExtra(EXTRA_POLISH_MODEL, polish.model());
            intent.putExtra(EXTRA_POLISH_TOKEN, polish.token());
            intent.putExtra(EXTRA_POLISH_PROMPT, polish.prompt());
        }
        context.startActivity(intent);
    }

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        active = new WeakReference<>(this);
        String requestId = getIntent().getStringExtra(EXTRA_REQUEST_ID);
        if (requestId != null) activeRequestId = requestId;
        // Only the platform recognizer needs the system service. A configured provider records
        // here, so a device without that service can still use voice input through one.
        if (!usesProvider() && !available(this)) {
            fail("设备没有可用的系统语音识别服务");
            finish();
            return;
        }
        if (checkSelfPermission(android.Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[] {android.Manifest.permission.RECORD_AUDIO},
                REQUEST_RECORD_AUDIO);
            return;
        }
        startRecognition();
    }

    @Override public void onRequestPermissionsResult(int requestCode, String[] permissions,
            int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode != REQUEST_RECORD_AUDIO || finished) return;
        if (grantResults.length == 1 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            startRecognition();
        } else {
            fail("语音识别需要麦克风权限");
            finishRequest();
        }
    }

    /** Requests that the recognizer finish the current utterance and deliver final results. */
    public static void stopActive() {
        VoiceRecognitionActivity activity = active.get();
        if (activity != null) {
            activity.runOnUiThread(activity::stopRecognition);
        }
    }

    /** Stops the platform recognizer launched for the shared Tauri voice panel. */
    public static void cancelActive() {
        VoiceRecognitionActivity activity = active.get();
        if (activity != null) activity.runOnUiThread(activity::cancelRecognition);
    }

    @Override protected void onDestroy() {
        finished = true;
        if (provider != null) {
            // The recorder holds the microphone until it is told to stop, and a worker outliving
            // this window would keep it past the point anything can use the result.
            provider.cancel();
            provider = null;
        }
        if (providerWorker != null) {
            providerWorker.shutdownNow();
            providerWorker = null;
        }
        if (recognizer != null) {
            recognizer.destroy();
            recognizer = null;
        }
        if (active.get() == this) {
            active = new WeakReference<>(null);
            // A configuration change recreates the activity for the same request.
            // Keep the request visible while the replacement activity registers
            // itself; otherwise the Tauri-side poller settles the job as cancelled.
            if (!isChangingConfigurations()) {
                clearRequest(getIntent().getStringExtra(EXTRA_REQUEST_ID));
            }
        }
        super.onDestroy();
    }

    /** Whether this request carries a provider configuration this host can actually speak. */
    private boolean usesProvider() {
        Intent intent = getIntent();
        return HttpAsrPolicy.usable(intent.getStringExtra(EXTRA_PROVIDER),
            intent.getStringExtra(EXTRA_ENDPOINT), intent.getStringExtra(EXTRA_MODEL),
            intent.getStringExtra(EXTRA_TOKEN));
    }

    private void startRecognition() {
        if (finished) return;
        if (usesProvider()) {
            startProviderRecognition();
            return;
        }
        if (recognizer != null) return;
        recognizer = SpeechRecognizer.createSpeechRecognizer(this);
        recognizer.setRecognitionListener(new RecognitionListener() {
            @Override public void onReadyForSpeech(Bundle params) { }
            @Override public void onBeginningOfSpeech() { }
            @Override public void onRmsChanged(float rmsdB) { }
            @Override public void onBufferReceived(byte[] buffer) { }
            @Override public void onEndOfSpeech() { }
            @Override public void onError(int error) {
                if (!finished) {
                    if (!stopping) fail("语音识别未返回结果");
                    finishRequest();
                }
            }
            @Override public void onResults(Bundle results) {
                if (finished) return;
                ArrayList<String> values = results == null
                    ? null : results.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION);
                if (values != null && !values.isEmpty()) {
                    // Off the main thread: polishing is a network round trip, and onResults is
                    // delivered on the thread drawing this window.
                    deliver(values.get(0));
                    return;
                }
                finishRequest();
            }
            @Override public void onPartialResults(Bundle partialResults) { }
            @Override public void onEvent(int eventType, Bundle params) { }
        });
        recognizer.startListening(recognitionIntent(
            getIntent().getStringExtra(EXTRA_LANGUAGE)));
    }

    /**
     * Record, upload and hand back the text, off the main thread.
     *
     * <p>The recording runs until the user stops it, then the upload waits on a network round
     * trip; neither belongs on the thread drawing this window.
     */
    private void startProviderRecognition() {
        if (provider != null) return;
        Intent intent = getIntent();
        String requestId = intent.getStringExtra(EXTRA_REQUEST_ID);
        String language = intent.getStringExtra(EXTRA_LANGUAGE);
        String endpoint = intent.getStringExtra(EXTRA_ENDPOINT);
        String model = intent.getStringExtra(EXTRA_MODEL);
        String token = intent.getStringExtra(EXTRA_TOKEN);
        provider = new HttpAsrRecognizer();
        providerWorker = Executors.newSingleThreadExecutor();
        HttpAsrRecognizer running = provider;
        providerWorker.execute(() -> {
            String text = null;
            String message = null;
            try {
                text = running.recognize(requestId, language, endpoint, model, token);
            } catch (HttpAsrRecognizer.Refused refused) {
                message = switch (refused.failure()) {
                    case PERMISSION -> "语音识别需要麦克风权限";
                    case UNAVAILABLE -> "麦克风被其他应用占用";
                    case NETWORK -> "语音服务未响应，请检查网络与密钥";
                    case EMPTY -> "没有听到内容";
                    case CANCELLED -> null;
                };
            }
            String finalText = text;
            String finalMessage = message;
            String polishedText = finalText == null ? null : polished(finalText);
            runOnUiThread(() -> {
                if (finished) return;
                if (polishedText != null) saveResult(polishedText);
                else if (finalMessage != null) fail(finalMessage);
                finishRequest();
            });
        });
    }

    private void stopRecognition() {
        if (finished) return;
        stopping = true;
        if (provider != null) {
            provider.stop();
            return;
        }
        if (recognizer != null) recognizer.stopListening();
    }

    private void cancelRecognition() {
        if (finished) return;
        finished = true;
        if (provider != null) provider.cancel();
        if (recognizer != null) recognizer.cancel();
        clearRequest(getIntent().getStringExtra(EXTRA_REQUEST_ID));
        finish();
    }

    private void finishRequest() {
        if (finished) return;
        finished = true;
        if (recognizer != null) recognizer.stopListening();
        if (provider != null) provider.stop();
        clearRequest(getIntent().getStringExtra(EXTRA_REQUEST_ID));
        finish();
    }

    private void fail(String message) {
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show();
    }

    /**
     * The rewrite the user asked for, or the transcript unchanged.
     *
     * <p>Best effort: a rewrite improves text the user already has, so any failure keeps the
     * original rather than losing a recognised sentence to an unreachable service. It runs for
     * both engines, because the setting is about the result and not about who produced it.
     */
    /** Polish on a worker, then save and finish on the thread that owns this window. */
    private void deliver(String text) {
        if (getIntent().getStringExtra(EXTRA_POLISH_ENDPOINT) == null) {
            saveResult(text);
            finishRequest();
            return;
        }
        if (providerWorker == null) providerWorker = Executors.newSingleThreadExecutor();
        providerWorker.execute(() -> {
            String result = polished(text);
            runOnUiThread(() -> {
                if (finished) return;
                saveResult(result);
                finishRequest();
            });
        });
    }

    private String polished(String text) {
        Intent intent = getIntent();
        String endpoint = intent.getStringExtra(EXTRA_POLISH_ENDPOINT);
        if (endpoint == null) return text;
        String polished = VoicePolisher.polish(endpoint,
            intent.getStringExtra(EXTRA_POLISH_MODEL),
            intent.getStringExtra(EXTRA_POLISH_TOKEN),
            intent.getStringExtra(EXTRA_POLISH_PROMPT), text);
        return polished == null ? text : polished;
    }

    private void saveResult(String text) {
        File files = getFilesDir();
        if (files == null) {
            Toast.makeText(this, "语音结果无法保存", Toast.LENGTH_SHORT).show();
            return;
        }
        try {
            new VoiceResultStore(files.toPath().resolve("voice-handoff"))
                .save(text, System.currentTimeMillis());
            Toast.makeText(this, "语音结果已发送到键盘，10 分钟内可插入", Toast.LENGTH_LONG).show();
        } catch (VoiceResultStore.Failure error) {
            String message = error.reason() == VoiceResultStore.Reason.BUSY
                ? "语音结果正在更新，请稍后重试" : "语音结果无法保存";
            Toast.makeText(this, message, Toast.LENGTH_SHORT).show();
        }
    }

    private static Intent recognitionIntent(String language) {
        Intent intent = new Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH);
        intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL,
            RecognizerIntent.LANGUAGE_MODEL_FREE_FORM);
        intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE, safeLanguage(language));
        intent.putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1);
        intent.putExtra(RecognizerIntent.EXTRA_PROMPT, "水杉语音输入");
        return intent;
    }

    private static String safeLanguage(String language) {
        if (language != null && !language.isEmpty() && language.length() <= 64
                && language.chars().noneMatch(Character::isISOControl)) {
            Locale locale = Locale.forLanguageTag(language.replace('_', '-'));
            if (!locale.getLanguage().isEmpty()) return locale.toLanguageTag();
        }
        String fallback = Locale.getDefault().toLanguageTag();
        return fallback.isEmpty() ? "zh-CN" : fallback;
    }
}
