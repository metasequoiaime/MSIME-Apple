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

/** Platform-owned voice capture. Android's SpeechRecognizer owns the microphone;
 * this activity persists only its bounded text result for the isolated IME process.
 */
public final class VoiceRecognitionActivity extends Activity {
    private static final int REQUEST_RECORD_AUDIO = 1;
    private static final String EXTRA_LANGUAGE = "app.msime.client.voice.LANGUAGE";
    private static final String EXTRA_REQUEST_ID = "app.msime.client.voice.REQUEST_ID";
    private static volatile WeakReference<VoiceRecognitionActivity> active =
        new WeakReference<>(null);
    private static volatile String activeRequestId;
    private SpeechRecognizer recognizer;
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

    public static void launch(Context context, String requestId, String language) {
        markLaunched(requestId);
        Intent intent = new Intent(context, VoiceRecognitionActivity.class);
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        intent.putExtra(EXTRA_REQUEST_ID, requestId);
        intent.putExtra(EXTRA_LANGUAGE, safeLanguage(language));
        context.startActivity(intent);
    }

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        active = new WeakReference<>(this);
        String requestId = getIntent().getStringExtra(EXTRA_REQUEST_ID);
        if (requestId != null) activeRequestId = requestId;
        if (!available(this)) {
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
        if (recognizer != null) {
            recognizer.destroy();
            recognizer = null;
        }
        if (active.get() == this) active = new WeakReference<>(null);
        if (!isChangingConfigurations() && !isFinishing()) {
            clearRequest(getIntent().getStringExtra(EXTRA_REQUEST_ID));
        } else if (isFinishing()) {
            clearRequest(getIntent().getStringExtra(EXTRA_REQUEST_ID));
        }
        super.onDestroy();
    }

    private void startRecognition() {
        if (finished || recognizer != null) return;
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
                if (values != null && !values.isEmpty()) saveResult(values.get(0));
                finishRequest();
            }
            @Override public void onPartialResults(Bundle partialResults) { }
            @Override public void onEvent(int eventType, Bundle params) { }
        });
        recognizer.startListening(recognitionIntent(
            getIntent().getStringExtra(EXTRA_LANGUAGE)));
    }

    private void stopRecognition() {
        if (finished || recognizer == null) return;
        stopping = true;
        recognizer.stopListening();
    }

    private void cancelRecognition() {
        if (finished) return;
        finished = true;
        if (recognizer != null) recognizer.cancel();
        clearRequest(getIntent().getStringExtra(EXTRA_REQUEST_ID));
        finish();
    }

    private void finishRequest() {
        if (finished) return;
        finished = true;
        if (recognizer != null) recognizer.stopListening();
        clearRequest(getIntent().getStringExtra(EXTRA_REQUEST_ID));
        finish();
    }

    private void fail(String message) {
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show();
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
