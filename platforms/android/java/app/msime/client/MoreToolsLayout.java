package app.msime.client;

/** Platform-neutral layout and accessibility contract for the Apple-style tools panel. */
public final class MoreToolsLayout {
    public static final int CARD_HEIGHT_DP = 48;
    public static final int HEADER_HEIGHT_DP = 44;
    public static final int ROW_SPACING_DP = 6;
    public static final int CARD_SPACING_DP = 8;

    public enum Section {
        TOOLS("", 1),
        FEEDBACK("按键反馈", 2),
        HAPTIC_STRENGTH("振动强度", 3),
        LOCAL_INPUT("本地输入", 2);

        private final String title;
        private final int columns;

        Section(String title, int columns) {
            this.title = title;
            this.columns = columns;
        }

        public String title() { return title; }
        public int columns() { return columns; }
    }

    private MoreToolsLayout() { }

    public static int rowCount(int itemCount, Section section) {
        if (itemCount < 0) throw new IllegalArgumentException("Negative item count");
        return (itemCount + section.columns() - 1) / section.columns();
    }

    public static String state(Section section, boolean active) {
        return switch (section) {
            case FEEDBACK -> active ? "已开启" : "已关闭";
            case HAPTIC_STRENGTH -> active ? "已选中" : "点击选择";
            case TOOLS, LOCAL_INPUT -> "点击打开";
        };
    }
}
