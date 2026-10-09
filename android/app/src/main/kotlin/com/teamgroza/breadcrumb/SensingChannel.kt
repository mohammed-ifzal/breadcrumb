package com.teamgroza.breadcrumb

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
class SensingChannel(context: Context, messenger: BinaryMessenger) :
    EventChannel.StreamHandler, SensorEventListener {
    private val manager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val main = Handler(Looper.getMainLooper())
    private val channel = EventChannel(messenger, "breadcrumb/sensing")
    private val step = manager.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR)
    private val gyro = manager.getDefaultSensor(Sensor.TYPE_GYROSCOPE)
    private val gravity = manager.getDefaultSensor(Sensor.TYPE_GRAVITY)
    private val accelerometer = manager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
    private var sink: EventChannel.EventSink? = null
    private var startNs = 0L
    private var registered = false
    private var paused = false
    private var stepUnavailable = false
    private var gravityVector: DoubleArray? = null
    private var acceleration: Double? = null

    init { channel.setStreamHandler(this) }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        unregister()
        sink = events
        startNs = SystemClock.elapsedRealtimeNanos()
        gravityVector = null
        acceleration = null
        stepUnavailable = false
        if (step == null) disableStep()
        if (!paused) register()
    }

    override fun onCancel(arguments: Any?) {
        unregister()
        sink = null
    }

    fun pause() {
        paused = true
        unregister()
    }

    fun resume() {
        paused = false
        if (sink != null) register()
    }

    fun dispose() {
        onCancel(null)
        channel.setStreamHandler(null)
    }

    private fun register() {
        if (registered) return
        if (gyro == null || gravity == null || accelerometer == null) {
            fail("sensor_unavailable", "Gyroscope, gravity and accelerometer sensors are required.")
            return
        }
        try {
            // 20,000 microseconds requests about 50 Hz; this is a sampling period,
            // not a detection threshold. A zero batch latency sends samples live.
            for (sensor in listOfNotNull(gravity, accelerometer, gyro)) {
                if (!manager.registerListener(this, sensor, 20_000, 0, main)) {
                    unregister()
                    fail("sensor_unavailable", "Could not register sensor ${sensor.name}.")
                    return
                }
            }
            registered = true
            // Step detection is optional; its permission/registration failure must
            // never unregister the motion sensors that have already succeeded.
            if (step != null && !stepUnavailable) {
                try {
                    if (!manager.registerListener(this, step, 20_000, 0, main)) disableStep()
                } catch (error: RuntimeException) {
                    disableStep()
                }
            }
        } catch (error: SecurityException) {
            unregister()
            fail("permission_denied", error.message ?: "Grant activity recognition externally.")
        }
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
        val target = sink ?: return
        main.post {
            if (sink === target && !stepUnavailable) {
                try { target.success(mapOf("type" to "step", "t" to t)) }
                catch (_: RuntimeException) { disableStep() }
            }
        }
    }

    private fun unregister() {
        manager.unregisterListener(this)
        registered = false
    }

    private fun fail(code: String, message: String) {
        val target = sink ?: return
        main.post { if (sink === target) target.error(code, message, null) }
    }

    private fun emit(event: Map<String, Any>) {
        val target = sink ?: return
        main.post { if (sink === target) target.success(event) }
    }

    override fun onSensorChanged(event: SensorEvent) {
        if (sink == null || paused || event.timestamp < startNs) return
        val t = (event.timestamp - startNs) / 1_000_000L
        when (event.sensor.type) {
            Sensor.TYPE_STEP_DETECTOR -> emitStep(t)
            Sensor.TYPE_GRAVITY -> gravityVector = DoubleArray(3) { event.values[it].toDouble() }
            Sensor.TYPE_ACCELEROMETER -> {
                acceleration = sqrt(event.values.sumOf { it.toDouble() * it.toDouble() })
            }
            Sensor.TYPE_GYROSCOPE -> {
                val g = gravityVector ?: return
                val accel = acceleration ?: return
                val norm = sqrt(g.sumOf { it * it })
                if (norm == 0.0) return
                // Android's positive rotation around the upward gravity axis is
                // counter-clockwise when viewed from above: positive means left.
                val radiansPerSecond = (0..2).sumOf { event.values[it].toDouble() * g[it] / norm }
                emit(mapOf("type" to "motion", "t" to t,
                    "yawRate" to Math.toDegrees(radiansPerSecond), "accel" to accel))
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
}
