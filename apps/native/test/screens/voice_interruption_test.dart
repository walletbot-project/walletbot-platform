import 'dart:async';
import 'dart:typed_data';

import 'package:app/l10n/l10n.dart';
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
    await tester.pumpWidget(_voiceApp(command));

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
      await tester.pumpWidget(_voiceApp(command));

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

  testWidgets('active reconnect is visible immediately when screen attaches', (
    tester,
  ) async {
    final command = _ActiveVoiceCommand(connected: false);
    await tester.pumpWidget(_voiceApp(command));

    expect(find.text('connecting'), findsOneWidget);
    expect(
      find.text('Connection lost. Reconnecting automatically…'),
      findsOneWidget,
    );

    await tester.pumpWidget(_voiceApp(command, locale: const Locale('es')));
    await tester.pump();

    expect(find.text('conectando'), findsOneWidget);
    expect(
      find.text('Se perdió la conexión. Reconectando automáticamente…'),
      findsOneWidget,
    );
  });

  testWidgets('voice input restores audio playback after a typed turn', (
    tester,
  ) async {
    final command = _ActiveVoiceCommand();
    await tester.pumpWidget(_voiceApp(command));

    await tester.enterText(find.byType(TextField), 'typed message');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(command.audioPlaybackStates, [false]);

    command.emit(VoiceUserTranscriptDelta('voice message'));
    await tester.pump();
    expect(command.audioPlaybackStates, [false, true]);
  });

  testWidgets('incoming events do not pull the user away from chat history', (
    tester,
  ) async {
    final command = _ActiveVoiceCommand();
    await tester.pumpWidget(_voiceApp(command));

    for (var i = 0; i < 24; i++) {
      command.emit(
        VoiceAgentTranscriptDelta(
          'Response $i with enough detail to make the conversation scroll.',
        ),
      );
      command.emit(VoiceAgentTurnComplete());
    }
    await tester.pump();
    command.emit(VoiceAgentTranscriptDelta('Latest response.'));
    command.emit(VoiceAgentTurnComplete());
    await tester.pumpAndSettle();

    final listFinder = find.byType(ListView);
    final controller = tester.widget<ListView>(listFinder).controller!;
    expect(controller.position.maxScrollExtent, greaterThan(0));
    await tester.drag(listFinder, const Offset(0, -10000));
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(controller.position.maxScrollExtent, 1));

    await tester.drag(listFinder, const Offset(0, 40));
    await tester.pumpAndSettle();
    final historyOffset = controller.offset;
    expect(historyOffset, lessThan(controller.position.maxScrollExtent));

    command.emit(VoiceUsageMetadataEvent(const {'totalTokenCount': 42}));
    command.emit(VoiceClientActionEvent('background_heartbeat'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.offset, closeTo(historyOffset, 1));

    command.emit(VoiceAgentTranscriptDelta('A new response arrived.'));
    command.emit(VoiceAgentTurnComplete());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(controller.offset, closeTo(historyOffset, 1));

    await tester.drag(listFinder, const Offset(0, -10000));
    await tester.pumpAndSettle();
    command.emit(VoiceAgentTranscriptDelta('Following live messages again.'));
    command.emit(VoiceAgentTurnComplete());
    await tester.pumpAndSettle();

    expect(controller.offset, closeTo(controller.position.maxScrollExtent, 1));
  });
}

Widget _voiceApp(
  _ActiveVoiceCommand command, {
  Locale locale = const Locale('en'),
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: VoiceScreen(commandFactory: _ActiveVoiceCommandFactory(command)),
);

class _ActiveVoiceCommandFactory implements VoiceExpenseCommandFactory {
  _ActiveVoiceCommandFactory(this.command);
  final _ActiveVoiceCommand command;

  @override
  VoiceExpenseCommand? get activeCommand => command;

  @override
  VoiceExpenseCommand create() => command;

  @override
  void prefetchToken() {}

  @override
  Future<List<VoiceEvent>> restorableHistory() async => const [];

  @override
  Future<void> discardRestorableSession() async {}
}

class _ActiveVoiceCommand implements VoiceExpenseCommand {
  _ActiveVoiceCommand({this.connected = true});

  final _events = StreamController<VoiceEvent>.broadcast();
  final List<String> interruptionReasons = [];
  final List<String> clientActions = [];
  final List<bool> audioPlaybackStates = [];
  final bool connected;
  bool audioStreamEnded = false;
  int ensureConnectedCalls = 0;

  @override
  Stream<VoiceEvent> get events => _events.stream;

  @override
  List<VoiceEvent> get history => const [];

  void emit(VoiceEvent event) => _events.add(event);

  @override
  bool get isActive => true;

  @override
  bool get isConnected => connected;

  @override
  Future<void> ensureConnected() async {
    ensureConnectedCalls += 1;
  }

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
  void setAudioPlaybackEnabled(bool enabled) {
    audioPlaybackStates.add(enabled);
  }

  @override
  Future<void> start({bool respondWithAudio = true}) async {}

  @override
  Future<VoiceExpenseCommandResult> stop() async =>
      const VoiceExpenseCommandResult(message: 'stopped');
}
