import AVFAudio
import Flutter
import Foundation

/// The native half of the iOS voice session: ONE AVAudioEngine doing both
/// the agent-audio playback and the mic capture, with Apple's
/// voice-processing I/O (echo cancellation) enabled on it.
///
/// Why one engine: voice processing requires both I/O nodes of the SAME
/// engine (AVAudioIONode.h), and the far-end reference for the echo
/// canceller is that engine's own output. Split-engine topologies were
/// tried and failed both ways on hardware — see AUDIO.md § iOS.
///
/// The call sequence below follows Apple's "Using voice processing" sample
/// (AVEchoTouch) with the guards production stacks add around it (WebRTC's
/// iOS ADM, LiveKit's AVAudioEngine ADM):
/// session configured+activated first → setVoiceProcessingEnabled on a
/// fresh, stopped engine before any wiring → formats read AFTER the VP
/// switch (it changes them) → mixer→output connected explicitly → input
/// tap installed BEFORE engine.start() → start retried (VPIO can fail
/// transiently with undocumented -66635/-66637) → engine restarted on
/// AVAudioEngineConfigurationChange.
///
/// AGC is deliberately left at its default (enabled): WebRTC's
/// voice_processing_audio_unit.mm force-enables it, citing devices where
/// "only zeros are recorded and a disabled AGC could be one of the reasons".
///
/// Playback: `live.walletbot.app/pcm_audio` method channel
/// (start/enqueue/interrupt/stop), 24 kHz mono PCM16 in, mirroring
/// Android's MainActivity.kt. `start` returns a diagnostics map that the
/// Dart side persists into the voice-session event log.
/// Capture: `live.walletbot.app/pcm_audio/capture` event channel emitting
/// 16 kHz mono PCM16 chunks (the Gemini Live wire format). The tap lives
/// for the whole engine lifetime; listen/cancel only gates delivery.
final class PcmAudioPlayer: NSObject {
  static let channelName = "live.walletbot.app/pcm_audio"
  static let captureChannelName = "live.walletbot.app/pcm_audio/capture"

  /// The single graph format (Apple's sample calls this the voiceIOFormat):
  /// player→mixer, mixer→output, and the session's preferred rate all use
  /// it. 24 kHz is the agent-audio wire rate and a native VPIO rate.
  private static let voiceIORate: Double = 24000
  private static let captureRate: Double = 16000

  private var engine: AVAudioEngine?
  private var playerNode: AVAudioPlayerNode?
  private var playbackFormat: AVAudioFormat?
  private var voiceProcessingActive = false
  private var vpFallbackReason: String?
  private var configChangeObserver: NSObjectProtocol?
  private var enqueueCount = 0

  private var captureSink: FlutterEventSink?
  private var captureConverter: AVAudioConverter?
  private var captureTapInstalled = false
  private var captureChunkCount = 0

  private var sessionConfigured = false
  private var previousCategory: AVAudioSession.Category = .soloAmbient
  private var previousMode: AVAudioSession.Mode = .default
  private var previousOptions: AVAudioSession.CategoryOptions = []

