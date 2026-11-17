package com.allinone.all_in_one

import android.app.Activity
import android.net.Uri
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.SpeedParameters
import androidx.media3.common.audio.SpeedProvider
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.Presentation
import androidx.media3.effect.ScaleAndRotateTransformation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Exports a montage of trimmed clips (speed, rotation, optional music)
 * with Media3 Transformer. Every method runs on the main thread.
 */
@OptIn(UnstableApi::class)
class VideoExporter(private val activity: Activity) {
    private var transformer: Transformer? = null
    private var output: String? = null
    private val holder = ProgressHolder()

    private fun uriOf(value: String): Uri =
        if (value.contains("://")) Uri.parse(value) else Uri.fromFile(File(value))

    private fun constantSpeed(speed: Float) = object : SpeedProvider {
        override fun getSpeed(timeUs: Long) = speed
        override fun getNextSpeedChangeTimeUs(timeUs: Long) = C.TIME_UNSET
    }

    /** 0–100 while exporting, or -1 when no progress is available. */
    fun progress(): Int {
        val t = transformer ?: return -1
        return if (t.getProgress(holder) == Transformer.PROGRESS_STATE_AVAILABLE) holder.progress else -1
    }

    fun cancel() {
        transformer?.cancel()
        transformer = null
        output?.let { File(it).delete() }
    }

    fun export(args: Map<String, Any?>, result: MethodChannel.Result) {
        if (transformer != null) {
            result.error("busy", "Un export est déjà en cours", null)
            return
        }
        try {
            @Suppress("UNCHECKED_CAST")
            val clips = args["clips"] as List<Map<String, Any?>>
            val path = args["output"] as String
            val muteOriginal = args["muteOriginal"] as Boolean
            val music = args["music"] as String?
            val width = (args["width"] as Number).toInt()
            val height = (args["height"] as Number).toInt()

            var totalMs = 0L
            val items = clips.map { c ->
                val start = (c["startMs"] as Number).toLong()
                val end = (c["endMs"] as Number).toLong()
                val speed = (c["speed"] as Number).toFloat()
                val rotation = (c["rotation"] as Number).toFloat()
                totalMs += ((end - start) / speed).toLong()

                val item = MediaItem.Builder()
                    .setUri(uriOf(c["uri"] as String))
                    .setClippingConfiguration(
                        MediaItem.ClippingConfiguration.Builder()
                            .setStartPositionMs(start)
                            .setEndPositionMs(end)
                            .build()
                    )
                    .build()
                val video = mutableListOf<Effect>()
                // The user turns clockwise; Media3 counts counter-clockwise.
                if (rotation != 0f) {
                    video.add(ScaleAndRotateTransformation.Builder().setRotationDegrees(-rotation).build())
                }
                // Every clip is fitted in the same frame, with black bars.
                video.add(Presentation.createForWidthAndHeight(width, height, Presentation.LAYOUT_SCALE_TO_FIT))
                val builder = EditedMediaItem.Builder(item)
                    .setEffects(Effects(emptyList(), video))
                    .setRemoveAudio(muteOriginal || music != null)
                if (speed != 1f) builder.setSpeed(SpeedParameters(constantSpeed(speed), true))
                builder.build()
            }

            val videoSequence = if (muteOriginal || music != null) {
                EditedMediaItemSequence.withVideoFrom(items)
            } else {
                EditedMediaItemSequence.withAudioAndVideoFrom(items)
            }
            val sequences = mutableListOf(videoSequence)
            if (music != null) {
                val track = EditedMediaItem.Builder(MediaItem.fromUri(uriOf(music)))
                    .setRemoveVideo(true)
                    .build()
                // Looped, and cut where the video ends.
                sequences.add(
                    EditedMediaItemSequence.Builder(setOf(C.TRACK_TYPE_AUDIO))
                        .addItem(track)
                        .setIsLooping(true)
                        .build()
                )
            }

            File(path).parentFile?.mkdirs()
            File(path).delete()
            output = path
            val t = Transformer.Builder(activity)
                .setVideoMimeType(MimeTypes.VIDEO_H264)
                .setAudioMimeType(MimeTypes.AUDIO_AAC)
                .addListener(object : Transformer.Listener {
                    override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                        transformer = null
                        result.success(path)
                    }

                    override fun onError(
                        composition: Composition,
                        exportResult: ExportResult,
                        exportException: ExportException,
                    ) {
                        transformer = null
                        File(path).delete()
                        result.error("export", exportException.message ?: "Échec de l'export", null)
                    }
                })
                .build()
            transformer = t
            t.start(Composition.Builder(sequences).build(), path)
        } catch (e: Exception) {
            transformer = null
            result.error("export", e.message ?: "Échec de l'export", null)
        }
    }
}
