import app.msime.client.DictionarySnapshotQueue;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.Comparator;
import java.util.HexFormat;
import java.util.UUID;
import java.util.stream.Stream;

public final class DictionarySnapshotQueueSmoke {
    interface Checked { void run() throws Exception; }
    static void check(boolean condition) { if (!condition) throw new AssertionError(); }
    static void fails(DictionarySnapshotQueue.Reason reason, Checked action) throws Exception {
        try { action.run(); }
        catch (DictionarySnapshotQueue.Failure error) {
            check(error.reason() == reason);
            return;
        }
        throw new AssertionError();
    }

    public static void main(String[] args) throws Exception {
        Path root = Files.createTempDirectory("msime-snapshot-queue-");
        try {
            DictionarySnapshotQueue queue = new DictionarySnapshotQueue(root.resolve("queue"));
            String version = "local-v1:legacy:" + "a".repeat(64);
            check(DictionarySnapshotQueue.validVersion(version));
            check(!DictionarySnapshotQueue.validVersion("local-v1:legacy:" + "A".repeat(64)));
            Path source = root.resolve("download.ndjson");
            Files.writeString(source, "record-one\nrecord-two\n");
            String digest = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
                .digest(Files.readAllBytes(source)));
            String account = "fixture-account";
            queue.publishLocalVersion(version);
            check(queue.read().request() == null);
            UUID id = queue.enqueue(source, account, 42, version, digest);
            DictionarySnapshotQueue.State queued = queue.read();
            check(queued.request() != null && queued.request().id().equals(id)
                && queued.request().status() == DictionarySnapshotQueue.Status.QUEUED);
            check(Files.exists(queue.filePath(id)));
            try (DictionarySnapshotQueue.WorkerLease lease = queue.acquireWorkerLease()) {
                DictionarySnapshotQueue.Request claimed = queue.claim(lease);
                check(claimed.status() == DictionarySnapshotQueue.Status.PREPARING);
                check(queue.complete(id, lease, version, false,
                    () -> "local-v1:" + id + ":" + "b".repeat(64)));
            }
            check(queue.read().request().status() == DictionarySnapshotQueue.Status.APPLIED);
            check(!Files.exists(queue.filePath(id)));
            fails(DictionarySnapshotQueue.Reason.CONFLICT,
                () -> queue.enqueue(source, account, 43, "local-v1:legacy:" + "c".repeat(64), digest));
            String appliedVersion = "local-v1:" + id + ":" + "b".repeat(64);
            UUID second = queue.enqueue(source, account, 43, appliedVersion, digest);
            try (DictionarySnapshotQueue.WorkerLease lease = queue.acquireWorkerLease()) {
                queue.claim(lease);
                check(!queue.complete(second, lease, "local-v1:legacy:" + "d".repeat(64), false,
                    () -> "local-v1:legacy:" + "e".repeat(64)));
            }
            check(queue.read().request().status() == DictionarySnapshotQueue.Status.CONFLICT);
            queue.cancel(account);
            check(queue.read().request().status() == DictionarySnapshotQueue.Status.CONFLICT);
            System.out.println("Android dictionary snapshot queue: atomic files, hash bounds, lease and conflict guards passed");
        } finally {
            try (Stream<Path> paths = Files.walk(root)) {
                paths.sorted(Comparator.reverseOrder()).forEach(path -> {
                    try { Files.deleteIfExists(path); }
                    catch (Exception error) { throw new IllegalStateException(error); }
                });
            }
        }
    }
}