  func register(with messenger: FlutterBinaryMessenger) {
    let captureChannel = FlutterEventChannel(
      name: Self.captureChannelName,
      binaryMessenger: messenger
    )
    captureChannel.setStreamHandler(self)

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
    do {
      try startEngine()
      result(diagnostics())
    } catch {
      NSLog("[PcmAudio] start FAILED: \(error)")
      stopEngine()
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
        NSLog(
          "[PcmAudio] enqueue #%d frames=%d engineRunning=%d nodePlaying=%d "
            + "route=[%@] hwRate=%.0f outVol=%.2f",
          enqueueCount,
          Int(buffer.frameLength),
          engine.isRunning ? 1 : 0,
          playerNode.isPlaying ? 1 : 0,
          routeDescription(),
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
    stopEngine()
    result(nil)
  }

  // MARK: - Engine lifecycle

  private func startEngine() throws {
    NSLog("[PcmAudio] start requested")
    stopEngine()

    try configureVoiceSession()

    guard
      let voiceIOFormat = AVAudioFormat(
        standardFormatWithSampleRate: Self.voiceIORate,
        channels: 1
      )
    else {
      throw NSError(
        domain: "PcmAudioPlayer",
        code: 1,
        userInfo: [
          NSLocalizedDescriptionKey: "Cannot build \(Self.voiceIORate) Hz format"
        ]
      )
    }

    // Fresh engine every time: voice processing defaults to off on a new
    // engine and LiveKit's ADM rebuilds rather than reuse for that reason.
    let engine = AVAudioEngine()

    // Voice processing must be flipped while the engine is stopped, before
    // any wiring; enabling it on the input node enables it on the output
    // node too (AVAudioIONode.h). This makes our own playback the echo
    // canceller's far-end reference.
    voiceProcessingActive = false
    vpFallbackReason = nil
    do {
      try engine.inputNode.setVoiceProcessingEnabled(true)
      voiceProcessingActive = true
      NSLog("[PcmAudio] voice processing ENABLED")
    } catch {
      vpFallbackReason = "enable_failed: \(error)"
      NSLog("[PcmAudio] setVoiceProcessingEnabled FAILED: \(error)")
    }

    // Formats must be read AFTER the VP switch — it changes them. A zero
    // sample rate/channel count here means input is not actually available
    // and the engine would throw or run dead (Apple's documented check,
    // enforced the way LiveKit's ADM does).
    var inputFormat = engine.inputNode.outputFormat(forBus: 0)
    logFormats(engine: engine, label: "post-vp")
    if voiceProcessingActive && !isUsable(inputFormat) {
      vpFallbackReason = "zero_input_format: \(inputFormat)"
      NSLog("[PcmAudio] input format unusable with VP, disabling VP")
      try engine.inputNode.setVoiceProcessingEnabled(false)
      voiceProcessingActive = false
      inputFormat = engine.inputNode.outputFormat(forBus: 0)
      logFormats(engine: engine, label: "post-vp-fallback")
    }
    guard isUsable(inputFormat) else {
      throw NSError(
        domain: "PcmAudioPlayer",
        code: 2,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Microphone input unavailable (format: \(inputFormat))"
        ]
      )
    }

    let node = AVAudioPlayerNode()
    engine.attach(node)
    engine.connect(node, to: engine.mainMixerNode, format: voiceIOFormat)
    // Apple's sample connects mixer→output explicitly with the voiceIO
    // format instead of trusting the implicit connection; the output node
    // converts to the hardware rate.
    engine.connect(engine.mainMixerNode, to: engine.outputNode, format: voiceIOFormat)

    // Tap installed BEFORE engine.start() (Apple sample and record_ios —
    // the latter is the sequence proven to capture on this hardware), with
    // the node's actual post-VP format; conversion to the 16 kHz wire
    // format happens in emitCapturedBuffer.
    try installCaptureTap(engine: engine, srcFormat: inputFormat)

    engine.prepare()
    try startWithRetry(engine)
    node.play()

    // The engine stops itself when the session's I/O configuration changes
    // (route change, VP renegotiation). Restart it eagerly — a naive engine
    // stays silently stopped after this notification.
    configChangeObserver = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange,
      object: engine,
      queue: .main
    ) { [weak self] _ in
      self?.handleConfigurationChange()
    }

    self.engine = engine
    self.playerNode = node
    self.playbackFormat = voiceIOFormat
    self.enqueueCount = 0

    let session = AVAudioSession.sharedInstance()
    NSLog(
      "[PcmAudio] started: vp=%d running=%d category=%@ mode=%@ route=[%@] "
        + "hwRate=%.0f ioBuf=%.1fms",
      voiceProcessingActive ? 1 : 0,
      engine.isRunning ? 1 : 0,
      session.category.rawValue,
      session.mode.rawValue,
      routeDescription(),
      session.sampleRate,
      session.ioBufferDuration * 1000
    )
  }

