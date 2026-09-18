import app.msime.client.CandidateAppearance;

public final class CandidateAppearanceSmoke {
    static void check(boolean condition) { if (!condition) throw new AssertionError(); }

    public static void main(String[] args) {
        check(!CandidateAppearance.isHorizontal("vertical"));
        check(CandidateAppearance.isHorizontal("horizontal"));
        check(!CandidateAppearance.isHorizontal("untrusted"));
        check(CandidateAppearance.fontSize(12) == 12);
        check(CandidateAppearance.fontSize(32) == 32);
        check(CandidateAppearance.fontSize(11) == 16);
        check(CandidateAppearance.fontSize(33) == 16);
        System.out.println("Android candidate appearance: orientation and bounded font sizes passed");
    }
}
