package app.msime.client.home;

import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.View;
import android.widget.LinearLayout;
import android.widget.TextView;
import androidx.annotation.Nullable;
import androidx.appcompat.app.AppCompatActivity;
import app.msime.client.R;
import com.google.android.material.appbar.MaterialToolbar;

/**
 * 关于水杉：版本、电脑版、帮助与开源、隐私。
 *
 * <p>Built from the Apple app's `AboutView` (`AboutAndDownloadViews.swift`), section for section,
 * including the two footers -- what the keyboard sends and when is a claim, and it should read the
 * same on both platforms rather than being paraphrased per host.
 *
 * <p>使用帮助 and 反馈问题与建议 are their own screens over there and have not been ported; this page
 * links out to the site and the repository instead of pretending to carry them.
 */
public final class AboutActivity extends AppCompatActivity {
    private static final String SITE = "https://msime.app/";
    private static final String PRIVACY = "https://msime.app/privacy/";
    private static final String REPOSITORY = "https://github.com/metasequoiaime/msime";

    @Override protected void onCreate(@Nullable Bundle state) {
        super.onCreate(state);
        setContentView(R.layout.activity_about);
        MaterialToolbar bar = findViewById(R.id.about_bar);
        bar.setNavigationOnClickListener(ignored -> finish());

        ((TextView) findViewById(R.id.about_version)).setText(version());

        LinearLayout about = findViewById(R.id.about_msime_rows);
        addRow(about, "电脑版下载", "macOS、Windows、Linux 的安装包与指南",
            () -> startActivity(new Intent(this, DesktopDownloadActivity.class)));

        LinearLayout help = findViewById(R.id.about_help_rows);
        addRow(help, "官方网站", "msime.app", () -> open(SITE));
        divider(help);
        addRow(help, "开源代码与许可证", "GitHub", () -> open(REPOSITORY));

        LinearLayout privacy = findViewById(R.id.about_privacy_rows);
        addRow(privacy, "隐私说明", "msime.app", () -> open(PRIVACY));
    }

    /** `版本 1.2 (34)`, or a dash for either half that the package manager will not give up. */
    private String version() {
        String name = "—";
        String code = "—";
        try {
            PackageInfo info = getPackageManager().getPackageInfo(getPackageName(), 0);
            if (info.versionName != null) name = info.versionName;
            code = String.valueOf(android.os.Build.VERSION.SDK_INT >= 28
                ? info.getLongVersionCode() : info.versionCode);
        } catch (PackageManager.NameNotFoundException error) {
            // 自己的包查不到自己，这种时候把「—」摆出来，比一个假版本号诚实。
        }
        return getString(R.string.about_version, name, code);
    }

    private void open(String url) {
        try {
            startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url)));
        } catch (RuntimeException error) {
            // 没有浏览器可开就什么也不做：这一行是个链接，不是一件非成功不可的操作。
        }
    }

    private void addRow(LinearLayout parent, String title, String value, Runnable action) {
        LinearLayout row = (LinearLayout) LayoutInflater.from(this)
            .inflate(R.layout.item_setting_row, parent, false);
        // 这几行没有图标：母版那边每行带一个 SF Symbol，Android 这边没有对应的一套字形，
        // 与其塞六个凑数的图，不如留白。
        row.findViewById(R.id.row_badge).setVisibility(View.GONE);
        ((TextView) row.findViewById(R.id.row_title)).setText(title);
        ((TextView) row.findViewById(R.id.row_value)).setText(value);
        row.setContentDescription(title + "，" + value);
        row.setOnClickListener(ignored -> action.run());
        parent.addView(row);
    }

    private void divider(LinearLayout parent) {
        View line = new View(this);
        int height = Math.max(1, Math.round(getResources().getDisplayMetrics().density));
        LinearLayout.LayoutParams params =
            new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, height);
        params.leftMargin = Math.round(16 * getResources().getDisplayMetrics().density);
        line.setLayoutParams(params);
        line.setBackgroundColor(androidx.core.content.ContextCompat.getColor(this, R.color.hairline));
        parent.addView(line);
    }
}
