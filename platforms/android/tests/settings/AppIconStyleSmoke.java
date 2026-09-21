import app.msime.client.AppIconStyle;
import java.util.ArrayList;
import java.util.List;

public final class AppIconStyleSmoke {
    private static final String PACKAGE = "app.msime.android";

    public static void main(String[] args) {
        List<AppIconStyle> all = AppIconStyle.all();
        check(all.size() == 5, "five icon styles");
        check(all.get(0) == AppIconStyle.CLASSIC, "classic is first, as the shipped default");

        List<String> ids = new ArrayList<>();
        List<String> components = new ArrayList<>();
        for (AppIconStyle style : all) {
            check(!style.id().isEmpty() && !style.title().isEmpty()
                && !style.description().isEmpty(), "every style is named: " + style.id());
            check(!ids.contains(style.id()), "no id appears twice: " + style.id());
            ids.add(style.id());
            String component = style.component(PACKAGE);
            check(component.startsWith(PACKAGE + "."), "components live in this package");
            // Two styles mapping to one component means selecting either leaves the other
            // looking selected, and disabling "the rest" would disable the one just enabled.
            check(!components.contains(component), "no component is shared: " + component);
            components.add(component);
        }

        // Classic is the launcher activity itself: the manifest enables it, and there is no alias
        // to turn on for it. Naming one would disable the real entry point and take the app out of
        // the launcher with no way back from the launcher.
        check(AppIconStyle.CLASSIC.alias().isEmpty(), "classic has no alias of its own");
        check((PACKAGE + ".home.HomeActivity").equals(AppIconStyle.CLASSIC.component(PACKAGE)),
            "classic resolves to the launcher activity");
        check((PACKAGE + ".MainActivityForest").equals(AppIconStyle.FOREST.component(PACKAGE)),
            "an alias resolves to its manifest name");
        for (AppIconStyle style : all) {
            if (style == AppIconStyle.CLASSIC) continue;
            check(!style.alias().isEmpty(), "every other style has an alias: " + style.id());
        }

        check(AppIconStyle.from("sky") == AppIconStyle.SKY, "a stored id resolves");
        check(AppIconStyle.from("from a newer build") == AppIconStyle.CLASSIC,
            "an unknown id falls back to the component the manifest enables");
        check(AppIconStyle.from(null) == AppIconStyle.CLASSIC, "so does a missing one");
        System.out.println("Android app icon styles: ids, components and fallback passed");
    }

    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
}
