package app.msime.client.home;

import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.fragment.app.Fragment;
import com.google.android.material.tabs.TabLayout;
import app.msime.client.R;

/**
 * The 社区 tab: skins, dictionaries and replies published by other people.
 *
 * The catalogue is served by the backend, and this host has no reader for it yet -- the keyboard's own
 * community replies come through a different path. So the page shows its real chrome and states that
 * the listing is not wired up, rather than filling the grid with invented cards: a fake skin with a
 * fake author and a fake download count is worse than an honest empty state.
 */
public final class CommunityFragment extends Fragment {

    @Override public View onCreateView(@NonNull LayoutInflater inflater, @Nullable ViewGroup parent,
                                       @Nullable Bundle state) {
        return inflater.inflate(R.layout.page_community, parent, false);
    }

    @Override public void onViewCreated(@NonNull View view, @Nullable Bundle state) {
        TabLayout kinds = view.findViewById(R.id.community_kinds);
        for (String label : new String[] {"皮肤", "词库", "回复"}) {
            kinds.addTab(kinds.newTab().setText(label));
        }
    }
}
