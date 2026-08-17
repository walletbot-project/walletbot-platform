import 'dart:async';
import 'dart:typed_data';

import 'voice_event.dart';

abstract interface class VoiceExpenseCommandFactory {
  VoiceExpenseCommand? get activeCommand;

  VoiceExpenseCommand create();

  /// Conversation events of the session a newly created command would resume,
  /// restored from the durable log. Empty when the next session starts fresh
  /// (no resumable session), so a restored transcript always matches the
  /// context the model will actually continue from.
  Future<List<VoiceEvent>> restorableHistory();
}

abstract interface class VoiceExpenseCommand {
  String get label;

  /// Live events only, from subscription time onward. A re-attaching screen
  /// rebuilds prior conversation state from [history] in one pass instead of
  /// replaying the stream event by event.
  Stream<VoiceEvent> get events;

  /// Events already emitted in this session, oldest first.
  List<VoiceEvent> get history;

  bool get isActive;

  bool get isConnected;

  Future<void> start({bool respondWithAudio = true});

  /// Reconnects immediately when the session is active but the transport is
  /// down (e.g. after the OS resumes the app, skipping any pending backoff
  /// timer). No-op when already connected or when there is no session.
  Future<void> ensureConnected();

  Future<void> addAudioChunk(Uint8List chunk);

  /// Flushes any audio buffered server-side since the last chunk so the
  /// model treats the current audio turn as complete. Safe to call when no
  /// audio has been sent since the last flush — implementations no-op in
  /// that case. Required by Gemini Live's automatic VAD whenever the
  /// client pauses the stream (mic mute, switching to text input, etc.)
  /// so that the next utterance isn't concatenated with a half-spoken one.
  Future<void> endAudioStream();

  Future<void> sendText(String text);

  void setAudioPlaybackEnabled(bool enabled);

  void recordClientEvent(
    String action, [
    Map<String, Object?> details = const {},
  ]);

  /// Immediately clears queued agent audio without ending the Live session.
  Future<void> interruptAgentResponse({required String reason});

  Future<VoiceExpenseCommandResult> stop();

  Future<void> dispose();
}

class VoiceExpenseCommandResult {
  const VoiceExpenseCommandResult({
    required this.message,
    this.createdExpense = false,
  });

  final String message;
  final bool createdExpense;
}

class DebugVoiceExpenseCommandFactory implements VoiceExpenseCommandFactory {
  const DebugVoiceExpenseCommandFactory();

  @override
  VoiceExpenseCommand? get activeCommand => null;

  @override
  VoiceExpenseCommand create() => DebugVoiceExpenseCommand();

  @override
  Future<List<VoiceEvent>> restorableHistory() async => const [];
}

class DebugVoiceExpenseCommand implements VoiceExpenseCommand {
  final _events = StreamController<VoiceEvent>.broadcast();

  int _chunks = 0;
  int _bytes = 0;

  @override
  String get label => 'Debug voice expense command';

  @override
  Stream<VoiceEvent> get events => _events.stream;

  @override
  List<VoiceEvent> get history => const [];

  @override
  bool get isActive => true;

  @override
  bool get isConnected => true;

  @override
  Future<void> start({bool respondWithAudio = true}) async {
    _chunks = 0;
    _bytes = 0;
    _events.add(
      VoiceConnectingEvent(
        'Debug command started (respondWithAudio=$respondWithAudio)',
      ),
    );
    _events.add(VoiceConnectedEvent());
  }

  @override
  Future<void> ensureConnected() async {}

  @override
  Future<void> addAudioChunk(Uint8List chunk) async {
    _chunks += 1;
    _bytes += chunk.length;
  }

  @override
  Future<void> endAudioStream() async {
    _events.add(VoiceSystemEvent('Debug audio stream ended'));
  }

  @override
  Future<void> sendText(String text) async {
    _events.add(VoiceSystemEvent('Debug received text: $text'));
  }

  @override
  void setAudioPlaybackEnabled(bool enabled) {
    _events.add(VoiceSystemEvent('Debug audio playback: $enabled'));
  }

  @override
  void recordClientEvent(
    String action, [
    Map<String, Object?> details = const {},
  ]) {
    _events.add(VoiceClientActionEvent(action, details: details));
  }

  @override
  Future<void> interruptAgentResponse({required String reason}) async {
    _events.add(VoiceAgentInterruptedEvent(reason: reason));
  }

  @override
  Future<VoiceExpenseCommandResult> stop() async {
    final message =
        'Debug implementation received $_chunks audio chunks ($_bytes bytes).';
    _events.add(VoiceSystemEvent(message));
    _events.add(VoiceDisconnectedEvent());
    return VoiceExpenseCommandResult(message: message);
  }

  @override
  Future<void> dispose() async {
    await _events.close();
  }
}
