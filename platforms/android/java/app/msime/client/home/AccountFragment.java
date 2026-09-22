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
        addRow(rows, R.drawable.ic_feature_dictionary, R.color.badge_field, "云剪贴板",
            "在设备之间同步你明确添加的内容", () -> startActivity(new android.content.Intent(
                requireContext(), CloudClipboardActivity.class)));
        addRow(rows, R.drawable.ic_feature_dictionary, R.color.badge_field, "云词库",
            "管理云端词条、个人候选和词库快照", this::openCloudDictionary);
        addRow(rows, R.drawable.ic_feature_ai, R.color.badge_field, "社区作品",
            "发布、收藏皮肤、词库和回复", this::openCommunityAccount);
    }

    /** Open the shared Tauri mobile panel; dictionary UI stays in the common settings surface. */
    private void openCloudDictionary() {
        android.content.Intent intent = new android.content.Intent();
        intent.setClassName(requireContext(), "app.msime.client.MainActivity");
        intent.putExtra("msime_mobile_panel", "cloud-dictionary");
        startActivity(intent);
    }

    private void openCommunityAccount() {
        android.content.Intent intent = new android.content.Intent();
        intent.setClassName(requireContext(), "app.msime.client.MainActivity");
        intent.putExtra("msime_settings_page", "account");
        startActivity(intent);
    }

    /**
     * 最后一段：电脑版下载和关于，和母版 `AccountSettingsView` 的末段一样。
     *
     * <p>词包与回复模板、社区皮肤、打字统计三行去掉了——它们只是跳到底部那三个 tab 里已有的地方；
     * 设置与词库位置说的是一个路径，没人会从这一页找它。Apple 那边这四行一个都没有，这一页要放的是
     * 别处没有的东西。
     *
     * <p>母版那一段还有第三行「重新查看新手引导」。Android 没有可重看的引导——启动时那段动画是个
     * 700ms 的标，不是一趟流程，所以这一行没有对应物，空着比放一个点了没反应的入口好。
     */
    private void bindContent() {
        View view = getView();
        if (view == null) return;
        LinearLayout rows = view.findViewById(R.id.account_storage_rows);
        rows.removeAllViews();
        addRow(rows, R.drawable.ic_about_desktop, R.color.badge_field, "电脑版下载",
            "macOS、Windows、Linux 的安装包与指南", () -> startActivity(
                new android.content.Intent(requireContext(), DesktopDownloadActivity.class)));
        divider(rows);
        addRow(rows, R.drawable.ic_feature_system, R.color.badge_field, "关于水杉",
            "版本、开源与隐私", () -> startActivity(
                new android.content.Intent(requireContext(), AboutActivity.class)));
        divider(rows);
        addRow(rows, R.drawable.ic_feature_ai, R.color.badge_field, "重新查看新手引导",
            "四步走完键盘的启用和设置", () -> startActivity(
                new android.content.Intent(requireContext(), OnboardingActivity.class)));
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
