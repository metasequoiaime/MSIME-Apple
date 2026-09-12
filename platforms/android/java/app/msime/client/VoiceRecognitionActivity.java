package app.msime.client;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import android.speech.RecognizerIntent;
import android.widget.Toast;
import java.io.File;
import java.util.ArrayList;
import java.util.Locale;

/** Platform-owned voice capture. The selected recognizer owns audio; this activity
 * persists only its bounded text result for the isolated IME process.
 */
@SuppressWarnings("deprecation")
public final class VoiceRecognitionActivity extends Activity {
    private static final int REQUEST_RECOGNITION = 1;
    private static final String EXTRA_LANGUAGE = "app.msime.client.voice.LANGUAGE";
    private static final String STATE_LAUNCHED = "recognizer_launched";

    public static boolean available(Context context) {
        return recognitionIntent("").resolveActivity(context.getPackageManager()) != null;
    }

    public static void launch(Context context, String language) {
        Intent intent = new Intent(context, VoiceRecognitionActivity.class);
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        intent.putExtra(EXTRA_LANGUAGE, safeLanguage(language));
        context.startActivity(intent);
    }

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        if (state != null && state.getBoolean(STATE_LAUNCHED, false)) return;
        Intent recognition = recognitionIntent(getIntent().getStringExtra(EXTRA_LANGUAGE));
        if (recognition.resolveActivity(getPackageManager()) == null) {
            Toast.makeText(this, "设备没有可用的系统语音识别服务", Toast.LENGTH_SHORT).show();
            finish();
            return;
        }
        try { startActivityForResult(recognition, REQUEST_RECOGNITION); }
        catch (ActivityNotFoundException | SecurityException error) {
            Toast.makeText(this, "系统语音识别服务无法启动", Toast.LENGTH_SHORT).show();
            finish();
        }
    }

    @Override protected void onSaveInstanceState(Bundle state) {
        state.putBoolean(STATE_LAUNCHED, true);
        super.onSaveInstanceState(state);
    }

    @Override protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == REQUEST_RECOGNITION && resultCode == RESULT_OK && data != null) {
            ArrayList<String> results = data.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS);
            if (results != null && !results.isEmpty()) saveResult(results.get(0));
        }
        finish();
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
