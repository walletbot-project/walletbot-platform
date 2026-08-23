import 'dart:async';

import 'package:app/auth/account.dart';
import 'package:app/auth/auth_controller.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/screens/account_switcher.dart';
import 'package:app/database.dart';
import 'package:app/user_settings/default_currency_controller.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _ana = UserAccount(id: 'a', type: AccountType.local, name: 'Ana');
const _bruno = UserAccount(id: 'b', type: AccountType.local, name: 'Bruno');
const _rita = UserAccount(
  id: 'r',
  type: AccountType.remote,
  name: 'Rita',
  email: 'rita@example.com',
  sessionToken: 'tok',
);

/// Stands in for [AuthController] so the switcher can be driven without
/// `ConvexClient.initialize()`, which widget tests cannot do (the constraint
/// documented in widget_test.dart). Only the account bookkeeping the switcher
/// reads is overridden; the notification behaviour matches the real one.
class _FakeAuth extends AuthController {
  _FakeAuth(this._accounts, this._activeId);

  List<UserAccount> _accounts;
  String? _activeId;

  @override
  List<UserAccount> get accounts => List.unmodifiable(_accounts);

  @override
  String? get activeId => _activeId;

  @override
  UserAccount? get activeAccount {
    for (final account in _accounts) {
      if (account.id == _activeId) return account;
    }
    return null;
  }

  @override
  Future<void> switchTo(String id) async {
    _activeId = id;
    notifyListeners();
    // The real controller notifies a second time a beat later, when convex
    // auth attaches for the new account (`onAuthChange` in
    // `_attachAuthForActive`). That late notification is the fatal one: by
    // then the previous account's subtree is not merely deactivated but
    // unmounted, so a builder holding its `State.context` throws.
    Timer.run(notifyListeners);
  }

  bool signedOutRemote = false;

  @override
  Future<void> signOutRemote(String id) async {
    signedOutRemote = true;
    _accounts = [
      for (final account in _accounts)
        if (account.id != id) account,
    ];
    if (_activeId == id) _activeId = null;
    notifyListeners();
  }

  @override
  Future<void> deleteLocal(String id) async {
    _accounts = [
      for (final account in _accounts)
        if (account.id != id) account,
    ];
    if (_activeId == id) _activeId = null;
    notifyListeners();
  }
}

/// The shape of `_AuthGate`: the account-scoped subtree is rekeyed per
/// account, so switching unmounts everything below it while any route pushed
/// on the root navigator stays up. [child] is what the gate renders when an
/// account is active.
Widget _gate(AuthController auth, Widget child) {
  return ChangeNotifierProvider<AuthController>.value(
    value: auth,
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Consumer<AuthController>(
        builder: (context, a, _) {
          final active = a.activeAccount;
          if (active == null) {
            return a.accounts.isEmpty
                ? const Scaffold(body: Text('login'))
                : const AccountChooserScreen();
          }
          return KeyedSubtree(key: ObjectKey(active), child: child);
        },
      ),
    ),
  );
}

class _Host extends StatefulWidget {
  const _Host({this.database});

  /// Supplied when a test needs to seed the active account's database;
  /// otherwise the host owns an empty one.
  final AppDatabase? database;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late final AppDatabase _owned =
      widget.database ?? AppDatabase.forTesting(NativeDatabase.memory());

  @override
  void dispose() {
    if (widget.database == null) _owned.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => showAccountSwitcher(
            context,
            defaultCurrency: DefaultCurrencyController(
              accountId: 'a',
              isRemote: false,
            ),
            database: _owned,
          ),
          child: const Text('open'),
        ),
      ),
    );
  }
}

/// The switcher as it was written before this change: a `showDialog` builder
/// closing over the host `State`'s `context`. Kept so the test below proves
/// the harness actually detects the defect it is guarding against.
class _LegacyHost extends StatefulWidget {
  const _LegacyHost();

  @override
  State<_LegacyHost> createState() => _LegacyHostState();
}

