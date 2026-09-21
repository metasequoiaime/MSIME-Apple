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
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.function.Consumer;

/** The community listing: one card per published work. */
public final class CommunityAdapter extends RecyclerView.Adapter<CommunityAdapter.Holder> {
    private final List<CommunityCatalog.Item> items = new ArrayList<>();
    private final Consumer<CommunityCatalog.Item> onOpen;

    /**
     * @param onOpen open the detail sheet, which is where a work is looked at and saved
     */
    public CommunityAdapter(Consumer<CommunityCatalog.Item> onOpen) {
        this.onOpen = onOpen;
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
        // 卡片上不再有「保存到皮肤库」：这张卡只有一个 52dp 的色块，凭它决定不了要不要用，
        // 一个摆在外面的保存按钮等于请人盲存。看和存都在详情里，点卡片打开它。
        holder.itemView.setOnClickListener(ignored -> onOpen.accept(item));
        holder.itemView.setContentDescription(item.name() + "，" + author(item) + "，"
            + rating(item) + "，点按查看详情");
    }

    /**
     * The design to draw beside a skin's name.
     *
     * <p>Resolved through the same custom-skin path the keyboard renders a saved design with, so
     * the swatch is the skin rather than an approximation of it. Anything unreadable draws nothing.
     */
    @androidx.annotation.Nullable
    static KeyboardSkin preview(CommunityCatalog.Item item) {
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
        final SkinSwatchView swatch;

        Holder(@NonNull View view) {
            super(view);
            name = view.findViewById(R.id.community_item_name);
            description = view.findViewById(R.id.community_item_description);
            author = view.findViewById(R.id.community_item_author);
            rating = view.findViewById(R.id.community_item_rating);
            swatch = view.findViewById(R.id.community_item_swatch);
        }
    }
}
