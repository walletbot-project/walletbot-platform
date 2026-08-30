import 'package:app/auth/account.dart';
import 'package:flutter_test/flutter_test.dart';

// Only the persisted flag is covered here. The banner that reads it lives in
// `_AuthGate`'s subtree, which needs the full provider stack (database, voice
// sync, Convex transport) to build. The banner branch is manual QA.
void main() {
  group('UserAccount.serverDeleted', () {
    test('survives a storage round-trip', () {
      const account = UserAccount(
        id: 'u1',
        type: AccountType.remote,
        email: 'a@b.c',
        sessionToken: 'tok',
        requiresReauth: true,
        serverDeleted: true,
      );

      final restored = UserAccount.fromJson(account.toJson());

      // The banner is driven off this flag, so losing it on restart would put
      // the "Reconnect" button — and the duplicate-account trap — back.
      expect(restored.serverDeleted, isTrue);
      expect(restored.requiresReauth, isTrue);
    });

    test('defaults to false for accounts stored before the flag existed', () {
      final restored = UserAccount.fromJson(const {
        'id': 'u1',
        'type': 'remote',
        'email': 'a@b.c',
        'sessionToken': 'tok',
        'requiresReauth': true,
      });

      expect(restored.serverDeleted, isFalse);
      expect(restored.requiresReauth, isTrue);
    });

    test('copyWith leaves the flag alone unless asked', () {
      const account = UserAccount(
        id: 'u1',
        type: AccountType.remote,
        serverDeleted: true,
      );

      expect(account.copyWith(name: 'A').serverDeleted, isTrue);
      expect(account.copyWith(serverDeleted: false).serverDeleted, isFalse);
    });
  });
}
