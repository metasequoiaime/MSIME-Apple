package app.msime.client;

import java.nio.file.Files;
import java.nio.file.Path;
import org.json.JSONObject;

/** Runs snapshot preparation and activation only after the IME session is gone. */
public final class DictionarySnapshotWorker {
    private DictionarySnapshotWorker() {}

    public static void process(Path queueDirectory, Path stagingDirectory, String options)
            throws Exception {
        DictionarySnapshotQueue queue = new DictionarySnapshotQueue(queueDirectory);
        String current = version(options);
        queue.publishLocalVersion(current);
        try (DictionarySnapshotQueue.WorkerLease lease = queue.acquireWorkerLease()) {
            DictionarySnapshotQueue.Request request = queue.claim(lease);
            if (request == null) return;
            long handle = 0;
            try {
                Files.createDirectories(stagingDirectory);
                String prepareRequest = new JSONObject()
                    .put("options", new JSONObject(options))
                    .put("staging_root", stagingDirectory.toAbsolutePath().normalize().toString())
                    .put("expected_version", request.expectedLocalVersion())
                    .put("records", 0)
                    .toString();
                JSONObject prepared = new JSONObject(NativeClient.snapshotPrepare(
                    prepareRequest, queue.filePath(request.id()).toString()));
                if (!prepared.optBoolean("ok", false)) {
                    queue.fail(request.id(), lease);
                    return;
                }
                handle = prepared.getJSONObject("value").getLong("handle");
                final long preparedHandle = handle;
                boolean applied = queue.complete(request.id(), lease, current, false, () -> {
                    JSONObject activated = new JSONObject(NativeClient.snapshotActivate(
                        preparedHandle, request.expectedLocalVersion()));
                    if (!activated.optBoolean("ok", false))
                        throw new IllegalStateException("snapshot activation rejected");
                    return version(options);
                });
                if (!applied) {
                    try { NativeClient.snapshotDiscard(preparedHandle); }
                    finally { handle = 0; }
                } else handle = 0;
            } catch (Exception error) {
                try { queue.fail(request.id(), lease); }
                catch (Exception ignored) { /* Preserve the original worker failure. */ }
                throw error;
            } finally {
                if (handle != 0) NativeClient.snapshotDiscard(handle);
            }
        }
    }

    private static String version(String options) throws Exception {
        JSONObject result = new JSONObject(NativeClient.snapshotVersion(options));
        if (!result.optBoolean("ok", false)) throw new IllegalStateException("snapshot version unavailable");
        String value = result.getJSONObject("value").getString("version");
        if (!DictionarySnapshotQueue.validDigest(value)) throw new IllegalStateException("snapshot version invalid");
        return "local-v1:legacy:" + value;
    }
}
