import app.msime.client.MoreToolsLayout;

public final class MoreToolsLayoutSmoke {
    public static void main(String[] args) {
        check(MoreToolsLayout.Section.TOOLS.columns() == 2, "tools use two columns");
        check(MoreToolsLayout.Section.SETTINGS.columns() == 2, "settings use two columns");
        check(MoreToolsLayout.Section.LOCAL_INPUT.columns() == 2,
            "local input uses two columns");
        check(MoreToolsLayout.Section.LOCAL_INPUT_BACK.columns() == 1,
            "local input navigation uses one full-width column");
        check(MoreToolsLayout.rowCount(4, MoreToolsLayout.Section.TOOLS) == 2,
            "four Apple tools occupy two rows");
        check(MoreToolsLayout.rowCount(8, MoreToolsLayout.Section.LOCAL_INPUT) == 4,
            "eight local tools occupy four rows");
        check("已开启".equals(MoreToolsLayout.state(MoreToolsLayout.Section.SETTINGS, true)),
            "enabled setting state");
        check("已关闭".equals(MoreToolsLayout.state(MoreToolsLayout.Section.SETTINGS, false)),
            "disabled setting state");
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
