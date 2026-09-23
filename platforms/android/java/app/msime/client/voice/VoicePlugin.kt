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

    /**
     * The configured transcription provider, absent when the user has not set one up.
     *
     * The shared layer resolves and validates it; absent means the platform recognizer, which is
     * this host's default and works with no account at all.
     */
    var provider: VoiceProviderArgs? = null

    /** The optional rewrite over whatever was transcribed, absent unless the user asked for it. */
    var polish: VoicePolishArgs? = null
}

@InvokeArg
class VoicePolishArgs {
    var endpoint: String = ""
    var model: String = ""
    var token: String = ""
    var promptId: String = ""
    var promptLegacy: String = ""
    var promptCustom1: String = ""
    var promptCustom2: String = ""
    var promptCustom3: String = ""
}

@InvokeArg
class VoiceProviderArgs {
    var provider: String = ""
    var endpoint: String = ""
    var model: String = ""
    var token: String = ""
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
    private data class VoiceJob(val requestId: String, val invoke: Invoke, val startedAt: Long)

    private val hostActivity = activity
    private val worker = Executors.newSingleThreadExecutor()
    private val activeJob = AtomicReference<VoiceJob?>(null)

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
        val job = VoiceJob(args.requestId, invoke, System.currentTimeMillis())
        if (!activeJob.compareAndSet(null, job)) {
            invoke.reject("busy", "busy")
            return
        }
        // Only one of the two engines needs the system service. A provider records in the
        // activity itself, so a device without that service still has voice input through one.
        val provider = args.provider?.takeIf {
            HttpAsrPolicy.usable(it.provider, it.endpoint, it.model, it.token)
        }
        if (provider == null && !VoiceRecognitionActivity.available(hostActivity)) {
            activeJob.compareAndSet(job, null)
            invoke.reject("unavailable", "unavailable")
            return
        }
        try {
            VoiceRecognitionActivity.markLaunched(args.requestId)
            VoiceRecognitionActivity.launch(
                hostActivity, args.requestId, args.language,
                provider?.provider, provider?.endpoint, provider?.model, provider?.token,
                args.polish?.let {
                    // The prompt itself is resolved from the shared preset table on the way in,
                    // so the activity carries text rather than a slot id to look up again.
                    VoiceRecognitionActivity.Polish(
                        it.endpoint, it.model, it.token,
                        NativeClient.polishPrompt(
                            it.promptId, it.promptLegacy,
                            it.promptCustom1, it.promptCustom2, it.promptCustom3,
                        ),
                    )
                },
            )
        } catch (_: RuntimeException) {
            VoiceRecognitionActivity.clearRequest(args.requestId)
            activeJob.compareAndSet(job, null)
            invoke.reject("unavailable", "unavailable")
            return
        }
        worker.execute { pollResult(job) }
    }

    private fun pollResult(job: VoiceJob) {
        val deadline = job.startedAt + 2 * 60 * 1000L
        try {
            while (activeJob.get() === job && System.currentTimeMillis() < deadline) {
                val entry = try {
                    store().read(System.currentTimeMillis())
                } catch (error: VoiceResultStore.Failure) {
                    if (error.reason() == VoiceResultStore.Reason.BUSY) null else throw error
                }
                if (entry != null && entry.createdAtMillis() >= job.startedAt) {
                    if (!activeJob.compareAndSet(job, null)) return
                    job.invoke.resolve(JSObject().put("text", entry.text()))
                    return
                }
                // The recognizer may finish with BACK, a missing service, or a
                // system cancellation without producing a result file. Treat
                // the Activity lifecycle as authoritative instead of waiting
                // for the two-minute polling deadline.
                if (!VoiceRecognitionActivity.isRequestActive(job.requestId)) {
                    if (!activeJob.compareAndSet(job, null)) return
                    job.invoke.reject("cancelled", "cancelled")
                    return
                }
                Thread.sleep(200L)
            }
            if (activeJob.compareAndSet(job, null)) job.invoke.reject("cancelled", "cancelled")
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
            if (activeJob.compareAndSet(job, null)) job.invoke.reject("cancelled", "cancelled")
        } catch (_: VoiceResultStore.Failure) {
            if (activeJob.compareAndSet(job, null)) job.invoke.reject("unavailable", "unavailable")
        }
    }

    @Command
    fun stopVoice(invoke: Invoke) {
        val requestId = try {
            invoke.parseArgs(VoiceControlArgs::class.java).requestId
        } catch (_: Exception) {
            null
        }
        val current = activeJob.get()
        if (current == null || requestId == null || requestId == current.requestId) {
            VoiceRecognitionActivity.stopActive()
        }
        invoke.resolve()
    }

    @Command
    fun cancelVoice(invoke: Invoke) = cancel(invoke)

    private fun cancel(invoke: Invoke) {
        val requestId = try {
            invoke.parseArgs(VoiceControlArgs::class.java).requestId
        } catch (_: Exception) {
            null
        }
        val current = activeJob.get()
        if (current == null || requestId == null || requestId == current.requestId) {
            if (current != null && activeJob.compareAndSet(current, null)) {
                current.invoke.reject("cancelled", "cancelled")
            }
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
