import 'package:app/components/tags_view.dart';
import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:app/l10n/l10n.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// The tag tree reorders by level (WAL-199): a tag moves only among its
// siblings, carrying its sub-tags, and never above its own parent.
void main() {
  late AppDatabase db;
  late AppRepositories repos;
  late Map<String, String> ids;

  setUp(() async {
    // Streams must close synchronously under the widget tester's fake clock,
    // or cancelling one leaves a pending drift timer behind.
    db = AppDatabase.forTesting(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    repos = AppRepositories(db);
    // Hogar (children Luz, Agua), Auto, Viajes.
    final hogar = await repos.tags.create(name: 'Hogar');
    ids = {
      'Hogar': hogar,
      'Luz': await repos.tags.create(name: 'Luz', parentId: hogar),
      'Agua': await repos.tags.create(name: 'Agua', parentId: hogar),
      'Auto': await repos.tags.create(name: 'Auto'),
      'Viajes': await repos.tags.create(name: 'Viajes'),
    };
  });

  tearDown(() async => db.close());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      Provider<AppRepositories>.value(
        value: repos,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: TagsView(onSelect: (_) {})),
        ),
      ),
    );
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    // Drift streams resolve outside the fake clock.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  /// Visible top-to-bottom order of the given chip labels.
  List<String> visible(WidgetTester tester, List<String> labels) {
    final tops = {
      for (final l in labels) l: tester.getTopLeft(find.text(l)).dy,
    };
    return [...labels]..sort((a, b) => tops[a]!.compareTo(tops[b]!));
  }

  Future<void> drag(WidgetTester tester, String label, double dy) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.text(label)),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    const steps = 12;
    for (var i = 0; i < steps; i++) {
      await gesture.moveBy(Offset(0, dy / steps));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    // Let the repository write and the stream re-emit.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  Future<Map<String, Tag>> stored(WidgetTester tester) async {
    final rows = await tester.runAsync(() => repos.tags.listActive());
    return {for (final t in rows!) t.name: t};
  }

  const all = ['Auto', 'Hogar', 'Agua', 'Luz', 'Viajes'];

  testWidgets('starts alphabetical within each level', (tester) async {
    await pump(tester);
    expect(visible(tester, all), ['Auto', 'Hogar', 'Agua', 'Luz', 'Viajes']);
  });

  testWidgets('a top-level tag moves above a whole family', (tester) async {
    await pump(tester);
    final above = tester.getTopLeft(find.text('Auto')).dy;
    final viajes = tester.getTopLeft(find.text('Viajes')).dy;

    await drag(tester, 'Viajes', above - viajes - 10);

    expect(visible(tester, all), ['Viajes', 'Auto', 'Hogar', 'Agua', 'Luz']);
    final tags = await stored(tester);
    expect(tags['Viajes']!.position, 0);
    expect(tags['Viajes']!.parentId, isNull);
  });

  testWidgets('dragging a parent carries its children along', (tester) async {
    await pump(tester);
    final auto = tester.getTopLeft(find.text('Auto')).dy;
    final hogar = tester.getTopLeft(find.text('Hogar')).dy;

    await drag(tester, 'Hogar', auto - hogar - 10);

    expect(visible(tester, all), ['Hogar', 'Agua', 'Luz', 'Auto', 'Viajes']);
    final tags = await stored(tester);
    expect(tags['Agua']!.parentId, ids['Hogar']);
    expect(tags['Luz']!.parentId, ids['Hogar']);
  });

  testWidgets('siblings swap inside their family', (tester) async {
    await pump(tester);
    final agua = tester.getTopLeft(find.text('Agua')).dy;
    final luz = tester.getTopLeft(find.text('Luz')).dy;

    await drag(tester, 'Luz', agua - luz - 10);

    expect(visible(tester, all), ['Auto', 'Hogar', 'Luz', 'Agua', 'Viajes']);
    final tags = await stored(tester);
    expect(tags['Luz']!.position, 0);
    expect(tags['Agua']!.position, 1);
    // Top level untouched.
    expect(tags['Auto']!.position, isNull);
  });

  testWidgets('a child never lands above its parent', (tester) async {
    await pump(tester);
    final top = tester.getTopLeft(find.text('Auto')).dy;
    final luz = tester.getTopLeft(find.text('Luz')).dy;

    // Far above the whole list.
    await drag(tester, 'Luz', top - luz - 200);

    final order = visible(tester, all);
    expect(order.indexOf('Luz'), greaterThan(order.indexOf('Hogar')));
    final tags = await stored(tester);
    expect(tags['Luz']!.parentId, ids['Hogar']);
  });

  testWidgets('overshooting past the top still lands a family first', (
    tester,
  ) async {
    await pump(tester);
    final hogar = tester.getTopLeft(find.text('Hogar')).dy;

    // Well past the first tag, where ReorderableListView snapped back.
    await drag(tester, 'Hogar', -hogar - 150);

    expect(visible(tester, all), ['Hogar', 'Agua', 'Luz', 'Auto', 'Viajes']);
  });

  testWidgets('a family moves down past a sibling', (tester) async {
    await pump(tester);
    final auto = tester.getCenter(find.text('Auto')).dy;
    final viajes = tester.getBottomLeft(find.text('Viajes')).dy;

    // Past the last tag: the last previewed slot (after Viajes) holds.
    await drag(tester, 'Auto', viajes - auto + 60);

    expect(visible(tester, all), ['Hogar', 'Agua', 'Luz', 'Viajes', 'Auto']);
  });

  testWidgets('a plain tap still opens the tag', (tester) async {
    Tag? opened;
    await tester.pumpWidget(
      Provider<AppRepositories>.value(
        value: repos,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: TagsView(onSelect: (tag) => opened = tag)),
        ),
      ),
    );
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Luz'));
    await tester.pumpAndSettle();

    expect(opened?.id, ids['Luz']);
  });
}
