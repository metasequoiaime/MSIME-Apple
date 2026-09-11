package app.msime.client;

/** Android-native colors for the shared candidate_skin preference. */
public final class KeyboardSkin {
    private final String id;
    private final String background;
    private final String keyBackground;
    private final String keyForeground;
    private final String accent;
    private final String actionBackground;
    private final String actionForeground;
    private final int cornerRadius;
    private final boolean monospaced;

    private KeyboardSkin(String id, String background, String keyBackground, String keyForeground,
            String accent, String actionBackground, String actionForeground, int cornerRadius,
            boolean monospaced) {
        this.id = id;
        this.background = background;
        this.keyBackground = keyBackground;
        this.keyForeground = keyForeground;
        this.accent = accent;
        this.actionBackground = actionBackground;
        this.actionForeground = actionForeground;
        this.cornerRadius = cornerRadius;
        this.monospaced = monospaced;
    }

    public static KeyboardSkin from(String value) {
        return switch (value == null ? "" : value) {
            case "wechat" -> new KeyboardSkin("wechat", "#F0FAF4", "#E8FFF0", "#155B32",
                "#32B76A", "#D7F5E2", "#155B32", 12, false);
            case "graphite" -> new KeyboardSkin("graphite", "#1F2125", "#2B2D31", "#F1F1F1",
                "#8AB4F8", "#41454D", "#FFFFFF", 3, true);
            case "willow_green" -> new KeyboardSkin("willow_green", "#EDF5EA", "#F0F8ED", "#244B2B",
                "#6B9B63", "#D6E9D0", "#244B2B", 18, false);
            default -> new KeyboardSkin("fluent", "#F1F4F8", "#FFFFFF", "#1E293B",
                "#2563EB", "#E0E7FF", "#1E3A8A", 8, false);
        };
    }

    public String id() { return id; }
    public String background() { return background; }
    public String keyBackground() { return keyBackground; }
    public String keyForeground() { return keyForeground; }
    public String accent() { return accent; }
    public String actionBackground() { return actionBackground; }
    public String actionForeground() { return actionForeground; }
    public int cornerRadius() { return cornerRadius; }
    public boolean monospaced() { return monospaced; }
}
