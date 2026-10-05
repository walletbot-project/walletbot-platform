import 'dart:async';
import 'dart:typed_data';

import 'voice_event.dart';

/// Who ends a spoken turn. The mode is baked into the Live token, so changing
/// it opens a new socket, seeded from the conversation log.
enum VoiceConversationMode {
  /// Voice notes and text. Gemini's voice activity detection is off and the
  /// client brackets each turn with `activityStart`/`activityEnd`, so a note
  /// released mid-word is still answered.
  chat,

  /// Hands-free conversation: Gemini's voice activity detection ends turns.
  live;

  String get turnDetection => this == chat ? 'manual' : 'auto';
}

abstract interface class VoiceExpenseCommandFactory {
  VoiceExpenseCommand? get activeCommand;

  VoiceExpenseCommand create();

  /// Starts fetching a live token before a session needs it, so the mint
  /// round trip (roughly half of a cold connect) is hidden behind the user's
  /// think time on the voice screen. Tokens are single-use with a short
  /// new-session window, so implementations must discard stale prefetches
  /// rather than hand them to a connect. No-op when prefetching is
  /// irrelevant (debug, already-fresh prefetch in flight).
  void prefetchToken();

  /// Conversation events of the session a newly created command would resume,
  /// restored from the durable log. Empty when the next session starts fresh
  /// (no resumable session), so a restored transcript always matches the
  /// context the model will actually continue from.
  Future<List<VoiceEvent>> restorableHistory();

  /// Explicitly ends the session [restorableHistory] would restore, so a
  /// later screen open neither rehydrates its transcript nor resumes its
  /// model context. No-op when nothing is resumable.
  Future<void> discardRestorableSession();

  /// Id of the session [restorableHistory] would restore, so a report filed
  /// against a rehydrated transcript still names the conversation it came
  /// from. Null when nothing is resumable.
  Future<String?> restorableSessionId();
}

abstract interface class VoiceExpenseCommand {
  String get label;

  /// Id of the logged session this command is recording into, once one exists.
  /// Read when reporting a response, so the report points at the conversation
  /// the moderator can pull from `voiceSessionEvents`.
  String? get sessionId;

  /// Live events only, from subscription time onward. A re-attaching screen
  /// rebuilds prior conversation state from [history] in one pass instead of
  /// replaying the stream event by event.
  Stream<VoiceEvent> get events;

  /// Events already emitted in this session, oldest first.
  List<VoiceEvent> get history;

  bool get isActive;

  bool get isConnected;

  VoiceConversationMode get mode;

  Future<void> start({
    bool respondWithAudio = true,
    VoiceConversationMode mode = VoiceConversationMode.chat,
  });

  /// Moves the conversation to [next]: closes any open turn and replaces the
  /// socket with one minted for that mode, seeded from the conversation log.
  /// The replacement emits [VoiceConnectingEvent] and [VoiceConnectedEvent]
  /// but no [VoiceDisconnectedEvent]: it is not a dropped connection.
  Future<void> switchMode(VoiceConversationMode next);

  /// Reconnects immediately when the session is active but the transport is
  /// down (e.g. after the OS resumes the app, skipping any pending backoff
  /// timer). No-op when already connected or when there is no session.
  Future<void> ensureConnected();

  /// Acquires native audio for microphone capture or audible responses.
  /// Text-only sessions do not need an audio device or audio focus.
  Future<void> prepareAudio();

  Future<void> addAudioChunk(Uint8List chunk);

  /// Ends the current audio turn. In [VoiceConversationMode.chat] this is
  /// `activityEnd`, which makes the model answer right away. In
  /// [VoiceConversationMode.live] it is `audioStreamEnd`, which flushes the
  /// server's buffer while its voice activity detection still decides when
  /// the turn is over. Safe to call when no audio has been sent since the
  /// last end; implementations no-op in that case.
  Future<void> endTurn();

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
  void prefetchToken() {}

  @override
  Future<List<VoiceEvent>> restorableHistory() async => const [];

  @override
  Future<void> discardRestorableSession() async {}

  @override
  Future<String?> restorableSessionId() async => null;
}

class DebugVoiceExpenseCommand implements VoiceExpenseCommand {
  final _events = StreamController<VoiceEvent>.broadcast();

  int _chunks = 0;
  int _bytes = 0;

  @override
  String get label => 'Debug voice expense command';

  @override
  String? get sessionId => null;

  @override
  Stream<VoiceEvent> get events => _events.stream;

  @override
  List<VoiceEvent> get history => const [];

  @override
  bool get isActive => true;

  @override
  bool get isConnected => true;

  @override
  VoiceConversationMode mode = VoiceConversationMode.chat;

  @override
  Future<void> start({
    bool respondWithAudio = true,
    VoiceConversationMode mode = VoiceConversationMode.chat,
  }) async {
    _chunks = 0;
    _bytes = 0;
    this.mode = mode;
    _events.add(
      VoiceConnectingEvent(
        'Debug command started (respondWithAudio=$respondWithAudio)',
      ),
    );
    _events.add(VoiceConnectedEvent());
  }

  @override
  Future<void> switchMode(VoiceConversationMode next) async {
    if (next == mode) return;
    mode = next;
    _events.add(VoiceConnectingEvent('Debug switched to ${next.name}'));
    _events.add(VoiceConnectedEvent());
  }

  @override
  Future<void> ensureConnected() async {}

  @override
  Future<void> prepareAudio() async {}

  @override
  Future<void> addAudioChunk(Uint8List chunk) async {
    _chunks += 1;
    _bytes += chunk.length;
  }

  @override
  Future<void> endTurn() async {
    _events.add(VoiceSystemEvent('Debug audio turn ended'));
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
