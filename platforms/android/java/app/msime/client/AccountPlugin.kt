package app.msime.client

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.Settings
import android.view.inputmethod.InputMethodManager
import app.tauri.annotation.Command
import app.tauri.annotation.InvokeArg
import app.tauri.annotation.TauriPlugin
import app.tauri.plugin.Invoke
import app.tauri.plugin.JSObject
import app.tauri.plugin.Plugin
import java.io.File
import java.nio.file.LinkOption
import java.nio.file.Path

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

@InvokeArg
class CopyTextArgs {
    lateinit var text: String
}

@InvokeArg
class EnqueueSnapshotArgs {
    lateinit var source: String
    lateinit var accountId: String
    var cloudRevision: Long = -1
    lateinit var expectedLocalVersion: String
    lateinit var fileSha256: String
}

@InvokeArg
class CancelSnapshotArgs {
    lateinit var accountId: String
}

@TauriPlugin
class AccountPlugin(activity: Activity) : Plugin(activity) {
    private val hostActivity = activity
    private val storage = AndroidAccountSessionStorage(activity)
    private val feedback = activity.getSharedPreferences("keyboard-feedback", Context.MODE_PRIVATE)

    private fun snapshotQueue(): DictionarySnapshotQueue {
        val files = hostActivity.filesDir
            ?: throw IllegalStateException("private files unavailable")
        return DictionarySnapshotQueue(File(files, "bootstrap/state/dictionary-snapshots").toPath())
    }

    private fun snapshotQueueRoot(): Path {
        val files = hostActivity.filesDir
            ?: throw IllegalStateException("private files unavailable")
        return File(files, "bootstrap/state/dictionary-snapshots").toPath().toAbsolutePath().normalize()
    }

    private fun privateSnapshotSource(value: String): Path {
        val source = Path.of(value).toAbsolutePath().normalize()
        val root = snapshotQueueRoot()
        if (!source.startsWith(root) || !java.nio.file.Files.isRegularFile(source, LinkOption.NOFOLLOW_LINKS)) {
            throw IllegalArgumentException("invalid snapshot source")
        }
        return source
    }

    private fun snapshotStateResponse(): JSObject {
        val state = snapshotQueue().read()
        val response = JSObject()
        state.localVersion()?.let { response.put("localVersion", it) }
        val request = state.request()
        if (request != null) {
            response.put("request", JSObject()
                .put("id", request.id().toString())
                .put("accountId", request.accountId())
                .put("cloudRevision", request.cloudRevision())
                .put("expectedLocalVersion", request.expectedLocalVersion())
                .put("fileSha256", request.fileSha256())
                .put("status", request.status().wire()))
        }
        return response
    }

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

    @Command
    fun copyText(invoke: Invoke) {
        try {
            val text = invoke.parseArgs(CopyTextArgs::class.java).text
            if (text.isEmpty() || text.length > 4000 || text.contains('\u0000') ||
                text.any { it.isISOControl() && it != '\n' && it != '\r' && it != '\t' }) {
                invoke.reject("invalid_text", "invalid_text")
                return
            }
            val clipboard = hostActivity.getSystemService(ClipboardManager::class.java)
                ?: throw IllegalStateException("clipboard unavailable")
            clipboard.setPrimaryClip(ClipData.newPlainText("MSIME", text))
            invoke.resolve()
        } catch (_: IllegalArgumentException) {
            invoke.reject("invalid_text", "invalid_text")
        } catch (_: Exception) {
            invoke.reject("clipboard", "clipboard")
        }
    }

    @Command
    fun openInputMethodSettings(invoke: Invoke) {
        try {
            hostActivity.startActivity(Intent(Settings.ACTION_INPUT_METHOD_SETTINGS))
            invoke.resolve()
        } catch (_: Exception) {
            invoke.reject("system_settings", "system_settings")
        }
    }

    @Command
    fun showInputMethodPicker(invoke: Invoke) {
        try {
            val manager = hostActivity.getSystemService(InputMethodManager::class.java)
                ?: throw IllegalStateException("input method manager unavailable")
            manager.showInputMethodPicker()
            invoke.resolve()
        } catch (_: Exception) {
            invoke.reject("input_method_picker", "input_method_picker")
        }
    }

    /** Rust-only bridge; WebView code never receives the private source path. */
    @Command
    fun enqueueSnapshot(invoke: Invoke) {
        try {
            val args = invoke.parseArgs(EnqueueSnapshotArgs::class.java)
            snapshotQueue().enqueue(
                privateSnapshotSource(args.source), args.accountId, args.cloudRevision,
                args.expectedLocalVersion, args.fileSha256)
            invoke.resolve(snapshotStateResponse())
        } catch (error: DictionarySnapshotQueue.Failure) {
            invoke.reject("snapshot_${error.reason().name.lowercase()}", "snapshot_${error.reason().name.lowercase()}")
        } catch (error: IllegalArgumentException) {
            invoke.reject("snapshot_invalid", error.message)
        } catch (_: Exception) {
            invoke.reject("snapshot_unavailable", "snapshot_unavailable")
        }
    }

    @Command
    fun snapshotState(invoke: Invoke) {
        try { invoke.resolve(snapshotStateResponse()) }
        catch (error: DictionarySnapshotQueue.Failure) {
            invoke.reject("snapshot_${error.reason().name.lowercase()}", "snapshot_${error.reason().name.lowercase()}")
        } catch (_: Exception) { invoke.reject("snapshot_unavailable", "snapshot_unavailable") }
    }

    @Command
    fun cancelSnapshot(invoke: Invoke) {
        try {
            val accountId = invoke.parseArgs(CancelSnapshotArgs::class.java).accountId
            snapshotQueue().cancel(accountId)
            invoke.resolve(snapshotStateResponse())
        } catch (error: DictionarySnapshotQueue.Failure) {
            invoke.reject("snapshot_${error.reason().name.lowercase()}", "snapshot_${error.reason().name.lowercase()}")
        } catch (error: IllegalArgumentException) {
            invoke.reject("snapshot_invalid", error.message)
        } catch (_: Exception) { invoke.reject("snapshot_unavailable", "snapshot_unavailable") }
    }
}
