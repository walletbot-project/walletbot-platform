import 'dart:convert';

import 'package:app/app_config/client_info.dart';
import 'package:app/components/feedback/feedback_sheet.dart';
import 'package:app/convex/convex_client.dart';
import 'package:app/feedback/feedback_submitter.dart';
import 'package:app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _clientInfo = ClientInfo(
  platform: 'android',
  appVersion: '0.2.0',
  deviceId: 'device-1',
);

/// Pumps the sheet on a modal route over a [Scaffold], the way the app shows
/// it. The scaffold matters: it is where a snackbar would land, underneath this
/// route, which is how every rejection used to end up invisible.
Future<void> _pumpSheet(
  WidgetTester tester, {
  required FeedbackSubmitter submitter,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => FeedbackSheet(
                submitter: submitter,
                clientInfo: _clientInfo,
                locale: 'en',
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

FeedbackSubmitter _submitterAnswering(String response) => FeedbackSubmitter(
  clientInfo: _clientInfo,
  mutation: (name, args) async => jsonDecode(response),
);

void main() {
  testWidgets('a refused send is explained inside the sheet', (tester) async {
    await _pumpSheet(
      tester,
      submitter: _submitterAnswering('{"ok":false,"error":"rate_limited"}'),
    );

    await tester.enterText(find.byType(TextField), 'the totals are wrong');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pumpAndSettle();

    const rateLimited =
        'You have sent several messages already. Try again later.';
    // Inside the sheet's own subtree, not in a snackbar the sheet covers.
    expect(
      find.descendant(
        of: find.byType(FeedbackSheet),
        matching: find.text(rateLimited),
      ),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);

    // And the sheet is still open with the text intact, so a retry costs
    // nothing.
    expect(find.text('Send feedback'), findsOneWidget);
    expect(find.text('the totals are wrong'), findsOneWidget);
  });

  testWidgets('an offline send names the connection, not a generic failure', (
    tester,
  ) async {
    await _pumpSheet(
      tester,
      submitter: FeedbackSubmitter(
        clientInfo: _clientInfo,
        // Airplane mode: the Convex client waits on a socket that never opens,
        // then gives up on its own `operationTimeout` with this exception.
        mutation: (name, args) => Future.error(
          OperationTimeoutError(
            functionName: name,
            phase: TimeoutPhase.operation,
            timeout: const Duration(seconds: 30),
            connectionStatus: ConnectionStatus.connecting,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'no wifi');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(FeedbackSheet),
        matching: find.text(
          'No connection. Check your internet and try again, '
          'or write to us by email.',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('send is disabled until the message has text', (tester) async {
    await _pumpSheet(tester, submitter: _submitterAnswering('{"ok":true}'));

    FilledButton sendButton() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Send'));

    expect(sendButton().onPressed, isNull);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(sendButton().onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();
    expect(sendButton().onPressed, isNotNull);
  });

  testWidgets('the email fallback offers the localized support mailbox', (
    tester,
  ) async {
    await _pumpSheet(tester, submitter: _submitterAnswering('{"ok":true}'));

    await tester.tap(find.text('Send an email instead'));
    await tester.pumpAndSettle();

    expect(find.text('Write to support'), findsOneWidget);
    expect(find.text('support@walletbot.live'), findsOneWidget);
  });
}
