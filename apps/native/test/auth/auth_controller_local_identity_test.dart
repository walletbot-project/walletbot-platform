import 'dart:convert';
import 'package:app/auth/auth_controller.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'local identities are distinct, persist offline, and do not register at creation',
    () async {
      var requests = 0;
      final auth = AuthController(
        httpClient: MockClient((_) async {
          requests++;
          throw StateError('offline');
        }),
      );
      final a = await auth.addLocal(name: 'A');
      final b = await auth.addLocal(name: 'B');
      expect(a.localAccountId, isNotNull);
      expect(a.localAccountId, isNot(b.localAccountId));
      expect(requests, 0);
      final reloaded = AuthController();
      await reloaded.load();
      expect(reloaded.accounts.map((a) => a.localAccountId), [
        a.localAccountId,
        b.localAccountId,
      ]);
      auth.dispose();
      reloaded.dispose();
    },
  );
  test(
    'legacy migration preserves database identity and active account across launches',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'accounts': jsonEncode([
          {'id': 'local_old', 'type': 'local', 'name': 'Old'},
          {'id': 'remote_user', 'type': 'remote'},
        ]),
        'active_account_id': 'local_old',
      });
      final auth = AuthController();
      await auth.load();
      final id = auth.activeAccount!.localAccountId;
      expect(id, isNotNull);
      expect(auth.activeAccount!.id, 'local_old');
      expect(auth.accounts.last.localAccountId, isNull);
      final reloaded = AuthController();
      await reloaded.load();
      expect(reloaded.activeAccount!.id, 'local_old');
      expect(reloaded.activeAccount!.localAccountId, id);
      auth.dispose();
      reloaded.dispose();
    },
  );
}