  /// VPIO initialization can fail transiently: WebRTC retries for the
  /// undocumented -66635, LiveKit retries -66637 after interruptions and
  /// when another process still holds the voice-processing unit.
  private func startWithRetry(_ engine: AVAudioEngine, attempts: Int = 5) throws {
    var lastError: Error?
    for attempt in 1...attempts {
      do {
        try engine.start()
        if attempt > 1 {
          NSLog("[PcmAudio] engine.start succeeded on attempt %d", attempt)
        }
        return
      } catch {
        lastError = error
        NSLog(
          "[PcmAudio] engine.start attempt %d FAILED: %@",
          attempt,
          String(describing: error)
        )
        Thread.sleep(forTimeInterval: 0.1)
      }
    }
    throw lastError
      ?? NSError(
        domain: "PcmAudioPlayer",
        code: 3,
        userInfo: [NSLocalizedDescriptionKey: "engine.start failed"]
      )
  }

  private func handleConfigurationChange() {
    guard let engine, let playerNode else { return }
    let session = AVAudioSession.sharedInstance()
    NSLog(
      "[PcmAudio] engine configuration change: running=%d hwRate=%.0f route=[%@]",
      engine.isRunning ? 1 : 0,
      session.sampleRate,
      routeDescription()
    )
    logFormats(engine: engine, label: "config-change")
    guard !engine.isRunning else { return }
    do {
      try startWithRetry(engine, attempts: 3)
      playerNode.play()
      NSLog("[PcmAudio] engine restarted after configuration change")
    } catch {
      NSLog("[PcmAudio] restart after configuration change FAILED: \(error)")
    }
  }

  private func stopEngine() {
    if let observer = configChangeObserver {
      NotificationCenter.default.removeObserver(observer)
      configChangeObserver = nil
    }
    if engine != nil {
      NSLog(
        "[PcmAudio] stop: %d chunks played, %d captured",
        enqueueCount,
        captureChunkCount
      )
    }
    removeCaptureTap()
    playerNode?.stop()
    engine?.stop()
    playerNode = nil
    engine = nil
    playbackFormat = nil
    voiceProcessingActive = false
    restoreSession()
  }

  // MARK: - Audio session

  /// iOS analog of Android's MODE_IN_COMMUNICATION + speakerphone block.
  /// Same category/mode/options as WebRTC's RTCAudioSessionConfiguration
  /// (playAndRecord + voiceChat + Bluetooth), plus `.defaultToSpeaker`.
  /// The preferred rate matches the graph's voiceIO format (Apple's sample
  /// does the same with its rate) and the 20 ms buffer follows WebRTC.
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
    try? session.setPreferredSampleRate(Self.voiceIORate)
    try? session.setPreferredIOBufferDuration(0.02)
    try session.setActive(true)
    sessionConfigured = true
    NSLog(
      "[PcmAudio] session active: category=%@ mode=%@ hwRate=%.0f route=[%@] "
        + "inputAvailable=%d otherAudio=%d",
      session.category.rawValue,
      session.mode.rawValue,
      session.sampleRate,
      routeDescription(),
      session.isInputAvailable ? 1 : 0,
      session.isOtherAudioPlaying ? 1 : 0
    )
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

  // MARK: - Mic capture

