package app.msime.client.home;

import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.view.inputmethod.EditorInfo;
import android.widget.TextView;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.fragment.app.Fragment;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import app.msime.client.CommunityCatalog;
import app.msime.client.CommunityRequest;
import app.msime.client.R;
import com.google.android.material.button.MaterialButton;
import com.google.android.material.snackbar.Snackbar;
import com.google.android.material.tabs.TabLayout;
import com.google.android.material.textfield.TextInputEditText;
import com.google.android.material.textfield.TextInputLayout;
import java.nio.file.Paths;

/**
 * The 社区 tab: skins, dictionaries and reply templates published by other people.
 *
 * Read-only. Publishing and rating need a signed-in account, and this host carries only the
 * keyboard's anonymous identity; a publish button that always answers "请先登录" would be worse
 * than the honest absence of one. Saving a skin, which is what people open this tab to do, works.
 */
public final class CommunityFragment extends Fragment {
    private static final String ARG_KIND = "kind";

    private CommunityRequest.Kind kind = CommunityRequest.Kind.SKIN;
    private CommunityAdapter adapter;
    private String search = "";
    private boolean loading;
    private boolean hasMore;

    /** The tab, opened on one kind of work; a null kind opens on skins. */
    public static CommunityFragment forKind(@Nullable CommunityRequest.Kind kind) {
        CommunityFragment fragment = new CommunityFragment();
        if (kind != null) {
            Bundle arguments = new Bundle();
            arguments.putString(ARG_KIND, kind.id());
            fragment.setArguments(arguments);
        }
        return fragment;
    }

    @Override public View onCreateView(@NonNull LayoutInflater inflater, @Nullable ViewGroup parent,
                                       @Nullable Bundle state) {
        return inflater.inflate(R.layout.page_community, parent, false);
    }

    @Override public void onViewCreated(@NonNull View view, @Nullable Bundle state) {
        Bundle arguments = getArguments();
        if (arguments != null) {
            for (CommunityRequest.Kind value : CommunityRequest.kinds()) {
                if (value.id().equals(arguments.getString(ARG_KIND))) kind = value;
            }
        }
        TabLayout kinds = view.findViewById(R.id.community_kinds);
        for (CommunityRequest.Kind value : CommunityRequest.kinds()) {
            kinds.addTab(kinds.newTab().setText(value.title()));
        }
        kinds.addOnTabSelectedListener(new TabLayout.OnTabSelectedListener() {
            @Override public void onTabSelected(TabLayout.Tab tab) {
                kind = CommunityRequest.kinds().get(tab.getPosition());
                updateSearchHint();
                load(true);
            }

            @Override public void onTabUnselected(TabLayout.Tab tab) {}

            @Override public void onTabReselected(TabLayout.Tab tab) {}
        });

        adapter = new CommunityAdapter(this::install);
        RecyclerView items = view.findViewById(R.id.community_items);
        items.setLayoutManager(new LinearLayoutManager(requireContext()));
        items.setAdapter(adapter);
        items.addOnScrollListener(new RecyclerView.OnScrollListener() {
            @Override public void onScrolled(@NonNull RecyclerView list, int dx, int dy) {
                if (dy <= 0 || loading || !hasMore) return;
                LinearLayoutManager manager = (LinearLayoutManager) list.getLayoutManager();
                if (manager == null) return;
                // One screen of slack so the next page is already arriving when the last card is
                // reached, rather than after a stop at the bottom.
                if (manager.findLastVisibleItemPosition()
                    >= adapter.size() - CommunityRequest.PAGE_SIZE / 4) load(false);
            }
        });

        TextInputEditText field = view.findViewById(R.id.community_search);
        field.setOnEditorActionListener((text, action, event) -> {
            if (action != EditorInfo.IME_ACTION_SEARCH) return false;
            search = text.getText() == null ? "" : text.getText().toString();
            load(true);
            return true;
        });

        MaterialButton retry = view.findViewById(R.id.community_retry);
        retry.setOnClickListener(ignored -> load(true));

        TabLayout.Tab opening = kinds.getTabAt(CommunityRequest.kinds().indexOf(kind));
        if (opening != null && !opening.isSelected()) {
            // Selecting the tab loads the listing through the listener; doing both would issue the
            // first request twice.
            opening.select();
        } else {
            load(true);
        }
        updateSearchHint();
    }

    private void updateSearchHint() {
        View view = getView();
        if (view == null) return;
        ((TextInputLayout) view.findViewById(R.id.community_search_field))
            .setHint(kind.searchHint());
    }

    private void load(boolean fresh) {
        View view = getView();
        if (view == null || loading) return;
        loading = true;
        int offset = fresh ? 0 : adapter.size();
        if (fresh) {
            hasMore = false;
            adapter.set(java.util.List.of());
            state("正在载入…", false);
        }
        CommunityRequest.Kind requested = kind;
        String term = search;
        HostTask.run(this,
            context -> new CommunityCatalog(context).list(requested, term, offset),
            page -> {
                loading = false;
                if (page == null) {
                    state(CommunityRequest.message(null, 0), true);
                    return;
                }
                // The tab or the search may have moved on while this page was in flight; a stale
                // answer must not replace what the user is now looking at.
                if (requested != kind || !term.equals(search)) return;
                if (page.failed()) {
                    state(page.failure(), true);
                    return;
                }
                hasMore = page.hasMore();
                if (offset == 0) adapter.set(page.items()); else adapter.append(page.items());
                state(adapter.size() == 0 ? emptyMessage() : "", false);
            });
    }

    private String emptyMessage() {
        return search.isEmpty()
            ? "社区里还没有公开的" + kind.title() + "。"
            : "没有找到匹配「" + search + "」的" + kind.title() + "。";
    }

    private void state(String message, boolean retryable) {
        View view = getView();
        if (view == null) return;
        TextView state = view.findViewById(R.id.community_state);
        state.setText(message);
        state.setVisibility(message.isEmpty() ? View.GONE : View.VISIBLE);
        view.findViewById(R.id.community_retry)
            .setVisibility(retryable ? View.VISIBLE : View.GONE);
    }

    private void install(CommunityCatalog.Item item) {
        HostTask.run(this, context -> {
            String directory = HostStore.directory(context);
            if (directory.isEmpty()) return "键盘还没有完成首次准备，请先打开一次键盘。";
            return new CommunityCatalog(context).install(Paths.get(directory), item);
        }, failure -> {
            View view = getView();
            if (view == null) return;
            Snackbar.make(view, failure == null || failure.isEmpty()
                ? "已保存到皮肤库，在键盘的皮肤面板里选用。" : failure,
                Snackbar.LENGTH_LONG).show();
        });
    }
}
