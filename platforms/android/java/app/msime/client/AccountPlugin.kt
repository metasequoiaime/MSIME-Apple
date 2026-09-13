package app.msime.client

import android.app.Activity
import android.content.Context
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

@TauriPlugin
class AccountPlugin(activity: Activity) : Plugin(activity) {
    private val storage = AndroidAccountSessionStorage(activity)
    private val feedback = activity.getSharedPreferences("keyboard-feedback", Context.MODE_PRIVATE)

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
}
