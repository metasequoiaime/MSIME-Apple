package app.msime.client

import android.app.Activity
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

@TauriPlugin
class AccountPlugin(activity: Activity) : Plugin(activity) {
    private val storage = AndroidAccountSessionStorage(activity)

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
}
