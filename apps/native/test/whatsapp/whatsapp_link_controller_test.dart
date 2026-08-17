import 'dart:async';
import 'dart:convert';

import 'package:app/whatsapp/whatsapp_link_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what the controller asked for and replays canned responses.
class _FakeApi implements WhatsappLinkApi {
  _FakeApi();

  final List<String> queries = [];
  final List<({String name, Map<String, dynamic> args})> mutations = [];

  /// Queued query responses, consumed in order. The last one repeats, so a
  /// reload after an unlink does not need its own entry.
  final List<Object> queryResponses = [];
  Object? mutationResponse;

  Object? queryError;
  Object? mutationError;

  @override
  Future<String> query(String name, Map<String, dynamic> args) async {
    queries.add(name);
    if (queryError != null) throw queryError!;
    final next = queryResponses.length > 1
        ? queryResponses.removeAt(0)
        : queryResponses.first;
    return next is String ? next : jsonEncode(next);
  }

  @override
  Future<String> mutation({
    required String name,
    required Map<String, dynamic> args,
  }) async {
    mutations.add((name: name, args: args));
    if (mutationError != null) throw mutationError!;
    final response = mutationResponse;
    return response is String ? response : jsonEncode(response ?? {});
  }
}

Map<String, Object?> _status({
  bool available = true,
  String? businessNumber = '5491123991858',
  List<Map<String, Object?>> numbers = const [],
}) => {
  'available': available,
  'businessNumber': businessNumber,
  'numbers': numbers,
};

