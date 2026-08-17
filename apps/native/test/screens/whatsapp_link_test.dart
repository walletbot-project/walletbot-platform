import 'dart:async';
import 'dart:convert';

import 'package:app/l10n/l10n.dart';
import 'package:app/screens/whatsapp_link.dart';
import 'package:app/whatsapp/whatsapp_link_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubApi implements WhatsappLinkApi {
  _StubApi({this.status, this.code, this.queryError});

  final Map<String, Object?>? status;
  final Map<String, Object?>? code;
  final Object? queryError;

  int mutationCalls = 0;
  int queryCalls = 0;

  @override
  Future<String> query(String name, Map<String, dynamic> args) async {
    queryCalls += 1;
    if (queryError != null) throw queryError!;
    return jsonEncode(status ?? const {});
  }

  @override
  Future<String> mutation({
    required String name,
    required Map<String, dynamic> args,
  }) async {
    mutationCalls += 1;
    return jsonEncode(code ?? const {});
  }
}

/// Never completes, so the loading state stays observable.
class _HangingApi implements WhatsappLinkApi {
  @override
  Future<String> query(String name, Map<String, dynamic> args) =>
      Completer<String>().future;

  @override
  Future<String> mutation({
    required String name,
    required Map<String, dynamic> args,
  }) => Completer<String>().future;
}

Widget _app({required bool isRemote, WhatsappLinkApi? api}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: WhatsappLinkScreen(isRemote: isRemote, api: api),
);

Map<String, Object?> _status({
  bool available = true,
  List<Map<String, Object?>> numbers = const [],
}) => {
  'available': available,
  'businessNumber': '5491123991858',
  'numbers': numbers,
};

void main() {
  testWidgets('a local account is told why it cannot link', (tester) async {
    final api = _StubApi(status: _status());
    await tester.pumpWidget(_app(isRemote: false, api: api));
    await tester.pumpAndSettle();

    expect(find.text('Not available for local accounts'), findsOne);
    expect(find.text('Connect WhatsApp'), findsNothing);
    // The gate is real, not just visual: no backend call was made.
    expect(api.queryCalls, 0);
  });

  testWidgets('shows a spinner while loading', (tester) async {
    await tester.pumpWidget(_app(isRemote: true, api: _HangingApi()));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOne);
  });

  testWidgets('a failed load offers a retry that reloads', (tester) async {
    final api = _StubApi(queryError: StateError('offline'));
    await tester.pumpWidget(_app(isRemote: true, api: api));
    await tester.pumpAndSettle();

    expect(find.text('Could not load your WhatsApp status'), findsOne);
    expect(find.text('Tap to try again'), findsOne);
    expect(api.queryCalls, 1);

    await tester.tap(find.text('Tap to try again'));
    await tester.pumpAndSettle();

    expect(api.queryCalls, 2);
  });

  testWidgets('an unlinked account is offered the connect button', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(isRemote: true, api: _StubApi(status: _status())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Not connected'), findsOne);
    expect(find.text('Connect WhatsApp'), findsOne);
    expect(find.text('Disconnect'), findsNothing);
  });

  testWidgets('tapping connect shows the code and the WhatsApp button', (
    tester,
  ) async {
    final api = _StubApi(
      status: _status(),
      code: {
        'code': 'A1B2-C3D4',
        'expiresAt': DateTime.now()
            .add(const Duration(minutes: 10))
            .millisecondsSinceEpoch,
        'deepLink': 'https://wa.me/5491123991858?text=Wallet%20Bot',
      },
    );
    await tester.pumpWidget(_app(isRemote: true, api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Connect WhatsApp'));
    await tester.pumpAndSettle();

    expect(api.mutationCalls, 1);
    expect(find.text('A1B2-C3D4'), findsOne);
    expect(find.text('Your linking code'), findsOne);
    // The user taps this; Wallet Bot never messages first.
    expect(find.text('Open WhatsApp'), findsOne);
    expect(find.text('Copy code'), findsOne);
  });

  testWidgets('a code with no deep link still offers copy', (tester) async {
    final api = _StubApi(
      status: _status(),
      code: {
        'code': 'A1B2-C3D4',
        'expiresAt': DateTime.now()
            .add(const Duration(minutes: 10))
            .millisecondsSinceEpoch,
        'deepLink': null,
      },
    );
    await tester.pumpWidget(_app(isRemote: true, api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Connect WhatsApp'));
    await tester.pumpAndSettle();

    expect(find.text('A1B2-C3D4'), findsOne);
    expect(find.text('Open WhatsApp'), findsNothing);
    expect(find.text('Copy code'), findsOne);
  });

  testWidgets('a failed code request shows a toast and no code', (
    tester,
  ) async {
    // `code: null` makes the mutation return `{}`, which the controller
    // rejects as unusable.
    final api = _StubApi(status: _status());
    await tester.pumpWidget(_app(isRemote: true, api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Connect WhatsApp'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Could not create a linking code'), findsOne);
    expect(find.text('Your linking code'), findsNothing);
  });

  testWidgets('a linked number is listed with a disconnect action', (
    tester,
  ) async {
    final api = _StubApi(
      status: _status(
        numbers: [
          {
            'waId': '5491123991858',
            'linkedAt': DateTime.utc(2026, 8, 17).millisecondsSinceEpoch,
          },
        ],
      ),
    );
    await tester.pumpWidget(_app(isRemote: true, api: api));
    await tester.pumpAndSettle();

    expect(find.text('Connected'), findsOne);
    expect(find.text('+5491123991858'), findsOne);
    expect(find.text('Disconnect'), findsOne);
    expect(find.text('Connect WhatsApp'), findsNothing);
  });

  testWidgets('disconnecting asks for confirmation first', (tester) async {
    final api = _StubApi(
      status: _status(
        numbers: [
          {'waId': '5491123991858'},
        ],
      ),
    );
    await tester.pumpWidget(_app(isRemote: true, api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOne);
    // Cancelling must not call the backend — unlinking is destructive.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(api.mutationCalls, 0);
    expect(find.text('+5491123991858'), findsOne);
  });

  testWidgets('confirming the disconnect calls the backend', (tester) async {
    final api = _StubApi(
      status: _status(
        numbers: [
          {'waId': '5491123991858'},
        ],
      ),
    );
    await tester.pumpWidget(_app(isRemote: true, api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    // 'Disconnect' appears three times now: the row button, the dialog title,
    // and the dialog's confirm action. Target the action.
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Disconnect'),
      ),
    );
    await tester.pumpAndSettle();

    expect(api.mutationCalls, 1);
  });

  testWidgets('a deployment with no business number says so', (tester) async {
    final api = _StubApi(status: _status(available: false));
    await tester.pumpWidget(_app(isRemote: true, api: api));
    await tester.pumpAndSettle();

    expect(find.text('Not available yet'), findsOne);
    expect(find.text('Connect WhatsApp'), findsNothing);
  });

  testWidgets('renders in Spanish', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: WhatsappLinkScreen(
          isRemote: true,
          api: _StubApi(status: _status()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sin conectar'), findsOne);
    expect(find.text('Conectar WhatsApp'), findsOne);
  });
}
