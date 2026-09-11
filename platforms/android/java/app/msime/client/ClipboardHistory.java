package app.msime.client;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/** Platform-independent clipboard history ordering and mutation rules. */
public final class ClipboardHistory {
    public static final class Item {
        private final String id;
        private final String text;
        private final long timestamp;
        private final boolean pinned;

        public Item(String id, String text, long timestamp, boolean pinned) {
            this.id = id;
            this.text = text;
            this.timestamp = timestamp;
            this.pinned = pinned;
        }

        public String id() { return id; }
        public String text() { return text; }
        public long timestamp() { return timestamp; }
        public boolean pinned() { return pinned; }
    }

    private final List<Item> items;

    public ClipboardHistory(List<Item> values) {
        if (values.size() > ClipboardHistoryPolicy.LIMIT
                || values.stream().anyMatch(item -> !ClipboardHistoryPolicy.acceptable(item.text())))
            throw new IllegalStateException("Invalid clipboard history");
        items = new ArrayList<>(values);
        sort();
    }

    public List<Item> items() { return List.copyOf(items); }

    public void add(String text, String id, long now) {
        if (!ClipboardHistoryPolicy.acceptable(text)) throw new IllegalArgumentException("Clipboard has no usable text");
        for (int index = 0; index < items.size(); index++) {
            Item item = items.get(index);
            if (item.text().equals(text)) {
                items.set(index, new Item(item.id(), item.text(), now, item.pinned()));
                sort();
                return;
            }
        }
        if (items.size() >= ClipboardHistoryPolicy.LIMIT) {
            int removable = -1;
            for (int index = items.size() - 1; index >= 0; index--) {
                if (!items.get(index).pinned()) { removable = index; break; }
            }
            if (removable < 0) throw new IllegalStateException("All clipboard entries are pinned");
            items.remove(removable);
        }
        items.add(new Item(id, text, now, false));
        sort();
    }

    public void remove(String id) { items.removeIf(item -> item.id().equals(id)); }

    public void togglePinned(String id) {
        for (int index = 0; index < items.size(); index++) {
            Item item = items.get(index);
            if (item.id().equals(id)) {
                items.set(index, new Item(item.id(), item.text(), item.timestamp(), !item.pinned()));
                sort();
                return;
            }
        }
    }

    private void sort() {
        items.sort(Comparator.comparing(Item::pinned).reversed()
            .thenComparing(Comparator.comparingLong(Item::timestamp).reversed()));
    }
}
