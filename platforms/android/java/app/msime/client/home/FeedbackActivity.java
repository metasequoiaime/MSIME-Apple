package app.msime.client.home;

import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.widget.EditText;
import android.widget.TextView;
import androidx.annotation.Nullable;
import androidx.appcompat.app.AppCompatActivity;
import app.msime.client.R;
import com.google.android.material.appbar.MaterialToolbar;
import com.google.android.material.button.MaterialButton;
import com.google.android.material.chip.Chip;
import com.google.android.material.chip.ChipGroup;

/**
 * 反馈问题与建议：写一段，连同版本和机型一起带走。
 *
 * <p>The same shape as the Apple app's `FeedbackView` -- a kind, a description, the environment
 * shown rather than collected silently, and the two ways out: copy the whole thing, or open a
 * prefilled issue. The environment is Android's here, and it is on screen because a report that
 * quietly attaches facts about someone's device should at least show them which facts.
 */
public final class FeedbackActivity extends AppCompatActivity {
    private static final String[] KINDS = {"功能异常", "候选词不对", "功能建议", "其他"};
    private static final String ISSUES = "https://github.com/metasequoiaime/msime/issues/new";
    /** GitHub 的地址长度有限，过长的正文在这里截断，完整的走「复制报告」。 */
    private static final int MAX_BODY = 4000;

    private String kind = KINDS[0];
    private EditText detail;

    @Override protected void onCreate(@Nullable Bundle state) {
        super.onCreate(state);
        setContentView(R.layout.activity_feedback);
        MaterialToolbar bar = findViewById(R.id.feedback_bar);
        bar.setNavigationOnClickListener(ignored -> finish());

        ChipGroup kinds = findViewById(R.id.feedback_kinds);
        for (String value : KINDS) {
            Chip chip = new Chip(this);
            chip.setText(value);
            chip.setCheckable(true);
            chip.setId(android.view.View.generateViewId());
            chip.setChecked(value.equals(kind));
            chip.setOnClickListener(ignored -> kind = value);
            kinds.addView(chip);
        }

        detail = findViewById(R.id.feedback_detail);
        ((TextView) findViewById(R.id.feedback_environment)).setText(environment());

        MaterialButton copy = findViewById(R.id.feedback_copy);
        copy.setOnClickListener(ignored -> {
            ClipboardManager clipboard = getSystemService(ClipboardManager.class);
            if (clipboard == null) return;
            clipboard.setPrimaryClip(ClipData.newPlainText("水杉反馈", report()));
            copy.setText(R.string.feedback_copied);
        });

        findViewById(R.id.feedback_submit).setOnClickListener(ignored -> submit());
    }

    @Override protected void onStart() {
        super.onStart();
        ((MaterialButton) findViewById(R.id.feedback_copy)).setText(R.string.feedback_copy);
    }

    /** 版本、系统和机型——附上去的就是屏幕上显示的这三行，没有别的。 */
    private String environment() {
        String version = "开发构建";
        String build = "-";
        try {
            PackageInfo info = getPackageManager().getPackageInfo(getPackageName(), 0);
            if (info.versionName != null) version = info.versionName;
            build = String.valueOf(Build.VERSION.SDK_INT >= 28
                ? info.getLongVersionCode() : info.versionCode);
        } catch (PackageManager.NameNotFoundException error) {
            // 查不到自己的包就用上面那两个占位，别把一个假版本号写进别人的问题单。
        }
        return "水杉输入法 " + version + "（构建 " + build + "）\n"
            + "Android " + Build.VERSION.RELEASE + "（API " + Build.VERSION.SDK_INT + "）\n"
            + Build.MANUFACTURER + " " + Build.MODEL;
    }

    private String report() {
        String text = detail == null ? "" : detail.getText().toString();
        return "### 类型\n" + kind + "\n\n### 描述\n" + text + "\n\n### 环境\n" + environment() + "\n";
    }

    private void submit() {
        String body = report();
        if (body.length() > MAX_BODY) body = body.substring(0, MAX_BODY);
        Uri url = Uri.parse(ISSUES).buildUpon()
            .appendQueryParameter("title", kind)
            .appendQueryParameter("body", body)
            .build();
        try {
            startActivity(new Intent(Intent.ACTION_VIEW, url));
        } catch (RuntimeException error) {
            // 打不开浏览器时还有「复制报告」那条路，不在这里报一个用户处理不了的错。
        }
    }
}
