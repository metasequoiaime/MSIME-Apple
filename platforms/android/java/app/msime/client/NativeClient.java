package app.msime.client;

import java.io.BufferedInputStream;
import java.io.ByteArrayOutputStream;
import java.io.FileInputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** JNI transport for an Android IME host. Session operations use the creating thread.
 * JSON response ownership is handled inside JNI. The host parses the envelope,
 * maps handled/commit/view to InputConnection and UI, and destroys its session.
 */
public final class NativeClient {
    private static final int EMOJI_QUERY_LIMIT = 16_384;
    private static final int EMOJI_RESOURCES_LIMIT = 4_096;
    private static final int EMOJI_RESPONSE_LIMIT = 1_048_576;
    private static final int GLOSS_REQUEST_LIMIT = 262_144;
    private static final int GLOSS_RESOURCES_LIMIT = 4_096;
    private static final int GLOSS_RESPONSE_LIMIT = 1_048_576;
    static { System.loadLibrary("msime_android"); }
    private NativeClient() {}
    private static String text(byte[] value) { return new String(value, StandardCharsets.UTF_8); }
    public static String create(String options) { return text(createRaw(options.getBytes(StandardCharsets.UTF_8))); }
    public static String prepareHost(String options) { return text(prepareHostRaw(options.getBytes(StandardCharsets.UTF_8))); }
    /** Reads the current native dictionary version without creating a session. */
    public static String snapshotVersion(String options) {
        return text(snapshotVersionRaw(options.getBytes(StandardCharsets.UTF_8)));
    }
    /** Streams one NDJSON record at a time into native preparation. Call on a worker. */
    public static String snapshotPrepare(String request, String file) {
        try {
            String adjusted = replaceRecordCount(request, inspectSnapshot(file));
            return text(snapshotPrepareRaw(adjusted.getBytes(StandardCharsets.UTF_8),
                file.getBytes(StandardCharsets.UTF_8)));
        } catch (Exception error) {
            return text(snapshotPrepareRaw("{}".getBytes(StandardCharsets.UTF_8),
                "invalid".getBytes(StandardCharsets.UTF_8)));
        }
    }
    public static String snapshotDiscard(long handle) {
        if (handle <= 0) throw new IllegalArgumentException("Invalid snapshot handle");
        return text(snapshotDiscardRaw(handle));
    }
    public static String snapshotActivate(long handle, String expectedVersion) {
        if (handle <= 0) throw new IllegalArgumentException("Invalid snapshot handle");
        return text(snapshotActivateRaw(handle, expectedVersion.getBytes(StandardCharsets.UTF_8)));
    }
    /** May block on the shared file lock. Call on a worker, without a session handle. */
    public static String loadPreferences(String directory) { return text(loadPreferencesRaw(directory.getBytes(StandardCharsets.UTF_8))); }
    /** Classifies committed text in native memory and persists only aggregate counts. Call on a worker. */
    public static String typingStatistics(String request) {
        return text(typingStatisticsRaw(request.getBytes(StandardCharsets.UTF_8)));
    }
    /** Reads one bounded page from the verified packaged emoji catalog. Call on a worker. */
    public static String emojiCatalog(String query, String resources) {
        byte[] queryBytes = query.getBytes(StandardCharsets.UTF_8);
        byte[] resourcesBytes = resources.getBytes(StandardCharsets.UTF_8);
        if (queryBytes.length > EMOJI_QUERY_LIMIT || resourcesBytes.length > EMOJI_RESOURCES_LIMIT)
            throw new IllegalArgumentException("Emoji catalog request is too large");
        byte[] result = emojiCatalogRaw(queryBytes, resourcesBytes);
        if (result == null || result.length > EMOJI_RESPONSE_LIMIT)
            throw new IllegalStateException("Emoji catalog response is too large");
        return text(result);
    }
    /** Resolves copied candidates against the packaged offline dictionary. Call on a worker. */
    public static String candidateGlosses(String request, String resources) {
        byte[] requestBytes = request.getBytes(StandardCharsets.UTF_8);
        byte[] resourcesBytes = resources.getBytes(StandardCharsets.UTF_8);
        if (requestBytes.length > GLOSS_REQUEST_LIMIT
                || resourcesBytes.length > GLOSS_RESOURCES_LIMIT)
            throw new IllegalArgumentException("Candidate gloss request is too large");
        byte[] result = candidateGlossesRaw(requestBytes, resourcesBytes);
        if (result == null || result.length > GLOSS_RESPONSE_LIMIT)
            throw new IllegalStateException("Candidate gloss response is too large");
        return text(result);
    }
    /** May block on the shared file lock. Call on a worker, without a session handle. */
    public static String savePreferences(String directory, long expectedRevision, String snapshot) {
        if (expectedRevision < 0) throw new IllegalArgumentException("Invalid preferences revision");
        return text(savePreferencesRaw(directory.getBytes(StandardCharsets.UTF_8), expectedRevision,
            snapshot.getBytes(StandardCharsets.UTF_8)));
    }
    /** Applies a bounded batch of queued personal dictionary edits. Call with no active session. */
    public static String personalDictionarySync(String options) {
        return text(personalDictionarySyncRaw(options.getBytes(StandardCharsets.UTF_8)));
    }
    public static String focus(long session, boolean focused) { return text(focusRaw(session, focused)); }
    public static String setNineKeyMode(long session, boolean enabled) {
        return text(setNineKeyModeRaw(session, enabled));
    }
    public static String setEnglishMode(long session, boolean enabled) {
        return text(setEnglishModeRaw(session, enabled));
    }
    public static String character(long session, int ascii, boolean shift) {
        if (ascii < 0 || ascii > 127) throw new IllegalArgumentException("Engine character must be ASCII");
        return text(characterRaw(session, ascii, shift));
    }
    public static String command(long session, int command) { return text(commandRaw(session, command)); }
    public static String select(long session, long generation, long index) {
        if (index < 0) throw new IllegalArgumentException("Invalid candidate index");
        return text(selectRaw(session, generation, index));
    }
    public static String selectAnyCandidate(long session, long generation, long index) {
        if (index < 0) throw new IllegalArgumentException("Invalid candidate index");
        return text(selectAnyCandidateRaw(session, generation, index));
    }
    public static String pinCandidate(long session, long generation, long index) {
        if (index < 0) throw new IllegalArgumentException("Invalid candidate index");
        return text(pinCandidateRaw(session, generation, index));
    }
    public static String fixCandidatePosition(long session, long generation, long index, int position) {
        if (index < 0) throw new IllegalArgumentException("Invalid candidate index");
        return text(fixCandidatePositionRaw(session, generation, index,
            CandidateManagementAction.validatePosition(position)));
    }
    public static String clearCandidatePosition(long session, long generation, long index) {
        if (index < 0) throw new IllegalArgumentException("Invalid candidate index");
        return text(clearCandidatePositionRaw(session, generation, index));
    }
    public static String removeCandidate(long session, long generation, long index) {
        if (index < 0) throw new IllegalArgumentException("Invalid candidate index");
        return text(removeCandidateRaw(session, generation, index));
    }
    public static String chooseNineKeySpelling(long session, long generation, long index) {
        if (index < 0) throw new IllegalArgumentException("Invalid nine-key spelling index");
        return text(chooseNineKeySpellingRaw(session, generation, index));
    }
    public static String allCandidates(long session) { return text(allCandidatesRaw(session)); }
    public static String applyTranslations(long session, long generation, String translations) {
        if (generation < 0) throw new IllegalArgumentException("Invalid candidate generation");
        byte[] payload = translations.getBytes(StandardCharsets.UTF_8);
        if (payload.length > GLOSS_RESPONSE_LIMIT)
            throw new IllegalArgumentException("Candidate translations are too large");
        return text(applyTranslationsRaw(session, generation, payload));
    }
    public static String view(long session) { return text(viewRaw(session)); }
    public static String updatePreferences(long session, String snapshot) { return text(updatePreferencesRaw(session, snapshot.getBytes(StandardCharsets.UTF_8))); }
    public static String destroy(long session) { return text(destroyRaw(session)); }
    private static native byte[] createRaw(byte[] options);
    private static native byte[] prepareHostRaw(byte[] options);
    private static native byte[] snapshotVersionRaw(byte[] options);
    private static native byte[] snapshotPrepareRaw(byte[] request, byte[] file);
    private static native byte[] snapshotDiscardRaw(long handle);
    private static native byte[] snapshotActivateRaw(long handle, byte[] expectedVersion);
    private static native byte[] loadPreferencesRaw(byte[] directory);
    private static native byte[] typingStatisticsRaw(byte[] request);
    private static native byte[] emojiCatalogRaw(byte[] query, byte[] resources);
    private static native byte[] candidateGlossesRaw(byte[] request, byte[] resources);
    private static native byte[] savePreferencesRaw(byte[] directory, long expectedRevision, byte[] snapshot);
    private static native byte[] personalDictionarySyncRaw(byte[] options);
    private static native byte[] focusRaw(long session, boolean focused);
    private static native byte[] setNineKeyModeRaw(long session, boolean enabled);
    private static native byte[] setEnglishModeRaw(long session, boolean enabled);
    private static native byte[] characterRaw(long session, int ascii, boolean shift);
    private static native byte[] commandRaw(long session, int command);
    private static native byte[] selectRaw(long session, long generation, long index);
    private static native byte[] selectAnyCandidateRaw(long session, long generation, long index);
    private static native byte[] pinCandidateRaw(long session, long generation, long index);
    private static native byte[] fixCandidatePositionRaw(long session, long generation, long index,
        int position);
    private static native byte[] clearCandidatePositionRaw(long session, long generation, long index);
    private static native byte[] removeCandidateRaw(long session, long generation, long index);
    private static native byte[] chooseNineKeySpellingRaw(long session, long generation, long index);
    private static native byte[] allCandidatesRaw(long session);
    private static native byte[] applyTranslationsRaw(long session, long generation,
        byte[] translations);
    private static native byte[] viewRaw(long session);
    private static native byte[] updatePreferencesRaw(long session, byte[] snapshot);
    private static native byte[] destroyRaw(long session);

