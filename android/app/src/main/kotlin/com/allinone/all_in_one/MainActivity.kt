package com.allinone.all_in_one

import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.graphics.Bitmap
import android.media.AudioManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.provider.MediaStore
import android.util.Size
import android.view.WindowManager
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/**
 * Extends AudioServiceActivity so playback keeps running in the background.
 * Also exposes the device music library and storage figures to Flutter.
 */
class MainActivity : AudioServiceActivity() {
    private val executor = Executors.newFixedThreadPool(4)
    private val main = Handler(Looper.getMainLooper())
    private val pdf = PdfDocuments()
    private val effects = AudioEffects()
    private val video by lazy { VideoExporter(this) }
    private val intake by lazy { ShareIntake(this, executor, main) }
    private val tools by lazy { DeviceTools(this) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Not after a recreation (rotation): the intent was already read.
        if (savedInstanceState == null) intake.handle(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        intake.handle(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "allinone/orientation")
            .setStreamHandler(tools)
        val media = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "allinone/media")
        intake.channel = media
        media.setMethodCallHandler { call, result ->
                // Window and volume calls are instant and need the UI thread.
                if (handleOnMainThread(call, result)) return@setMethodCallHandler
                // Every other call touches disk, so none runs on the UI thread.
                executor.execute {
                    try {
                        val value: Any? = when (call.method) {
                            "songs" -> querySongs()
                            "artwork" -> artwork(
                                (call.argument<Number>("songId"))!!.toLong(),
                                (call.argument<Number>("albumId"))!!.toLong(),
                                call.argument<Int>("size") ?: 512,
                            )
                            "storage" -> storage()
                            "media" -> queryMedia()
                            "calendarEvents" -> calendarEvents(
                                (call.argument<Number>("start"))!!.toLong(),
                                (call.argument<Number>("end"))!!.toLong(),
                            )
                            "thumbnail" -> thumbnail(
                                (call.argument<Number>("id"))!!.toLong(),
                                call.argument<Boolean>("video") ?: false,
                                call.argument<Int>("size") ?: 256,
                            )
                            "pdfOpen" -> pdf.open(call.argument<String>("path")!!)
                            "pdfRender" -> pdf.render(
                                call.argument<Int>("id")!!,
                                call.argument<Int>("page")!!,
                                call.argument<Int>("width")!!,
                            )
                            "pdfClose" -> {
                                pdf.close(call.argument<Int>("id")!!)
                                null
                            }
                            "scan" -> {
                                val paths = call.argument<List<String>>("paths") ?: emptyList()
                                MediaScannerConnection.scanFile(this, paths.toTypedArray(), null, null)
                                null
                            }
                            else -> NOT_IMPLEMENTED
                        }
                        main.post {
                            if (value === NOT_IMPLEMENTED) result.notImplemented() else result.success(value)
                        }
                    } catch (e: Exception) {
                        main.post { result.error("media_error", e.message, null) }
                    }
                }
            }
    }

    private var pipArmed = false
    private var pipWidth = 16
    private var pipHeight = 9

