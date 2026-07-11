import 'dart:async';
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

  testWidgets(
    'repeated transient connection errors render as one friendly notice',
    (tester) async {
      final command = _ActiveVoiceCommand();
      await tester.pumpWidget(
        MaterialApp(
          home: VoiceScreen(
            commandFactory: _ActiveVoiceCommandFactory(command),
          ),
        ),
      );

      command.emit(
        VoiceErrorEvent(
          'WebSocket error: SocketException: Failed host lookup',
          isTransient: true,
        ),
      );
      command.emit(VoiceDisconnectedEvent());
      command.emit(VoiceConnectingEvent('Reconnecting to Gemini Live in 1s'));
      command.emit(
        VoiceErrorEvent(
          'Reconnect failed: Gemini disconnected before setup completed',
          isTransient: true,
        ),
      );
      command.emit(VoiceConnectingEvent('Reconnecting to Gemini Live in 2s'));
      await tester.pump();

      expect(
        find.text('Connection lost. Reconnecting automatically…'),
        findsOneWidget,
      );
      expect(find.textContaining('WebSocket error'), findsNothing);
      expect(find.textContaining('Reconnect failed'), findsNothing);
      expect(find.text('connecting'), findsOneWidget);

      command.emit(VoiceConnectedEvent());
      await tester.pump();

      expect(
        find.text('Connection lost. Reconnecting automatically…'),
        findsNothing,
      );
    },
  );
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
  final _events = StreamController<VoiceEvent>.broadcast();
  final List<String> interruptionReasons = [];
  final List<String> clientActions = [];
  bool audioStreamEnded = false;

  @override
  Stream<VoiceEvent> get events => _events.stream;

  void emit(VoiceEvent event) => _events.add(event);

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
