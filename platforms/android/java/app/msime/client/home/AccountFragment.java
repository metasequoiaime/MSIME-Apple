package app.msime.client.home;

import android.content.res.ColorStateList;
import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import android.widget.TextView;
import androidx.annotation.ColorRes;
import androidx.annotation.DrawableRes;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.core.content.ContextCompat;
import app.msime.client.AccountIdentity;
import app.msime.client.AppIconStyle;
import app.msime.client.CommunityRequest;
import app.msime.client.R;
import com.google.android.material.imageview.ShapeableImageView;
import com.google.android.material.snackbar.Snackbar;

/**
 * The 我的 tab: who this device is to the backend, what the app looks like, and where content is.
 *
 * There is no sign-in on Android yet. What exists is the anonymous identity the keyboard creates on
 * its first backend request, and that is what this page shows -- naming it is more use than a bare
 * "未登录", because it is the identity the community catalogue is read with. Rows whose destination
 * needs a real account say so rather than opening an empty screen.
 */
public final class AccountFragment extends HomeTabFragment {
    @Override public View onCreateView(@NonNull LayoutInflater inflater, @Nullable ViewGroup parent,
                                       @Nullable Bundle state) {
        return inflater.inflate(R.layout.page_account, parent, false);
    }

    @Override public void onViewCreated(@NonNull View view, @Nullable Bundle state) {
        render();
    }

    // The icon may have been changed elsewhere, and the keyboard may have created its identity
    // while this screen was in the background.
    @Override protected void onBecameVisible() { render(); }

    private void render() {
        View view = getView();
        if (view == null) return;
        HostTask.run(this, AccountIdentity::subject, subject -> bind(subject == null ? "" : subject));
        bindIcons();
        bindContent();
        bindStorage();
        ((TextView) view.findViewById(R.id.account_note)).setText(
            "水杉在 Android 上还没有登录入口。匿名身份只用来读取社区目录，不携带你的输入内容，也不在设备之间同步。");
    }

    private void bind(String subject) {
        View view = getView();
        if (view == null) return;
        TextView subtitle = view.findViewById(R.id.account_subtitle);
        subtitle.setText(subject.isEmpty()
            ? "键盘还没有用到后端，因此还没有匿名身份"
            : "匿名身份 " + AccountIdentity.shortSubject(subject));
    }

    private void bindIcons() {
        View view = getView();
        if (view == null) return;
        LinearLayout rows = view.findViewById(R.id.account_personal_rows);
        rows.removeAllViews();
        AppIconStyle current = AppIcons.selected(requireContext());
        addRow(rows, R.drawable.ic_feature_skin, R.color.tile_violet, "App 图标",
            current.title() + " · " + current.description(), this::showIcons);
    }

    private void bindContent() {
        View view = getView();
        if (view == null) return;
        LinearLayout rows = view.findViewById(R.id.account_content_rows);
        rows.removeAllViews();
        addRow(rows, R.drawable.ic_feature_dictionary, R.color.tile_sand, "词包与回复模板",
            "在社区里浏览并保存", () -> openCommunity(CommunityRequest.Kind.DICTIONARY));
        divider(rows);
        addRow(rows, R.drawable.ic_feature_skin, R.color.tile_pink, "社区皮肤",
            "保存后在键盘的皮肤面板里选用", () -> openCommunity(CommunityRequest.Kind.SKIN));
        divider(rows);
        addRow(rows, R.drawable.ic_tab_community, R.color.tile_green, "我发布的",
            "需要登录水杉账号，Android 上尚未提供", () -> unavailable(
                "发布和管理作品需要登录水杉账号。Android 宿主目前只有键盘的匿名身份，没有登录入口。"));
    }

    private void bindStorage() {
        View view = getView();
        if (view == null) return;
        LinearLayout rows = view.findViewById(R.id.account_storage_rows);
        rows.removeAllViews();
        addRow(rows, R.drawable.ic_feature_system, R.color.tile_green, "设置与词库位置",
            "读取中…", this::showStorage);
        divider(rows);
        addRow(rows, R.drawable.ic_tab_statistics, R.color.tile_grey, "打字统计",
            "记录开关、保留期和清除都在统计页", () -> openTab(R.id.tab_statistics));

        HostTask.run(this, HostStore::directory, directory -> {
            View current = getView();
            if (current == null) return;
            LinearLayout list = current.findViewById(R.id.account_storage_rows);
            if (list.getChildCount() == 0) return;
            TextView value = list.getChildAt(0).findViewById(R.id.row_value);
            value.setText(directory == null || directory.isEmpty()
                ? "尚未准备；打开一次键盘即可创建" : "本机 · 未同步到云端");
        });
    }

