import AVFAudio
import Flutter
import Foundation

/// iOS peer of the Android PCM playback handler (MainActivity.kt).
///
/// Plays the Gemini Live output audio (24 kHz mono PCM16, streamed) through
/// an AVAudioEngine + AVAudioPlayerNode, and owns the shared AVAudioSession
/// for the whole voice session: `.playAndRecord` + `.voiceChat` +
/// `.defaultToSpeaker`. The `record` plugin captures the mic with
/// `echoCancel: false` on iOS and is told NOT to manage the session
/// (see voice.dart), so the two sides don't fight over it.
///
/// There is NO echo cancellation on iOS in this configuration — the known
/// consequence is that the agent's own speech can leak from the speaker into
/// the mic and interrupt it. Apple's voice-processing I/O was tried in every
/// topology and failed on hardware; the experiments and their outcomes are
/// recorded in AUDIO.md § iOS. Do not re-enable `echoCancel` on iOS or add
/// `setVoiceProcessingEnabled` here without reading that section first.
final class PcmAudioPlayer: NSObject {
  static let channelName = "live.walletbot.app/pcm_audio"

  private var engine: AVAudioEngine?
  private var playerNode: AVAudioPlayerNode?
  private var playbackFormat: AVAudioFormat?
  private var configChangeObserver: NSObjectProtocol?
  private var enqueueCount = 0

  private var sessionConfigured = false
  private var previousCategory: AVAudioSession.Category = .soloAmbient
  private var previousMode: AVAudioSession.Mode = .default
  private var previousOptions: AVAudioSession.CategoryOptions = []

