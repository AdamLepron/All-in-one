package com.allinone.all_in_one

import android.app.Activity
import android.net.Uri
import android.graphics.Color
import android.text.SpannableString
import android.text.Spanned
import android.text.style.AbsoluteSizeSpan
import android.text.style.BackgroundColorSpan
import android.text.style.ForegroundColorSpan
import android.text.style.StyleSpan
import android.graphics.Typeface
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.SpeedParameters
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.ChannelMixingAudioProcessor
import androidx.media3.common.audio.ChannelMixingMatrix
import androidx.media3.common.audio.SpeedProvider
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.OverlayEffect
import androidx.media3.common.OverlaySettings
import androidx.media3.effect.StaticOverlaySettings
import androidx.media3.effect.Presentation
import androidx.media3.effect.RgbMatrix
import androidx.media3.effect.TextOverlay
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

    /** Scales the sound level; null when nothing needs to change. */
    private fun volumeProcessor(volume: Float): AudioProcessor? {
        if (volume == 1f) return null
        val mixer = ChannelMixingAudioProcessor()
        // Mono and stereo are what phones record; each keeps its layout.
        for (channels in 1..2) {
            mixer.putChannelMixingMatrix(ChannelMixingMatrix.createForConstantGain(channels, channels).scaleBy(volume))
        }
        return mixer
    }

    /** Darkens the picture to black over the first and last stretches of a clip. */
    private class Fade(
        private val inUs: Long,
        private val outStartUs: Long,
        private val outSpanUs: Long,
    ) : RgbMatrix {
        override fun getMatrix(presentationTimeUs: Long, useHdr: Boolean): FloatArray {
            var g = 1f
            if (inUs > 0 && presentationTimeUs < inUs) g = presentationTimeUs.toFloat() / inUs
            if (outStartUs >= 0 && presentationTimeUs > outStartUs) {
                g = minOf(g, 1f - (presentationTimeUs - outStartUs).toFloat() / outSpanUs.coerceAtLeast(1))
            }
            g = g.coerceIn(0f, 1f)
            // Column-major 4x4: scales red, green and blue, keeps alpha.
            return floatArrayOf(g, 0f, 0f, 0f, 0f, g, 0f, 0f, 0f, 0f, g, 0f, 0f, 0f, 0f, 1f)
        }
    }

    /** A title shown between two moments of the finished video. */
    private class Title(
        private val text: String,
        private val startUs: Long,
        private val endUs: Long,
        private val color: Int,
        private val sizePx: Int,
        private val place: Int,
    ) : TextOverlay() {
        override fun getText(presentationTimeUs: Long): SpannableString {
            val visible = presentationTimeUs in startUs until endUs
            val s = SpannableString(if (visible) text else " ")
            if (visible) {
                s.setSpan(ForegroundColorSpan(color), 0, s.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                s.setSpan(BackgroundColorSpan(Color.argb(140, 0, 0, 0)), 0, s.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                s.setSpan(AbsoluteSizeSpan(sizePx), 0, s.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                s.setSpan(StyleSpan(Typeface.BOLD), 0, s.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
            return s
        }

        override fun getOverlaySettings(presentationTimeUs: Long): OverlaySettings {
            // 0 top, 1 middle, 2 bottom, in the frame's -1..1 coordinates.
            val y = when (place) { 0 -> 0.8f; 1 -> 0f; else -> -0.8f }
            return StaticOverlaySettings.Builder()
                .setBackgroundFrameAnchor(0f, y)
                .setOverlayFrameAnchor(0f, 0f)
                .build()
        }
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
                val volume = (c["volume"] as Number?)?.toFloat() ?: 1f
                val fadeInMs = (c["fadeInMs"] as Number?)?.toLong() ?: 0L
                val fadeOutMs = (c["fadeOutMs"] as Number?)?.toLong() ?: 0L
                val outputMs = ((end - start) / speed).toLong()
                totalMs += outputMs

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
                if (fadeInMs > 0 || fadeOutMs > 0) {
                    video.add(
                        Fade(
                            fadeInMs * 1000,
                            if (fadeOutMs > 0) (outputMs - fadeOutMs) * 1000 else -1L,
                            fadeOutMs * 1000,
                        )
                    )
                }
                val audio = listOfNotNull(volumeProcessor(volume))
                val builder = EditedMediaItem.Builder(item)
                    .setEffects(Effects(audio, video))
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
                val musicVolume = (args["musicVolume"] as Number?)?.toFloat() ?: 1f
                val track = EditedMediaItem.Builder(MediaItem.fromUri(uriOf(music)))
                    .setRemoveVideo(true)
                    .setEffects(Effects(listOfNotNull(volumeProcessor(musicVolume)), emptyList()))
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
            // Titles are laid over the whole montage, on its own timeline.
            @Suppress("UNCHECKED_CAST")
            val titles = (args["titles"] as List<Map<String, Any?>>?) ?: emptyList()
            val builder = Composition.Builder(sequences)
            if (titles.isNotEmpty()) {
                val overlays = titles.map { t ->
                    Title(
                        t["text"] as String,
                        (t["startMs"] as Number).toLong() * 1000,
                        (t["endMs"] as Number).toLong() * 1000,
                        (t["color"] as Number).toInt(),
                        ((t["size"] as Number).toFloat() * height).toInt().coerceAtLeast(12),
                        (t["place"] as Number).toInt(),
                    )
                }
                builder.setEffects(Effects(emptyList(), listOf(OverlayEffect(overlays))))
            }
            t.start(builder.build(), path)
        } catch (e: Exception) {
            transformer = null
            result.error("export", e.message ?: "Échec de l'export", null)
        }
    }
}
