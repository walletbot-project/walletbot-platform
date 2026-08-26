import 'package:app/app_config/client_info.dart';
import 'package:app/components/voice/report_response_sheet.dart';
import 'package:app/l10n/l10n.dart';
import 'package:app/voice/agent_report_submitter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _clientInfo = ClientInfo(
  platform: 'android',
  appVersion: '0.3.1',
  deviceId: 'device-1',
);

/// Pumps the sheet on a modal route over a [Scaffold], the way the app shows
/// it. The scaffold matters: it is where a snackbar would land, underneath this
/// route, which is why a rejection has to be reported inside the sheet instead.
Future<void> _pumpSheet(
  WidgetTester tester, {
  required AgentReportSubmitter submitter,
  String? reportedText = 'something the agent said',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showModalBottomSheet<bool>(
              context: context,
              isScrollControlled: true,
              builder: (_) => ReportResponseSheet(
                submitter: submitter,
                locale: 'en',
                reportedText: reportedText,
                sessionId: 'session-1',
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// The sheet is taller than the 800x600 test viewport, so the actions sit below
/// the fold — scroll them into reach the way a user would.
Future<void> _tapSend(WidgetTester tester) async {
  final send = find.widgetWithText(FilledButton, 'Send report');
  await tester.ensureVisible(send);
  await tester.pumpAndSettle();
  await tester.tap(send);
  await tester.pumpAndSettle();
}

AgentReportSubmitter _submitterAnswering(String response) =>
    AgentReportSubmitter(
      clientInfo: _clientInfo,
      mutation: ({required name, required args}) async => response,
    );

void main() {
  testWidgets('shows the flagged text, so the report is not sent blind', (
    tester,
  ) async {
    await _pumpSheet(tester, submitter: _submitterAnswering('{"ok":true}'));

    expect(find.text('something the agent said'), findsOneWidget);
    expect(find.text('Reported response'), findsOneWidget);
  });

  testWidgets('cannot send until a reason is picked', (tester) async {
    await _pumpSheet(tester, submitter: _submitterAnswering('{"ok":true}'));

    final send = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Send report'),
    );
    expect(send.onPressed, isNull);

    await tester.tap(find.text('Sexual content'));
    await tester.pumpAndSettle();

    final enabled = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Send report'),
    );
    expect(enabled.onPressed, isNotNull);
  });

  testWidgets('a refused send is explained inside the sheet', (tester) async {
    await _pumpSheet(
      tester,
      submitter: _submitterAnswering('{"ok":false,"error":"rate_limited"}'),
    );

    await tester.tap(find.text('Something else'));
    await tester.pumpAndSettle();
    await _tapSend(tester);

    // The sheet stays open with the reason intact, and says why.
    expect(
      find.text('You have sent several reports already. Try again later.'),
      findsOneWidget,
    );
    expect(find.text('Send report'), findsOneWidget);
  });

  testWidgets('an accepted report closes the sheet and reports true', (
    tester,
  ) async {
    await _pumpSheet(tester, submitter: _submitterAnswering('{"ok":true}'));

    await tester.tap(find.text('Dangerous or illegal'));
    await tester.pumpAndSettle();
    await _tapSend(tester);

    expect(find.text('Send report'), findsNothing);
    expect(find.text('Thank you. We will review this response'), findsOneWidget);
  });

  testWidgets('with no flagged text it reports the session instead', (
    tester,
  ) async {
    await _pumpSheet(
      tester,
      submitter: _submitterAnswering('{"ok":true}'),
      reportedText: null,
    );

    expect(find.text('Reported response'), findsNothing);
    expect(
      find.text(
        'This sends the conversation from this session, without the audio.',
      ),
      findsOneWidget,
    );
  });
}
