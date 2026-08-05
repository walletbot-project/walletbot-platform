import 'package:app/components/dashboard/dashboard_models.dart';
import 'package:app/components/dashboard/dashboard_view.dart';
import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:app/l10n/l10n.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  late AppDatabase db;
  late AppRepositories repos;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repos = AppRepositories(db);
  });

  tearDown(() => db.close());

  testWidgets('overlapping persisted rows render through the safe reflow', (
    tester,
  ) async {
    final rows = [
      _row('stat-0', 0, 'third', 1, 0),
      _row('stat-1', 1, 'third', 1, 2),
      _row('stat-overlap', 2, 'third', 1, 2),
      _row('stat-2', 3, 'third', 1, 4),
      _row('full-0', 4, 'full', 2, 0),
      _row('full-overlap', 5, 'full', 2, 0),
    ];
    final items = [
      for (final row in rows)
        DashboardViewItem(
          row: row,
          spec: StatWidgetSpec(
            title: row.id,
            filter: const TransactionFilter(),
            aggregation: StatAggregation.count,
            width: DashboardWidth.fromWire(row.width)!,
          ),
        ),
    ];

    await tester.pumpWidget(
      Provider<AppRepositories>.value(
        value: repos,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(width: 416, child: DashboardView(items: items)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(DashboardView), findsOneWidget);
    expect(find.text('stat-overlap'), findsOneWidget);
    expect(find.text('full-overlap'), findsOneWidget);

    // Explicitly cancel Drift query streams and flush their zero-duration
    // cleanup timer before the widget-test binding verifies pending timers.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}

DashboardWidget _row(String id, int position, String width, int row, int col) {
  final now = BigInt.from(position + 1);
  return DashboardWidget(
    id: id,
    type: 'stat',
    position: position,
    width: width,
    options: '{"layout":{"row":$row,"col":$col}}',
    archived: false,
    createdAt: now,
    updatedAt: now,
    dirty: false,
  );
}
