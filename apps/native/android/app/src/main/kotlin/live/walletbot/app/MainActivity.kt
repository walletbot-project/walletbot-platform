package live.walletbot.app

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "live.walletbot.app/pcm_audio"
    private var audioTrack: AudioTrack? = null
    private var audioThread: HandlerThread? = null
    private var audioHandler: Handler? = null
    private var previousAudioMode: Int = AudioManager.MODE_NORMAL
    private var previousSpeakerphoneOn: Boolean = false
    private var audioModeChanged: Boolean = false
    private var communicationDeviceSet: Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> handleStart(call, result)
                    "enqueue" -> handleEnqueue(call, result)
                    "interrupt" -> handleInterrupt(result)
                    "stop" -> handleStop(result)
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        stopPlayback()
        super.onDestroy()
    }

    private fun handleStart(call: MethodCall, result: MethodChannel.Result) {
        val sampleRate = call.argument<Int>("sampleRate") ?: 24000
        try {
            startPlayback(sampleRate)
            result.success(null)
        } catch (error: Exception) {
            result.error("pcm_start_failed", error.message, null)
        }
    }

    private fun handleEnqueue(call: MethodCall, result: MethodChannel.Result) {
        val bytes = call.arguments as? ByteArray
        if (bytes == null) {
            result.error("pcm_bad_args", "Expected PCM bytes", null)
            return
        }

        val track = audioTrack
        val handler = audioHandler
        if (track == null || handler == null) {
            result.error("pcm_not_started", "PCM playback is not started", null)
            return
        }

        handler.post {
            var offset = 0
            while (offset < bytes.size) {
                val written = track.write(bytes, offset, bytes.size - offset)
                if (written <= 0) break
                offset += written
            }
        }
        result.success(null)
    }

    private fun handleInterrupt(result: MethodChannel.Result) {
        try {
            audioHandler?.post {
                audioTrack?.pause()
                audioTrack?.flush()
                audioTrack?.play()
            }
            result.success(null)
        } catch (error: Exception) {
            result.error("pcm_interrupt_failed", error.message, null)
        }
    }

    private fun handleStop(result: MethodChannel.Result) {
        try {
            stopPlayback()
            result.success(null)
        } catch (error: Exception) {
            result.error("pcm_stop_failed", error.message, null)
        }
    }

    private fun startPlayback(sampleRate: Int) {
        stopPlayback()

        configureVoiceCommunicationMode()

        val minBufferSize = AudioTrack.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        val bufferSize = maxOf(minBufferSize, sampleRate)

        val track = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setSampleRate(sampleRate)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .build()
            )
            .setTransferMode(AudioTrack.MODE_STREAM)
            .setBufferSizeInBytes(bufferSize)
            .build()

        val thread = HandlerThread("walletbot-pcm-playback")
        thread.start()

        audioTrack = track
        audioThread = thread
        audioHandler = Handler(thread.looper)
        track.play()
    }

    private fun stopPlayback() {
        val track = audioTrack
        audioTrack = null

        try {
            track?.pause()
            track?.flush()
            track?.release()
        } catch (_: Exception) {
            // Best effort cleanup.
        }

        audioThread?.quitSafely()
        audioThread = null
        audioHandler = null

        restoreAudioMode()
    }

    private fun configureVoiceCommunicationMode() {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        previousAudioMode = audioManager.mode
        previousSpeakerphoneOn = audioManager.isSpeakerphoneOn
        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
        audioModeChanged = true
        routeToLoudSpeaker(audioManager)
    }

    private fun routeToLoudSpeaker(audioManager: AudioManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val speaker = audioManager.availableCommunicationDevices.firstOrNull {
                it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
            }
            if (speaker != null && audioManager.setCommunicationDevice(speaker)) {
                communicationDeviceSet = true
                return
            }
            Log.w("PcmAudio", "setCommunicationDevice(speaker) failed; falling back")
        }
        @Suppress("DEPRECATION")
        audioManager.isSpeakerphoneOn = true
    }

    private fun restoreAudioMode() {
        if (!audioModeChanged) return
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (communicationDeviceSet && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            audioManager.clearCommunicationDevice()
            communicationDeviceSet = false
        }
        @Suppress("DEPRECATION")
        audioManager.isSpeakerphoneOn = previousSpeakerphoneOn
        audioManager.mode = previousAudioMode
        audioModeChanged = false
    }
}