void main() {
  group('local accounts', () {
    test('never touch the network and are never linkable', () async {
      final api = _FakeApi();
      final controller = WhatsappLinkController(isRemote: false, api: api);

      await controller.load();

      expect(controller.state, WhatsappLinkState.ready);
      expect(controller.available, isFalse);
      expect(controller.isLinked, isFalse);
      expect(api.queries, isEmpty);
    });

    test('createCode and unlink are no-ops', () async {
      final api = _FakeApi();
      final controller = WhatsappLinkController(isRemote: false, api: api);

      await controller.createCode();
      await controller.unlink();

      expect(api.mutations, isEmpty);
      expect(controller.code, isNull);
    });
  });

  group('load', () {
    test('parses an unlinked status', () async {
      final api = _FakeApi()..queryResponses.add(_status());
      final controller = WhatsappLinkController(isRemote: true, api: api);

      await controller.load();

      expect(controller.state, WhatsappLinkState.ready);
      expect(controller.available, isTrue);
      expect(controller.businessNumber, '5491123991858');
      expect(controller.isLinked, isFalse);
      expect(api.queries, ['v1/whatsapp/queries:linkStatus']);
    });

    test('parses linked numbers and their timestamps', () async {
      final linkedAt = DateTime.utc(2026, 8, 17, 12, 30);
      final api = _FakeApi()
        ..queryResponses.add(
          _status(
            numbers: [
              {
                'waId': '5491123991858',
                'linkedAt': linkedAt.millisecondsSinceEpoch,
              },
              {'waId': '5491125891334', 'linkedAt': null},
            ],
          ),
        );
      final controller = WhatsappLinkController(isRemote: true, api: api);

      await controller.load();

      expect(controller.isLinked, isTrue);
      expect(controller.numbers, hasLength(2));
      expect(controller.numbers.first.waId, '5491123991858');
      // Same instant, local zone: `DateTime ==` also compares the UTC flag, so
      // compare moments rather than objects.
      expect(
        controller.numbers.first.linkedAt!.isAtSameMomentAs(linkedAt),
        isTrue,
      );
      // A null timestamp is tolerated rather than dropping the whole number.
      expect(controller.numbers.last.waId, '5491125891334');
      expect(controller.numbers.last.linkedAt, isNull);
    });

    test('skips malformed entries instead of failing the whole load', () async {
      final api = _FakeApi()
        ..queryResponses.add(
          _status(
            numbers: [
              {'waId': ''},
              {'linkedAt': 1},
              {'waId': '5491123991858'},
            ],
          ),
        );
      final controller = WhatsappLinkController(isRemote: true, api: api);

      await controller.load();

      expect(controller.state, WhatsappLinkState.ready);
      expect(controller.numbers.map((n) => n.waId), ['5491123991858']);
    });

    test('reports available: false when the backend has no number', () async {
      final api = _FakeApi()
        ..queryResponses.add(_status(available: false, businessNumber: null));
      final controller = WhatsappLinkController(isRemote: true, api: api);

      await controller.load();

      expect(controller.available, isFalse);
      expect(controller.businessNumber, isNull);
    });

    test('surfaces a network failure as failed, not as empty', () async {
      final api = _FakeApi()..queryError = StateError('offline');
      final controller = WhatsappLinkController(isRemote: true, api: api);

      await controller.load();

      // The distinction matters: "failed" offers a retry, whereas a silent
      // empty list would read as "you have no numbers linked".
      expect(controller.state, WhatsappLinkState.failed);
      expect(controller.loadError, isA<StateError>());
      expect(controller.isLinked, isFalse);
    });

    test('treats a non-object response as a failure', () async {
      final api = _FakeApi()..queryResponses.add('"nope"');
      final controller = WhatsappLinkController(isRemote: true, api: api);

      await controller.load();

      expect(controller.state, WhatsappLinkState.failed);
    });

    test('retrying after a failure recovers', () async {
      final api = _FakeApi()
        ..queryError = StateError('offline')
        ..queryResponses.add(_status());
      final controller = WhatsappLinkController(isRemote: true, api: api);

      await controller.load();
      expect(controller.state, WhatsappLinkState.failed);

      api.queryError = null;
      await controller.load();

      expect(controller.state, WhatsappLinkState.ready);
      expect(controller.loadError, isNull);
    });
  });

  group('createCode', () {
    test('exposes the code, expiry and deep link', () async {
      final expiresAt = DateTime.now().add(const Duration(minutes: 10));
      final api = _FakeApi()
        ..queryResponses.add(_status())
        ..mutationResponse = {
          'code': 'A1B2-C3D4',
          'expiresAt': expiresAt.millisecondsSinceEpoch,
          'deepLink': 'https://wa.me/5491123991858?text=Wallet%20Bot',
        };
      final controller = WhatsappLinkController(isRemote: true, api: api);
      await controller.load();

      await controller.createCode();

      expect(controller.code?.code, 'A1B2-C3D4');
      expect(controller.code?.deepLink, contains('wa.me'));
      expect(controller.code?.isExpired, isFalse);
      expect(api.mutations.single.name, 'v1/whatsapp/mutations:createLinkCode');
      addTearDown(controller.dispose);
    });

    test('tolerates a null deep link', () async {
      final api = _FakeApi()
        ..queryResponses.add(_status())
        ..mutationResponse = {
          'code': 'A1B2-C3D4',
          'expiresAt': DateTime.now()
              .add(const Duration(minutes: 10))
              .millisecondsSinceEpoch,
          'deepLink': null,
        };
      final controller = WhatsappLinkController(isRemote: true, api: api);
      await controller.load();

      await controller.createCode();

      expect(controller.code?.code, 'A1B2-C3D4');
      expect(controller.code?.deepLink, isNull);
      addTearDown(controller.dispose);
    });

    test('rethrows so the screen can show a toast', () async {
      final api = _FakeApi()
        ..queryResponses.add(_status())
        ..mutationError = StateError('rate limited');
      final controller = WhatsappLinkController(isRemote: true, api: api);
      await controller.load();

      await expectLater(controller.createCode(), throwsStateError);
      expect(controller.code, isNull);
      expect(controller.busy, isFalse);
    });

    test('rejects a response missing the code', () async {
      final api = _FakeApi()
        ..queryResponses.add(_status())
        ..mutationResponse = {'expiresAt': 1};
      final controller = WhatsappLinkController(isRemote: true, api: api);
      await controller.load();

      await expectLater(controller.createCode(), throwsFormatException);
      expect(controller.code, isNull);
    });

    test('never shows a code that arrives already expired', () async {
      final api = _FakeApi()
        ..queryResponses.add(_status())
        ..mutationResponse = {
          'code': 'A1B2-C3D4',
          'expiresAt': DateTime.now()
              .subtract(const Duration(seconds: 1))
              .millisecondsSinceEpoch,
        };
      final controller = WhatsappLinkController(isRemote: true, api: api);
      await controller.load();

      await controller.createCode();

      expect(controller.code, isNull);
    });

    test('clears the code when it expires', () async {
      final api = _FakeApi()
        ..queryResponses.add(_status())
        ..mutationResponse = {
          'code': 'A1B2-C3D4',
          'expiresAt': DateTime.now()
              .add(const Duration(milliseconds: 40))
              .millisecondsSinceEpoch,
        };
      final controller = WhatsappLinkController(isRemote: true, api: api);
      await controller.load();
      await controller.createCode();
      expect(controller.code, isNotNull);

      var notified = false;
      controller.addListener(() => notified = true);
      await Future<void>.delayed(const Duration(milliseconds: 120));

      // Sending an expired code would be rejected over WhatsApp, so the screen
      // must stop offering it rather than let the user try.
      expect(controller.code, isNull);
      expect(notified, isTrue);
      addTearDown(controller.dispose);
    });

    test('dismissCode drops it locally without a backend call', () async {
      final api = _FakeApi()
        ..queryResponses.add(_status())
        ..mutationResponse = {
          'code': 'A1B2-C3D4',
          'expiresAt': DateTime.now()
              .add(const Duration(minutes: 10))
              .millisecondsSinceEpoch,
        };
      final controller = WhatsappLinkController(isRemote: true, api: api);
      await controller.load();
      await controller.createCode();

      controller.dismissCode();

      expect(controller.code, isNull);
      expect(api.mutations, hasLength(1));
      addTearDown(controller.dispose);
    });
  });

  group('unlink', () {
    test('sends the waId and reloads', () async {
      final api = _FakeApi()
        ..queryResponses.addAll([
          _status(
            numbers: [
              {'waId': '5491123991858'},
            ],
          ),
          _status(),
        ]);
      final controller = WhatsappLinkController(isRemote: true, api: api);
      await controller.load();
      expect(controller.isLinked, isTrue);

      await controller.unlink(waId: '5491123991858');

      expect(api.mutations.single.name, 'v1/whatsapp/mutations:unlink');
      expect(api.mutations.single.args, {'waId': '5491123991858'});
      // Reloaded, so the list reflects the backend rather than a local guess.
      expect(api.queries, hasLength(2));
      expect(controller.isLinked, isFalse);
    });

    test('omits waId entirely when unlinking everything', () async {
      final api = _FakeApi()..queryResponses.add(_status());
      final controller = WhatsappLinkController(isRemote: true, api: api);
      await controller.load();

      await controller.unlink();

      expect(api.mutations.single.args, isEmpty);
    });

    test('drops a pending code, which the backend has revoked', () async {
      final api = _FakeApi()
        ..queryResponses.add(_status())
        ..mutationResponse = {
          'code': 'A1B2-C3D4',
          'expiresAt': DateTime.now()
              .add(const Duration(minutes: 10))
              .millisecondsSinceEpoch,
        };
      final controller = WhatsappLinkController(isRemote: true, api: api);
      await controller.load();
      await controller.createCode();
      expect(controller.code, isNotNull);

      api.mutationResponse = {'unlinked': 1};
      await controller.unlink();

      expect(controller.code, isNull);
      addTearDown(controller.dispose);
    });

    test('rethrows and clears busy on failure', () async {
      final api = _FakeApi()..queryResponses.add(_status());
      final controller = WhatsappLinkController(isRemote: true, api: api);
      await controller.load();
      api.mutationError = StateError('boom');

      await expectLater(controller.unlink(), throwsStateError);
      expect(controller.busy, isFalse);
    });
  });

  test('a second call is ignored while one is in flight', () async {
    final gate = Completer<void>();
    final api = _SlowApi(gate);
    final controller = WhatsappLinkController(isRemote: true, api: api);

    final first = controller.createCode();
    expect(controller.busy, isTrue);
    // Guards against a double-tap minting two codes, each of which would be a
    // live credential.
    await controller.createCode();
    expect(api.calls, 1);

    gate.complete();
    await first;
    expect(controller.busy, isFalse);
    addTearDown(controller.dispose);
  });
}

/// Holds a mutation open until its gate completes, so the busy guard is
/// observable.
class _SlowApi implements WhatsappLinkApi {
  _SlowApi(this._gate);

  final Completer<void> _gate;
  int calls = 0;

  @override
  Future<String> query(String name, Map<String, dynamic> args) async =>
      jsonEncode(_status());

  @override
  Future<String> mutation({
    required String name,
    required Map<String, dynamic> args,
  }) async {
    calls += 1;
    await _gate.future;
    return jsonEncode({
      'code': 'A1B2-C3D4',
      'expiresAt': DateTime.now()
          .add(const Duration(minutes: 10))
          .millisecondsSinceEpoch,
    });
  }
}
