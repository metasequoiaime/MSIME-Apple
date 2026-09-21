package app.msime.client;

import java.util.List;

/**
 * 主屏幕图标的几种配色。
 *
 * <p>Android has no API for changing an app's icon. What it has is launcher components that can be
 * enabled and disabled, so each style is an `activity-alias` in the manifest and switching means
 * enabling one and disabling the rest. The classic style is the launcher activity itself and has no
 * alias of its own, which is why {@link #alias()} is empty for it rather than naming a component
 * that does not exist.
 *
 * <p>Exactly one component must be enabled at any time. Two leaves a duplicate icon in the
 * launcher; none removes the app from it entirely, which the user cannot undo from the launcher.
 */
public enum AppIconStyle {
    CLASSIC("classic", "", "经典", "深绿描线的水杉"),
    FOREST("forest", "MainActivityForest", "林绿", "饱和度更高的森林绿"),
    SKY("sky", "MainActivitySky", "天青", "浅蓝底色"),
    DUSK("dusk", "MainActivityDusk", "暮色", "暗紫与橘的渐层"),
    VERMILION("vermilion", "MainActivityVermilion", "朱砂", "暖红底色");

    private final String id;
    private final String alias;
    private final String title;
    private final String description;

    AppIconStyle(String id, String alias, String title, String description) {
        this.id = id;
        this.alias = alias;
        this.title = title;
        this.description = description;
    }

    public String id() { return id; }

    /** The alias' class name, or an empty string for the launcher activity itself. */
    public String alias() { return alias; }

    public String title() { return title; }

    public String description() { return description; }

    public static List<AppIconStyle> all() { return List.of(values()); }

    /**
     * The style for a stored id.
     *
     * <p>Falls back to classic, which is also the right answer for an interrupted package-manager
     * update or an id written by a newer build: the launcher activity is the one component the
     * manifest enables on its own.
     */
    public static AppIconStyle from(String value) {
        for (AppIconStyle style : values()) {
            if (style.id.equals(value)) return style;
        }
        return CLASSIC;
    }

    /** The component to enable or disable for this style, given the host's package. */
    public String component(String packageName) {
        return alias.isEmpty() ? packageName + ".home.HomeActivity" : packageName + "." + alias;
    }
}
