package com.geoshift.geoshift

import android.Manifest
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= 33) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "geoshift/mock")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isReady" -> result.success(MockEngine.isReady(this))
                    "openDeveloperSettings" -> {
                        try {
                            startActivity(Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS))
                        } catch (e: Exception) {
                            startActivity(Intent(Settings.ACTION_SETTINGS))
                        }
                        result.success(null)
                    }
                    "update" -> {
                        val i = Intent(this, MockLocationService::class.java)
                            .putExtra("lat", (call.argument<Double>("lat") ?: 0.0))
                            .putExtra("lng", (call.argument<Double>("lng") ?: 0.0))
                            .putExtra("speed", (call.argument<Double>("speed") ?: 0.0).toFloat())
                            .putExtra("bearing", (call.argument<Double>("bearing") ?: 0.0).toFloat())
                        ContextCompat.startForegroundService(this, i)
                        result.success(null)
                    }
                    "stop" -> {
                        stopService(Intent(this, MockLocationService::class.java))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
