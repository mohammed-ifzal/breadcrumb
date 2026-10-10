package com.teamgroza.breadcrumb

import android.app.ActivityManager
import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import kotlin.math.sqrt

/** Raw sensor transport only. All step/turn decisions belong to Dart. */
class SensingChannel(private val context: Context, messenger: BinaryMessenger) :
    EventChannel.StreamHandler, SensorEventListener {
    private val manager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val main = Handler(Looper.getMainLooper())
    private val channel = EventChannel(messenger, "breadcrumb/sensing")
    private val step = optionalSensor(Sensor.TYPE_STEP_DETECTOR)
    private val gyro = manager.getDefaultSensor(Sensor.TYPE_GYROSCOPE)
    private val accelerometer = manager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
    private val gravity = optionalSensor(Sensor.TYPE_GRAVITY)
    private val proximity = optionalSensor(Sensor.TYPE_PROXIMITY)
    private val light = optionalSensor(Sensor.TYPE_LIGHT)
    private var sink: EventChannel.EventSink? = null
    private var startNs = 0L
    private var registered = false
    private var paused = false
    private var stepUnavailable = false
    private val unavailable = mutableSetOf<Int>()
    private val reportedAvailable = mutableSetOf<Int>()
    private var usingGravitySensor = false
    private var gravityVector: DoubleArray? = null
    private var acceleration: Double? = null
    // Coefficients and feature flags come from Dart tuning. Legacy clients
    // without options use an unfiltered accelerometer fallback.
    private var gravityLowPassEnabled = false
    private var gravityAlpha = 0.0
    private var lightCoalescingEnabled = false
    private var lastProximity: Pair<Boolean, Double>? = null
    private var lastLightLux: Double? = null
    private var lastLightEmissionNs: Long? = null
    private var pendingLight: Pair<Long, Double>? = null
    private val lightFlush = Runnable { flushLight() }

    init { channel.setStreamHandler(this) }

    private fun optionalSensor(type: Int): Sensor? =
        try { manager.getDefaultSensor(type) } catch (_: RuntimeException) { null }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        unregister()
        sink = events
        startNs = SystemClock.elapsedRealtimeNanos()
        stepUnavailable = false
        unavailable.clear()
        reportedAvailable.clear()
        lastProximity = null
        lastLightLux = null
        lastLightEmissionNs = null
        val options = arguments as? Map<*, *>
        val alpha = (options?.get("gravityFallbackLowPassAlpha") as? Number)?.toDouble()
        gravityLowPassEnabled = options?.get("gravityFallbackLowPassEnabled") == true &&
            alpha != null && alpha.isFinite() && alpha >= 0.0 && alpha < 1.0
        gravityAlpha = if (gravityLowPassEnabled) alpha!! else 0.0
        lightCoalescingEnabled = options?.get("lightCoalescingEnabled") == true
        if (step == null) disableStep()
        emitMemoryInfo()
        if (!paused) register()
    }

    override fun onCancel(arguments: Any?) { unregister(); sink = null }
    fun pause() { paused = true; unregister() }
    fun resume() { paused = false; if (sink != null) register() }
    fun dispose() { onCancel(null); channel.setStreamHandler(null) }

    private fun emitMemoryInfo() {
        try {
            val activity = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val memory = ActivityManager.MemoryInfo()
            activity.getMemoryInfo(memory)
            // Binary MB: unit conversion, never a sensing threshold.
            emit(mapOf("type" to "info", "t" to 0L, "totalRamMb" to memory.totalMem / (1024L * 1024L)))
        } catch (_: RuntimeException) {
            emit(mapOf("type" to "info", "t" to 0L, "totalRamAvailable" to false))
        }
    }

    private fun register() {
        if (registered) return
        if (gyro == null || accelerometer == null) {
            fail("sensor_unavailable", "Gyroscope and accelerometer sensors are required.")
            return
        }
        try {
            // 20,000 us requests about 50 Hz; zero batch latency sends live data.
            for (sensor in listOfNotNull(accelerometer, gyro)) {
                if (!manager.registerListener(this, sensor, 20_000, 0, main)) {
                    unregister()
                    fail("sensor_unavailable", "Could not register sensor " + sensor.name)
                    return
                }
            }
            registered = true
        } catch (error: RuntimeException) {
            unregister()
            val code = if (error is SecurityException) "permission_denied" else "sensor_unavailable"
            fail(code, error.message ?: "Could not register motion sensors.")
            return
        }
        // Independent optional registrations never unregister motion or steps.
        usingGravitySensor = registerOptional(gravity, Sensor.TYPE_GRAVITY, "gravityAvailable", 20_000)
        registerOptional(proximity, Sensor.TYPE_PROXIMITY, "proximityAvailable", SensorManager.SENSOR_DELAY_NORMAL)
        registerOptional(light, Sensor.TYPE_LIGHT, "lightAvailable", 200_000)
        if (step != null && !stepUnavailable) {
            try {
                if (!manager.registerListener(this, step, 20_000, 0, main)) disableStep()
            } catch (_: RuntimeException) { disableStep() }
        }
    }

    private fun registerOptional(sensor: Sensor?, type: Int, flag: String, periodUs: Int): Boolean {
        if (type in unavailable) return false
        if (sensor == null) { disableOptional(sensor, type, flag); return false }
        try {
            if (!manager.registerListener(this, sensor, periodUs, 0, main)) {
                disableOptional(sensor, type, flag)
                return false
            }
        } catch (_: RuntimeException) { disableOptional(sensor, type, flag); return false }
        if (reportedAvailable.add(type)) {
            val info = mutableMapOf<String, Any>("type" to "info", "t" to elapsedMs(), flag to true)
            if (type == Sensor.TYPE_GRAVITY) {
                info["gravitySource"] = "sensor"
                info["gravityLowPassEnabled"] = false
            }
            emit(info)
        }
        return true
    }

    private fun disableOptional(sensor: Sensor?, type: Int, flag: String) {
        if (!unavailable.add(type)) return
        if (sensor != null) {
            try { manager.unregisterListener(this, sensor) } catch (_: RuntimeException) { }
        }
        val info = mutableMapOf<String, Any>("type" to "info", "t" to elapsedMs(), flag to false)
        if (type == Sensor.TYPE_GRAVITY) {
            usingGravitySensor = false
            gravityVector = null
            info["gravitySource"] = "accelerometer"
            info["gravityLowPassEnabled"] = gravityLowPassEnabled
        }
        if (type == Sensor.TYPE_LIGHT) { main.removeCallbacks(lightFlush); pendingLight = null }
        emit(info)
    }

    private fun disableStep() {
        if (stepUnavailable) return
        stepUnavailable = true
        if (step != null) {
            try { manager.unregisterListener(this, step) } catch (_: RuntimeException) { }
        }
        emit(mapOf("type" to "info", "stepDetector" to false))
    }

    private fun emitStep(t: Long) {
        emit(mapOf("type" to "step", "t" to t),
            allowed = { !stepUnavailable }, onFailure = { disableStep() })
    }

    private fun unregister() {
        try { manager.unregisterListener(this) } catch (_: RuntimeException) { }
        registered = false
        usingGravitySensor = false
        gravityVector = null
        acceleration = null
        pendingLight = null
        main.removeCallbacks(lightFlush)
    }

    private fun elapsedMs(): Long = (SystemClock.elapsedRealtimeNanos() - startNs) / 1_000_000L

    private fun fail(code: String, message: String) {
        val target = sink ?: return
        main.post {
            if (sink === target) {
                try { target.error(code, message, null) } catch (_: RuntimeException) { }
            }
        }
    }

    private fun emit(event: Map<String, Any>, allowed: () -> Boolean = { true }, onFailure: (() -> Unit)? = null) {
        val target = sink ?: return
        main.post {
            if (sink === target && allowed()) {
                try { target.success(event) } catch (_: RuntimeException) { onFailure?.invoke() }
            }
        }
    }

    private fun queueLight(t: Long, lux: Double) {
        if (pendingLight == null && lux == lastLightLux) return
        val now = SystemClock.elapsedRealtimeNanos()
        val last = lastLightEmissionNs
        // 200 ms enforces the requested 5 Hz transport limit, not a detector gate.
        if (!lightCoalescingEnabled && last != null && now - last < 200_000_000L) return
        pendingLight = Pair(t, lux)
        flushLight()
    }

    // Both sensor callbacks and the single delayed flush run on the main handler.
    private fun flushLight() {
        main.removeCallbacks(lightFlush)
        if (sink == null || paused || Sensor.TYPE_LIGHT in unavailable) { pendingLight = null; return }
        val sample = pendingLight ?: return
        val now = SystemClock.elapsedRealtimeNanos()
        val last = lastLightEmissionNs
        val waitNs = if (last == null) 0L else 200_000_000L - (now - last)
        if (waitNs > 0) {
            main.postDelayed(lightFlush, (waitNs + 999_999L) / 1_000_000L)
            return
        }
        pendingLight = null
        if (sample.second == lastLightLux) return
        lastLightEmissionNs = now
        lastLightLux = sample.second
        // Main-thread delivery here prevents a second queue from bunching events.
        try {
            sink?.success(mapOf("type" to "light", "t" to sample.first, "lux" to sample.second))
        } catch (_: RuntimeException) { disableOptional(light, Sensor.TYPE_LIGHT, "lightAvailable") }
    }

    override fun onSensorChanged(event: SensorEvent) {
        if (sink == null || paused || event.timestamp < startNs) return
        val t = (event.timestamp - startNs) / 1_000_000L
        when (event.sensor.type) {
            Sensor.TYPE_STEP_DETECTOR -> emitStep(t)
            Sensor.TYPE_GRAVITY -> {
                if (!usingGravitySensor) return
                try {
                    val vector = DoubleArray(3) { event.values[it].toDouble() }
                    if (!vector.all { it.isFinite() } || vector.all { it == 0.0 }) throw IllegalArgumentException("Invalid gravity vector")
                    gravityVector = vector
                } catch (_: RuntimeException) { disableOptional(gravity, Sensor.TYPE_GRAVITY, "gravityAvailable") }
            }
            Sensor.TYPE_ACCELEROMETER -> {
                val vector = DoubleArray(3) { event.values[it].toDouble() }
                acceleration = sqrt(vector.sumOf { it * it })
                if (!usingGravitySensor) {
                    val previous = gravityVector
                    gravityVector = if (previous == null || !gravityLowPassEnabled) vector else
                        DoubleArray(3) { gravityAlpha * previous[it] + (1.0 - gravityAlpha) * vector[it] }
                }
            }
            Sensor.TYPE_GYROSCOPE -> {
                val g = gravityVector ?: return
                val accel = acceleration ?: return
                val norm = sqrt(g.sumOf { it * it })
                if (norm == 0.0) return
                val radiansPerSecond = (0..2).sumOf { event.values[it].toDouble() * g[it] / norm }
                emit(mapOf("type" to "gravity", "t" to t, "x" to g[0], "y" to g[1], "z" to g[2],
                    "source" to if (usingGravitySensor) "sensor" else "accelerometer"),
                    onFailure = { if (usingGravitySensor) disableOptional(gravity, Sensor.TYPE_GRAVITY, "gravityAvailable") })
                // Same gyro projection and convention: deg/s, positive = left.
                emit(mapOf("type" to "motion", "t" to t,
                    "yawRate" to Math.toDegrees(radiansPerSecond), "accel" to accel))
            }
            Sensor.TYPE_PROXIMITY -> {
                if (Sensor.TYPE_PROXIMITY in unavailable) return
                try {
                    val cm = event.values[0].toDouble()
                    if (!cm.isFinite() || cm < 0.0) throw IllegalArgumentException("Invalid proximity distance")
                    // Sensor-defined near/far range, never a hardcoded cm gate.
                    val sample = Pair(cm < event.sensor.maximumRange.toDouble(), cm)
                    if (sample != lastProximity) {
                        lastProximity = sample
                        emit(mapOf("type" to "proximity", "t" to t, "near" to sample.first, "cm" to cm),
                            allowed = { Sensor.TYPE_PROXIMITY !in unavailable && !paused },
                            onFailure = { disableOptional(proximity, Sensor.TYPE_PROXIMITY, "proximityAvailable") })
                    }
                } catch (_: RuntimeException) { disableOptional(proximity, Sensor.TYPE_PROXIMITY, "proximityAvailable") }
            }
            Sensor.TYPE_LIGHT -> {
                if (Sensor.TYPE_LIGHT in unavailable) return
                try {
                    val lux = event.values[0].toDouble()
                    if (!lux.isFinite() || lux < 0.0) throw IllegalArgumentException("Invalid illuminance")
                    queueLight(t, lux)
                } catch (_: RuntimeException) { disableOptional(light, Sensor.TYPE_LIGHT, "lightAvailable") }
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
}