    private static final Pattern TYPE = Pattern.compile("\\\"type\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"");
    private static final Pattern RECORDS = Pattern.compile("(\\\"records\\\"\\s*:\\s*)\\d+");
    private static final Pattern FOOTER_RECORDS = Pattern.compile("\\\"records\\\"\\s*:\\s*(\\d+)");
    private static final Pattern SHA256 = Pattern.compile("\\\"sha256\\\"\\s*:\\s*\\\"([0-9a-f]{64})\\\"");

    private static String replaceRecordCount(String request, int records) {
        Matcher matcher = RECORDS.matcher(request);
        if (!matcher.find()) throw new IllegalArgumentException("Snapshot request is missing records");
        return matcher.replaceFirst(Matcher.quoteReplacement(matcher.group(1) + records));
    }

    private static int inspectSnapshot(String file) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        int engineRecords = 0;
        int dataRecords = 0;
        boolean header = false;
        boolean ended = false;
        String footerHash = null;
        int footerRecords = -1;
        try (BufferedInputStream input = new BufferedInputStream(new FileInputStream(file))) {
            ByteArrayOutputStream line = new ByteArrayOutputStream();
            int value;
            while ((value = input.read()) != -1) {
                if (value == '\n') {
                    if (line.size() == 0) throw new IOException("empty snapshot line");
                    byte[] bytes = line.toByteArray();
                    if (bytes.length > 65_535) throw new IOException("snapshot line too large");
                    String text = new String(bytes, StandardCharsets.UTF_8);
                    Matcher type = TYPE.matcher(text);
                    if (!type.find()) throw new IOException("missing snapshot type");
                    String kind = type.group(1);
                    if ("header".equals(kind)) {
                        if (header || dataRecords != 0 || ended) throw new IOException("invalid snapshot header");
                        header = true;
                    } else if ("footer".equals(kind)) {
                        if (!header || footerHash != null) throw new IOException("invalid snapshot footer");
                        Matcher count = FOOTER_RECORDS.matcher(text);
                        Matcher hash = SHA256.matcher(text);
                        if (!count.find() || !hash.find()) throw new IOException("invalid snapshot footer");
                        footerRecords = Integer.parseInt(count.group(1));
                        footerHash = hash.group(1);
                        ended = true;
                    } else if ("entry".equals(kind) || "overlay".equals(kind)
                            || "position".equals(kind) || "selection".equals(kind)) {
                        if (!header || ended) throw new IOException("invalid snapshot record");
                        digest.update(bytes);
                        digest.update((byte) '\n');
                        dataRecords++;
                        if (!"entry".equals(kind)) engineRecords++;
                    } else throw new IOException("unknown snapshot record");
                    line.reset();
                } else {
                    line.write(value);
                    if (line.size() > 65_535) throw new IOException("snapshot line too large");
                }
            }
            if (line.size() != 0) throw new IOException("unterminated snapshot line");
        }
        if (!header || footerHash == null || footerRecords != dataRecords
                || !footerHash.equals(hex(digest.digest())) || engineRecords > 500_000) {
            throw new IOException("invalid snapshot envelope");
        }
        return engineRecords;
    }

    private static String hex(byte[] bytes) {
        char[] digits = "0123456789abcdef".toCharArray();
        char[] output = new char[bytes.length * 2];
        for (int index = 0; index < bytes.length; index++) {
            int value = bytes[index] & 0xff;
            output[index * 2] = digits[value >>> 4];
            output[index * 2 + 1] = digits[value & 0x0f];
        }
        return new String(output);
    }
}
