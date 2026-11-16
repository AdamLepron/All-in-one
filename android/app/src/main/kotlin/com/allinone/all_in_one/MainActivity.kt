package com.allinone.all_in_one

import android.content.ContentUris
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.provider.MediaStore
import android.util.Size
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/**
 * Extends AudioServiceActivity so playback keeps running in the background.
 * Also exposes the device music library and storage figures to Flutter.
 */
class MainActivity : AudioServiceActivity() {
    private val executor = Executors.newFixedThreadPool(3)
    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "allinone/media")
            .setMethodCallHandler { call, result ->
                // Every call touches disk, so none runs on the UI thread.
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
        executor.shutdown()
        super.onDestroy()
    }

    private companion object {
        val NOT_IMPLEMENTED = Any()
    }
}
