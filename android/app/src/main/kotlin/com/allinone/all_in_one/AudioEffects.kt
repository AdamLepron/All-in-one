package com.allinone.all_in_one

import android.media.audiofx.BassBoost
import android.media.audiofx.DynamicsProcessing
import android.media.audiofx.Equalizer
import android.media.audiofx.LoudnessEnhancer
import android.media.audiofx.Virtualizer
import android.os.Build
import kotlin.math.abs

/**
 * Equaliser, bass boost, stereo widening, loudness and left/right balance
 * attached to the audio session of the app's player.
 *
 * Every effect is optional: a device that lacks one simply skips it.
 */
class AudioEffects {
    private var session = -1
    private var equalizer: Equalizer? = null
    private var bass: BassBoost? = null
    private var virtualizer: Virtualizer? = null
    private var loudness: LoudnessEnhancer? = null
    private var dynamics: DynamicsProcessing? = null

    private fun <T> attempt(create: () -> T): T? = try {
        create()
    } catch (e: Throwable) {
        null
    }

    private fun attach(sessionId: Int) {
        if (sessionId == session) return
        release()
        session = sessionId
        equalizer = attempt { Equalizer(0, sessionId) }
        bass = attempt { BassBoost(0, sessionId) }
        virtualizer = attempt { Virtualizer(0, sessionId) }
        loudness = attempt { LoudnessEnhancer(sessionId) }
    }

    /**
     * Applies the whole state at once and returns what the device supports:
     * band centre frequencies in Hz and the level range in dB.
     *
     * [levels] are dB per band, [bassAmount], [widening] and [gain] go from
     * 0 to 1, [balance] from -1 (left only) to 1 (right only).
     */
    fun apply(
        sessionId: Int,
        enabled: Boolean,
        levels: List<Double>,
        bassAmount: Double,
        widening: Double,
        gain: Double,
        balance: Double,
    ): Map<String, Any> {
        attach(sessionId)
        val info = HashMap<String, Any>()

        equalizer?.let { eq ->
            attempt {
                val range = eq.bandLevelRange // millibels
                val count = eq.numberOfBands.toInt()
                for (band in 0 until count) {
                    val db = levels.getOrElse(band) { 0.0 }
                    val mb = (db * 100).toInt().coerceIn(range[0].toInt(), range[1].toInt())
                    eq.setBandLevel(band.toShort(), mb.toShort())
                }
                eq.enabled = enabled
                info["freqs"] = (0 until count).map { eq.getCenterFreq(it.toShort()) / 1000 }
                info["min"] = range[0] / 100.0
                info["max"] = range[1] / 100.0
            }
        }
        bass?.let { effect ->
            attempt {
                if (effect.strengthSupported) effect.setStrength((bassAmount * 1000).toInt().toShort())
                effect.enabled = enabled && bassAmount > 0.0
                info["bass"] = true
            }
        }
        virtualizer?.let { effect ->
            attempt {
                if (effect.strengthSupported) effect.setStrength((widening * 1000).toInt().toShort())
                effect.enabled = enabled && widening > 0.0
                info["widening"] = true
            }
        }
        loudness?.let { effect ->
            attempt {
                effect.setTargetGain((gain * 1000).toInt()) // up to +10 dB
                effect.enabled = enabled && gain > 0.0
                info["gain"] = true
            }
        }
        info["balance"] = applyBalance(sessionId, if (enabled) balance else 0.0)
        return info
    }

    /** Balance attenuates the opposite channel; needs Android 9. */
    private fun applyBalance(sessionId: Int, balance: Double): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return false
        return attempt {
            if (abs(balance) < 0.01) {
                dynamics?.release()
                dynamics = null
            } else {
                val effect = dynamics ?: DynamicsProcessing(
                    0,
                    sessionId,
                    DynamicsProcessing.Config.Builder(
                        DynamicsProcessing.VARIANT_FAVOR_FREQUENCY_RESOLUTION,
                        2, false, 0, false, 0, false, 0, false,
                    ).build(),
                ).also { dynamics = it }
                // Full deflection mutes the far channel (-60 dB).
                val cut = (-60.0 * abs(balance)).toFloat()
                effect.setInputGainbyChannel(0, if (balance > 0) cut else 0f)
                effect.setInputGainbyChannel(1, if (balance < 0) cut else 0f)
                effect.enabled = true
            }
            true
        } ?: false
    }

    fun release() {
        listOf(equalizer, bass, virtualizer, loudness, dynamics).forEach { effect ->
            attempt { effect?.release() }
        }
        equalizer = null
        bass = null
        virtualizer = null
        loudness = null
        dynamics = null
        session = -1
    }
}
