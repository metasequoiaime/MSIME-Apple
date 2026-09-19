package app.msime.client;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import org.json.JSONArray;
import org.json.JSONObject;

/** Reads the named custom skins shared by the Android settings surface and keyboard host. */
public final class CustomSkinLibrary {
    private static final long MAX_LIBRARY_BYTES = 1_048_576;
    private static final int MAX_DESIGNS = 12;

    private CustomSkinLibrary() {}

    public record Item(String id, String name, JSONObject design) {
    }

    public static List<Item> read(Path preferencesDirectory) throws IOException {
        Path file = preferencesDirectory.resolve("CustomSkins").resolve("library.json");
        if (!Files.isRegularFile(file) || Files.size(file) > MAX_LIBRARY_BYTES)
            return List.of();
        // Files.readString arrived in API 34; this host runs from API 28, and only the real
        // APK build rejects it. Read the bytes and decode them, which every level has.
        String document = new String(Files.readAllBytes(file), StandardCharsets.UTF_8);
        final JSONArray values;
        try {
            values = new JSONArray(document);
        } catch (org.json.JSONException error) {
            return List.of();
        }
        ArrayList<Item> result = new ArrayList<>();
        for (int index = 0; index < values.length() && result.size() < MAX_DESIGNS; index++) {
            JSONObject item = values.optJSONObject(index);
            if (item == null) continue;
            String id = item.optString("id", "");
            String name = item.optString("name", "").trim();
            JSONObject design = item.optJSONObject("design");
            if (id.isEmpty() || name.isEmpty() || name.length() > 32 || design == null) continue;
            result.add(new Item(id, name, design));
        }
        return List.copyOf(result);
    }
}
