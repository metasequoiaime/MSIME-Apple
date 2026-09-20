package app.msime.client.home;

import android.content.Intent;
import android.os.Bundle;
import android.provider.Settings;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.fragment.app.Fragment;
import androidx.recyclerview.widget.GridLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import com.google.android.material.button.MaterialButton;
import java.util.Arrays;
import java.util.List;
import app.msime.client.FirstRunPreparation;
import app.msime.client.R;

/** The 键盘 tab: what the keyboard currently is, a way to try it, and the way in to each group. */
public final class KeyboardFragment extends Fragment {

    @Override public View onCreateView(@NonNull LayoutInflater inflater, @Nullable ViewGroup parent,
                                       @Nullable Bundle state) {
        return inflater.inflate(R.layout.page_keyboard, parent, false);
    }

    @Override public void onViewCreated(@NonNull View view, @Nullable Bundle state) {
        // Shipped defaults until the preferences reader lands; not invented values.
        String skin = "水杉绿";
        String scheme = "全拼 9 键";
        ((TextView) view.findViewById(R.id.keyboard_summary)).setText(skin + " · " + scheme);

        MaterialButton trial = view.findViewById(R.id.keyboard_try);
        // The Apple app opens an editor here rather than the system picker: trying the keyboard
        // means typing with it, and the picker only offers to switch away from it.
        trial.setOnClickListener(ignored ->
            startActivity(new Intent(requireContext(), KeyboardTryoutActivity.class)));

        List<FeatureAdapter.Feature> features = Arrays.asList(
            new FeatureAdapter.Feature(R.drawable.ic_feature_skin, R.color.tile_pink, "皮肤", skin, null),
            new FeatureAdapter.Feature(R.drawable.ic_feature_scheme, R.color.tile_green, "输入方案", scheme, null),
            new FeatureAdapter.Feature(R.drawable.ic_feature_keys, R.color.tile_violet, "按键", "间距与语音", null),
            new FeatureAdapter.Feature(R.drawable.ic_feature_dictionary, R.color.tile_sand, "词库", "个人词与同步", null),
            new FeatureAdapter.Feature(R.drawable.ic_feature_ai, R.color.tile_amber, "AI", "回复与润色", null),
            new FeatureAdapter.Feature(R.drawable.ic_feature_system, R.color.tile_grey, "系统设置", "启用与完全访问",
                () -> startActivity(new Intent(Settings.ACTION_INPUT_METHOD_SETTINGS))));

        RecyclerView grid = view.findViewById(R.id.keyboard_features);
        grid.setLayoutManager(new GridLayoutManager(requireContext(), 3));
        grid.setAdapter(new FeatureAdapter(features));

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
                default -> preparation.setVisibility(View.GONE);
            }
        });
    }

    @Override public void onDestroyView() {
        FirstRunPreparation.observe(null);
        super.onDestroyView();
    }
}
