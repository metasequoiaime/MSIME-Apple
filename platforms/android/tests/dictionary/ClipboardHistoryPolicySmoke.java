import app.msime.client.ClipboardHistoryPolicy;
import app.msime.client.ClipboardHistory;
import java.util.ArrayList;
import java.util.List;

public final class ClipboardHistoryPolicySmoke {
    static void check(boolean condition) { if (!condition) throw new AssertionError(); }

    public static void main(String[] args) {
        check(!ClipboardHistoryPolicy.acceptable(null));
        check(!ClipboardHistoryPolicy.acceptable("   \n"));
        check(ClipboardHistoryPolicy.acceptable("synthetic clipboard text"));
        check(!ClipboardHistoryPolicy.acceptable("x".repeat(ClipboardHistoryPolicy.MAX_CHARS + 1)));
        check(!ClipboardHistoryPolicy.acceptable("🌲".repeat(ClipboardHistoryPolicy.MAX_BYTES)));
        check(ClipboardHistoryPolicy.LIMIT == 50);
        ClipboardHistory history = new ClipboardHistory(List.of());
        history.add("older", "one", 1);
        history.add("newer", "two", 2);
        check(history.items().get(0).id().equals("two"));
        history.togglePinned("one");
        check(history.items().get(0).id().equals("one") && history.items().get(0).pinned());
        history.add("older", "replacement-id", 3);
        check(history.items().size() == 2 && history.items().get(0).id().equals("one"));
        history.remove("one");
        check(history.items().size() == 1 && history.items().get(0).id().equals("two"));

        List<ClipboardHistory.Item> full = new ArrayList<>();
        for (int index = 0; index < ClipboardHistoryPolicy.LIMIT; index++)
            full.add(new ClipboardHistory.Item("id-" + index, "entry-" + index, index, index < 49));
        ClipboardHistory bounded = new ClipboardHistory(full);
        bounded.add("replacement", "new", 100);
        check(bounded.items().size() == ClipboardHistoryPolicy.LIMIT);
        check(bounded.items().stream().noneMatch(item -> item.id().equals("id-49")));
        ClipboardHistory allPinned = new ClipboardHistory(full.stream()
            .map(item -> new ClipboardHistory.Item(item.id(), item.text(), item.timestamp(), true)).toList());
        try { allPinned.add("overflow", "overflow", 100); throw new AssertionError(); }
        catch (IllegalStateException expected) { /* Every entry is protected. */ }
        System.out.println("Android clipboard history: policy, dedupe, pinning, removal and bounds passed");
    }
}
