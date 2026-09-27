package com.example.wind_chimes

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val NOTIFICATIONS_REQUEST = 4201
    }

    private var notificationsResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // The notification's Stop closes the app, as swiping it away does.
        PlaybackService.onStop = { finishAndRemoveTask() }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "wind_chimes/background_playback")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> try {
                        PlaybackService.start(this)
                        result.success(null)
                    } catch (e: IllegalStateException) {
                        // Too long after leaving the screen (Android 12+ refuses then).
                        result.error("not_allowed", e.message, null)
                    }
                    "stop" -> {
                        PlaybackService.stop(this)
                        result.success(null)
                    }
                    "requestNotifications" -> requestNotifications(result)
                    else -> result.notImplemented()
                }
            }
    }

    /** Answers whether the notification can show, asking first on Android 13+. */
    private fun requestNotifications(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (notificationsResult != null) {
            result.error("busy", "Already asking", null)
            return
        }
        notificationsResult = result
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATIONS_REQUEST)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != NOTIFICATIONS_REQUEST) return
        notificationsResult?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
        notificationsResult = null
    }

    override fun onDestroy() {
        // The Flutter engine, and with it the sound, goes with this activity (the back button on
        // older Android, the system reclaiming it, or Stop): don't leave a notification for nothing.
        if (!isChangingConfigurations) PlaybackService.stop(this)
        PlaybackService.onStop = null
        super.onDestroy()
    }
}
