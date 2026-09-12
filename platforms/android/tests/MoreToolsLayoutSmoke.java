import app.msime.client.MoreToolsLayout;

public final class MoreToolsLayoutSmoke {
    public static void main(String[] args) {
        check(MoreToolsLayout.Section.TOOLS.columns() == 1, "tools use full-width cards");
        check(MoreToolsLayout.Section.FEEDBACK.columns() == 2, "feedback uses two columns");
        check(MoreToolsLayout.Section.HAPTIC_STRENGTH.columns() == 3,
            "strength uses three columns");
        check(MoreToolsLayout.Section.LOCAL_INPUT.columns() == 2,
            "local input uses two columns");
        check(MoreToolsLayout.rowCount(3, MoreToolsLayout.Section.TOOLS) == 3,
            "three Apple tools occupy three full-width rows");
        check(MoreToolsLayout.rowCount(8, MoreToolsLayout.Section.LOCAL_INPUT) == 4,
            "eight local tools occupy four rows");
        check("已开启".equals(MoreToolsLayout.state(MoreToolsLayout.Section.FEEDBACK, true)),
            "enabled feedback state");
        check("已关闭".equals(MoreToolsLayout.state(MoreToolsLayout.Section.FEEDBACK, false)),
            "disabled feedback state");
        check("已选中".equals(MoreToolsLayout.state(
            MoreToolsLayout.Section.HAPTIC_STRENGTH, true)), "selected strength state");
        check("点击选择".equals(MoreToolsLayout.state(
            MoreToolsLayout.Section.HAPTIC_STRENGTH, false)), "unselected strength state");
        check(MoreToolsLayout.CARD_HEIGHT_DP == 48 && MoreToolsLayout.HEADER_HEIGHT_DP == 44,
            "Apple card and header dimensions");
        boolean rejected = false;
        try { MoreToolsLayout.rowCount(-1, MoreToolsLayout.Section.TOOLS); }
        catch (IllegalArgumentException expected) { rejected = true; }
        check(rejected, "negative counts rejected");
        System.out.println("Android more tools: Apple grouping, dimensions and states passed");
    }

    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
}