    /** Floating window for the video player (Android 8+). */
    private fun enterPip(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        if (!packageManager.hasSystemFeature(android.content.pm.PackageManager.FEATURE_PICTURE_IN_PICTURE)) return false
        // Android only accepts ratios between about 0.42 and 2.39.
        val ratio = (pipWidth.toDouble() / pipHeight.coerceAtLeast(1)).coerceIn(0.5, 2.0)
        val params = android.app.PictureInPictureParams.Builder()
            .setAspectRatio(android.util.Rational((ratio * 1000).toInt(), 1000))
            .build()
        return try {
            enterPictureInPictureMode(params)
        } catch (e: IllegalStateException) {
            false
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (pipArmed) enterPip()
    }

    private fun handleOnMainThread(call: MethodCall, result: MethodChannel.Result): Boolean {
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
        when (call.method) {
            "getBrightness" -> {
                val own = window.attributes.screenBrightness
                val value = if (own >= 0f) own else try {
                    android.provider.Settings.System.getInt(
                        contentResolver, android.provider.Settings.System.SCREEN_BRIGHTNESS
                    ) / 255f
                } catch (e: Exception) {
                    0.5f
                }
                result.success(value.toDouble().coerceIn(0.0, 1.0))
            }
            // A negative value hands brightness back to the system.
            "setBrightness" -> {
                val value = (call.argument<Number>("value"))!!.toFloat()
                window.attributes = window.attributes.apply {
                    screenBrightness = if (value < 0f) -1f else value.coerceIn(0.01f, 1f)
                }
                result.success(null)
            }
            "getVolume" -> result.success(
                audio.getStreamVolume(AudioManager.STREAM_MUSIC).toDouble() / max
            )
            "setVolume" -> {
                val value = (call.argument<Number>("value"))!!.toDouble().coerceIn(0.0, 1.0)
                audio.setStreamVolume(AudioManager.STREAM_MUSIC, Math.round(value * max).toInt(), 0)
                result.success(null)
            }
            "effects" -> result.success(
                effects.apply(
                    call.argument<Int>("session")!!,
                    call.argument<Boolean>("enabled") ?: false,
                    call.argument<List<Double>>("levels") ?: emptyList(),
                    call.argument<Double>("bass") ?: 0.0,
                    call.argument<Double>("widening") ?: 0.0,
                    call.argument<Double>("gain") ?: 0.0,
                    call.argument<Double>("balance") ?: 0.0,
                )
            )
            "sharedContent" -> result.success(intake.take())
            "exportVideo" -> {
                @Suppress("UNCHECKED_CAST")
                video.export(call.arguments as Map<String, Any?>, result)
            }
            "exportProgress" -> result.success(video.progress())
            "cancelExport" -> {
                video.cancel()
                result.success(null)
            }
            "hasTorch" -> result.success(tools.hasTorch())
            "torch" -> result.success(tools.setTorch(call.argument<Boolean>("on") == true))
            "dpi" -> result.success(tools.dpi())
            "ring" -> {
                if (call.argument<Boolean>("on") == true) tools.ring() else tools.stopRing()
                result.success(null)
            }
            "setAlarm" -> result.success(
                tools.setAlarm(
                    call.argument<Int>("hour")!!,
                    call.argument<Int>("minute")!!,
                    call.argument<String>("label") ?: "",
                )
            )
            "audioOutput" -> {
                val types = audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                    .map { it.type to it.productName.toString() }
                // Bluetooth (A2DP 8, SCO 7, BLE 26/27/30) wins over cables, then the speaker.
                val bluetooth = types.firstOrNull { it.first in listOf(7, 8, 26, 27, 30) }
                val wired = types.firstOrNull { it.first in listOf(3, 4) }
                val usb = types.firstOrNull { it.first in listOf(11, 22) }
                val out = when {
                    bluetooth != null -> mapOf("type" to "bluetooth", "name" to bluetooth.second)
                    wired != null -> mapOf("type" to "wired", "name" to wired.second)
                    usb != null -> mapOf("type" to "usb", "name" to usb.second)
                    else -> mapOf("type" to "speaker", "name" to "")
                }
                result.success(out)
            }
            "pipArm" -> {
                pipArmed = call.argument<Boolean>("on") == true
                pipWidth = call.argument<Number>("w")?.toInt() ?: 16
                pipHeight = call.argument<Number>("h")?.toInt() ?: 9
                result.success(null)
            }
            "pipEnter" -> {
                pipWidth = call.argument<Number>("w")?.toInt() ?: 16
                pipHeight = call.argument<Number>("h")?.toInt() ?: 9
                result.success(enterPip())
            }
            "keepScreenOn" -> {
                if (call.argument<Boolean>("on") == true) {
                    window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                } else {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                }
                result.success(null)
            }
            else -> return false
        }
        return true
    }

    /** Occurrences of the phone's calendar events between two instants. */
    private fun calendarEvents(start: Long, end: Long): List<Map<String, Any?>> {
        val events = ArrayList<Map<String, Any?>>()
        val uri = android.provider.CalendarContract.Instances.CONTENT_URI.buildUpon()
            .appendPath(start.toString())
            .appendPath(end.toString())
            .build()
        val columns = arrayOf(
            android.provider.CalendarContract.Instances.EVENT_ID,
            android.provider.CalendarContract.Instances.TITLE,
            android.provider.CalendarContract.Instances.BEGIN,
            android.provider.CalendarContract.Instances.END,
            android.provider.CalendarContract.Instances.ALL_DAY,
            android.provider.CalendarContract.Instances.DISPLAY_COLOR,
            android.provider.CalendarContract.Instances.EVENT_LOCATION,
            android.provider.CalendarContract.Instances.CALENDAR_DISPLAY_NAME,
        )
        try {
            contentResolver.query(uri, columns, null, null, null)?.use { c ->
                while (c.moveToNext()) {
                    events.add(
                        mapOf(
                            "id" to c.getLong(0),
                            "title" to c.getString(1),
                            "start" to c.getLong(2),
                            "end" to c.getLong(3),
                            "allDay" to (c.getInt(4) != 0),
                            "color" to c.getInt(5),
                            "location" to c.getString(6),
                            "calendar" to c.getString(7),
                        )
                    )
                }
            }
        } catch (e: SecurityException) {
            // Calendar access not granted: no device events.
        }
        return events
    }

    /** Every photo and video of the device, unsorted. */
    private fun queryMedia(): List<Map<String, Any?>> {
        val items = ArrayList<Map<String, Any?>>()
        fun collect(base: Uri, video: Boolean) {
            val columns = arrayListOf(
                MediaStore.MediaColumns._ID,
                MediaStore.MediaColumns.DATA,
                MediaStore.MediaColumns.DISPLAY_NAME,
                MediaStore.MediaColumns.DATE_MODIFIED,
                MediaStore.MediaColumns.SIZE,
                MediaStore.MediaColumns.WIDTH,
                MediaStore.MediaColumns.HEIGHT,
                "datetaken",
                "bucket_display_name",
            )
            if (video) columns.add("duration")
            try {
                contentResolver.query(base, columns.toTypedArray(), null, null, null)?.use { c ->
                    while (c.moveToNext()) {
                        val id = c.getLong(0)
                        val taken = if (c.isNull(7)) 0L else c.getLong(7)
                        items.add(
                            mapOf(
                                "id" to id,
                                "video" to video,
                                "path" to c.getString(1),
                                "name" to c.getString(2),
                                // Milliseconds; falls back to the modification date.
                                "date" to if (taken > 0L) taken else c.getLong(3) * 1000L,
                                "size" to c.getLong(4),
                                "width" to c.getInt(5),
                                "height" to c.getInt(6),
                                "album" to c.getString(8),
                                "duration" to if (video) c.getLong(9) else 0L,
                                "uri" to ContentUris.withAppendedId(base, id).toString(),
                            )
                        )
                    }
                }
            } catch (e: SecurityException) {
                // Permission for this media type not granted: skip it.
            }
        }
        collect(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, false)
        collect(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, true)
        return items
    }

    /** Thumbnail of a photo or video as JPEG bytes, or null. */
    private fun thumbnail(id: Long, video: Boolean, size: Int): ByteArray? {
        return try {
            val bitmap: Bitmap? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val base = if (video) MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                else MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                contentResolver.loadThumbnail(ContentUris.withAppendedId(base, id), Size(size, size), null)
            } else if (video) {
                @Suppress("DEPRECATION")
                MediaStore.Video.Thumbnails.getThumbnail(
                    contentResolver, id, MediaStore.Video.Thumbnails.MINI_KIND, null
                )
            } else {
                @Suppress("DEPRECATION")
                MediaStore.Images.Thumbnails.getThumbnail(
                    contentResolver, id, MediaStore.Images.Thumbnails.MINI_KIND, null
                )
            }
            bitmap?.let {
                ByteArrayOutputStream().use { out ->
                    it.compress(Bitmap.CompressFormat.JPEG, 82, out)
                    it.recycle()
                    out.toByteArray()
                }
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun querySongs(): List<Map<String, Any?>> {
        val songs = ArrayList<Map<String, Any?>>()
        val columns = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.ALBUM_ID,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.TRACK,
            MediaStore.Audio.Media.DATE_ADDED,
            MediaStore.Audio.Media.DATA,
        )
        contentResolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            columns,
            "${MediaStore.Audio.Media.IS_MUSIC} != 0",
            null,
            "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE ASC",
        )?.use { c ->
            while (c.moveToNext()) {
                val id = c.getLong(0)
                songs.add(
                    mapOf(
                        "id" to id,
                        "title" to c.getString(1),
                        "artist" to c.getString(2),
                        "album" to c.getString(3),
                        "albumId" to c.getLong(4),
                        "duration" to c.getLong(5),
                        "track" to c.getInt(6),
                        "dateAdded" to c.getLong(7),
                        "path" to c.getString(8),
                        "uri" to ContentUris.withAppendedId(
                            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id
                        ).toString(),
                    )
                )
            }
        }
        return songs
    }

    /** Cover art as JPEG bytes, or null when the track has none. */
    private fun artwork(songId: Long, albumId: Long, size: Int): ByteArray? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val uri = ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, songId)
                val bitmap = contentResolver.loadThumbnail(uri, Size(size, size), null)
                ByteArrayOutputStream().use { out ->
                    bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 88, out)
                    bitmap.recycle()
                    out.toByteArray()
                }
            } else {
                val uri = ContentUris.withAppendedId(Uri.parse("content://media/external/audio/albumart"), albumId)
                contentResolver.openInputStream(uri)?.use { it.readBytes() }
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun storage(): Map<String, Long> {
        val stat = StatFs(Environment.getExternalStorageDirectory().path)
        return mapOf("total" to stat.totalBytes, "free" to stat.availableBytes)
    }

    override fun onDestroy() {
        video.cancel()
        tools.release()
        effects.release()
        pdf.closeAll()
        executor.shutdown()
        super.onDestroy()
    }

    private companion object {
        val NOT_IMPLEMENTED = Any()
    }
}
