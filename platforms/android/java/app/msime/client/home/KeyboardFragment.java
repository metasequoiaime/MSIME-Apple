package app.msime.client.home;

import android.content.Intent;
import android.os.Bundle;
import android.provider.Settings;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.view.inputmethod.InputMethodInfo;
import android.view.inputmethod.InputMethodManager;
import android.widget.TextView;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.recyclerview.widget.GridLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import app.msime.client.KeyboardScheme;
import app.msime.client.KeyboardSkin;
import app.msime.client.R;
import com.google.android.material.button.MaterialButton;
import com.google.android.material.chip.Chip;
import java.util.ArrayList;
import java.util.List;
import app.msime.client.FirstRunPreparation;
import app.msime.client.R;
import org.json.JSONObject;

/** The 键盘 tab: what the keyboard currently is, a way to try it, and the way in to each group. */
public final class KeyboardFragment extends HomeTabFragment {
    private static final String SERVICE = "app.msime.client.MSIMEInputService";

    @Nullable private JSONObject snapshot;
    private FeatureAdapter features;
    private boolean loaded;
    private boolean prepared = true;

    @Override public View onCreateView(@NonNull LayoutInflater inflater, @Nullable ViewGroup parent,
                                       @Nullable Bundle state) {
        return inflater.inflate(R.layout.page_keyboard, parent, false);
    }

    @Override public void onViewCreated(@NonNull View view, @Nullable Bundle state) {
        MaterialButton trial = view.findViewById(R.id.keyboard_try);
        // The Apple app opens an editor here rather than the system picker: trying the keyboard
        // means typing with it, and the picker only offers to switch away from it.
        trial.setOnClickListener(ignored ->
            startActivity(new Intent(requireContext(), KeyboardTryoutActivity.class)));

        features = new FeatureAdapter(java.util.List.of());
        RecyclerView grid = view.findViewById(R.id.keyboard_features);
        grid.setLayoutManager(new GridLayoutManager(requireContext(), 3));
        grid.setAdapter(features);
        render();
        reload();

        // Preparation is silent while it works out and while it is done; it only takes the screen
        // when the keyboard cannot reach the Engine, which is the one case the user has to know.
        TextView preparation = view.findViewById(R.id.keyboard_preparation);
        preparation.setOnClickListener(ignored -> FirstRunPreparation.retry(requireContext()));
        FirstRunPreparation.observe(status -> {
            if (!isAdded()) return;
            switch (status) {
                case RUNNING -> {
                    preparation.setText(R.string.preparation_running);
                    preparation.setClickable(false);
                    preparation.setVisibility(View.VISIBLE);
                }
                case FAILED -> {
                    preparation.setText(R.string.preparation_failed);
                    preparation.setClickable(true);
                    preparation.setVisibility(View.VISIBLE);
                }
                default -> {
                    preparation.setVisibility(View.GONE);
                    // The store only becomes readable once preparation finishes, so the tiles have
                    // to be asked again; otherwise they keep saying 尚未准备 until the tab is left.
                    reload();
                }
            }
        });
    }

    @Override public void onDestroyView() {
        FirstRunPreparation.observe(null);
        super.onDestroyView();
    }

    // The keyboard's own pickers write the same file, so what this tab shows can go stale while
    // the user is in the keyboard rather than in here.
    @Override protected void onBecameVisible() { reload(); }

    private void reload() {
        HostTask.run(this, context -> {
            boolean ready = HostStore.prepared(context);
            return new Object[] {ready, ready ? HostStore.loadPreferences(context) : null};
        }, result -> {
            if (result != null) {
                prepared = Boolean.TRUE.equals(result[0]);
                if (result[1] instanceof JSONObject value) snapshot = value;
            }
            loaded = true;
            render();
        });
    }

