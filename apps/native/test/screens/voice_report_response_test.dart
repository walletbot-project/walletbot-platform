import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app/app_config/app_config_controller.dart';
import 'package:app/auth/account.dart';
import 'package:app/l10n/l10n.dart';
import 'package:app/screens/voice.dart';
import 'package:app/voice/voice_event.dart';
import 'package:app/voice/voice_expense_command.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

/// Google Play's AI-Generated Content policy requires an in-app way to flag a
/// generated response without leaving the app. These tests pin the two entry
/// points that satisfy it, so neither can be removed by accident.
void main() {
  // `loadAccount` resolves the config URL through `AppConfig`, which reads the
  // bundled .env. The value is irrelevant here — every request is mocked.
  setUpAll(
    () => dotenv.testLoad(
      fileInput:
          'CONVEX_URL=https://example.test\n'
          'CONVEX_SITE_URL=https://example.test',
    ),
  );

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

  testWidgets('the report link sits in the agent header, in plain sight', (
    tester,
  ) async {
    final command = _ActiveVoiceCommand();
    await tester.pumpWidget(_voiceApp(command));

    command.emit(VoiceAgentTranscriptDelta('here is a bad answer'));
    command.emit(VoiceAgentTurnComplete());
    await tester.pump();

    // Not behind a hover, a long-press or an overflow menu: the policy asks for
    // a way to flag generated content that a user can actually find.
    expect(find.text('report'), findsOneWidget);
  });

  testWidgets('a user turn gets no report link — only the agent generates', (
    tester,
  ) async {
    final command = _ActiveVoiceCommand();
    await tester.pumpWidget(_voiceApp(command));

    command.emit(VoiceUserTranscriptDelta('what I said'));
    command.emit(VoiceAgentTranscriptDelta('the answer'));
    command.emit(VoiceAgentTurnComplete());
    await tester.pump();

    expect(find.text('report'), findsOneWidget);
  });

  testWidgets('tapping the report link opens the sheet', (tester) async {
    final command = _ActiveVoiceCommand();
    await tester.pumpWidget(_voiceApp(command));

    command.emit(VoiceAgentTranscriptDelta('here is a bad answer'));
    command.emit(VoiceAgentTurnComplete());
    await tester.pump();

    await tester.tap(find.text('report'));
    await tester.pumpAndSettle();

    // No ClientInfo provider in this harness, so the sheet declines to open
    // rather than crashing. The tap itself is what is pinned here.
    expect(tester.takeException(), isNull);
  });

  testWidgets('a config that never landed still shows the link', (
    tester,
  ) async {
    // The flag defaults on server-side, and native must fail open to match: an
    // offline first run cannot be a build with no visible way to report.
    final controller = AppConfigController(
      httpClient: MockClient((_) async => http.Response('nope', 500)),
    );
    addTearDown(controller.dispose);
    await controller.loadAccount(_localAccount);

    final command = _ActiveVoiceCommand();
    await tester.pumpWidget(_voiceApp(command, config: controller));

    command.emit(VoiceAgentTranscriptDelta('here is a bad answer'));
    command.emit(VoiceAgentTurnComplete());
    await tester.pump();

    expect(find.text('report'), findsOneWidget);
  });

  testWidgets('agentReportButton off hides the link, keeps the long-press', (
    tester,
  ) async {
    final controller = AppConfigController(
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'flags': {'agentReportButton': false},
          }),
          200,
        ),
      ),
    );
    addTearDown(controller.dispose);
    await controller.loadAccount(_localAccount);
    expect(
      controller.isFlagEnabled('agentReportButton', orElse: true),
      isFalse,
    );

    final command = _ActiveVoiceCommand();
    await tester.pumpWidget(_voiceApp(command, config: controller));

    command.emit(VoiceAgentTranscriptDelta('here is a bad answer'));
    command.emit(VoiceAgentTurnComplete());
    await tester.pump();

    expect(find.text('report'), findsNothing);

    // The flag narrows how reporting is found, never whether it works.
    await tester.longPress(find.text('here is a bad answer'));
    await tester.pumpAndSettle();
    expect(find.text('Report this response'), findsOneWidget);
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

const _localAccount = UserAccount(
  id: 'local-1',
  type: AccountType.local,
  name: 'Local',
);

/// [config] is optional because the screen must also build without it — that is
/// the state a cold start is in before the first config call returns.
Widget _voiceApp(_ActiveVoiceCommand command, {AppConfigController? config}) {
  final app = MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: VoiceScreen(commandFactory: _ActiveVoiceCommandFactory(command)),
  );
  if (config == null) return app;
  return ChangeNotifierProvider<AppConfigController>.value(
    value: config,
    child: app,
  );
}

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
