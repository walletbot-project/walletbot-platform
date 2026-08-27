import 'package:flutter_test/flutter_test.dart';
import 'package:app/convex/local_query_set.dart';
import 'package:app/convex/protocol.dart';

void main() {
  test('first subscriber produces Add, duplicates share the queryId', () {
    final local = LocalQuerySet();
    final (first, firstMessage) = local.subscribe('q:f', const {'a': 1});
    expect(firstMessage, isNotNull);
    expect(firstMessage!.baseVersion, 0);
    expect(firstMessage.newVersion, 1);
    final (second, secondMessage) = local.subscribe('q:f', const {'a': 1});
    expect(secondMessage, isNull);
    expect(identical(first, second), isTrue);
    expect(first.refCount, 2);
    final (third, thirdMessage) = local.subscribe('q:f', const {'a': 2});
    expect(thirdMessage, isNotNull);
    expect(third.queryId, isNot(first.queryId));
  });

  test('unsubscribe removes only after the last subscriber', () {
    final local = LocalQuerySet();
    final (query, _) = local.subscribe('q:f', const {});
    local.subscribe('q:f', const {});
    expect(local.unsubscribe(query), isNull);
    final removal = local.unsubscribe(query);
    expect(removal, isNotNull);
    expect(removal!.modifications.single, isA<RemoveQueryModification>());
    expect(local.queries, isEmpty);
    expect(local.unsubscribe(query), isNull);
  });

  test('restart resets the version and re-adds everything with journals', () {
    final local = LocalQuerySet();
    final (query, _) = local.subscribe('q:f', const {});
    local.subscribe('q:g', const {});
    local.saveJournal(query.queryId, 'cursor-1');
    expect(local.version, 2);
    final restart = local.restart();
    expect(restart, isNotNull);
    expect(restart!.baseVersion, 0);
    expect(restart.newVersion, 1);
    expect(local.version, 1);
    final adds = restart.modifications.cast<AddQueryModification>();
    expect(adds, hasLength(2));
    final readded = adds.firstWhere((a) => a.queryId == query.queryId);
    expect(readded.hasJournal, isTrue);
    expect(readded.journal, 'cursor-1');
    final other = adds.firstWhere((a) => a.queryId != query.queryId);
    expect(other.hasJournal, isFalse);
  });

  test('restart with no subscriptions returns null and resets the version', () {
    final local = LocalQuerySet();
    final (query, _) = local.subscribe('q:f', const {});
    local.unsubscribe(query);
    expect(local.version, 2);
    expect(local.restart(), isNull);
    expect(local.version, 0);
  });
}
