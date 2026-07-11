import 'dart:typed_data';

import 'package:app/screens/voice.dart';
import 'package:app/voice/voice_event.dart';
import 'package:app/voice/voice_expense_command.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('leaving voice screen interrupts the current agent response', (
    tester,
  ) async {
    final command = _ActiveVoiceCommand();
    await tester.pumpWidget(
      MaterialApp(
        home: VoiceScreen(commandFactory: _ActiveVoiceCommandFactory(command)),
      ),
    );

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();

    expect(command.interruptionReasons, ['screen_detached']);
    expect(command.clientActions, contains('screen_detached'));
    expect(command.audioStreamEnded, isTrue);
  });
}

class _ActiveVoiceCommandFactory implements VoiceExpenseCommandFactory {
  _ActiveVoiceCommandFactory(this.command);
  final _ActiveVoiceCommand command;

  @override
  VoiceExpenseCommand? get activeCommand => command;

  @override
  VoiceExpenseCommand create() => command;
}

class _ActiveVoiceCommand implements VoiceExpenseCommand {
  final List<String> interruptionReasons = [];
  final List<String> clientActions = [];
  bool audioStreamEnded = false;

  @override
  Stream<VoiceEvent> get events => const Stream.empty();

  @override
  bool get isActive => true;

  @override
  bool get isConnected => true;

  @override
  String get label => 'test';

  @override
  Future<void> addAudioChunk(Uint8List chunk) async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> endAudioStream() async {
    audioStreamEnded = true;
  }

  @override
  Future<void> interruptAgentResponse({required String reason}) async {
    interruptionReasons.add(reason);
  }

  @override
  void recordClientEvent(
    String action, [
    Map<String, Object?> details = const {},
  ]) {
    clientActions.add(action);
  }

  @override
  Future<void> sendText(String text) async {}

  @override
  void setAudioPlaybackEnabled(bool enabled) {}

  @override
  Future<void> start({bool respondWithAudio = true}) async {}

  @override
  Future<VoiceExpenseCommandResult> stop() async =>
      const VoiceExpenseCommandResult(message: 'stopped');
}