  func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(
          FlutterError(
            code: "pcm_disposed",
            message: "PCM player is gone",
            details: nil
          )
        )
        return
      }
      switch call.method {
      case "start":
        self.handleStart(call, result: result)
      case "enqueue":
        self.handleEnqueue(call, result: result)
      case "interrupt":
        self.handleInterrupt(result)
      case "stop":
        self.handleStop(result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func handleStart(_ call: FlutterMethodCall, result: FlutterResult) {
    let args = call.arguments as? [String: Any]
    let sampleRate = args?["sampleRate"] as? Int ?? 24000
    do {
      try startPlayback(sampleRate: sampleRate)
      result(nil)
    } catch {
      NSLog("[PcmAudio] start FAILED: \(error)")
      stopPlayback()
      result(
        FlutterError(
          code: "pcm_start_failed",
          message: error.localizedDescription,
          details: nil
        )
      )
    }
  }

  private func handleEnqueue(_ call: FlutterMethodCall, result: FlutterResult) {
    guard let bytes = call.arguments as? FlutterStandardTypedData else {
      result(
        FlutterError(
          code: "pcm_bad_args",
          message: "Expected PCM bytes",
          details: nil
        )
      )
      return
    }
    guard let engine, let playerNode, let playbackFormat else {
      result(
        FlutterError(
          code: "pcm_not_started",
          message: "PCM playback is not started",
          details: nil
        )
      )
      return
    }

    // An audio-session interruption (call, Siri, ...) stops the engine.
    // Apple's guidance is to restart it afterwards; do so lazily here.
    if !engine.isRunning {
      NSLog("[PcmAudio] enqueue: engine not running, restarting")
      do {
        try engine.start()
        playerNode.play()
        NSLog("[PcmAudio] enqueue: engine restarted OK")
      } catch {
        NSLog("[PcmAudio] enqueue: engine restart FAILED: \(error)")
      }
    }

    if let buffer = makeBuffer(from: bytes.data, format: playbackFormat) {
      // Non-blocking: appends to the node's schedule queue. Unlike Android's
      // AudioTrack.write there is no blocking write loop, so no generation
      // counter is needed — interrupt()'s stop() clears the whole queue.
      playerNode.scheduleBuffer(buffer, completionHandler: nil)
      enqueueCount += 1
      if enqueueCount == 1 || enqueueCount % 50 == 0 {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs
          .map { "\($0.portType.rawValue):\($0.portName)" }
          .joined(separator: ",")
        NSLog(
          "[PcmAudio] enqueue #%d frames=%d engineRunning=%d nodePlaying=%d "
            + "route=[%@] hwRate=%.0f outVol=%.2f",
          enqueueCount,
          Int(buffer.frameLength),
          engine.isRunning ? 1 : 0,
          playerNode.isPlaying ? 1 : 0,
          outputs,
          session.sampleRate,
          session.outputVolume
        )
      }
    } else {
      NSLog("[PcmAudio] enqueue: makeBuffer FAILED (bytes=%d)", bytes.data.count)
    }
    result(nil)
  }

  private func handleInterrupt(_ result: FlutterResult) {
    // AVAudioPlayerNode.stop() clears all scheduled buffers, including the
    // one mid-play (AVAudioPlayerNode.h) — the exact flush semantics
    // interrupt needs. Restart so later enqueues are audible.
    NSLog("[PcmAudio] interrupt after %d chunks", enqueueCount)
    playerNode?.stop()
    playerNode?.play()
    result(nil)
  }

  private func handleStop(_ result: FlutterResult) {
    stopPlayback()
    result(nil)
  }

  private func startPlayback(sampleRate: Int) throws {
    NSLog("[PcmAudio] start requested: rate=%d", sampleRate)
    stopPlayback()

    try configureVoiceSession()

    guard
      let format = AVAudioFormat(
        standardFormatWithSampleRate: Double(sampleRate),
        channels: 1
      )
    else {
      throw NSError(
        domain: "PcmAudioPlayer",
        code: 1,
        userInfo: [
          NSLocalizedDescriptionKey: "Unsupported sample rate: \(sampleRate)"
        ]
      )
    }

    let engine = AVAudioEngine()
    let node = AVAudioPlayerNode()
    engine.attach(node)
    // The mixer resamples 24 kHz mono to whatever the hardware route runs at.
    engine.connect(node, to: engine.mainMixerNode, format: format)
    engine.prepare()
    try engine.start()
    node.play()

    // The engine stops itself when the session's I/O configuration changes
    // (e.g. a route change). Observe it for the forensic trail; the actual
    // restart happens lazily in enqueue.
    configChangeObserver = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange,
      object: engine,
      queue: nil
    ) { [weak engine] _ in
      let session = AVAudioSession.sharedInstance()
      NSLog(
        "[PcmAudio] engine configuration change: engineRunning=%d hwRate=%.0f",
        (engine?.isRunning ?? false) ? 1 : 0,
        session.sampleRate
      )
    }

    let session = AVAudioSession.sharedInstance()
    let outputs = session.currentRoute.outputs
      .map { "\($0.portType.rawValue):\($0.portName)" }
      .joined(separator: ",")
    NSLog(
      "[PcmAudio] start: rate=%d category=%@ mode=%@ route=[%@] hwRate=%.0f",
      sampleRate,
      session.category.rawValue,
      session.mode.rawValue,
      outputs,
      session.sampleRate
    )

    self.engine = engine
    self.playerNode = node
    self.playbackFormat = format
    self.enqueueCount = 0
  }

  private func stopPlayback() {
    if let observer = configChangeObserver {
      NotificationCenter.default.removeObserver(observer)
      configChangeObserver = nil
    }
    if engine != nil {
      NSLog("[PcmAudio] stop: enqueued %d chunks total", enqueueCount)
    }
    playerNode?.stop()
    engine?.stop()
    playerNode = nil
    engine = nil
    playbackFormat = nil
    restoreSession()
  }

  /// iOS analog of Android's MODE_IN_COMMUNICATION + speakerphone block:
  /// `.voiceChat` selects the voice-communication signal path, and
  /// `.defaultToSpeaker` routes to the loudspeaker unless headphones or
  /// Bluetooth are connected.
  private func configureVoiceSession() throws {
    let session = AVAudioSession.sharedInstance()
    previousCategory = session.category
    previousMode = session.mode
    previousOptions = session.categoryOptions
    try session.setCategory(
      .playAndRecord,
      mode: .voiceChat,
      options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP]
    )
    try session.setActive(true)
    sessionConfigured = true
  }

  private func restoreSession() {
    guard sessionConfigured else { return }
    sessionConfigured = false
    let session = AVAudioSession.sharedInstance()
    // Best-effort, mirroring Android's restoreAudioMode.
    try? session.setActive(false, options: .notifyOthersOnDeactivation)
    try? session.setCategory(
      previousCategory,
      mode: previousMode,
      options: previousOptions
    )
  }

  /// Wire format is little-endian PCM16 mono; the player node's connection
  /// format is deinterleaved Float32, so convert sample-by-sample.
  private func makeBuffer(
    from data: Data,
    format: AVAudioFormat
  ) -> AVAudioPCMBuffer? {
    let frameCount = data.count / MemoryLayout<Int16>.size
    guard frameCount > 0,
      let buffer = AVAudioPCMBuffer(
        pcmFormat: format,
        frameCapacity: AVAudioFrameCount(frameCount)
      ),
      let channel = buffer.floatChannelData?[0]
    else {
      return nil
    }
    buffer.frameLength = AVAudioFrameCount(frameCount)
    data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
      let samples = raw.bindMemory(to: Int16.self)
      for i in 0..<frameCount {
        channel[i] = Float(Int16(littleEndian: samples[i])) / 32768.0
      }
    }
    return buffer
  }
}
