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
import app.msime.client.BackendAccount;
import app.msime.client.CommunityRequest;
import app.msime.client.GoogleSignInFlow;
import app.msime.client.R;
import com.google.android.material.imageview.ShapeableImageView;
import com.google.android.material.snackbar.Snackbar;

/**
 * The 我的 tab: who this device is to the backend, what the app looks like, and where content is.
 *
 * 这台设备的身份是自己生成的，不存在登录这一步，所以这一页也不提登录。What it shows is the
 * device's own anonymous identity -- the one the community catalogue is read with -- and the rows
 * are the things this host can actually do with it.
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
        bindSignIn();
        bindIcons();
        bindContent();
        bindStorage();
        ((TextView) view.findViewById(R.id.account_note)).setText(
            "这个身份由本机自动生成，不需要注册或登录。它只用来读取社区目录，不携带你的输入内容，也不在设备之间同步。");
    }

    private void bind(String subject) {
        View view = getView();
        if (view == null) return;
        TextView subtitle = view.findViewById(R.id.account_subtitle);
        subtitle.setText(subject.isEmpty()
            ? "本机身份读取失败"
            : "本机身份 " + AccountIdentity.shortSubject(subject));
    }

    /**
     * 登录那一块。
     *
     * <p>Three states and they are not the same sentence: signed in, offered, and absent. The offer
     * only appears when the backend says it accepts Google and this build carries a client ID --
     * `/v1/auth/providers` answers false for a provider with no client ID configured, and a button
     * that is certain to fail is worse than no button.
     */
    private void bindSignIn() {
        View view = getView();
        if (view == null) return;
        LinearLayout rows = view.findViewById(R.id.account_sign_in_rows);
        rows.removeAllViews();
        String clientId = getString(R.string.google_server_client_id);
        HostTask.run(this, context -> {
            BackendAccount account = new BackendAccount(context);
            if (account.signedIn()) return "signed-in";
            return clientId.isEmpty() || !account.supports("google") ? "" : "offer";
        }, state -> {
            View current = getView();
            if (current == null || state == null || state.isEmpty()) return;
            LinearLayout list = current.findViewById(R.id.account_sign_in_rows);
            list.removeAllViews();
            if ("signed-in".equals(state)) {
                addRow(list, R.drawable.ic_tab_account, R.color.badge_field,
                    getString(R.string.account_signed_in), getString(R.string.account_sign_out),
                    this::signOut);
            } else {
                addRow(list, R.drawable.ic_tab_account, R.color.badge_field,
                    getString(R.string.account_sign_in_google),
                    getString(R.string.account_sign_in_hint), this::signIn);
            }
        });
    }

    /** Challenge, Google, exchange -- each step off the main thread, the chooser on it. */
    private void signIn() {
        String clientId = getString(R.string.google_server_client_id);
        HostTask.run(this, context -> {
            try {
                return new BackendAccount(context).challenge("google", null);
            } catch (Exception | LinkageError error) {
                return null;
            }
        }, challenge -> {
            if (challenge == null) {
                note("现在无法开始 Google 登录，请稍后再试。");
                return;
            }
            GoogleSignInFlow.start(requireActivity(), clientId, challenge.nonce(),
                java.util.concurrent.Executors.newSingleThreadExecutor(),
                new GoogleSignInFlow.Listener() {
                    @Override public void onToken(String idToken) {
                        HostTask.run(AccountFragment.this, context -> {
                            try {
                                new BackendAccount(context).login(challenge, idToken);
                                return "";
                            } catch (Exception | LinkageError error) {
                                return "登录没有完成：" + error.getMessage();
                            }
                        }, failure -> {
                            if (failure == null || failure.isEmpty()) render();
                            else note(failure);
                        });
                    }

                    @Override public void onFailure(String message) {
                        requireActivity().runOnUiThread(() -> note(message));
                    }
                });
        });
    }

    private void signOut() {
        HostTask.run(this, context -> {
            new BackendAccount(context).signOut();
            return "";
        }, ignored -> render());
    }

    private void note(String message) {
        View view = getView();
        if (view != null) Snackbar.make(view, message, Snackbar.LENGTH_LONG).show();
    }

    private void bindIcons() {
        View view = getView();
        if (view == null) return;
        LinearLayout rows = view.findViewById(R.id.account_personal_rows);
        rows.removeAllViews();
        AppIconStyle current = AppIcons.selected(requireContext());
        addRow(rows, R.drawable.ic_feature_skin, R.color.badge_field, "App 图标",
            current.title() + " · " + current.description(), this::showIcons);
    }

    private void bindContent() {
        View view = getView();
        if (view == null) return;
        LinearLayout rows = view.findViewById(R.id.account_content_rows);
        rows.removeAllViews();
        addRow(rows, R.drawable.ic_feature_dictionary, R.color.badge_field, "词包与回复模板",
            "在社区里浏览并保存", () -> openCommunity(CommunityRequest.Kind.DICTIONARY));
        divider(rows);
        addRow(rows, R.drawable.ic_feature_skin, R.color.badge_field, "社区皮肤",
            "保存后在键盘的皮肤面板里选用", () -> openCommunity(CommunityRequest.Kind.SKIN));
        // 「我发布的」那一行去掉了：它唯一的作用是告诉用户去登录一个这里不存在、也不需要的账号。
    }

    private void bindStorage() {
        View view = getView();
        if (view == null) return;
        LinearLayout rows = view.findViewById(R.id.account_storage_rows);
        rows.removeAllViews();
        addRow(rows, R.drawable.ic_feature_system, R.color.badge_field, "设置与词库位置",
            "读取中…", this::showStorage);
        divider(rows);
        addRow(rows, R.drawable.ic_tab_statistics, R.color.badge_field, "打字统计",
            "记录开关、保留期和清除都在统计页", () -> openTab(R.id.tab_statistics));
        divider(rows);
        addRow(rows, R.drawable.ic_feature_system, R.color.badge_field, "关于水杉",
            "版本、电脑版下载、开源与隐私", () -> startActivity(
                new android.content.Intent(requireContext(), AboutActivity.class)));

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
            // 这一行画的是图标本身，不是字形：不着色，也不要那块底。
            badge.setImageResource(icon(style));
            badge.setBackground(null);
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

    private void addRow(LinearLayout parent, @DrawableRes int icon, @ColorRes int tint,
            String title, String value, Runnable action) {
        LinearLayout row = (LinearLayout) LayoutInflater.from(requireContext())
            .inflate(R.layout.item_setting_row, parent, false);
        ShapeableImageView badge = row.findViewById(R.id.row_badge);
        badge.setImageResource(icon);
        badge.setBackgroundTintList(
            ColorStateList.valueOf(ContextCompat.getColor(requireContext(), tint)));
        badge.setImageTintList(ColorStateList.valueOf(
            ContextCompat.getColor(requireContext(), R.color.forest)));
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
