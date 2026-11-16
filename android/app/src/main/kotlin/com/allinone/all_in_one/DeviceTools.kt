package com.allinone.all_in_one

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.provider.AlarmClock
import io.flutter.plugin.common.EventChannel

/** Torch, orientation sensor, alarm sound and system alarm creation. */
class DeviceTools(private val activity: Activity) : EventChannel.StreamHandler, SensorEventListener {
    private val sensors = activity.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private var events: EventChannel.EventSink? = null
    private var ringtone: Ringtone? = null
    private var torchOn = false

    private fun torchCamera(): Pair<CameraManager, String>? {
        val manager = activity.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val id = manager.cameraIdList.firstOrNull {
            manager.getCameraCharacteristics(it)
                .get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
        } ?: return null
        return manager to id
    }

    fun hasTorch(): Boolean = try {
        torchCamera() != null
    } catch (e: Exception) {
        false
    }

    /** Returns false when the device has no flash or it is in use. */
    fun setTorch(on: Boolean): Boolean = try {
        val (manager, id) = torchCamera() ?: return false
        manager.setTorchMode(id, on)
        torchOn = on
        true
    } catch (e: Exception) {
        false
    }

    /** Physical pixel density, used to draw a ruler to scale. */
    fun dpi(): Map<String, Double> {
        val metrics = activity.resources.displayMetrics
        return mapOf(
            "xdpi" to metrics.xdpi.toDouble(),
            "ydpi" to metrics.ydpi.toDouble(),
            "density" to metrics.density.toDouble(),
        )
    }

    /** Plays the default alarm sound until [stopRing]. */
    fun ring() {
        stopRing()
        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        ringtone = RingtoneManager.getRingtone(activity, uri)?.also {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) it.isLooping = true
            it.play()
        }
    }

    fun stopRing() {
        ringtone?.stop()
        ringtone = null
    }

    /** Hands a new alarm to the system clock app; false if there is none. */
    fun setAlarm(hour: Int, minute: Int, label: String): Boolean = try {
        activity.startActivity(
            Intent(AlarmClock.ACTION_SET_ALARM)
                .putExtra(AlarmClock.EXTRA_HOUR, hour)
                .putExtra(AlarmClock.EXTRA_MINUTES, minute)
                .putExtra(AlarmClock.EXTRA_MESSAGE, label)
        )
        true
    } catch (e: Exception) {
        false
    }

    // ---- Orientation stream: [azimuth, pitch, roll] in degrees ----

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        val sensor = sensors.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
        if (sensor == null) {
            sink.error("no_sensor", "Capteur d'orientation absent", null)
            return
        }
        events = sink
        sensors.registerListener(this, sensor, SensorManager.SENSOR_DELAY_UI)
    }

    override fun onCancel(arguments: Any?) {
        sensors.unregisterListener(this)
        events = null
    }

    private val rotation = FloatArray(9)
    private val angles = FloatArray(3)

    override fun onSensorChanged(event: SensorEvent) {
        SensorManager.getRotationMatrixFromVector(rotation, event.values)
        SensorManager.getOrientation(rotation, angles)
        val azimuth = (Math.toDegrees(angles[0].toDouble()) + 360.0) % 360.0
        events?.success(
            listOf(
                azimuth,
                Math.toDegrees(angles[1].toDouble()),
                Math.toDegrees(angles[2].toDouble()),
            )
        )
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    fun release() {
        sensors.unregisterListener(this)
        stopRing()
        if (torchOn) setTorch(false)
    }
}
