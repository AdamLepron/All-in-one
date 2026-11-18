package com.allinone.all_in_one

import android.app.Activity
import android.net.Uri
import android.graphics.Color
import android.graphics.Matrix
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
import androidx.media3.effect.Contrast
import androidx.media3.effect.GaussianBlur
import androidx.media3.effect.BitmapOverlay
import androidx.media3.common.VideoCompositorSettings
import androidx.media3.common.util.Size
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.os.Build
import androidx.media3.effect.MatrixTransformation
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

    /** Something that did not go as asked in the last export, said once. */
    var warning: String? = null

    fun takeWarning(): String? = warning.also { warning = null }


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

    /** Colour treatment of a clip: a fixed 4x4 matrix (column-major). */
    private class Look(private val matrix: FloatArray) : RgbMatrix {
        override fun getMatrix(presentationTimeUs: Long, useHdr: Boolean): FloatArray = matrix
    }

    /** A motion over a whole clip, as a function of the clip's own time. */
    private class Motion(private val kind: Int, private val durationUs: Long) : MatrixTransformation {
        override fun getMatrix(presentationTimeUs: Long): Matrix {
            val m = Matrix()
            val p = (presentationTimeUs.toFloat() / durationUs.coerceAtLeast(1)).coerceIn(0f, 1f)
            val sec = presentationTimeUs / 1_000_000f
            when (kind) {
                1 -> m.postScale(1f + 0.25f * p, 1f + 0.25f * p) // zoom in
                2 -> m.postScale(1.25f - 0.25f * p, 1.25f - 0.25f * p) // zoom out
                3 -> { // pulse: a gentle beat
                    val k = 1f + 0.06f * (0.5f + 0.5f * Math.sin(sec * 2 * Math.PI / 0.8).toFloat())
                    m.postScale(k, k)
                }
                4 -> { // shake, enlarged a little to hide the edges
                    m.postScale(1.06f, 1.06f)
                    m.postTranslate(
                        0.02f * Math.sin(sec * 38.0).toFloat(),
                        0.02f * Math.sin(sec * 51.0 + 1.0).toFloat(),
                    )
                }
            }
            return m
        }
    }

    /** Easing 0..1 -> 0..1, slow at both ends. */
    private object Easing {
        fun ease(x: Float): Float {
            val k = x.coerceIn(0f, 1f)
            return k * k * (3f - 2f * k)
        }
    }

    /**
     * How a clip arrives (inKind over inUs) and leaves (outKind from outStartUs
     * for outUs). Kinds: 2 flash, 3 slide left, 4 slide right, 5 zoom.
     */
    private class Transit(
        private val inKind: Int, private val inUs: Long,
        private val outKind: Int, private val outStartUs: Long, private val outUs: Long,
    ) {
        /** 0 when the clip is fully there, up to 1 as it arrives or leaves. */
        fun phase(timeUs: Long): Pair<Int, Float> {
            if (inKind != 0 && inUs > 0 && timeUs < inUs) return Pair(inKind, 1f - Easing.ease(timeUs.toFloat() / inUs))
            if (outKind != 0 && outStartUs >= 0 && timeUs > outStartUs) {
                return Pair(outKind, Easing.ease((timeUs - outStartUs).toFloat() / outUs.coerceAtLeast(1)))
            }
            return Pair(0, 0f)
        }
        val incoming get() = inKind
        fun arriving(timeUs: Long) = inKind != 0 && inUs > 0 && timeUs < inUs
    }

    private class TransitMotion(private val t: Transit) : MatrixTransformation {
        override fun getMatrix(presentationTimeUs: Long): Matrix {
            val m = Matrix()
            val (kind, k) = t.phase(presentationTimeUs)
            if (k <= 0f) return m
            val arriving = t.arriving(presentationTimeUs)
            when (kind) {
                3 -> m.postTranslate(if (arriving) 2f * k else -2f * k, 0f) // left: leaves to the left, arrives from the right
                4 -> m.postTranslate(if (arriving) -2f * k else 2f * k, 0f)
                5 -> { val s = 1f + 0.6f * k; m.postScale(s, s) }
            }
            return m
        }
    }

    private class TransitLook(private val t: Transit) : RgbMatrix {
        override fun getMatrix(presentationTimeUs: Long, useHdr: Boolean): FloatArray {
            val (kind, k) = t.phase(presentationTimeUs)
            var g = 1f
            when (kind) {
                2 -> g = 1f + 11f * k * k // overexposed to white
                5 -> g = 1f - k // zoom dips to black as it grows
            }
            return floatArrayOf(g, 0f, 0f, 0f, 0f, g, 0f, 0f, 0f, 0f, g, 0f, 0f, 0f, 0f, 1f)
        }
    }

    /** A still picture laid over the montage between two moments. */
    private class ImageLayer(
        private val bitmap: Bitmap,
        private val startUs: Long,
        private val endUs: Long,
        private val cx: Float,
        private val cy: Float,
        private val opacity: Float,
    ) : BitmapOverlay() {
        override fun getBitmap(presentationTimeUs: Long): Bitmap = bitmap
        override fun getOverlaySettings(presentationTimeUs: Long): OverlaySettings {
            val visible = presentationTimeUs in startUs until endUs
            return StaticOverlaySettings.Builder()
                .setBackgroundFrameAnchor(cx * 2f - 1f, 1f - cy * 2f)
                .setOverlayFrameAnchor(0f, 0f)
                .setAlphaScale(if (visible) opacity else 0f)
                .build()
        }
    }

    /** Where each overlaid video sits; input 0 is the main track. */
    private class Placement(
        private val width: Int,
        private val height: Int,
        private val spots: List<Triple<Float, Float, Float>>, // cx, cy, opacity
    ) : VideoCompositorSettings {
        override fun getOutputSize(inputSizes: List<Size>) = Size(width, height)
        override fun getOverlaySettings(inputId: Int, presentationTimeUs: Long): OverlaySettings {
            val spot = spots.getOrNull(inputId - 1) ?: return StaticOverlaySettings.Builder().build()
            return StaticOverlaySettings.Builder()
                .setBackgroundFrameAnchor(spot.first * 2f - 1f, 1f - spot.second * 2f)
                .setOverlayFrameAnchor(0f, 0f)
                .setAlphaScale(spot.third)
                .build()
        }
    }

    /** Decodes a picture no wider than [target] pixels, upright. */
    private fun loadBitmap(value: String, target: Int): Bitmap? = try {
        val uri = uriOf(value)
        if (Build.VERSION.SDK_INT >= 28) {
            ImageDecoder.decodeBitmap(ImageDecoder.createSource(activity.contentResolver, uri)) { decoder, info, _ ->
                val w = info.size.width.coerceAtLeast(1)
                val scale = target.toFloat() / w
                decoder.setTargetSize(target.coerceAtLeast(2), (info.size.height * scale).toInt().coerceAtLeast(2))
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            }
        } else {
            activity.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it) }?.let {
                Bitmap.createScaledBitmap(it, target, (it.height * target.toFloat() / it.width).toInt().coerceAtLeast(2), true)
            }
        }
    } catch (e: Exception) {
        null
    }

    /** A title shown between two moments of the finished video. */
    private class Title(
        private val text: String,
        private val startUs: Long,
        private val endUs: Long,
        private val color: Int,
        private val sizePx: Int,
        private val place: Int,
        private val align: Int,
        private val animation: Int,
        private val box: Int,
        private val freeX: Float?,
        private val freeY: Float?,
    ) : TextOverlay() {
        override fun getText(presentationTimeUs: Long): SpannableString {
            val visible = presentationTimeUs in startUs until endUs
            val s = SpannableString(if (visible) text else " ")
            if (visible) {
                s.setSpan(ForegroundColorSpan(color), 0, s.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                when (box) {
                    1 -> s.setSpan(BackgroundColorSpan(Color.argb(140, 0, 0, 0)), 0, s.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                    2 -> s.setSpan(BackgroundColorSpan(Color.argb(255, 20, 20, 24)), 0, s.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                }
                s.setSpan(AbsoluteSizeSpan(sizePx), 0, s.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                s.setSpan(StyleSpan(Typeface.BOLD), 0, s.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
            return s
        }

        override fun getOverlaySettings(presentationTimeUs: Long): OverlaySettings {
            // Edges of the frame: 0 top, 1 middle, 2 bottom.
            val baseY = when (place) { 0 -> 0.92f; 1 -> 0f; else -> -0.92f }
            val anchorY = when (place) { 0 -> 1f; 1 -> 0f; else -> -1f }
            val x = align * 0.94f
            val inT = (presentationTimeUs - startUs) / 1000f // ms since appearing
            val outT = (endUs - presentationTimeUs) / 1000f // ms before leaving
            val edge = minOf(inT, outT).coerceAtLeast(0f)
            var alpha = 1f
            var scale = 1f
            var dy = 0f
            when (animation) {
                1 -> alpha = (edge / 350f).coerceIn(0f, 1f)
                2 -> { // slides in from below, fades out
                    val k = (inT / 400f).coerceIn(0f, 1f)
                    dy = -0.18f * (1f - k) * (1f - k)
                    alpha = minOf(k, (outT / 250f).coerceIn(0f, 1f))
                }
                3 -> { // pops in with a small overshoot
                    val k = (inT / 320f).coerceIn(0f, 1f)
                    scale = if (k < 1f) 0.4f + 0.6f * k + 0.25f * Math.sin(k * Math.PI).toFloat() else 1f
                    alpha = (outT / 200f).coerceIn(0f, 1f)
                }
            }
            val free = freeX != null && freeY != null
            return StaticOverlaySettings.Builder()
                .setBackgroundFrameAnchor(
                    if (free) freeX!! * 2f - 1f else x,
                    if (free) 1f - freeY!! * 2f + dy else baseY + dy,
                )
                .setOverlayFrameAnchor(if (free) 0f else align.toFloat(), if (free) 0f else anchorY)
                .setAlphaScale(alpha.coerceIn(0f, 1f))
                .setScale(scale, scale)
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
        warning = null
        run(args, result, true)
    }

    private fun run(args: Map<String, Any?>, result: MethodChannel.Result, allowVideoOverlays: Boolean) {
        try {
            @Suppress("UNCHECKED_CAST")
            val clips = args["clips"] as List<Map<String, Any?>>
            val path = args["output"] as String
            val muteOriginal = args["muteOriginal"] as Boolean
            val music = args["music"] as String?
            val width = (args["width"] as Number).toInt()
            val height = (args["height"] as Number).toInt()
            val fill = args["fill"] == true

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

                val isImage = c["image"] == true
                val item = if (isImage) {
                    MediaItem.Builder()
                        .setUri(uriOf(c["uri"] as String))
                        .setImageDurationMs(outputMs)
                        .build()
                } else {
                    MediaItem.Builder()
                        .setUri(uriOf(c["uri"] as String))
                        .setClippingConfiguration(
                            MediaItem.ClippingConfiguration.Builder()
                                .setStartPositionMs(start)
                                .setEndPositionMs(end)
                                .build()
                        )
                        .build()
                }
                val video = mutableListOf<Effect>()
                // The user turns clockwise; Media3 counts counter-clockwise.
                if (rotation != 0f) {
                    video.add(ScaleAndRotateTransformation.Builder().setRotationDegrees(-rotation).build())
                }
                if (c["flip"] == true) {
                    video.add(ScaleAndRotateTransformation.Builder().setScale(-1f, 1f).build())
                }
                // Every clip is placed in the same frame: with black bars, or
                // filling it (the edges are cropped).
                video.add(
                    Presentation.createForWidthAndHeight(
                        width, height,
                        if (fill) Presentation.LAYOUT_SCALE_TO_FIT_WITH_CROP else Presentation.LAYOUT_SCALE_TO_FIT,
                    )
                )
                val motion = (c["effect"] as Number?)?.toInt() ?: 0
                if (motion != 0) video.add(Motion(motion, outputMs * 1000))
                val colors = c["colorMatrix"] as List<*>?
                if (colors != null && colors.size == 16) {
                    video.add(Look(FloatArray(16) { (colors[it] as Number).toFloat() }))
                }
                val contrast = (c["contrast"] as Number?)?.toFloat() ?: 0f
                if (contrast != 0f) video.add(Contrast(contrast.coerceIn(-1f, 1f)))
                val blur = (c["blur"] as Number?)?.toFloat() ?: 0f
                // Sigma in pixels of the shorter side's hundredth part, up to ~2.5%.
                if (blur > 0f) video.add(GaussianBlur(blur * 0.025f * minOf(width, height)))
                if (fadeInMs > 0 || fadeOutMs > 0) {
                    video.add(
                        Fade(
                            fadeInMs * 1000,
                            if (fadeOutMs > 0) (outputMs - fadeOutMs) * 1000 else -1L,
                            fadeOutMs * 1000,
                        )
                    )
                }
                // Transitions other than the plain fade: slides, flash, zoom.
                val trIn = (c["trIn"] as Number?)?.toInt() ?: 0
                val trOut = (c["trOut"] as Number?)?.toInt() ?: 0
                if (trIn != 0 || trOut != 0) {
                    val inMs = (c["trInMs"] as Number?)?.toLong() ?: 0L
                    val outMs = (c["trOutMs"] as Number?)?.toLong() ?: 0L
                    val transit = Transit(
                        trIn, inMs * 1000,
                        trOut, if (trOut != 0) (outputMs - outMs) * 1000 else -1L, outMs * 1000,
                    )
                    video.add(TransitMotion(transit))
                    video.add(TransitLook(transit))
                }
                val audio = listOfNotNull(volumeProcessor(volume))
                val builder = EditedMediaItem.Builder(item)
                    .setEffects(Effects(audio, video))
                    .setRemoveAudio(muteOriginal || music != null)
                if (isImage) builder.setDurationUs(outputMs * 1000).setFrameRate(30)
                if (speed != 1f && !isImage) builder.setSpeed(SpeedParameters(constantSpeed(speed), true))
                builder.build()
            }

            val keepAudio = !(muteOriginal || music != null)
            val hasImage = clips.any { it["image"] == true }
            val videoSequence = if (!keepAudio) {
                EditedMediaItemSequence.withVideoFrom(items)
            } else if (hasImage) {
                // Pictures have no sound: silence fills their time.
                EditedMediaItemSequence.Builder(setOf(C.TRACK_TYPE_AUDIO, C.TRACK_TYPE_VIDEO))
                    .addItems(items)
                    .experimentalSetForceAudioTrack(true)
                    .build()
            } else {
                EditedMediaItemSequence.withAudioAndVideoFrom(items)
            }
            val sequences = mutableListOf(videoSequence)

            // Overlaid videos: one sequence each, started after a gap, shrunk
            // to their size; the compositor places them over the main track.
            @Suppress("UNCHECKED_CAST")
            val overlayList = ((args["overlays"] as List<Map<String, Any?>>?) ?: emptyList())
                .sortedBy { (it["track"] as Number?)?.toInt() ?: 0 }
            val videoOverlays = if (allowVideoOverlays) overlayList.filter { it["image"] != true } else emptyList()
            val spots = mutableListOf<Triple<Float, Float, Float>>()
            for (o in videoOverlays) {
                val startUs = (o["startMs"] as Number).toLong() * 1000
                val trim = (o["trimStartMs"] as Number).toLong()
                val dur = (o["durationMs"] as Number).toLong()
                val vol = (o["volume"] as Number?)?.toFloat() ?: 0f
                val aspect = (o["aspect"] as Number?)?.toFloat() ?: (16f / 9f)
                val w = ((o["width"] as Number).toFloat() * width).toInt().coerceAtLeast(2)
                val h = (w / aspect).toInt().coerceAtLeast(2)
                val item = EditedMediaItem.Builder(
                    MediaItem.Builder()
                        .setUri(uriOf(o["uri"] as String))
                        .setClippingConfiguration(
                            MediaItem.ClippingConfiguration.Builder()
                                .setStartPositionMs(trim)
                                .setEndPositionMs(trim + dur)
                                .build()
                        )
                        .build()
                )
                    .setRemoveAudio(vol <= 0f)
                    .setEffects(
                        Effects(
                            listOfNotNull(volumeProcessor(vol)),
                            listOf(Presentation.createForWidthAndHeight(w, h, Presentation.LAYOUT_SCALE_TO_FIT)),
                        )
                    )
                    .build()
                val b = EditedMediaItemSequence.Builder(
                    if (vol > 0f) setOf(C.TRACK_TYPE_AUDIO, C.TRACK_TYPE_VIDEO) else setOf(C.TRACK_TYPE_VIDEO)
                )
                if (startUs > 0) b.addGap(startUs)
                b.addItem(item)
                sequences.add(b.build())
                spots.add(
                    Triple(
                        (o["cx"] as Number).toFloat(),
                        (o["cy"] as Number).toFloat(),
                        (o["opacity"] as Number?)?.toFloat() ?: 1f,
                    )
                )
            }

            // Sounds placed on the timeline: one audio sequence each.
            @Suppress("UNCHECKED_CAST")
            for (a in ((args["sounds"] as List<Map<String, Any?>>?) ?: emptyList())) {
                val startUs = (a["startMs"] as Number).toLong() * 1000
                val trim = (a["trimStartMs"] as Number).toLong()
                val dur = (a["durationMs"] as Number).toLong()
                val vol = (a["volume"] as Number?)?.toFloat() ?: 1f
                val item = EditedMediaItem.Builder(
                    MediaItem.Builder()
                        .setUri(uriOf(a["path"] as String))
                        .setClippingConfiguration(
                            MediaItem.ClippingConfiguration.Builder()
                                .setStartPositionMs(trim)
                                .setEndPositionMs(trim + dur)
                                .build()
                        )
                        .build()
                )
                    .setRemoveVideo(true)
                    .setEffects(Effects(listOfNotNull(volumeProcessor(vol)), emptyList()))
                    .build()
                val b = EditedMediaItemSequence.Builder(setOf(C.TRACK_TYPE_AUDIO))
                if (startUs > 0) b.addGap(startUs)
                b.addItem(item)
                sequences.add(b.build())
            }
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
                        if (videoOverlays.isNotEmpty()) {
                            // Overlaid videos are the delicate part: try again without them.
                            warning = "Les vidéos incrustées n'ont pas pu être appliquées sur cet appareil."
                            run(args, result, false)
                            return
                        }
                        result.error("export", exportException.message ?: "Échec de l'export", null)
                    }
                })
                .build()
            transformer = t
            // Titles are laid over the whole montage, on its own timeline.
            @Suppress("UNCHECKED_CAST")
            val titles = (args["titles"] as List<Map<String, Any?>>?) ?: emptyList()
            val builder = Composition.Builder(sequences)
            if (videoOverlays.isNotEmpty()) {
                builder.setVideoCompositorSettings(Placement(width, height, spots))
            }
            val layers = mutableListOf<androidx.media3.effect.TextureOverlay>()
            for (o in overlayList.filter { it["image"] == true }) {
                val w = ((o["width"] as Number).toFloat() * width).toInt().coerceAtLeast(2)
                val bmp = loadBitmap(o["uri"] as String, w) ?: continue
                layers.add(
                    ImageLayer(
                        bmp,
                        (o["startMs"] as Number).toLong() * 1000,
                        ((o["startMs"] as Number).toLong() + (o["durationMs"] as Number).toLong()) * 1000,
                        (o["cx"] as Number).toFloat(),
                        (o["cy"] as Number).toFloat(),
                        (o["opacity"] as Number?)?.toFloat() ?: 1f,
                    )
                )
            }
            if (titles.isEmpty() && layers.isNotEmpty()) {
                builder.setEffects(Effects(emptyList(), listOf(OverlayEffect(layers))))
            }
            if (titles.isNotEmpty()) {
                val overlays = layers + titles.map { t ->
                    Title(
                        t["text"] as String,
                        (t["startMs"] as Number).toLong() * 1000,
                        (t["endMs"] as Number).toLong() * 1000,
                        (t["color"] as Number).toInt(),
                        ((t["size"] as Number).toFloat() * height).toInt().coerceAtLeast(12),
                        (t["place"] as Number).toInt(),
                        (t["align"] as Number?)?.toInt() ?: 0,
                        (t["animation"] as Number?)?.toInt() ?: 0,
                        (t["box"] as Number?)?.toInt() ?: 1,
                        (t["x"] as Number?)?.toFloat(),
                        (t["y"] as Number?)?.toFloat(),
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
