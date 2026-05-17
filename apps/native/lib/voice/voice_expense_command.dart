import 'dart:async';
import 'dart:typed_data';

import 'voice_event.dart';

abstract interface class VoiceExpenseCommandFactory {
  VoiceExpenseCommand create();
}

abstract interface class VoiceExpenseCommand {
  String get label;

  Stream<VoiceEvent> get events;

  Future<void> start();

  Future<void> addAudioChunk(Uint8List chunk);

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
  VoiceExpenseCommand create() => DebugVoiceExpenseCommand();
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
  Future<void> start() async {
    _chunks = 0;
    _bytes = 0;
    _events.add(VoiceConnectingEvent('Debug command started'));
    _events.add(VoiceConnectedEvent());
  }

  @override
  Future<void> addAudioChunk(Uint8List chunk) async {
    _chunks += 1;
    _bytes += chunk.length;
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
