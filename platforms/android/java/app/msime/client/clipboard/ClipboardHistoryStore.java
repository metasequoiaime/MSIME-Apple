package app.msime.client;

import android.content.Context;
import android.content.SharedPreferences;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

/** Private, text-only Android clipboard history; it never writes clipboard contents to logs. */
public final class ClipboardHistoryStore {
    private static final String ITEMS_KEY = "items";
    private final SharedPreferences preferences;

    public ClipboardHistoryStore(Context context) {
        preferences = context.getSharedPreferences("clipboard-history", Context.MODE_PRIVATE);
    }

    public List<ClipboardHistory.Item> load() {
        String encoded = preferences.getString(ITEMS_KEY, "[]");
        try {
            JSONArray array = new JSONArray(encoded);
            if (array.length() > ClipboardHistoryPolicy.LIMIT) throw new IllegalStateException("History is full");
            List<ClipboardHistory.Item> items = new ArrayList<>();
            for (int index = 0; index < array.length(); index++) {
                JSONObject value = array.getJSONObject(index);
                String text = value.getString("text");
                if (!ClipboardHistoryPolicy.acceptable(text)) throw new IllegalStateException("Invalid history entry");
                items.add(new ClipboardHistory.Item(value.getString("id"), text, value.getLong("timestamp"),
                    value.optBoolean("pinned", false)));
            }
            return new ClipboardHistory(items).items();
        } catch (JSONException error) {
            throw new IllegalStateException("Clipboard history cannot be read", error);
        }
    }

    public void add(String text) {
        if (!ClipboardHistoryPolicy.acceptable(text)) throw new IllegalArgumentException("Clipboard has no usable text");
        ClipboardHistory history = new ClipboardHistory(load());
        long now = System.currentTimeMillis();
        history.add(text, UUID.randomUUID().toString(), now);
        save(history.items());
    }

    public void remove(String id) { saveWithout(id, false); }

    public void togglePinned(String id) { saveWithout(id, true); }

    public void clear() { save(List.of()); }

    private void saveWithout(String id, boolean togglePinned) {
        ClipboardHistory history = new ClipboardHistory(load());
        if (togglePinned) history.togglePinned(id); else history.remove(id);
        save(history.items());
    }

    private void save(List<ClipboardHistory.Item> items) {
        JSONArray array = new JSONArray();
        try {
            for (ClipboardHistory.Item item : items) {
                array.put(new JSONObject().put("id", item.id()).put("text", item.text())
                    .put("timestamp", item.timestamp()).put("pinned", item.pinned()));
            }
        } catch (JSONException error) {
            throw new IllegalStateException("Clipboard history cannot be encoded", error);
        }
        preferences.edit().putString(ITEMS_KEY, array.toString()).apply();
    }
}