class _LegacyHostState extends State<_LegacyHost> {
  void _open() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final auth = dialogContext.watch<AuthController>();
        return Dialog.fullscreen(
          child: Scaffold(
            // `context` here is _LegacyHostState's, not the dialog's.
            appBar: AppBar(
              title: Text(Localizations.localeOf(context).toString()),
            ),
            body: ListView(
              children: [
                for (final account in auth.accounts)
                  ListTile(
                    title: Text(account.name ?? ''),
                    onTap: () => auth.switchTo(account.id),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(onPressed: _open, child: const Text('open')),
      ),
    );
  }
}

void main() {
  testWidgets('groups the current account above the other ones', (
    tester,
  ) async {
    await tester.pumpWidget(
      _gate(_FakeAuth([_ana, _bruno], 'a'), const _Host()),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Current account'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Delete this account'), findsOneWidget);
    expect(find.text('Other accounts'), findsOneWidget);
    expect(find.text('Add account'), findsOneWidget);

    // The active account appears once, in the top group — not as a switch
    // target among the others.
    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('Bruno'), findsOneWidget);
  });

  testWidgets('switching accounts with the switcher open does not throw', (
    tester,
  ) async {
    final auth = _FakeAuth([_ana, _bruno], 'a');
    await tester.pumpWidget(_gate(auth, const _Host()));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Same pump sequence as the pre-fix test below, which is the one that
    // actually reaches the fatal frame: the gate's rebuild deactivates the
    // host, and the notification after it finds the State unmounted.
    // `pumpAndSettle` alone stops short of it and would pass vacuously.
    await tester.tap(find.text('Bruno'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(auth.activeId, 'b');
    // The switcher does not float above a tree it no longer describes.
    expect(find.text('Your accounts'), findsNothing);
  });

  testWidgets('the pre-fix switcher shape throws on that same switch', (
    tester,
  ) async {
    final auth = _FakeAuth([_ana, _bruno], 'a');
    await tester.pumpWidget(_gate(auth, const _LegacyHost()));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The gate's rebuild only *deactivates* the host; the throw comes one
    // notification later, when it is properly unmounted — which is why
    // settling (letting the late notification land) is what reproduces it.
    await tester.tap(find.text('Bruno'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final error = tester.takeException();
    expect(error, isFlutterError);
    expect('$error', contains('unmounted'));
  });

  testWidgets('removing the active account keeps the others reachable', (
    tester,
  ) async {
    final auth = _FakeAuth([_ana, _bruno], 'a');
    await tester.pumpWidget(_gate(auth, const _Host()));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // A local account is not "signed out of": this is the only copy.
    await tester.tap(find.text('Delete this account'));
    await tester.pumpAndSettle();
    expect(find.text('Delete “Ana”?'), findsOneWidget);
    expect(find.textContaining('only exists on this device'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // No active account, but Bruno is still on the device: the chooser is
    // shown instead of the sign-in screen, and picking him gets back in.
    expect(auth.activeAccount, isNull);
    expect(find.text('login'), findsNothing);
    expect(find.text('Bruno'), findsOneWidget);

    await tester.tap(find.text('Bruno'));
    await tester.pumpAndSettle();

    expect(auth.activeId, 'b');
    expect(find.text('open'), findsOneWidget);
  });

  group('signing out of a remote account', () {
    Future<AppDatabase> pumpRemote(
      WidgetTester tester,
      _FakeAuth auth, {
      required bool withUnsyncedWork,
    }) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      if (withUnsyncedWork) {
        await db.customStatement(
          "INSERT INTO accounts (id, name, currency, created_at, updated_at,"
          " dirty) VALUES ('acc', 'Cash', 'USD', 0, 0, 1)",
        );
      }
      await tester.pumpWidget(_gate(auth, _Host(database: db)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return db;
    }

    testWidgets('is offered as a sign-out, not a deletion', (tester) async {
      final auth = _FakeAuth([_rita], 'r');
      final db = await pumpRemote(tester, auth, withUnsyncedWork: false);
      addTearDown(db.close);

      expect(find.text('Sign out'), findsOneWidget);
      expect(find.text('Delete this account'), findsNothing);

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      expect(find.text('Sign out of “Rita”?'), findsOneWidget);
      expect(find.textContaining('stays in your account'), findsOneWidget);
      // Nothing pending, so no scare.
      expect(find.textContaining('have not synced yet'), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
      await tester.pumpAndSettle();

      expect(auth.signedOutRemote, isTrue);
    });

    testWidgets('warns when the engine still holds unpushed writes', (
      tester,
    ) async {
      final auth = _FakeAuth([_rita], 'r');
      final db = await pumpRemote(tester, auth, withUnsyncedWork: true);
      addTearDown(db.close);

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      expect(find.textContaining('have not synced yet'), findsOneWidget);

      // The warning is a warning, not a block — and cancelling keeps the
      // account exactly where it was.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(auth.signedOutRemote, isFalse);
      expect(auth.activeId, 'r');
    });
  });
}
