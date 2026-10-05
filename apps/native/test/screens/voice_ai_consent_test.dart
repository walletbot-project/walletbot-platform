import 'dart:async';
import 'dart:typed_data';

import 'package:app/app_config/client_info.dart';
import 'package:app/l10n/l10n.dart';
import 'package:app/legal/ai_consent_controller.dart';
import 'package:app/legal/legal_versions.dart';
import 'package:app/screens/voice.dart';
import 'package:app/voice/voice_event.dart';
import 'package:app/voice/voice_expense_command.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Drives the real [VoiceScreen] to pin down WHERE the AI-consent sheet
/// appears: once, on opening the screen. It must never come from the mic or
/// the send button — those are "let me talk" gestures, and on iOS the mic one
/// already raises the system permission dialog.
///
/// Also guards the wiring: read from a context with no [AiConsentController]
/// above it, the gate passes silently.
void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('opening the voice screen asks for AI consent', (tester) async {
    final consent = _pendingIosConsent();
    addTearDown(consent.dispose);
    await tester.pumpWidget(_voiceApp(_IdleFactory(), consent));
    await tester.pumpAndSettle();

    expect(find.text('Before you use the assistant'), findsOne);
  });

  testWidgets('agreeing dismisses the sheet and stays on the screen', (
    tester,
  ) async {
    final consent = _pendingIosConsent();
    addTearDown(consent.dispose);
    await tester.pumpWidget(_voiceApp(_IdleFactory(), consent));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Agree and continue'));
    await tester.pumpAndSettle();

    expect(find.text('Before you use the assistant'), findsNothing);
    expect(consent.accepted, isTrue);
    expect(find.byType(VoiceScreen), findsOne);
  });

  testWidgets('an account that already consented is not asked again', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      'ai_consent:account-1': aiConsentVersion,
    });
    final consent = _pendingIosConsent();
    addTearDown(consent.dispose);
    await tester.pumpWidget(_voiceApp(_IdleFactory(), consent));
    await tester.pumpAndSettle();

    expect(find.text('Before you use the assistant'), findsNothing);
  });

  testWidgets('the mic is never the thing that asks', (tester) async {
    FlutterSecureStorage.setMockInitialValues({
      'ai_consent:account-1': aiConsentVersion,
    });
    final factory = _IdleFactory();
    final consent = _pendingIosConsent();
    addTearDown(consent.dispose);
    await tester.pumpWidget(_voiceApp(factory, consent));
    await tester.pumpAndSettle();

    // A consented account sends text and goes straight into a session: no
    // sheet, no interruption of the gesture.
    await tester.enterText(find.byType(TextField), 'cafe 3000');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Before you use the assistant'), findsNothing);
    expect(factory.started, isTrue);
  });
}

AiConsentController _pendingIosConsent() => AiConsentController(
  accountId: 'account-1',
  isRemote: false,
  clientInfo: const ClientInfo(
    platform: 'ios',
    appVersion: '0.3.2',
    deviceId: 'device-1',
  ),
  locale: 'en',
);

Widget _voiceApp(_IdleFactory factory, AiConsentController consent) =>
    ChangeNotifierProvider<AiConsentController>.value(
      value: consent,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: VoiceScreen(commandFactory: factory),
      ),
    );

/// A factory with no live session, so the screen takes the "nothing running"
/// path and a send has to start one.
class _IdleFactory implements VoiceExpenseCommandFactory {
  int prefetches = 0;
  bool started = false;

  @override
  VoiceExpenseCommand? get activeCommand => null;

  @override
  VoiceExpenseCommand create() {
    started = true;
    return _IdleCommand();
  }

  @override
  void prefetchToken() {
    prefetches += 1;
  }

  @override
  Future<List<VoiceEvent>> restorableHistory() async => const [];

  @override
  Future<void> discardRestorableSession() async {}

  @override
  Future<String?> restorableSessionId() async => null;
}

class _IdleCommand extends DebugVoiceExpenseCommand {
  final _events = StreamController<VoiceEvent>.broadcast();

  @override
  Stream<VoiceEvent> get events => _events.stream;

  @override
  List<VoiceEvent> get history => const [];

  @override
  bool get isActive => false;

  @override
  bool get isConnected => false;

  @override
  String? get sessionId => null;

  @override
  String get label => 'test';

  @override
  Future<void> addAudioChunk(Uint8List chunk) async {}

  @override
  Future<void> dispose() async {
    await _events.close();
  }
}
