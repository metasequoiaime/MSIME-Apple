package app.msime.client.home;

import android.content.Context;
import androidx.annotation.Nullable;
import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

/**
 * Reads the aggregate typing counts the input service writes.
 *
 * The file holds dates, character classes, commit sources and counts -- never the committed text --
 * and this reader keeps that boundary: it takes the daily totals and nothing else. A missing or
 * unreadable file is reported as absent rather than as zero, because the two say different things.
 */
public final class TypingStatistics {
    private TypingStatistics() {}

    /** Daily totals, most recent last, plus the two headline numbers. */
    public static final class Snapshot {
        public final int today;
        public final long total;
        public final int[] daily;

        Snapshot(int today, long total, int[] daily) {
            this.today = today;
            this.total = total;
            this.daily = daily;
        }
    }

    @Nullable public static Snapshot read(Context context) {
        File file = new File(context.getFilesDir(), "bootstrap/state/typing-statistics.json");
        if (!file.isFile()) return null;
        try {
            String text = new String(Files.readAllBytes(file.toPath()), StandardCharsets.UTF_8);
            JSONObject root = new JSONObject(text);
            JSONArray days = root.optJSONArray("daily");
            if (days == null) return null;
            int[] daily = new int[days.length()];
            for (int i = 0; i < days.length(); i++) {
                daily[i] = days.getJSONObject(i).optInt("count", 0);
            }
            int today = daily.length == 0 ? 0 : daily[daily.length - 1];
            return new Snapshot(today, root.optLong("total", 0L), daily);
        } catch (JSONException | java.io.IOException | SecurityException error) {
            // A statistics file that cannot be read is not an input fault; the page says "no record".
            return null;
        }
    }
}
