package io.flvpcore.app

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import org.json.JSONObject
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingPermission: Pair<String, MethodChannel.Result>? = null

    private fun dispatch(text: String, result: MethodChannel.Result) {
        CoreRuntime.dispatch(this, text) { response, error ->
            if (error != null) result.error("HOST_UNAVAILABLE", error, null)
            else result.success(response)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "io.flvpcore/core")
            .setMethodCallHandler { call, result ->
                if (call.method != "request") {
                    result.notImplemented()
                } else {
                    val text = call.arguments as? String
                    if (text == null || text.toByteArray(Charsets.UTF_8).size > 1024 * 1024) {
                        result.error("INVALID_REQUEST", "Invalid native request", null)
                    } else {
                        val operation = try { JSONObject(text).optString("operation") } catch (_: Exception) { "" }
                        val prefs = getSharedPreferences("native", MODE_PRIVATE)
                        if (operation == "start" && Build.VERSION.SDK_INT >= 33 &&
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED &&
                            !prefs.getBoolean("notificationPrompted", false)) {
                            prefs.edit().putBoolean("notificationPrompted", true).apply()
                            pendingPermission = text to result
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 100)
                        } else {
                            dispatch(text, result)
                        }
                    }
                }
            }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 100) {
            val pending = pendingPermission
            pendingPermission = null
            // Android allows a foreground service even if notification access
            // is denied. The in-app stop control remains available.
            if (pending != null) dispatch(pending.first, pending.second)
        }
    }

    override fun onDestroy() {
        pendingPermission?.second?.error("ACTIVITY_RECREATED", "Activity closed while requesting notification access; retry start", null)
        pendingPermission = null
        super.onDestroy()
    }
}
