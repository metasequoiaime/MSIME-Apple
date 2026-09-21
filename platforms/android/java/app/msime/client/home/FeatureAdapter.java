package app.msime.client.home;

import android.content.res.ColorStateList;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;
import androidx.annotation.ColorRes;
import androidx.annotation.DrawableRes;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.core.content.ContextCompat;
import androidx.recyclerview.widget.RecyclerView;
import com.google.android.material.imageview.ShapeableImageView;
import java.util.List;
import app.msime.client.R;

/** The feature squares under the keyboard card. */
public final class FeatureAdapter extends RecyclerView.Adapter<FeatureAdapter.Holder> {

    /** One square. A null action means the destination has not been built yet. */
    public static final class Feature {
        final int icon;
        final int tint;
        final String title;
        final String value;
        @Nullable final Runnable action;

        public Feature(@DrawableRes int icon, @ColorRes int tint, String title, String value,
                       @Nullable Runnable action) {
            this.icon = icon;
            this.tint = tint;
            this.title = title;
            this.value = value;
            this.action = action;
        }
    }

    private final List<Feature> features = new java.util.ArrayList<>();

    public FeatureAdapter(List<Feature> features) { this.features.addAll(features); }

    /**
     * Replace the squares in place.
     *
     * <p>Rather than handing the grid a new adapter on every render: that rebuilds all six views,
     * and the page re-renders whenever it comes back into view or a sheet saves a setting.
     */
    public void set(List<Feature> values) {
        features.clear();
        features.addAll(values);
        notifyDataSetChanged();
    }

    @NonNull @Override public Holder onCreateViewHolder(@NonNull ViewGroup parent, int type) {
        return new Holder(LayoutInflater.from(parent.getContext())
            .inflate(R.layout.item_feature, parent, false));
    }

    @Override public void onBindViewHolder(@NonNull Holder holder, int position) {
        Feature feature = features.get(position);
        holder.badge.setImageResource(feature.icon);
        holder.badge.setBackgroundTintList(
            ColorStateList.valueOf(ContextCompat.getColor(holder.itemView.getContext(), feature.tint)));
        holder.badge.setImageTintList(ColorStateList.valueOf(
            ContextCompat.getColor(holder.itemView.getContext(), R.color.forest)));
        holder.title.setText(feature.title);
        holder.value.setText(feature.value);
        holder.itemView.setEnabled(feature.action != null);
        holder.itemView.setOnClickListener(feature.action == null ? null : v -> feature.action.run());
    }

    @Override public int getItemCount() { return features.size(); }

    static final class Holder extends RecyclerView.ViewHolder {
        final ShapeableImageView badge;
        final TextView title;
        final TextView value;

        Holder(@NonNull View view) {
            super(view);
            badge = view.findViewById(R.id.feature_badge);
            title = view.findViewById(R.id.feature_title);
            value = view.findViewById(R.id.feature_value);
        }
    }
}
