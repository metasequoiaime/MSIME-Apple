package app.msime.client;

import java.nio.charset.StandardCharsets;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

/** Bounded host orchestration for display-only offline candidate glosses. */
public final class CandidateGlossModel {
    public static final int MAX_CANDIDATES = 4096;
    public static final int MAX_ENTRY_BYTES = 4096;
    public static final int MAX_REQUEST_BYTES = 262_144;
    public static final int MAX_RESPONSE_BYTES = 1_048_576;

    public record Result(long generation, String translations) {
        public Result {
            if (generation < 0 || translations == null)
                throw new IllegalArgumentException("Invalid candidate gloss result");
        }
    }

    private CandidateGlossModel() {}

    /** Copy only stable display fields from one complete Engine candidate generation. */
    public static String request(long generation, JSONArray candidates) throws JSONException {
        if (generation < 0 || candidates == null || candidates.length() == 0
                || candidates.length() > MAX_CANDIDATES)
            throw new IllegalArgumentException("Invalid candidate gloss request");
        JSONArray copied = new JSONArray();
        for (int index = 0; index < candidates.length(); index++) {
            JSONObject candidate = candidates.optJSONObject(index);
            if (candidate == null) throw new IllegalArgumentException("Invalid candidate entry");
            String text = candidate.optString("text", "");
            int source = candidate.optInt("source", -1);
            if (!bounded(text) || source < 0 || source > 255)
                throw new IllegalArgumentException("Invalid candidate entry");
            copied.put(new JSONObject().put("text", text).put("source", source));
        }
        String request = new JSONObject().put("generation", generation)
            .put("candidates", copied).toString();
        if (request.getBytes(StandardCharsets.UTF_8).length > MAX_REQUEST_BYTES)
            throw new IllegalArgumentException("Candidate gloss request is too large");
        return request;
    }

    /** Validate the native envelope before returning an apply_translations payload. */
    public static Result decode(String response) throws JSONException {
        if (response == null
                || response.getBytes(StandardCharsets.UTF_8).length > MAX_RESPONSE_BYTES)
            throw new IllegalArgumentException("Candidate gloss response is too large");
        JSONObject envelope = new JSONObject(response);
        if (!envelope.optBoolean("ok", false)) throw new JSONException("Candidate gloss failed");
        JSONObject value = envelope.getJSONObject("value");
        long generation = value.getLong("generation");
        JSONArray entries = value.getJSONArray("translations");
        if (generation < 0 || entries.length() > MAX_CANDIDATES)
            throw new IllegalArgumentException("Invalid candidate gloss response");
        JSONArray copied = new JSONArray();
        for (int index = 0; index < entries.length(); index++) {
            JSONObject entry = entries.optJSONObject(index);
            if (entry == null) throw new IllegalArgumentException("Invalid candidate gloss entry");
            String text = entry.optString("text", "");
            String translation = entry.optString("translation", "");
            if (!bounded(text) || !bounded(translation))
                throw new IllegalArgumentException("Invalid candidate gloss entry");
            copied.put(new JSONObject().put("text", text).put("translation", translation));
        }
        String payload = copied.toString();
        if (payload.getBytes(StandardCharsets.UTF_8).length > MAX_RESPONSE_BYTES)
            throw new IllegalArgumentException("Candidate gloss payload is too large");
        return new Result(generation, payload);
    }

    private static boolean bounded(String value) {
        return value != null && !value.isEmpty()
            && value.getBytes(StandardCharsets.UTF_8).length <= MAX_ENTRY_BYTES;
    }
}
