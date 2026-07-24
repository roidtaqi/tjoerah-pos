package com.tjoerah.tjoerah_mobile

import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SYSTEM_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openBluetoothSettings" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                        result.success(true)
                    } catch (error: Exception) {
                        result.error(
                            "bluetooth_settings_unavailable",
                            error.message,
                            null,
                        )
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    companion object {
        private const val SYSTEM_CHANNEL = "com.tjoerah.tjoerah_mobile/system"
    }
}
