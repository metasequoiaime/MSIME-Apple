package app.msime.client

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import app.tauri.annotation.Command
import app.tauri.annotation.InvokeArg
import app.tauri.annotation.TauriPlugin
import app.tauri.plugin.Invoke
import app.tauri.plugin.JSObject
import app.tauri.plugin.Plugin

@InvokeArg
class SaveAccountSessionArgs {
    lateinit var value: String
}

@InvokeArg
class SaveFeedbackArgs {
    var soundEnabled: Boolean = true
    var hapticsEnabled: Boolean = false
    var hapticStrength: String = "medium"
}

@InvokeArg
class SetAppIconArgs {
    var style: String = ""
}

@TauriPlugin
class AccountPlugin(activity: Activity) : Plugin(activity) {
    private val hostActivity = activity
    private val storage = AndroidAccountSessionStorage(activity)
    private val feedback = activity.getSharedPreferences("keyboard-feedback", Context.MODE_PRIVATE)

    private val appIconAliases = linkedMapOf(
        "classic" to null,
        "forest" to "MainActivityForest",
        "sky" to "MainActivitySky",
        "dusk" to "MainActivityDusk",
        "vermilion" to "MainActivityVermilion",
    )

    private fun appIconComponent(className: String?): ComponentName {
        return className?.let { ComponentName(hostActivity.packageName, "${hostActivity.packageName}.$it") }
            ?: ComponentName(hostActivity, hostActivity.javaClass)
    }

    private fun appIconSelected(): String {
        val packageManager = hostActivity.packageManager
        for ((style, alias) in appIconAliases) {
            if (alias == null) continue
            val state = packageManager.getComponentEnabledSetting(appIconComponent(alias))
            if (state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED) return style
        }
        // The base activity is enabled by the manifest unless a custom alias
        // has been selected. It is also the safe answer for an interrupted
        // package-manager update or an icon ID from a future build.
        return "classic"
    }

    private fun setAppIcon(style: String) {
        if (!appIconAliases.containsKey(style)) {
            throw IllegalArgumentException("invalid app icon")
        }
        val packageManager = hostActivity.packageManager
        val selected = appIconAliases[style]
        // Enable the target before disabling the old launcher component so the
        // launcher never observes a package with no entry point.
        packageManager.setComponentEnabledSetting(
            appIconComponent(selected),
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP,
        )
        for ((_, alias) in appIconAliases) {
            if (alias != selected) {
                packageManager.setComponentEnabledSetting(
                    appIconComponent(alias),
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                    PackageManager.DONT_KILL_APP,
                )
            }
        }
    }

    @Command
    fun loadSession(invoke: Invoke) {
        try {
            val response = JSObject()
            response.put("value", storage.load())
            invoke.resolve(response)
        } catch (_: Exception) {
            invoke.reject("secure_storage", "secure_storage")
        }
    }

    @Command
    fun saveSession(invoke: Invoke) {
        try {
            storage.save(invoke.parseArgs(SaveAccountSessionArgs::class.java).value)
            invoke.resolve()
        } catch (_: Exception) {
            invoke.reject("secure_storage", "secure_storage")
        }
    }

    @Command
    fun clearSession(invoke: Invoke) {
        try {
            storage.clear()
            invoke.resolve()
        } catch (_: Exception) {
            invoke.reject("secure_storage", "secure_storage")
        }
    }

    @Command
    fun loadFeedback(invoke: Invoke) {
        try {
            val response = JSObject()
            response.put("soundEnabled", feedback.getBoolean(KeyboardFeedbackPreferences.SOUND_KEY, true))
            response.put("hapticsEnabled", feedback.getBoolean(KeyboardFeedbackPreferences.HAPTICS_KEY, false))
            response.put("hapticStrength", KeyboardFeedbackPreferences.strength(
                feedback.getString(KeyboardFeedbackPreferences.STRENGTH_KEY, "medium") ?: "medium"
            ).id())
            invoke.resolve(response)
        } catch (_: Exception) {
            invoke.reject("feedback_storage", "feedback_storage")
        }
    }

    @Command
    fun saveFeedback(invoke: Invoke) {
        try {
            val args = invoke.parseArgs(SaveFeedbackArgs::class.java)
            if (args.hapticStrength !in setOf("light", "medium", "strong")) {
                invoke.reject("invalid_feedback", "invalid_feedback")
                return
            }
            feedback.edit()
                .putBoolean(KeyboardFeedbackPreferences.SOUND_KEY, args.soundEnabled)
                .putBoolean(KeyboardFeedbackPreferences.HAPTICS_KEY, args.hapticsEnabled)
                .putString(KeyboardFeedbackPreferences.STRENGTH_KEY, args.hapticStrength)
                .apply()
            invoke.resolve()
        } catch (_: Exception) {
            invoke.reject("feedback_storage", "feedback_storage")
        }
    }

    @Command
    fun appIconInfo(invoke: Invoke) {
        try {
            val response = JSObject()
            response.put("supported", true)
            response.put("selected", appIconSelected())
            invoke.resolve(response)
        } catch (_: Exception) {
            invoke.reject("app_icon", "app_icon")
        }
    }

    @Command
    fun setAppIcon(invoke: Invoke) {
        try {
            val args = invoke.parseArgs(SetAppIconArgs::class.java)
            setAppIcon(args.style)
            val response = JSObject()
            response.put("supported", true)
            response.put("selected", appIconSelected())
            invoke.resolve(response)
        } catch (error: IllegalArgumentException) {
            invoke.reject("invalid_app_icon", error.message)
        } catch (_: Exception) {
            invoke.reject("app_icon", "app_icon")
        }
    }
}
