import 'package:app/settings/display_settings.dart';
import 'package:app/user_settings/language_sync_controller.dart';
import 'package:convex_flutter/convex_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/memory_display_settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<DisplaySettingsController> settingsWith(DisplayLanguage language) async {
    final controller = DisplaySettingsController(
      store: MemoryDisplaySettingsStore(),
    );
    await controller.load();
    if (language != DisplayLanguage.system) {
      await controller.setLanguage(language);
    }
    return controller;
  }

  test('reports the system locale as overwritable', () async {
    final calls = <Map<String, dynamic>>[];
    final settings = await settingsWith(DisplayLanguage.system);
    final sync = LanguageSyncController(
      accountId: 'account-1',
      isRemote: true,
      displaySettings: settings,
      client: _StubConvexClient((name, args) async {
        calls.add({'name': name, ...args});
        return '{}';
      }),
    );
    addTearDown(sync.dispose);

    await sync.start();

    expect(calls, hasLength(1));
    expect(calls.single['name'], 'v1/users/mutations:updateLanguage');
    expect(calls.single['source'], 'device');
    // Whatever the host platform reports; the server resolves it.
    expect(calls.single['tag'], isNotEmpty);
  });

  test('reports an explicit pick as explicit', () async {
    final calls = <Map<String, dynamic>>[];
    final settings = await settingsWith(DisplayLanguage.spanish);
    final sync = LanguageSyncController(
      accountId: 'account-1',
      isRemote: true,
      displaySettings: settings,
      client: _StubConvexClient((name, args) async {
        calls.add(args);
        return '{}';
      }),
    );
    addTearDown(sync.dispose);

    await sync.start();

    expect(calls.single['source'], 'explicit');
    expect(calls.single['tag'], 'es');
  });

  test('a local-only account never reaches the network', () async {
    var called = false;
    final settings = await settingsWith(DisplayLanguage.english);
    final sync = LanguageSyncController(
      accountId: 'local-1',
      isRemote: false,
      displaySettings: settings,
      client: _StubConvexClient((name, args) async {
        called = true;
        return '{}';
      }),
    );
    addTearDown(sync.dispose);

    await sync.start();
    await settings.setLanguage(DisplayLanguage.spanish);

    expect(called, isFalse);
  });

  test('skips the push when the cached value already matches', () async {
    var calls = 0;
    final settings = await settingsWith(DisplayLanguage.english);
    FlutterSecureStorage.setMockInitialValues({
      'language_pushed_account-1': 'explicit:en',
    });
    final sync = LanguageSyncController(
      accountId: 'account-1',
      isRemote: true,
      displaySettings: settings,
      client: _StubConvexClient((name, args) async {
        calls++;
        return '{}';
      }),
    );
    addTearDown(sync.dispose);

    await sync.start();

    expect(calls, 0);
  });

  // The cache is only written after the mutation lands, so an offline start
  // retries instead of pretending the server knows.
  test('a failed push is retried on the next start', () async {
    var calls = 0;
    final settings = await settingsWith(DisplayLanguage.english);
    LanguageSyncController build() => LanguageSyncController(
      accountId: 'account-1',
      isRemote: true,
      displaySettings: settings,
      client: _StubConvexClient((name, args) async {
        calls++;
        throw StateError('offline');
      }),
    );

    final first = build();
    await first.start();
    first.dispose();
    final second = build();
    addTearDown(second.dispose);
    await second.start();

    expect(calls, 2);
  });

  test('pushes again when the user changes language', () async {
    final tags = <Object?>[];
    final settings = await settingsWith(DisplayLanguage.english);
    final sync = LanguageSyncController(
      accountId: 'account-1',
      isRemote: true,
      displaySettings: settings,
      client: _StubConvexClient((name, args) async {
        tags.add(args['tag']);
        return '{}';
      }),
    );
    addTearDown(sync.dispose);

    await sync.start();
    await settings.setLanguage(DisplayLanguage.spanish);
    // The listener fires synchronously; the push it starts does not.
    await Future<void>.delayed(Duration.zero);

    expect(tags, ['en', 'es']);
  });
}

class _StubConvexClient implements ConvexClient {
  _StubConvexClient(this.onMutation);

  final Future<String> Function(String name, Map<String, dynamic> args)
  onMutation;

  @override
  Future<String> mutation({
    required String name,
    required Map<String, dynamic> args,
  }) => onMutation(name, args);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
