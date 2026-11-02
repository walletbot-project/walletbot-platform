import 'dart:async';
import 'dart:typed_data';

import '../data/data.dart';
import 'demo_assistant_script.dart';
import 'live_protocol.dart';
import 'pcm_audio_player.dart';
import 'tool_executors.dart';
import 'voice_event.dart';
import 'voice_expense_command.dart';

/// Compile-time switch for the demo-video build
/// (`--dart-define=DEMO_ASSISTANT=true`). Off in every other build, so the
/// demo command and its script are tree-shaken away.
const kDemoAssistant = bool.fromEnvironment('DEMO_ASSISTANT');

class DemoVoiceExpenseCommandFactory implements VoiceExpenseCommandFactory {
  DemoVoiceExpenseCommandFactory(AppRepositories repositories)
    : _executors = ToolExecutors(repositories);

  final ToolExecutors _executors;
  DemoVoiceExpenseCommand? _active;

  @override
  VoiceExpenseCommand? get activeCommand =>
      (_active?.isActive ?? false) ? _active : null;

  @override
  VoiceExpenseCommand create() {
    final active = activeCommand;
    if (active != null) return active;
    return _active = DemoVoiceExpenseCommand(_executors);
  }

  @override
  void prefetchToken() {}

  @override
  Future<List<VoiceEvent>> restorableHistory() async => const [];

  @override
  Future<void> discardRestorableSession() async {}

  @override
  Future<String?> restorableSessionId() async => null;
}

/// Plays [demoAssistantScript] as a hands-free call: the user's words and the
/// agent's reply stream in word by word, like Gemini's live transcripts, with
/// no agent audio. Microphone input is ignored, but the native audio session
/// still has to be open for the screen's mic capture to start.
class DemoVoiceExpenseCommand implements VoiceExpenseCommand {
  DemoVoiceExpenseCommand(this._executors)
    : _turns = demoAssistantScript(DateTime.now());

  static const _userWordDelay = Duration(milliseconds: 330);
  static const _agentWordDelay = Duration(milliseconds: 220);
  static const _thinkingDelay = Duration(milliseconds: 1200);
  static const _toolDelay = Duration(milliseconds: 700);
  static const _turnGap = Duration(milliseconds: 2500);

  final ToolExecutors _executors;
  final List<DemoTurn> _turns;
  final _events = StreamController<VoiceEvent>.broadcast();
  final _history = <VoiceEvent>[];
  final _audioPlayer = PcmAudioPlayer();
  int _nextTurn = 0;
  int _toolCalls = 0;
  int _generation = 0;
  bool _active = false;
  bool _playing = false;

  @override
  String get label => 'Demo voice expense command';

  @override
  String? get sessionId => null;

  @override
  Stream<VoiceEvent> get events => _events.stream;

  @override
  List<VoiceEvent> get history => List.unmodifiable(_history);

  @override
  bool get isActive => _active;

  @override
  bool get isConnected => _active;

  @override
  VoiceConversationMode mode = VoiceConversationMode.chat;

  @override
  Future<void> start({
    bool respondWithAudio = true,
    VoiceConversationMode mode = VoiceConversationMode.chat,
  }) async {
    this.mode = mode;
    _active = true;
    _emit(VoiceConnectingEvent('Demo session starting'));
    _emit(VoiceConnectedEvent());
    if (mode == VoiceConversationMode.live) unawaited(_playRemaining());
  }

  @override
  Future<void> switchMode(VoiceConversationMode next) async {
    if (next == mode) return;
    mode = next;
    _generation++;
    _emit(VoiceConnectingEvent('Demo switched to ${next.name}'));
    _emit(VoiceConnectedEvent());
    if (next == VoiceConversationMode.live) unawaited(_playRemaining());
  }

  Future<void> _playRemaining() async {
    if (_playing) return;
    _playing = true;
    final generation = _generation;
    try {
      while (_nextTurn < _turns.length) {
        if (!await _pause(_turnGap, generation)) return;
        await _playTurn(_turns[_nextTurn++], generation);
      }
    } finally {
      _playing = false;
    }
  }

  Future<void> _playTurn(DemoTurn turn, int generation) async {
    for (final word in _words(turn.user)) {
      if (!await _pause(_userWordDelay, generation)) return;
      _emit(VoiceUserTranscriptDelta(word));
    }
    if (!await _pause(_thinkingDelay, generation)) return;
    final results = <Map<String, dynamic>>[];
    for (final call in turn.tools) {
      final id = 'demo-${++_toolCalls}';
      _emit(VoiceToolCallEvent(id: id, name: call.name, args: call.args));
      final result = await _executors.execute(call.name, call.args);
      if (!await _pause(_toolDelay, generation)) return;
      _emit(VoiceToolResultEvent(id: id, name: call.name, result: result));
      results.add(result);
    }
    for (final word in _words(turn.reply(results))) {
      if (!await _pause(_agentWordDelay, generation)) return;
      _emit(VoiceAgentTranscriptDelta(word));
    }
    _emit(VoiceAgentTurnComplete());
  }

  Future<bool> _pause(Duration duration, int generation) async {
    await Future<void>.delayed(duration);
    return _active &&
        generation == _generation &&
        mode == VoiceConversationMode.live;
  }

  Iterable<String> _words(String text) sync* {
    final words = text.split(' ');
    for (var i = 0; i < words.length; i++) {
      yield i == 0 ? words[i] : ' ${words[i]}';
    }
  }

  void _emit(VoiceEvent event) {
    if (_events.isClosed) return;
    _history.add(event);
    _events.add(event);
  }

  @override
  Future<void> ensureConnected() async {}

  @override
  Future<void> prepareAudio() async {
    if (!_active) return;
    await _audioPlayer.start(sampleRate: LiveProtocol.outputRate);
  }

  @override
  Future<void> addAudioChunk(Uint8List chunk) async {}

  @override
  Future<void> endTurn() async {}

  @override
  void discardTurn() {}

  @override
  bool get isNoteFull => false;

  @override
  Future<void> sendText(String text) async {}

  @override
  void setAudioPlaybackEnabled(bool enabled) {}

  @override
  void recordClientEvent(
    String action, [
    Map<String, Object?> details = const {},
  ]) {}

  @override
  Future<void> interruptAgentResponse({required String reason}) async {}

  @override
  Future<VoiceExpenseCommandResult> stop() async {
    _active = false;
    _generation++;
    _emit(VoiceDisconnectedEvent());
    await _audioPlayer.stop();
    return const VoiceExpenseCommandResult(message: 'Demo session ended');
  }

  @override
  Future<void> dispose() async {
    _active = false;
    _generation++;
    await _audioPlayer.stop();
    await _events.close();
  }
}
