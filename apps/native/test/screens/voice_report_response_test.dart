import 'dart:async';
import 'dart:typed_data';

import 'package:app/l10n/l10n.dart';
import 'package:app/screens/voice.dart';
import 'package:app/voice/voice_event.dart';
import 'package:app/voice/voice_expense_command.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Google Play's AI-Generated Content policy requires an in-app way to flag a
/// generated response without leaving the app. These tests pin the two entry
/// points that satisfy it, so neither can be removed by accident.
void main() {
  testWidgets('long-pressing an agent bubble offers to report it', (
    tester,
  ) async {
    final command = _ActiveVoiceCommand();
    await tester.pumpWidget(_voiceApp(command));

    command.emit(VoiceAgentTranscriptDelta('here is a bad answer'));
    // Finalised, so the bubble stops rendering its animated dots — an
    // indefinite animation never lets `pumpAndSettle` return.
    command.emit(VoiceAgentTurnComplete());
    await tester.pump();
    expect(find.text('here is a bad answer'), findsOneWidget);

    await tester.longPress(find.text('here is a bad answer'));
    await tester.pumpAndSettle();

    expect(find.text('Report this response'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
  });

  testWidgets('the app bar always carries the fallback report action', (
    tester,
  ) async {
    final command = _ActiveVoiceCommand();
    await tester.pumpWidget(_voiceApp(command));

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('Report a response'), findsOneWidget);
  });

  testWidgets('the session fallback says so when nothing has been said yet', (
    tester,
  ) async {
    final command = _ActiveVoiceCommand();
    await tester.pumpWidget(_voiceApp(command));

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report a response'));
    await tester.pumpAndSettle();

    expect(find.text('There is no response to report yet'), findsOneWidget);
  });

  testWidgets('a user turn is not long-pressable — only the agent is', (
    tester,
  ) async {
    final command = _ActiveVoiceCommand();
    await tester.pumpWidget(_voiceApp(command));

    command.emit(VoiceUserTranscriptDelta('what I said'));
    // The agent turn finalises the user bubble; a half-open one keeps an
    // indefinite animation running and `pumpAndSettle` would never return.
    command.emit(VoiceAgentTranscriptDelta('the answer'));
    command.emit(VoiceAgentTurnComplete());
    await tester.pump();

    await tester.longPress(find.text('what I said'));
    await tester.pumpAndSettle();

    expect(find.text('Report this response'), findsNothing);
  });
}

Widget _voiceApp(_ActiveVoiceCommand command) => MaterialApp(
  locale: const Locale('en'),
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

  @override
  Future<String?> restorableSessionId() async => 'test-session';
}

class _ActiveVoiceCommand implements VoiceExpenseCommand {
  final _events = StreamController<VoiceEvent>.broadcast();

  void emit(VoiceEvent event) => _events.add(event);

  @override
  String? get sessionId => 'test-session';

  @override
  Stream<VoiceEvent> get events => _events.stream;

  @override
  List<VoiceEvent> get history => const [];

  @override
  String get label => 'test command';

  @override
  bool get isActive => true;

  @override
  bool get isConnected => true;

  @override
  Future<void> start({bool respondWithAudio = true}) async {}

  @override
  Future<void> ensureConnected() async {}

  @override
  Future<void> addAudioChunk(Uint8List chunk) async {}

  @override
  Future<void> endAudioStream() async {}

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
  Future<VoiceExpenseCommandResult> stop() async =>
      const VoiceExpenseCommandResult(message: 'stopped');

  @override
  Future<void> dispose() async {
    await _events.close();
  }
}
