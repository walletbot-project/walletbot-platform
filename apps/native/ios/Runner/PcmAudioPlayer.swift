import AVFAudio
import Flutter
import Foundation

/// One native owner for playback, microphone capture and AVAudioSession.
/// Playback starts without requesting microphone access. The capture listener
/// upgrades to a single voice-processing engine after permission is granted.
/// Both directions then share the same echo-cancellation reference.
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
  private var configChangeObserver: NSObjectProtocol?
  private var enqueueCount = 0
  private var queuedFrames: AVAudioFrameCount = 0
  private var playbackGeneration = 0
  private var captureEnabled = false
  private var captureGeneration = 0
  private var interruptionObserver: NSObjectProtocol?

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
      try startEngine(capture: false)
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
    if engine == nil {
      do { try startEngine(capture: false) } catch {
        result(FlutterError(code: "pcm_restart_failed", message: error.localizedDescription, details: nil))
        return
      }
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
        result(FlutterError(code: "pcm_restart_failed", message: error.localizedDescription, details: nil))
        return
      }
    }

    guard bytes.data.count % 2 == 0 else {
      result(FlutterError(code: "pcm_bad_args", message: "Unaligned PCM16", details: nil))
      return
    }
    if let buffer = makeBuffer(from: bytes.data, format: playbackFormat) {
      guard queuedFrames + buffer.frameLength <= AVAudioFrameCount(Self.voiceIORate * 20) else {
        result(FlutterError(code: "pcm_queue_full", message: "Playback queue full", details: nil))
        return
      }
      // Non-blocking: appends to the node's schedule queue. Unlike Android's
      // AudioTrack.write there is no blocking write loop, so no generation
      // counter is needed — interrupt()'s stop() clears the whole queue.
      queuedFrames += buffer.frameLength
      let generation = playbackGeneration
      let frames = buffer.frameLength
      playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
        DispatchQueue.main.async {
          guard let self, self.playbackGeneration == generation else { return }
          self.queuedFrames -= min(self.queuedFrames, frames)
        }
      }
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
    playbackGeneration += 1
    queuedFrames = 0
    playerNode?.stop()
    playerNode?.play()
    result(nil)
  }

  private func handleStop(_ result: FlutterResult) {
    stopEngine()
    result(nil)
  }

  // MARK: - Engine lifecycle

  private func startEngine(capture: Bool) throws {
    NSLog("[PcmAudio] start requested")
    stopEngine()

    captureEnabled = capture
    try configureVoiceSession(capture: capture)

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
    self.engine = engine

    voiceProcessingActive = false
    if capture {
      // Never silently fall back to an echo-prone duplex session.
      try engine.inputNode.setVoiceProcessingEnabled(true)
      voiceProcessingActive = true
      let inputFormat = engine.inputNode.outputFormat(forBus: 0)
      guard isUsable(inputFormat) else {
        throw NSError(domain: "PcmAudioPlayer", code: 2,
          userInfo: [NSLocalizedDescriptionKey: "Microphone input unavailable"])
      }
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
    if capture {
      try installCaptureTap(engine: engine, srcFormat: engine.inputNode.outputFormat(forBus: 0))
    }

    engine.prepare()
    try startWithRetry(engine)
    node.play()

    configChangeObserver = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
    ) { [weak self] notification in
      guard let changedEngine = notification.object as? AVAudioEngine else { return }
      self?.handleConfigurationChange(changedEngine)
    }
    interruptionObserver = NotificationCenter.default.addObserver(
      forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
    ) { [weak self] notification in
      guard let self,
        let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
        let type = AVAudioSession.InterruptionType(rawValue: value) else { return }
      if type == .began {
        let sink = self.captureSink
        self.captureSink = nil
        self.stopEngine()
        sink?(FlutterError(code: "audio_interrupted", message: "Audio session interrupted", details: nil))
      }
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

  /// AVAudioEngine.h: on an I/O hardware change the engine stops itself and
  /// posts this; nodes stay attached and the app reestablishes connections
  /// whose format changed, then restarts. Enabling voice processing triggers
  /// it too, right after the first start(). Restart the same engine in place:
  /// a fresh engine plus session deactivate/reactivate re-posts the
  /// notification and resets the echo canceller on every pass.
  private func handleConfigurationChange(_ changedEngine: AVAudioEngine) {
    guard let engine, engine === changedEngine, let playerNode else { return }
    NSLog(
      "[PcmAudio] configuration change: running=%d capture=%d route=[%@] hwRate=%.0f",
      engine.isRunning ? 1 : 0,
      captureEnabled ? 1 : 0,
      routeDescription(),
      AVAudioSession.sharedInstance().sampleRate
    )
    do {
      if captureEnabled {
        removeCaptureTap()
        try installCaptureTap(engine: engine, srcFormat: engine.inputNode.outputFormat(forBus: 0))
      }
      // The stop dropped the player's schedule; account for it like interrupt.
      playbackGeneration += 1
      queuedFrames = 0
      playerNode.stop()
      engine.prepare()
      try startWithRetry(engine)
      playerNode.play()
      NSLog("[PcmAudio] configuration change handled: running=%d", engine.isRunning ? 1 : 0)
    } catch {
      NSLog("[PcmAudio] configuration change restart FAILED: \(error)")
      let sink = captureSink
      captureSink = nil
      stopEngine()
      sink?(FlutterError(code: "audio_route_failed", message: error.localizedDescription, details: nil))
    }
  }

  private func stopEngine() {
    captureGeneration += 1
    if let observer = interruptionObserver {
      NotificationCenter.default.removeObserver(observer)
      interruptionObserver = nil
    }
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
    playbackGeneration += 1
    queuedFrames = 0
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
  private func configureVoiceSession(capture: Bool) throws {
    let session = AVAudioSession.sharedInstance()
    previousCategory = session.category
    previousMode = session.mode
    previousOptions = session.categoryOptions
    sessionConfigured = true
    try session.setCategory(
      capture ? .playAndRecord : .playback,
      mode: capture ? .voiceChat : .default,
      options: capture ? [.defaultToSpeaker, .allowBluetoothHFP] : []
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
    let generation = captureGeneration
    engine.inputNode.installTap(
      onBus: 0,
      bufferSize: bufferSize,
      format: srcFormat
    ) { [weak self] buffer, _ in
      self?.emitCapturedBuffer(buffer, converter: converter, generation: generation)
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
  private func emitCapturedBuffer(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, generation: Int) {

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
      guard let self, self.captureGeneration == generation else { return }
      self.captureSink?(FlutterStandardTypedData(bytes: data))
    }
  }

  // MARK: - Diagnostics

  private func diagnostics() -> [String: Any] {
    let session = AVAudioSession.sharedInstance()
    let input = captureEnabled ? engine?.inputNode : nil
    let map: [String: Any] = [
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
    return map
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
    do {
      try startEngine(capture: true)
    } catch {
      stopEngine()
      return FlutterError(code: "pcm_capture_failed", message: error.localizedDescription, details: nil)
    }
    NSLog("[PcmAudio] capture sink attached")
    captureSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    NSLog("[PcmAudio] capture sink detached after %d chunks", captureChunkCount)
    captureSink = nil
    if engine != nil && captureEnabled {
      do { try startEngine(capture: false) } catch { stopEngine() }
    }
    return nil
  }
}
