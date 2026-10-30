package io.flvpcore.app

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import org.json.JSONObject
import java.util.UUID
import java.util.concurrent.Executors

// All JNI calls, including notification commands, share one worker. Activity
// recreation cannot create a second runtime or block the Android main thread.
object CoreRuntime {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val callbacks = mutableMapOf<String, (String?, String?) -> Unit>()
    @Volatile var serviceEpoch = 0L
        private set
    @Volatile private var desiredVersion = 0L

    fun serviceCreated(): Long { serviceEpoch += 1; return serviceEpoch }

    fun dispatch(context: Context, text: String, callback: (String?, String?) -> Unit) {
        try {
            val op = JSONObject(text).getString("operation")
            val version = if (op in listOf("start", "apply", "stop", "quit")) ++desiredVersion else desiredVersion
            if (op == "start" || op == "apply") {
                val token = UUID.randomUUID().toString()
                callbacks[token] = callback
                try {
                    context.startForegroundService(Intent(context, ProxyService::class.java)
                        .putExtra("request", text).putExtra("token", token).putExtra("version", version))
                } catch (error: Exception) {
                    callbacks.remove(token)
                    callback(null, error.message ?: "Cannot start foreground service")
                }
            } else execute(context.applicationContext, text, version, callback)
        } catch (error: Exception) {
            callback(null, error.message ?: "Invalid request")
        }
    }

    fun fromService(service: ProxyService, text: String, token: String, version: Long) {
        execute(service.applicationContext, text, version) { response, error ->
            callbacks.remove(token)?.invoke(response, error)
        }
    }

    private fun execute(context: Context, text: String, version: Long, callback: (String?, String?) -> Unit) {
        worker.execute {
            try {
                val response = CoreNative.request(text)
                val json = JSONObject(response)
                val status = if (json.optBoolean("ok")) json.optJSONObject("result")
                    else json.optJSONObject("status")
                val state = status?.optString("state")
                val mutation = JSONObject(text).optString("operation") in listOf("start", "apply", "stop", "quit")
                main.post {
                    if (mutation && version == desiredVersion && (state == "stopped" || state == "failed")) {
                        context.stopService(Intent(context, ProxyService::class.java))
                    } else if (version == desiredVersion && state == "running") {
                        ProxyService.current?.showRunning(status?.optInt("mixedPort") ?: 0)
                    }
                    callback(response, null)
                }
            } catch (error: Throwable) {
                main.post {
                    if (version == desiredVersion) context.stopService(Intent(context, ProxyService::class.java))
                    callback(null, "Native proxy unavailable: ${error.javaClass.simpleName}: ${error.message}")
                }
            }
        }
    }

    fun stopOwned(context: Context, epoch: Long? = null, expectedVersion: Long? = null): Long {
        val version = expectedVersion ?: ++desiredVersion
        worker.execute {
            // Ignore an old service's destruction after a replacement was made.
            if ((epoch != null && epoch != serviceEpoch) || version != desiredVersion) return@execute
            try {
                val status = JSONObject(CoreNative.request(JSONObject()
                    .put("requestId", UUID.randomUUID().toString()).put("operation", "status").toString()))
                    .getJSONObject("result")
                CoreNative.request(JSONObject().put("requestId", UUID.randomUUID().toString())
                    .put("operation", "stop")
                    .put("expectedGeneration", status.getLong("generation"))
                    .put("expectedAppliedRevision", status.getLong("appliedRevision")).toString())
            } catch (_: Throwable) { /* No runtime exists if loading failed. */ }
            main.post { if (version == desiredVersion && (epoch == null || epoch == serviceEpoch)) {
                context.stopService(Intent(context, ProxyService::class.java))
            } }
        }
        return version
    }
}