  private func installCaptureTap(
    engine: AVAudioEngine,
    srcFormat: AVAudioFormat
  ) throws {
    guard
      let dstFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: Self.captureRate,
        channels: 1,
        interleaved: true
      ),
      let converter = AVAudioConverter(from: srcFormat, to: dstFormat)
    else {
      throw NSError(
        domain: "PcmAudioPlayer",
        code: 4,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Cannot convert \(srcFormat) to 16 kHz mono PCM16"
        ]
      )
    }
    converter.sampleRateConverterQuality = AVAudioQuality.high.rawValue

    captureConverter = converter
    captureChunkCount = 0
    // ~100 ms per tap buffer, in source-format frames.
    let bufferSize = AVAudioFrameCount(max(srcFormat.sampleRate / 10, 1024))
    engine.inputNode.installTap(
      onBus: 0,
      bufferSize: bufferSize,
      format: srcFormat
    ) { [weak self] buffer, _ in
      self?.emitCapturedBuffer(buffer)
    }
    captureTapInstalled = true
    NSLog(
      "[PcmAudio] capture tap installed: src=%.0fHz ch=%d bufferSize=%d",
      srcFormat.sampleRate,
      srcFormat.channelCount,
      bufferSize
    )
  }

  private func removeCaptureTap() {
    guard captureTapInstalled else { return }
    engine?.inputNode.removeTap(onBus: 0)
    captureTapInstalled = false
    captureConverter = nil
  }

  /// Runs on the tap's realtime-adjacent thread; converts to the wire format
  /// and hands the bytes to Flutter on the main thread.
  private func emitCapturedBuffer(_ buffer: AVAudioPCMBuffer) {
    guard let converter = captureConverter else { return }

    let ratio = Self.captureRate / buffer.format.sampleRate
    let capacity =
      AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
    guard
      let out = AVAudioPCMBuffer(
        pcmFormat: converter.outputFormat,
        frameCapacity: capacity
      )
    else { return }

    // Offer the input buffer exactly once per convert() call; the converter
    // keeps resampler state across calls, so the stream stays continuous.
    var consumed = false
    var error: NSError?
    converter.convert(to: out, error: &error) { _, outStatus in
      if consumed {
        outStatus.pointee = .noDataNow
        return nil
      }
      consumed = true
      outStatus.pointee = .haveData
      return buffer
    }
    if let error {
      NSLog("[PcmAudio] capture convert FAILED: \(error)")
      return
    }

    let frames = Int(out.frameLength)
    guard frames > 0, let samples = out.int16ChannelData?[0] else { return }
    let data = Data(bytes: samples, count: frames * MemoryLayout<Int16>.size)

    captureChunkCount += 1
    if captureChunkCount == 1 || captureChunkCount % 100 == 0 {
      var peak: Int16 = 0
      for i in 0..<frames {
        let magnitude = samples[i] == Int16.min ? Int16.max : abs(samples[i])
        if magnitude > peak { peak = magnitude }
      }
      NSLog(
        "[PcmAudio] capture #%d frames=%d peak=%d sinkAttached=%d",
        captureChunkCount,
        frames,
        peak,
        captureSink != nil ? 1 : 0
      )
    }
    DispatchQueue.main.async { [weak self] in
      self?.captureSink?(FlutterStandardTypedData(bytes: data))
    }
  }

  // MARK: - Diagnostics

  private func diagnostics() -> [String: Any] {
    let session = AVAudioSession.sharedInstance()
    let input = engine?.inputNode
    var map: [String: Any] = [
      "voiceProcessing": voiceProcessingActive,
      "engineRunning": engine?.isRunning ?? false,
      "sessionCategory": session.category.rawValue,
      "sessionMode": session.mode.rawValue,
      "sessionSampleRate": session.sampleRate,
      "ioBufferMs": session.ioBufferDuration * 1000,
      "route": routeDescription(),
      "inputFormat": input.map { "\($0.outputFormat(forBus: 0))" } ?? "none",
      "inputHwFormat": input.map { "\($0.inputFormat(forBus: 0))" } ?? "none",
    ]
    if let vpFallbackReason {
      map["vpFallback"] = vpFallbackReason
    }
    return map
  }

  private func logFormats(engine: AVAudioEngine, label: String) {
    let input = engine.inputNode
    let output = engine.outputNode
    NSLog(
      "[PcmAudio] formats(%@): input.out=%@ input.hw=%@ output.out=%@",
      label,
      String(describing: input.outputFormat(forBus: 0)),
      String(describing: input.inputFormat(forBus: 0)),
      String(describing: output.outputFormat(forBus: 0))
    )
  }

  private func isUsable(_ format: AVAudioFormat) -> Bool {
    format.sampleRate > 0 && format.channelCount > 0
  }

  private func routeDescription() -> String {
    let route = AVAudioSession.sharedInstance().currentRoute
    let inputs = route.inputs.map { "\($0.portType.rawValue)" }
    let outputs = route.outputs.map { "\($0.portType.rawValue)" }
    return "in:\(inputs.joined(separator: "+")) out:\(outputs.joined(separator: "+"))"
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

extension PcmAudioPlayer: FlutterStreamHandler {
  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    guard engine != nil, captureTapInstalled else {
      return FlutterError(
        code: "pcm_not_started",
        message: "Voice engine is not running; start playback first",
        details: nil
      )
    }
    NSLog("[PcmAudio] capture sink attached")
    captureSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    NSLog("[PcmAudio] capture sink detached after %d chunks", captureChunkCount)
    captureSink = nil
    return nil
  }
}
