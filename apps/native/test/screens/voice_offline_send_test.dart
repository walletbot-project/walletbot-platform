import 'dart:async';

import 'package:app/l10n/l10n.dart';
import 'package:app/screens/voice.dart';
import 'package:app/voice/voice_event.dart';
import 'package:app/voice/voice_expense_command.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('texts sent while disconnected all flush in order on reconnect', (
    tester,
  ) async {
    final command = _RecordingCommand(active: true);
    final factory = _RecordingFactory(command);
    await tester.pumpWidget(_voiceApp(factory));

    await _sendText(tester, 'hola');
    await _sendText(tester, 'kek');
    await _sendText(tester, 'hey');

    expect(command.sentTexts, isEmpty);
    expect(find.text('hola'), findsOneWidget);
    expect(find.text('kek'), findsOneWidget);
    expect(find.text('hey'), findsOneWidget);

    command.emit(VoiceConnectedEvent());
    await tester.pump();

    expect(command.sentTexts, ['hola', 'kek', 'hey']);
    expect(find.text('hola'), findsOneWidget);
    expect(find.text('kek'), findsOneWidget);
    expect(find.text('hey'), findsOneWidget);
    expect(factory.discardCalls, 0);
  });

  testWidgets(
    'a failed start keeps the conversation and queued text, without raw errors',
    (tester) async {
      final command = _RecordingCommand(active: false, failStarts: true);
      final factory = _RecordingFactory(command);
      await tester.pumpWidget(_voiceApp(factory));
      await tester.pump();

      await _sendText(tester, 'first message');
      await tester.pump();

      expect(
        find.text("Couldn't start the conversation. Please try again."),
        findsOneWidget,
      );
      expect(find.text('first message'), findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
      expect(find.textContaining('StateError'), findsNothing);
      expect(factory.discardCalls, 0);

      command.failStarts = false;
      await _sendText(tester, 'second message');
      command.emit(VoiceConnectedEvent());
      await tester.pump();

      expect(command.sentTexts, ['first message', 'second message']);
      expect(find.text('first message'), findsOneWidget);
      expect(find.text('second message'), findsOneWidget);
      expect(factory.discardCalls, 0);
    },
  );
}

Future<void> _sendText(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pump();
}

Widget _voiceApp(_RecordingFactory factory) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: VoiceScreen(commandFactory: factory),
);

class _RecordingFactory implements VoiceExpenseCommandFactory {
  _RecordingFactory(this.command);
  final _RecordingCommand command;
  int discardCalls = 0;

  @override
  VoiceExpenseCommand? get activeCommand => command.isActive ? command : null;

  @override
  VoiceExpenseCommand create() => command;

  @override
  void prefetchToken() {}

  @override
  Future<List<VoiceEvent>> restorableHistory() async => const [];

  @override
  Future<void> discardRestorableSession() async {
    discardCalls += 1;
  }

  @override
  Future<String?> restorableSessionId() async => 'test-session';
}

class _RecordingCommand implements VoiceExpenseCommand {
  _RecordingCommand({required bool active, this.failStarts = false})
    : _active = active;

  final _events = StreamController<VoiceEvent>.broadcast();
  final List<String> sentTexts = [];
  bool failStarts;
  bool _active;

  void emit(VoiceEvent event) => _events.add(event);

  @override
  String? get sessionId => 'test-session';

  @override
  Stream<VoiceEvent> get events => _events.stream;

  @override
  List<VoiceEvent> get history => const [];

  @override
  bool get isActive => _active;

  @override
  bool get isConnected => false;

  @override
  String get label => 'test';

  @override
  Future<void> start({bool respondWithAudio = true}) async {
    if (failStarts) throw StateError('injected start failure');
    _active = true;
  }

  @override
  Future<void> ensureConnected() async {}

  @override
  Future<void> addAudioChunk(Uint8List chunk) async {}

  @override
  Future<void> endAudioStream() async {}

  @override
  Future<void> sendText(String text) async {
    sentTexts.add(text);
  }

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
    return const VoiceExpenseCommandResult(message: 'stopped');
  }

  @override
  Future<void> dispose() async {}
}
