package app.msime.client;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

/**
 * Sends one transcript through the user's AI service and returns the rewrite.
 *
 * <p>Best effort by construction: polishing improves a transcript the user already has, so every
 * failure returns null and the caller keeps the original. Losing a recognised sentence because a
 * rewrite service was unreachable would be a worse outcome than not polishing it.
 */
public final class VoicePolisher {
    private static final int CONNECT_TIMEOUT_MILLIS = 5_000;
    private static final int READ_TIMEOUT_MILLIS = 60_000;
    private static final int MAX_RESPONSE_BYTES = 1024 * 1024;

    private VoicePolisher() {}

    /** The polished text, or null to keep what was recognised. */
    public static String polish(String endpoint, String model, String token, String prompt,
                                String text) {
        if (!VoicePolishPolicy.usable(endpoint, model, token, prompt)
                || !VoicePolishPolicy.sendable(text)) {
            return null;
        }
        byte[] body = VoicePolishPolicy.requestBody(model, prompt, text)
            .getBytes(StandardCharsets.UTF_8);
        HttpURLConnection connection = null;
        try {
            connection = (HttpURLConnection) new URL(endpoint).openConnection();
            connection.setConnectTimeout(CONNECT_TIMEOUT_MILLIS);
            connection.setReadTimeout(READ_TIMEOUT_MILLIS);
            connection.setRequestMethod("POST");
            connection.setDoOutput(true);
            connection.setFixedLengthStreamingMode(body.length);
            connection.setRequestProperty("Authorization", "Bearer " + token);
            connection.setRequestProperty("Content-Type", "application/json");
            connection.setRequestProperty("Accept", "application/json");
            try (OutputStream out = connection.getOutputStream()) {
                out.write(body);
            }
            int status = connection.getResponseCode();
            if (status < 200 || status >= 300) return null;
            String content = content(read(connection.getInputStream()));
            return VoicePolishPolicy.sendable(content) ? content.trim() : null;
        } catch (IOException error) {
            return null;
        } finally {
            if (connection != null) connection.disconnect();
        }
    }

    private static String read(InputStream stream) throws IOException {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        byte[] chunk = new byte[8192];
        int read;
        while ((read = stream.read(chunk)) > 0 && out.size() < MAX_RESPONSE_BYTES) {
            out.write(chunk, 0, read);
        }
        return out.toString(StandardCharsets.UTF_8.name());
    }

    private static String content(String response) {
        try {
            JSONArray choices = new JSONObject(response).optJSONArray("choices");
            JSONObject first = choices == null ? null : choices.optJSONObject(0);
            JSONObject message = first == null ? null : first.optJSONObject("message");
            return message == null ? "" : message.optString("content", "");
        } catch (JSONException error) {
            return "";
        }
    }
}
