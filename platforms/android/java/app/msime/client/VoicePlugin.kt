package app.msime.client

import android.app.Activity
import app.tauri.annotation.Command
import app.tauri.annotation.InvokeArg
import app.tauri.annotation.TauriPlugin
import app.tauri.plugin.Invoke
import app.tauri.plugin.JSObject
import app.tauri.plugin.Plugin
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicReference

@InvokeArg
class VoiceRecognitionArgs {
    lateinit var language: String
    lateinit var requestId: String
}

@InvokeArg
class VoiceControlArgs {
    var requestId: String? = null
}

@InvokeArg
class SaveVoiceTextArgs {
    lateinit var text: String
}

/** Bridges the shared Tauri voice panel to Android's platform recognizer.
 * The recognizer owns microphone capture; only a bounded text result is handed
 * across to the isolated IME process through VoiceResultStore.
 */
@TauriPlugin
class VoicePlugin(activity: Activity) : Plugin(activity) {
    private val hostActivity = activity
    private val worker = Executors.newSingleThreadExecutor()
    private val activeRequest = AtomicReference<String?>(null)

    private fun store(): VoiceResultStore {
        val files = hostActivity.filesDir ?: throw IllegalStateException("private files unavailable")
        return VoiceResultStore(File(files, "voice-handoff").toPath())
    }

    @Command
    fun recognizeVoice(invoke: Invoke) {
        val args = try {
            invoke.parseArgs(VoiceRecognitionArgs::class.java)
        } catch (_: Exception) {
            invoke.reject("invalid_voice", "invalid_voice")
            return
        }
        if (!validRequest(args)) {
            invoke.reject("invalid_voice", "invalid_voice")
            return
        }
        if (!activeRequest.compareAndSet(null, args.requestId)) {
            invoke.reject("busy", "busy")
            return
        }
        if (!VoiceRecognitionActivity.available(hostActivity)) {
            activeRequest.compareAndSet(args.requestId, null)
            invoke.reject("unavailable", "unavailable")
            return
        }
        val startedAt = System.currentTimeMillis()
        try {
            VoiceRecognitionActivity.launch(hostActivity, args.language)
        } catch (_: RuntimeException) {
            activeRequest.compareAndSet(args.requestId, null)
            invoke.reject("unavailable", "unavailable")
            return
        }
        worker.execute { pollResult(invoke, args.requestId, startedAt) }
    }

    private fun pollResult(invoke: Invoke, requestId: String, startedAt: Long) {
        val deadline = startedAt + 2 * 60 * 1000L
        try {
            while (activeRequest.get() == requestId && System.currentTimeMillis() < deadline) {
                val entry = try {
                    store().read(System.currentTimeMillis())
                } catch (error: VoiceResultStore.Failure) {
                    if (error.reason() == VoiceResultStore.Reason.BUSY) null else throw error
                }
                if (entry != null && entry.createdAtMillis() >= startedAt) {
                    activeRequest.compareAndSet(requestId, null)
                    invoke.resolve(JSObject().put("text", entry.text()))
                    return
                }
                Thread.sleep(200L)
            }
            activeRequest.compareAndSet(requestId, null)
            invoke.reject("cancelled", "cancelled")
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
            activeRequest.compareAndSet(requestId, null)
            invoke.reject("cancelled", "cancelled")
        } catch (_: VoiceResultStore.Failure) {
            activeRequest.compareAndSet(requestId, null)
            invoke.reject("unavailable", "unavailable")
        }
    }

    @Command
    fun stopVoice(invoke: Invoke) = cancel(invoke)

    @Command
    fun cancelVoice(invoke: Invoke) = cancel(invoke)

    private fun cancel(invoke: Invoke) {
        val requestId = try {
            invoke.parseArgs(VoiceControlArgs::class.java).requestId
        } catch (_: Exception) {
            null
        }
        val current = activeRequest.get()
        if (current == null || requestId == null || requestId == current) {
            if (current != null) activeRequest.compareAndSet(current, null)
            VoiceRecognitionActivity.cancelActive()
        }
        invoke.resolve()
    }

    @Command
    fun saveVoiceText(invoke: Invoke) {
        try {
            val text = invoke.parseArgs(SaveVoiceTextArgs::class.java).text
            if (text.codePointCount(0, text.length) > VoiceResultStore.MAXIMUM_CHARACTERS
                || text.contains('\u0000') || text.trim().isEmpty()) {
                invoke.reject("invalid_text", "invalid_text")
                return
            }
            store().save(text, System.currentTimeMillis())
            invoke.resolve()
        } catch (_: VoiceResultStore.Failure) {
            invoke.reject("unavailable", "unavailable")
        } catch (_: Exception) {
            invoke.reject("unavailable", "unavailable")
        }
    }

    private fun validRequest(args: VoiceRecognitionArgs): Boolean {
        return args.requestId.length in 1..64
            && args.requestId.all { it.isLetterOrDigit() || it == '-' }
            && args.language.length in 1..64
            && args.language.none { it.isISOControl() }
    }
}
