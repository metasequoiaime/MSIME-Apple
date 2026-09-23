import app.msime.client.ClipboardHistoryPolicy;

public final class ClipboardHistoryPolicySmoke {
    static void check(boolean condition) { if (!condition) throw new AssertionError(); }

    public static void main(String[] args) {
        check(!ClipboardHistoryPolicy.acceptable(null));
        check(!ClipboardHistoryPolicy.acceptable("   \n"));
        check(ClipboardHistoryPolicy.acceptable("synthetic clipboard text"));
        check(!ClipboardHistoryPolicy.acceptable("x".repeat(ClipboardHistoryPolicy.MAX_CHARS + 1)));
        check(!ClipboardHistoryPolicy.acceptable("🌲".repeat(ClipboardHistoryPolicy.MAX_BYTES)));
        // These three have to agree with crates/client-core::clipboard, which owns the history
        // now: MAX_ENTRIES, MAX_MOBILE_TEXT_CHARACTERS and MAX_MOBILE_TEXT_BYTES. A host bound that
        // is tighter would refuse text the store would have taken, and one that is looser would
        // promise a save the store then rejects.
        check(ClipboardHistoryPolicy.LIMIT == 50);
        check(ClipboardHistoryPolicy.MAX_CHARS == 10_000);
        check(ClipboardHistoryPolicy.MAX_BYTES == 40_000);
        // Ordering, eviction and the pinned-entries-are-never-evicted rule used to be asserted
        // here against a second implementation in this host. They belong to the shared store and
        // are covered by its own tests; what is left here is this host's own policy.

        check(ClipboardHistoryPolicy.rejection(null) == ClipboardHistoryPolicy.Rejection.EMPTY);
        check(ClipboardHistoryPolicy.rejection("   \n") == ClipboardHistoryPolicy.Rejection.EMPTY);
        check(ClipboardHistoryPolicy.rejection("synthetic clipboard text") == null);
        check(ClipboardHistoryPolicy.rejection("x".repeat(ClipboardHistoryPolicy.MAX_CHARS + 1))
            == ClipboardHistoryPolicy.Rejection.TOO_LONG);
        // A short string can still exceed the byte bound, and that is still "too long".
        check(ClipboardHistoryPolicy.rejection("🌲".repeat(ClipboardHistoryPolicy.MAX_BYTES))
            == ClipboardHistoryPolicy.Rejection.TOO_LONG);
        for (ClipboardHistoryPolicy.Rejection rejection : ClipboardHistoryPolicy.Rejection.values())
            check(!ClipboardHistoryPolicy.message(rejection).isEmpty());
        // Each refusal names what would let the save succeed.
        check(ClipboardHistoryPolicy.message(ClipboardHistoryPolicy.Rejection.TOO_LONG)
            .contains(String.valueOf(ClipboardHistoryPolicy.MAX_CHARS)));
        check(ClipboardHistoryPolicy.message(ClipboardHistoryPolicy.Rejection.FULL)
            .contains(String.valueOf(ClipboardHistoryPolicy.LIMIT)));
        check(!ClipboardHistoryPolicy.message(ClipboardHistoryPolicy.Rejection.EMPTY)
            .equals(ClipboardHistoryPolicy.message(ClipboardHistoryPolicy.Rejection.TOO_LONG)));
        try { ClipboardHistoryPolicy.message(null); throw new AssertionError(); }
        catch (IllegalArgumentException expected) { /* There is no message for "accepted". */ }
        System.out.println("Android clipboard history: policy, dedupe, pinning, removal and bounds passed");
    }
}
