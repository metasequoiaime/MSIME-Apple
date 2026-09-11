import app.msime.client.HandwritingInk;
import app.msime.client.HandwritingRecognizer;
import java.util.ArrayList;
import java.util.List;

public final class HandwritingContractSmoke {
    static void check(boolean condition) { if (!condition) throw new AssertionError(); }

    public static void main(String[] args) {
        HandwritingInk ink = new HandwritingInk();
        check(ink.begin(-5, 12, 1, 100, 80));
        check(!ink.begin(1, 1, 2, 100, 80));
        check(ink.append(20, 30, 2, 100, 80));
        check(!ink.append(20.2f, 30.2f, 3, 100, 80));
        check(ink.append(150, 90, 4, 100, 80));
        check(ink.finish());
        List<List<HandwritingInk.Point>> snapshot = ink.snapshot();
        check(snapshot.size() == 1 && snapshot.get(0).size() == 3);
        check(snapshot.get(0).get(0).x() == 0 && snapshot.get(0).get(2).x() == 100);
        check(snapshot.get(0).get(2).y() == 80);
        long revision = ink.revision();
        HandwritingRecognizer.Request request = new HandwritingRecognizer.Request(
            revision, snapshot, 100, 80);
        check(request.revision() == revision && request.strokes().equals(snapshot));
        try {
            request.strokes().get(0).add(new HandwritingInk.Point(1, 1, 1));
            throw new AssertionError();
        } catch (UnsupportedOperationException expected) { }
        try {
            new HandwritingRecognizer.Request(1,
                List.of(List.of(new HandwritingInk.Point(101, 1, 1))), 100, 80);
            throw new AssertionError();
        } catch (IllegalArgumentException expected) { }
        check(ink.undo() && !ink.hasInk());

        List<String> values = new ArrayList<>();
        values.add(" 中 "); values.add("中"); values.add(""); values.add("\n");
        for (int index = 0; index < 20; index++) values.add("字" + index);
        List<String> candidates = HandwritingRecognizer.sanitizeCandidates(values);
        check(candidates.size() == HandwritingRecognizer.MAX_CANDIDATES);
        check(candidates.get(0).equals("中") && candidates.get(1).equals("字0"));
        check(candidates.stream().distinct().count() == candidates.size());

        for (int index = 0; index < HandwritingInk.MAX_STROKES; index++) {
            check(ink.begin(1, 1, index, 100, 80));
            check(ink.finish());
        }
        check(!ink.begin(1, 1, 100, 100, 80));
        check(ink.clear() && !ink.hasInk());
        System.out.println("Android handwriting contract: bounds, revisions, undo and candidates passed");
    }
}
