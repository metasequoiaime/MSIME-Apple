package app.msime.client.home;

import android.content.ComponentName;
import android.content.Context;
import android.content.pm.PackageManager;
import app.msime.client.AppIconStyle;

/**
 * 切换主屏幕图标：启用一个组件，关掉其余的。
 *
 * <p>The target is enabled before the others are disabled, so the launcher never observes a package
 * with no entry point at all -- the state the user cannot get out of from the launcher. The process
 * is kept alive through the change; killing it here would close the settings screen that asked for
 * it, and the launcher picks the change up either way.
 */
public final class AppIcons {
    private AppIcons() {}

    /** The style currently enabled, which is classic unless an alias was selected. */
    public static AppIconStyle selected(Context context) {
        PackageManager packages = context.getPackageManager();
        for (AppIconStyle style : AppIconStyle.all()) {
            if (style == AppIconStyle.CLASSIC) continue;
            if (packages.getComponentEnabledSetting(component(context, style))
                == PackageManager.COMPONENT_ENABLED_STATE_ENABLED) return style;
        }
        return AppIconStyle.CLASSIC;
    }

    /** Enable one style's component and disable every other. Returns false if the change failed. */
    public static boolean select(Context context, AppIconStyle style) {
        PackageManager packages = context.getPackageManager();
        try {
            packages.setComponentEnabledSetting(component(context, style),
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP);
            for (AppIconStyle other : AppIconStyle.all()) {
                if (other == style) continue;
                packages.setComponentEnabledSetting(component(context, other),
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                    PackageManager.DONT_KILL_APP);
            }
            return true;
        } catch (RuntimeException error) {
            return false;
        }
    }

    private static ComponentName component(Context context, AppIconStyle style) {
        return new ComponentName(context.getPackageName(),
            style.component(context.getPackageName()));
    }
}
