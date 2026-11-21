package com.geoshift.geoshift

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.location.Criteria
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import androidx.core.app.NotificationCompat

object MockEngine {
    @Volatile var running = false
    private val providers = arrayOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)

    private fun lm(c: Context) = c.getSystemService(Context.LOCATION_SERVICE) as LocationManager

    fun setup(c: Context): Boolean {
        val m = lm(c)
        return try {
            for (p in providers) {
                try { m.removeTestProvider(p) } catch (_: Exception) {}
                m.addTestProvider(p, false, false, false, false, true, true, true,
                    Criteria.POWER_LOW, Criteria.ACCURACY_FINE)
                m.setTestProviderEnabled(p, true)
            }
            true
        } catch (e: SecurityException) { false }
        catch (e: IllegalArgumentException) { false }
    }

    fun teardown(c: Context) {
        val m = lm(c)
        for (p in providers) {
            try { m.setTestProviderEnabled(p, false) } catch (_: Exception) {}
            try { m.removeTestProvider(p) } catch (_: Exception) {}
        }
    }

    fun isReady(c: Context): Boolean {
        if (running) return true
        val ok = setup(c)
        if (ok) teardown(c)
        return ok
    }

    fun push(c: Context, lat: Double, lng: Double, speed: Float, bearing: Float) {
        val m = lm(c)
        for (p in providers) {
            val l = Location(p).apply {
                latitude = lat
                longitude = lng
                altitude = 10.0
                accuracy = 4f
                this.speed = speed
                this.bearing = bearing
                time = System.currentTimeMillis()
                elapsedRealtimeNanos = SystemClock.elapsedRealtimeNanos()
                if (Build.VERSION.SDK_INT >= 26) {
                    verticalAccuracyMeters = 4f
                    speedAccuracyMetersPerSecond = 1f
                    bearingAccuracyDegrees = 5f
                }
            }
            try { m.setTestProviderLocation(p, l) } catch (_: Exception) {}
        }
    }
}

class MockLocationService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var lat = 0.0
    private var lng = 0.0
    private var speed = 0f
    private var bearing = 0f

    private val tick = object : Runnable {
        override fun run() {
            MockEngine.push(this@MockLocationService, lat, lng, speed, bearing)
            handler.postDelayed(this, 1000)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        intent?.let {
            lat = it.getDoubleExtra("lat", lat)
            lng = it.getDoubleExtra("lng", lng)
            speed = it.getFloatExtra("speed", 0f)
            bearing = it.getFloatExtra("bearing", 0f)
        }
        if (!MockEngine.running) {
            goForeground()
            if (!MockEngine.setup(this)) { stopSelf(); return START_NOT_STICKY }
            MockEngine.running = true
        }
        handler.removeCallbacks(tick)
        handler.post(tick)
        return START_NOT_STICKY
    }

    private fun goForeground() {
        val ch = "geoshift_mock"
        if (Build.VERSION.SDK_INT >= 26) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(
                NotificationChannel(ch, "GeoShift", NotificationManager.IMPORTANCE_LOW))
        }
        val n: Notification = NotificationCompat.Builder(this, ch)
            .setContentTitle("GeoShift")
            .setContentText("الموقع الوهمي شغال")
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(1, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(1, n)
        }
    }

    override fun onDestroy() {
        handler.removeCallbacks(tick)
        if (MockEngine.running) {
            MockEngine.teardown(this)
            MockEngine.running = false
        }
        super.onDestroy()
    }
}
