package app.msime.client;

/** Apple-compatible local input mode shortcuts exposed by the shared Engine. */
public enum LocalInputMode {
    UNICODE("U", "Unicode 码点", "unicode"),
    DATE_TIME("T", "日期与时间", "date_time"),
    QUICK_PHRASE("K", "快捷短语", "quick_phrase"),
    EMOJI("E", "Emoji", "emoji"),
    KAOMOJI("M", "颜文字", "kaomoji"),
    SUPER_JIANPIN("J", "超级简拼", "super_jianpin"),
    TEMPORARY_ENGLISH("Y", "临时英文", "temporary_english"),
    TEMPORARY_JAPANESE("R", "临时日语", "temporary_japanese");

    private final String trigger;
    private final String title;
    private final String preferenceKey;

    LocalInputMode(String trigger, String title, String preferenceKey) {
        this.trigger = trigger;
        this.title = title;
        this.preferenceKey = preferenceKey;
    }

    public String trigger() { return trigger; }
    public String title() { return title; }
    public String preferenceKey() { return preferenceKey; }
}