    private void showStorage() {
        HostTask.run(this, HostStore::directory, directory -> {
            String body = directory == null || directory.isEmpty()
                ? "键盘还没有完成首次准备，所以设置和词库还没有落盘。在任意输入框里打开一次水杉输入法就会创建。"
                : "设置、词库和统计都保存在应用私有目录下，只有这个应用能读：\n\n" + directory
                    + "\n\n卸载应用会一并删除。Android 上还没有云端同步，这些数据不会离开本机。";
            new com.google.android.material.dialog.MaterialAlertDialogBuilder(requireContext())
                .setTitle("设置与词库位置")
                .setMessage(body)
                .setPositiveButton("知道了", null)
                .show();
        });
    }

    private void showIcons() {
        SettingsSheet sheet = new SettingsSheet(requireContext(), "App 图标",
            "换掉主屏幕上的水杉。切换时桌面图标会短暂消失再出现，这是系统在重建启动项。");
        AppIconStyle current = AppIcons.selected(requireContext());
        for (AppIconStyle style : AppIconStyle.all()) {
            LinearLayout row = (LinearLayout) LayoutInflater.from(requireContext())
                .inflate(R.layout.item_setting_row, sheet.content(), false);
            ShapeableImageView badge = row.findViewById(R.id.row_badge);
            badge.setImageResource(icon(style));
            badge.setPadding(0, 0, 0, 0);
            ((TextView) row.findViewById(R.id.row_title)).setText(style.title());
            ((TextView) row.findViewById(R.id.row_value)).setText(style.description());
            TextView chevron = row.findViewById(R.id.row_chevron);
            chevron.setText(style == current ? "✓" : "");
            chevron.setTextColor(ContextCompat.getColor(requireContext(), R.color.forest));
            row.setOnClickListener(ignored -> {
                boolean changed = AppIcons.select(requireContext(), style);
                sheet.dismiss();
                bindIcons();
                View view = getView();
                if (view != null) {
                    Snackbar.make(view, changed
                        ? "已切换为「" + style.title() + "」，桌面图标稍后更新。"
                        : "系统拒绝了这次切换，图标保持不变。", Snackbar.LENGTH_LONG).show();
                }
            });
            sheet.add(row);
        }
        sheet.show();
    }

    @DrawableRes private static int icon(AppIconStyle style) {
        return switch (style) {
            case FOREST -> R.drawable.app_icon_forest;
            case SKY -> R.drawable.app_icon_sky;
            case DUSK -> R.drawable.app_icon_dusk;
            case VERMILION -> R.drawable.app_icon_vermilion;
            case CLASSIC -> R.drawable.app_icon_classic;
        };
    }

    private void openCommunity(CommunityRequest.Kind kind) {
        if (getActivity() instanceof HomeActivity home) home.openCommunity(kind);
    }

    private void openTab(int tabId) {
        if (getActivity() instanceof HomeActivity home) home.openTab(tabId);
    }

    private void unavailable(String message) {
        View view = getView();
        if (view != null) Snackbar.make(view, message, Snackbar.LENGTH_LONG).show();
    }

    private void addRow(LinearLayout parent, @DrawableRes int icon, @ColorRes int tint,
            String title, String value, Runnable action) {
        LinearLayout row = (LinearLayout) LayoutInflater.from(requireContext())
            .inflate(R.layout.item_setting_row, parent, false);
        ShapeableImageView badge = row.findViewById(R.id.row_badge);
        badge.setImageResource(icon);
        badge.setBackgroundTintList(
            ColorStateList.valueOf(ContextCompat.getColor(requireContext(), tint)));
        ((TextView) row.findViewById(R.id.row_title)).setText(title);
        ((TextView) row.findViewById(R.id.row_value)).setText(value);
        row.setOnClickListener(ignored -> action.run());
        parent.addView(row);
    }

    private void divider(LinearLayout parent) {
        View line = new View(requireContext());
        int height = Math.max(1, Math.round(
            getResources().getDisplayMetrics().density));
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, height);
        params.setMarginStart(Math.round(64 * getResources().getDisplayMetrics().density));
        line.setBackgroundColor(ContextCompat.getColor(requireContext(), R.color.hairline));
        parent.addView(line, params);
    }
}