    private void render() {
        View view = getView();
        if (view == null) return;
        JSONObject preferences = snapshot == null ? null : snapshot.optJSONObject("preferences");

        // Three states, and they are not the same sentence: still reading, never prepared, and
        // prepared but unreadable. A fresh install is the second one, and calling that a failure
        // sends the user looking for a fault instead of at the one step that is missing.
        String pending = !loaded ? "读取中…" : prepared ? "读取失败" : "尚未准备";
        String skin = pending;
        String scheme = pending;
        if (preferences != null) {
            boolean dark = KeyboardSkin.resolveDark(
                preferences.optString("screen_keyboard_theme", "follow"),
                preferences.optString("theme", "system"), false);
            KeyboardSkin resolved = KeyboardSkin.from(
                preferences.optString("touch_keyboard_skin", "forest"), dark,
                preferences.optJSONObject("custom_touch_keyboard_skin"));
            String layout = preferences.optString("touch_keyboard_layout", "twenty_six_key");
            KeyboardScheme selected = KeyboardScheme.fromPreferences(
                preferences.optString("scheme", "quanpin"),
                preferences.optString("shuangpin_profile", "xiaohe"), layout);
            skin = resolved.title();
            scheme = selected.title();
            // The picture is of this keyboard, not of a keyboard: a fixed nine-key grid in fixed
            // colours under a caption naming the user's own 26-key layout contradicted itself.
            ((KeyboardPreview) view.findViewById(R.id.keyboard_preview)).setKeyboard(
                resolved, "nine_key".equals(layout), selected.glyph() + selected.badge());
        }
        ((TextView) view.findViewById(R.id.keyboard_summary)).setText(skin + " · " + scheme);

        Chip look = view.findViewById(R.id.keyboard_look);
        boolean ready = isReady();
        look.setText(!prepared ? "待准备" : ready ? "已启用" : "未启用");
        look.setOnClickListener(ignored ->
            startActivity(new Intent(Settings.ACTION_INPUT_METHOD_SETTINGS)));

        List<FeatureAdapter.Feature> tiles = new ArrayList<>();
        tiles.add(new FeatureAdapter.Feature(R.drawable.ic_feature_skin, R.color.badge_field,
            "皮肤", skin, preferences == null ? null
                : () -> KeyboardSheets.showSkins(this, snapshot, this::reload)));
        tiles.add(new FeatureAdapter.Feature(R.drawable.ic_feature_scheme, R.color.badge_field,
            "输入方案", scheme, preferences == null ? null
                : () -> KeyboardSheets.showSchemes(this, snapshot, this::reload)));
        tiles.add(new FeatureAdapter.Feature(R.drawable.ic_feature_keys, R.color.badge_field,
            "按键", keysSummary(preferences), preferences == null ? null
                : () -> KeyboardSheets.showKeys(this, snapshot, this::reload)));
        tiles.add(new FeatureAdapter.Feature(R.drawable.ic_feature_dictionary, R.color.badge_field,
            "词库", dictionarySummary(preferences), preferences == null ? null
                : () -> KeyboardSheets.showInputFeatures(this, snapshot, this::reload)));
        tiles.add(new FeatureAdapter.Feature(R.drawable.ic_feature_dictionary, R.color.badge_field,
            "个人词库", "查询、编辑和导入用户词条", this::openPersonalDictionary));
        tiles.add(new FeatureAdapter.Feature(R.drawable.ic_feature_ai, R.color.badge_field,
            "AI", aiSummary(preferences), preferences == null ? null
                : () -> KeyboardSheets.showAi(this, snapshot, this::reload)));
        tiles.add(new FeatureAdapter.Feature(R.drawable.ic_feature_system, R.color.badge_field,
            "系统设置", ready ? "已启用" : "启用与切换",
            () -> startActivity(new Intent(Settings.ACTION_INPUT_METHOD_SETTINGS))));

        this.features.set(tiles);
    }

    /** Keep the dictionary editor in the shared Tauri UI while exposing it from the native shell. */
    private void openPersonalDictionary() {
        if (!tauriAvailable()) {
            android.widget.Toast.makeText(requireContext(),
                "个人词库需要管理界面合包，请使用 Tauri 合包打开。", android.widget.Toast.LENGTH_LONG)
                .show();
            return;
        }
        Intent intent = new Intent();
        intent.setClassName(requireContext(), "app.msime.client.MainActivity");
        intent.putExtra("msime_settings_page", "dictionary");
        startActivity(intent);
    }

    /** The standalone native APK deliberately has no WebView; the Tauri bundle does. */
    private boolean tauriAvailable() {
        try {
            Class.forName("app.msime.client.MainActivity");
            return true;
        } catch (ClassNotFoundException error) {
            return false;
        }
    }

    private String keysSummary(@Nullable JSONObject preferences) {
        if (preferences == null) return !loaded ? "读取中…" : prepared ? "读取失败" : "尚未准备";
        int height = preferences.optInt("touch_keyboard_height_adjustment", 0);
        return height == 0 ? "标准高度" : "高度 " + (height > 0 ? "+" : "") + height;
    }

    private String dictionarySummary(@Nullable JSONObject preferences) {
        if (preferences == null) return !loaded ? "读取中…" : prepared ? "读取失败" : "尚未准备";
        return preferences.optBoolean("learning", true) ? "记忆新词已开" : "记忆新词已关";
    }

    private String aiSummary(@Nullable JSONObject preferences) {
        if (preferences == null) return !loaded ? "读取中…" : prepared ? "读取失败" : "尚未准备";
        JSONObject ai = preferences.optJSONObject("ai_assistant");
        if (ai == null || !ai.optBoolean("enabled", false)) return "未启用";
        String model = ai.optString("model", "");
        return model.isEmpty() ? "已启用" : model;
    }

    /** Whether this host is in the system's enabled list, rather than merely installed. */
    private boolean isReady() {
        InputMethodManager manager = requireContext().getSystemService(InputMethodManager.class);
        if (manager == null) return false;
        for (InputMethodInfo info : manager.getEnabledInputMethodList()) {
            if (requireContext().getPackageName().equals(info.getPackageName())
                && SERVICE.equals(info.getServiceName())) return true;
        }
        return false;
    }
}
