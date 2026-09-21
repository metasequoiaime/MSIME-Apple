package app.msime.client.home;

import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;
import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;
import app.msime.client.CommunityCatalog;
import app.msime.client.CommunityRequest;
import app.msime.client.KeyboardSkin;
import app.msime.client.R;
import com.google.android.material.button.MaterialButton;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.function.Consumer;

/** The community listing: one card per published work. */
public final class CommunityAdapter extends RecyclerView.Adapter<CommunityAdapter.Holder> {
    private final List<CommunityCatalog.Item> items = new ArrayList<>();
    private final Consumer<CommunityCatalog.Item> onAction;

    public CommunityAdapter(Consumer<CommunityCatalog.Item> onAction) {
        this.onAction = onAction;
    }

    /** Replace the listing, for a new kind or a new search. */
    public void set(List<CommunityCatalog.Item> values) {
        items.clear();
        items.addAll(values);
        notifyDataSetChanged();
    }

    /** Append the next page, keeping what is already on screen where it is. */
    public void append(List<CommunityCatalog.Item> values) {
        if (values.isEmpty()) return;
        int start = items.size();
        items.addAll(values);
        notifyItemRangeInserted(start, values.size());
    }

    public int size() { return items.size(); }

    @NonNull @Override public Holder onCreateViewHolder(@NonNull ViewGroup parent, int type) {
        return new Holder(LayoutInflater.from(parent.getContext())
            .inflate(R.layout.item_community, parent, false));
    }

    @Override public void onBindViewHolder(@NonNull Holder holder, int position) {
        CommunityCatalog.Item item = items.get(position);
        holder.swatch.setSkin(preview(item));
        holder.name.setText(item.name());
        holder.description.setText(item.description().isEmpty()
            ? "作者没有写说明。" : item.description());
        holder.author.setText(author(item));
        holder.rating.setText(rating(item));
        boolean installable = item.kind() == CommunityRequest.Kind.SKIN && item.payload() != null;
        holder.action.setEnabled(installable);
        // 词库和回复要先有本地词库编辑器才谈得上导入，那一页还没搬过来；这里说清楚而不是给一个
        // 按下去没反应的按钮。
        holder.action.setText(installable ? "保存到皮肤库" : "暂不支持导入");
        holder.action.setOnClickListener(installable ? ignored -> onAction.accept(item) : null);
        holder.itemView.setOnClickListener(installable ? ignored -> onAction.accept(item) : null);
        holder.itemView.setClickable(installable);
        holder.itemView.setContentDescription(item.name() + "，" + author(item) + "，"
            + rating(item) + (installable ? "，点按保存到皮肤库" : "，暂不支持导入"));
    }

    /**
     * The design to draw beside a skin's name.
     *
     * <p>Resolved through the same custom-skin path the keyboard renders a saved design with, so
     * the swatch is the skin rather than an approximation of it. Anything unreadable draws nothing.
     */
    @androidx.annotation.Nullable
    private static KeyboardSkin preview(CommunityCatalog.Item item) {
        if (item.kind() != CommunityRequest.Kind.SKIN || item.payload() == null) return null;
        try {
            return KeyboardSkin.from("custom", false, item.payload());
        } catch (RuntimeException error) {
            return null;
        }
    }

    private static String author(CommunityCatalog.Item item) {
        String author = item.author().isEmpty() ? "匿名作者" : item.author();
        return item.saves() > 0 ? author + " · " + item.saves() + " 次保存" : author;
    }

    private static String rating(CommunityCatalog.Item item) {
        if (item.ratingCount() <= 0) return "暂无评分";
        return String.format(Locale.ROOT, "★ %.1f · %d 人", item.ratingAverage(),
            item.ratingCount());
    }

    @Override public int getItemCount() { return items.size(); }

    static final class Holder extends RecyclerView.ViewHolder {
        final TextView name;
        final TextView description;
        final TextView author;
        final TextView rating;
        final MaterialButton action;
        final SkinSwatchView swatch;

        Holder(@NonNull View view) {
            super(view);
            name = view.findViewById(R.id.community_item_name);
            description = view.findViewById(R.id.community_item_description);
            author = view.findViewById(R.id.community_item_author);
            rating = view.findViewById(R.id.community_item_rating);
            action = view.findViewById(R.id.community_item_action);
            swatch = view.findViewById(R.id.community_item_swatch);
        }
    }
}
