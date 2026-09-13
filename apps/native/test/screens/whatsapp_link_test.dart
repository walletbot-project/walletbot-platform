import 'dart:async';

import 'package:app/convex/convex_client.dart';
import 'package:app/l10n/l10n.dart';
import 'package:app/screens/whatsapp_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// `ConvexClient` is a concrete class with a live transport, so tests stub the
/// two calls this screen makes and let `noSuchMethod` swallow the rest — the
/// same shape as `test/settings/language_sync_controller_test.dart`.
class _StubClient implements ConvexClient {
  _StubClient({this.status, this.code, this.queryError});

  final Map<String, Object?>? status;
  final Map<String, Object?>? code;
  final Object? queryError;

  int mutationCalls = 0;
  int queryCalls = 0;

  @override
  Future<T> query<T>(
    String name,
    Map<String, Object?> args, {
    CallOptions? options,
  }) async {
    queryCalls += 1;
    if (queryError != null) throw queryError!;
    return (status ?? const <String, Object?>{}) as T;
  }

  @override
  Future<T> mutation<T>(
    String name,
    Map<String, Object?> args, {
    CallOptions? options,
  }) async {
    mutationCalls += 1;
    return (code ?? const <String, Object?>{}) as T;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Never completes, so the loading state stays observable.
class _HangingClient implements ConvexClient {
  @override
  Future<T> query<T>(
    String name,
    Map<String, Object?> args, {
    CallOptions? options,
  }) => Completer<T>().future;

  @override
  Future<T> mutation<T>(
    String name,
    Map<String, Object?> args, {
    CallOptions? options,
  }) => Completer<T>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app({required bool isRemote, ConvexClient? client}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: WhatsappLinkScreen(isRemote: isRemote, client: client),
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
    final client = _StubClient(status: _status());
    await tester.pumpWidget(_app(isRemote: false, client: client));
    await tester.pumpAndSettle();

    expect(find.text('Not available for local accounts'), findsOne);
    expect(find.text('Connect WhatsApp'), findsNothing);
    // The gate is real, not just visual: no backend call was made.
    expect(client.queryCalls, 0);
  });

  testWidgets('shows a spinner while loading', (tester) async {
    await tester.pumpWidget(_app(isRemote: true, client: _HangingClient()));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOne);
  });

  testWidgets('a failed load offers a retry that reloads', (tester) async {
    final client = _StubClient(queryError: StateError('offline'));
    await tester.pumpWidget(_app(isRemote: true, client: client));
    await tester.pumpAndSettle();

    expect(find.text('Could not load your WhatsApp status'), findsOne);
    expect(find.text('Tap to try again'), findsOne);
    expect(client.queryCalls, 1);

    await tester.tap(find.text('Tap to try again'));
    await tester.pumpAndSettle();

    expect(client.queryCalls, 2);
  });

  testWidgets('an unlinked account is offered the connect button', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(isRemote: true, client: _StubClient(status: _status())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Not connected'), findsOne);
    expect(find.text('Connect WhatsApp'), findsOne);
    expect(find.text('Disconnect'), findsNothing);
  });

  testWidgets('tapping connect shows the code and the WhatsApp button', (
    tester,
  ) async {
    final client = _StubClient(
      status: _status(),
      code: {
        'code': 'A1B2-C3D4',
        'expiresAt': DateTime.now()
            .add(const Duration(minutes: 10))
            .millisecondsSinceEpoch,
        'deepLink': 'https://wa.me/5491123991858?text=Wallet%20Bot',
      },
    );
    await tester.pumpWidget(_app(isRemote: true, client: client));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Connect WhatsApp'));
    await tester.pumpAndSettle();

    expect(client.mutationCalls, 1);
    expect(find.text('A1B2-C3D4'), findsOne);
    expect(find.text('Your linking code'), findsOne);
    // The user taps this; Wallet Bot never messages first.
    expect(find.text('Open WhatsApp'), findsOne);
    expect(find.text('Copy code'), findsOne);
  });

  testWidgets('a code with no deep link still offers copy', (tester) async {
    final client = _StubClient(
      status: _status(),
      code: {
        'code': 'A1B2-C3D4',
        'expiresAt': DateTime.now()
            .add(const Duration(minutes: 10))
            .millisecondsSinceEpoch,
        'deepLink': null,
      },
    );
    await tester.pumpWidget(_app(isRemote: true, client: client));
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
    final client = _StubClient(status: _status());
    await tester.pumpWidget(_app(isRemote: true, client: client));
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
    final client = _StubClient(
      status: _status(
        numbers: [
          {
            'waId': '5491123991858',
            'linkedAt': DateTime.utc(2026, 8, 17).millisecondsSinceEpoch,
          },
        ],
      ),
    );
    await tester.pumpWidget(_app(isRemote: true, client: client));
    await tester.pumpAndSettle();

    expect(find.text('Connected'), findsOne);
    expect(find.text('+5491123991858'), findsOne);
    expect(find.text('Disconnect'), findsOne);
    expect(find.text('Connect WhatsApp'), findsNothing);
  });

  testWidgets('disconnecting asks for confirmation first', (tester) async {
    final client = _StubClient(
      status: _status(
        numbers: [
          {'waId': '5491123991858'},
        ],
      ),
    );
    await tester.pumpWidget(_app(isRemote: true, client: client));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOne);
    // Cancelling must not call the backend — unlinking is destructive.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(client.mutationCalls, 0);
    expect(find.text('+5491123991858'), findsOne);
  });

  testWidgets('confirming the disconnect calls the backend', (tester) async {
    final client = _StubClient(
      status: _status(
        numbers: [
          {'waId': '5491123991858'},
        ],
      ),
    );
    await tester.pumpWidget(_app(isRemote: true, client: client));
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

    expect(client.mutationCalls, 1);
  });

  testWidgets('a deployment with no business number says so', (tester) async {
    final client = _StubClient(status: _status(available: false));
    await tester.pumpWidget(_app(isRemote: true, client: client));
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
          client: _StubClient(status: _status()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sin conectar'), findsOne);
    expect(find.text('Conectar WhatsApp'), findsOne);
  });
}
