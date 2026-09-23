package app.msime.client;

/** Platform-neutral layout and accessibility contract for the Apple-style tools panel. */
public final class MoreToolsLayout {
    public static final int CARD_HEIGHT_DP = 48;
    public static final int HEADER_HEIGHT_DP = 44;
    public static final int ROW_SPACING_DP = 6;
    public static final int CARD_SPACING_DP = 8;

    public enum Section {
        TOOLS("", 2),
        SETTINGS("设置", 2),
        LOCAL_INPUT("本地输入", 2),
        LOCAL_INPUT_BACK("", 1);

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
            case SETTINGS -> active ? "已开启" : "已关闭";
            case TOOLS, LOCAL_INPUT, LOCAL_INPUT_BACK -> "点击打开";
        };
    }

    /** Short, text-rendered affordances for the native card surface. */
    public static String icon(String title) {
        if (title == null) return "⌘";
        return switch (title) {
            case "表情" -> "☺";
            case "剪贴板历史" -> "▤";
            case "AI 润色" -> "✦";
            case "本地输入", "返回工具" -> "⌘";
            case "应用设置" -> "⚙";
            case "语音结果" -> "◉";
            case "繁体输出" -> "繁";
            case "全角输入" -> "Ａ";
            case "中文标点" -> "，";
            case "按键音" -> "♪";
            case "按键振动" -> "◌";
            case "振动强度" -> "↕";
            default -> "⌨";
        };
    }
}
