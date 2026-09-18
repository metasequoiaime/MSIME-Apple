package app.msime.client;

import android.content.Context;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.Locale;
import javax.net.ssl.HttpsURLConnection;
import org.json.JSONObject;

/** Creates and persists the keyboard-only anonymous backend identity. */
final class BackendAnonymousAccount {
    private static final String ORIGIN = "https://api.msime.app";
    private static final String SESSION_STORE = "msime_anonymous_session_v1";
    private static final String CREDENTIAL_STORE = "msime_anonymous_account_v1";
    private static final int MAX_RESPONSE_BYTES = 64 * 1024;
    private static final SecureRandom RANDOM = new SecureRandom();
    private static final Object LOCK = new Object();
    private final AndroidAccountSessionStorage sessions;
    private final AndroidAccountSessionStorage credentials;

    BackendAnonymousAccount(Context context) {
        sessions = new AndroidAccountSessionStorage(context, SESSION_STORE);
        credentials = new AndroidAccountSessionStorage(context, CREDENTIAL_STORE);
    }

    String accessToken() throws Exception {
        synchronized (LOCK) {
            String saved = sessions.load();
            if (saved != null) {
                String token = tokenFromSession(saved);
                if (token != null) return token;
            }
            JSONObject identity = loadOrCreateIdentity();
            JSONObject challenge = request("POST", "/v1/auth/challenges",
                new JSONObject().put("provider", "anonymous")
                    .put("target", identity.getString("subject"))
                    .put("purpose", "login"), null);
            String challengeID = challenge.optString("challenge_id", "");
            if (challengeID.isEmpty()) throw new IllegalStateException("anonymous account unavailable");
            JSONObject tokens = request("POST", "/v1/auth/login",
                new JSONObject().put("challenge_id", challengeID)
                    .put("credential", identity.getString("secret")), null);
            String token = validToken(tokens.optString("access_token", ""));
            String refresh = validToken(tokens.optString("refresh_token", ""));
            if (token == null || refresh == null || !"Bearer".equals(tokens.optString("token_type", "")))
                throw new IllegalStateException("anonymous account unavailable");
            long expires = tokens.optLong("expires_in", 0);
            if (expires <= 0 || expires > 86_400 * 30L) throw new IllegalStateException("anonymous account unavailable");
            JSONObject savedSession = new JSONObject().put("tokens", tokens)
                .put("expires_at_unix_ms", System.currentTimeMillis() + expires * 1000L);
            sessions.save(savedSession.toString());
            return token;
        }
    }

    private JSONObject loadOrCreateIdentity() throws Exception {
        String saved = credentials.load();
        if (saved != null) {
            JSONObject identity = new JSONObject(saved);
            if (identity.optString("subject", "").matches("msime-[a-z0-9]{16}")
                    && identity.optString("secret", "").matches("[a-z0-9]{48}")) return identity;
        }
        JSONObject identity = new JSONObject().put("subject", "msime-" + random(16))
            .put("secret", random(48));
        credentials.save(identity.toString());
        return identity;
    }

    private static String random(int length) {
        final char[] alphabet = "abcdefghijklmnopqrstuvwxyz0123456789".toCharArray();
        StringBuilder value = new StringBuilder(length);
        for (int index = 0; index < length; index++) value.append(alphabet[RANDOM.nextInt(alphabet.length)]);
        return value.toString();
    }

    private static String tokenFromSession(String encoded) {
        try {
            JSONObject session = new JSONObject(encoded);
            long expiry = session.optLong("expires_at_unix_ms", 0);
            if (expiry <= System.currentTimeMillis() + 30_000L) return null;
            return validToken(session.getJSONObject("tokens").optString("access_token", ""));
        } catch (Exception ignored) { return null; }
    }

    private static String validToken(String token) {
        return token.matches("[0-9a-fA-F]{64}") ? token : null;
    }

    private static JSONObject request(String method, String path, JSONObject body, String token) throws Exception {
        byte[] payload = body == null ? null : body.toString().getBytes(StandardCharsets.UTF_8);
        HttpsURLConnection connection = null;
        try {
            connection = (HttpsURLConnection) new URL(ORIGIN + path).openConnection();
            connection.setInstanceFollowRedirects(false);
            connection.setRequestMethod(method);
            connection.setConnectTimeout(30_000);
            connection.setReadTimeout(30_000);
            connection.setRequestProperty("Accept", "application/json");
            connection.setRequestProperty("User-Agent", "MSIME/Android");
            if (token != null) connection.setRequestProperty("Authorization", "Bearer " + token);
            if (payload != null) {
                connection.setDoOutput(true);
                connection.setFixedLengthStreamingMode(payload.length);
                connection.setRequestProperty("Content-Type", "application/json");
                try (OutputStream output = connection.getOutputStream()) { output.write(payload); }
            }
            if (connection.getResponseCode() != 200) throw new IllegalStateException("anonymous account unavailable");
            try (InputStream input = connection.getInputStream()) {
                return new JSONObject(new String(readBounded(input), StandardCharsets.UTF_8));
            }
        } finally { if (connection != null) connection.disconnect(); }
    }

    private static byte[] readBounded(InputStream input) throws Exception {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        byte[] buffer = new byte[4096]; int count;
        while ((count = input.read(buffer)) != -1) {
            if (output.size() + count > MAX_RESPONSE_BYTES) throw new IllegalStateException("anonymous account unavailable");
            output.write(buffer, 0, count);
        }
        return output.toByteArray();
    }
}
