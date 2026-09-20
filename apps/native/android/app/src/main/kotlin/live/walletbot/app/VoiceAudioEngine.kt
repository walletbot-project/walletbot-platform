package live.walletbot.app

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.*
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.NoiseSuppressor
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicInteger

/** One owner for communication routing, playback, capture, effects and focus. */
class VoiceAudioEngine(private val context: Context, messenger: BinaryMessenger) : EventChannel.StreamHandler {
    private val manager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val main = Handler(Looper.getMainLooper())
    private val methods = MethodChannel(messenger, "live.walletbot.app/pcm_audio")
    private val events = EventChannel(messenger, "live.walletbot.app/pcm_audio/capture")
    private var track: AudioTrack? = null
    private var playbackThread: HandlerThread? = null
    private var playback: Handler? = null
    private val playbackGeneration = AtomicInteger()
    private val queuedBytes = AtomicInteger()
    private val captureGeneration = AtomicInteger()
    private var recorder: AudioRecord? = null
    private var captureThread: Thread? = null
    private var echoCanceler: AcousticEchoCanceler? = null
    private var suppressor: NoiseSuppressor? = null
    private var sink: EventChannel.EventSink? = null
    private var previousMode = AudioManager.MODE_NORMAL
    private var previousSpeaker = false
    private var previousDevice: AudioDeviceInfo? = null
    private var ownsSession = false
    private var focusRequest: AudioFocusRequest? = null
    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        if (change < 0) {
            interrupt()
            val listener = sink
            stopCapture()
            listener?.error("audio_interrupted", "Microphone interrupted by another audio session", null)
        }
    }

    init {
        events.setStreamHandler(this)
        methods.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "start" -> {
                        require((call.argument<Int>("sampleRate") ?: 24000) == 24000)
                        start()
                        result.success(mapOf("inputRate" to 16000, "outputRate" to 24000,
                            "echoCancellationAvailable" to AcousticEchoCanceler.isAvailable()))
                    }
                    "enqueue" -> { enqueue(call.arguments as ByteArray); result.success(null) }
                    "interrupt" -> { interrupt(); result.success(null) }
                    "stop" -> { stop(); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                if (call.method == "start") stop()
                result.error("audio_${call.method}_failed", error.message, null)
            }
        }
    }

    private fun start() {
        if (track != null) return
        previousMode = manager.mode
        @Suppress("DEPRECATION")
        previousSpeaker = manager.isSpeakerphoneOn
        if (Build.VERSION.SDK_INT >= 31) previousDevice = manager.communicationDevice
        ownsSession = true
        manager.mode = AudioManager.MODE_IN_COMMUNICATION
        if (Build.VERSION.SDK_INT >= 31) {
            val devices = manager.availableCommunicationDevices
            // Respect headsets. The speaker is only the default route.
            val preferred = devices.firstOrNull { it.type in setOf(
                AudioDeviceInfo.TYPE_BLUETOOTH_SCO, AudioDeviceInfo.TYPE_BLE_HEADSET,
                AudioDeviceInfo.TYPE_WIRED_HEADSET, AudioDeviceInfo.TYPE_USB_HEADSET) }
                ?: devices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
            preferred?.let { manager.setCommunicationDevice(it) }
        } else {
            @Suppress("DEPRECATION")
            manager.isSpeakerphoneOn = !manager.isWiredHeadsetOn && !manager.isBluetoothScoOn
        }
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build()
        val focus = if (Build.VERSION.SDK_INT >= 26) {
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                .setAudioAttributes(attributes).setOnAudioFocusChangeListener(focusListener, main).build()
            focusRequest = request
            manager.requestAudioFocus(request)
        } else {
            @Suppress("DEPRECATION")
            manager.requestAudioFocus(focusListener, AudioManager.STREAM_VOICE_CALL, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
        }
        check(focus == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) { "Audio focus unavailable" }
        val minimum = AudioTrack.getMinBufferSize(24000, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)
        check(minimum > 0) { "PCM playback unsupported" }
        track = AudioTrack.Builder().setAudioAttributes(attributes)
            .setAudioFormat(AudioFormat.Builder().setSampleRate(24000)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO).setEncoding(AudioFormat.ENCODING_PCM_16BIT).build())
            .setTransferMode(AudioTrack.MODE_STREAM).setBufferSizeInBytes(maxOf(minimum, 4800)).build()
        check(track?.state == AudioTrack.STATE_INITIALIZED)
        playbackThread = HandlerThread("walletbot-playback").also { it.start() }
        playback = Handler(playbackThread!!.looper)
        track!!.play()
    }

    private fun enqueue(bytes: ByteArray) {
        require(bytes.size % 2 == 0) { "Unaligned PCM16" }
        val output = checkNotNull(track) { "Playback not started" }
        val handler = checkNotNull(playback)
        if (bytes.isEmpty()) return
        // At most 20 seconds of generated speech; overflow is visible to Dart.
        if (queuedBytes.addAndGet(bytes.size) > 24000 * 2 * 20) {
            queuedBytes.addAndGet(-bytes.size)
            throw IllegalStateException("Playback queue full")
        }
        val generation = playbackGeneration.get()
        handler.post {
            try {
                var offset = 0
                while (offset < bytes.size && generation == playbackGeneration.get()) {
                    val written = output.write(bytes, offset, minOf(960, bytes.size - offset), AudioTrack.WRITE_BLOCKING)
                    if (written <= 0) break
                    offset += written
                }
            } finally {
                if (generation == playbackGeneration.get()) queuedBytes.addAndGet(-bytes.size)
            }
        }
    }

    private fun interrupt() {
        playbackGeneration.incrementAndGet()
        playback?.removeCallbacksAndMessages(null)
        queuedBytes.set(0)
        track?.pause() // Unblocks a writer immediately.
        track?.flush()
        track?.play()
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        try {
            check(context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
                "Microphone permission denied"
            }
            check(track != null) { "Audio session not started" }
            stopCapture()
            sink = events
            val minimum = AudioRecord.getMinBufferSize(16000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
            check(minimum > 0) { "PCM capture unsupported" }
            val input = AudioRecord.Builder().setAudioSource(MediaRecorder.AudioSource.VOICE_COMMUNICATION)
                .setAudioFormat(AudioFormat.Builder().setSampleRate(16000)
                    .setChannelMask(AudioFormat.CHANNEL_IN_MONO).setEncoding(AudioFormat.ENCODING_PCM_16BIT).build())
                .setBufferSizeInBytes(maxOf(minimum, 6400)).build()
            recorder = input
            check(input.state == AudioRecord.STATE_INITIALIZED)
            if (AcousticEchoCanceler.isAvailable()) {
                echoCanceler = AcousticEchoCanceler.create(input.audioSessionId)?.also { it.enabled = true }
            }
            if (NoiseSuppressor.isAvailable()) {
                suppressor = NoiseSuppressor.create(input.audioSessionId)?.also { it.enabled = true }
            }
            input.startRecording()
            check(input.recordingState == AudioRecord.RECORDSTATE_RECORDING)
            val generation = captureGeneration.get()
            captureThread = Thread({
                val buffer = ByteArray(3200)
                while (generation == captureGeneration.get()) {
                    val count = input.read(buffer, 0, buffer.size, AudioRecord.READ_BLOCKING)
                    if (count <= 0) {
                        main.post {
                            if (generation == captureGeneration.get()) {
                                events.error("capture_failed", "AudioRecord read failed: $count", null)
                                stopCapture()
                            }
                        }
                        break
                    }
                    val bytes = buffer.copyOf(count)
                    main.post {
                        if (generation == captureGeneration.get()) sink?.success(bytes)
                    }
                }
            }, "walletbot-capture").also { it.start() }
        } catch (error: Exception) {
            stopCapture()
            events.error("capture_failed", error.message, null)
        }
    }

    override fun onCancel(arguments: Any?) = stopCapture()

    private fun stopCapture() {
        captureGeneration.incrementAndGet()
        sink = null
        val input = recorder
        recorder = null
        try { input?.stop() } catch (_: Exception) {}
        // stop() releases READ_BLOCKING. Join before releasing its native handle.
        captureThread?.join(500)
        captureThread = null
        echoCanceler?.release(); echoCanceler = null
        suppressor?.release(); suppressor = null
        input?.release()
    }

    fun stop() {
        stopCapture()
        interrupt()
        val output = track
        track = null
        output?.pause()
        playbackThread?.quitSafely()
        playbackThread?.join(500)
        playbackThread = null
        playback = null
        output?.release()
        if (ownsSession) {
            if (Build.VERSION.SDK_INT >= 26) focusRequest?.let { manager.abandonAudioFocusRequest(it) }
            else { @Suppress("DEPRECATION") manager.abandonAudioFocus(focusListener) }
            focusRequest = null
            if (Build.VERSION.SDK_INT >= 31) {
                val previous = previousDevice
                if (previous != null) manager.setCommunicationDevice(previous) else manager.clearCommunicationDevice()
            } else {
                @Suppress("DEPRECATION")
                manager.isSpeakerphoneOn = previousSpeaker
            }
            manager.mode = previousMode
            ownsSession = false
        }
    }

    fun dispose() {
        stop()
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
    }
}
