import 'dart:async';

import 'package:app/components/reorderable_grouped_list.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host({
    required List<String> items,
    required Future<void> Function(List<String>) onReorder,
    void Function(String)? onTap,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ReorderableGroupedList<String>(
          items: items,
          idOf: (item) => item,
          reorderFailedMessage: 'reorder failed',
          onReorder: onReorder,
          itemBuilder: (context, item, radius) => SizedBox(
            height: 60,
            child: Material(
              borderRadius: radius,
              child: InkWell(
                onTap: () => onTap?.call(item),
                child: Center(child: Text(item)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<String> visibleOrder(WidgetTester tester) {
    final labels = ['A', 'B', 'C'];
    final tops = {
      for (final label in labels) label: tester.getTopLeft(find.text(label)).dy,
    };
    return labels..sort((a, b) => tops[a]!.compareTo(tops[b]!));
  }

  Future<void> dragBelow(WidgetTester tester, String item, double dy) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.text(item)),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    // Small steps with frames in between, like a finger: the list animates
    // the gap open as the lifted row passes each neighbour.
    const steps = 10;
    for (var i = 0; i < steps; i++) {
      await gesture.moveBy(Offset(0, dy / steps));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('long-press and drag reports the new order and shows it', (
    tester,
  ) async {
    List<String>? saved;
    await tester.pumpWidget(
      host(items: ['A', 'B', 'C'], onReorder: (order) async => saved = order),
    );

    await dragBelow(tester, 'A', 150);

    expect(saved, ['B', 'C', 'A']);
    // Shown right away, before the caller's list catches up.
    expect(visibleOrder(tester), ['B', 'C', 'A']);
  });

  testWidgets('a failed write restores the order and says so', (tester) async {
    await tester.pumpWidget(
      host(
        items: ['A', 'B', 'C'],
        onReorder: (_) async => throw StateError('db down'),
      ),
    );

    await dragBelow(tester, 'A', 150);

    expect(visibleOrder(tester), ['A', 'B', 'C']);
    expect(find.text('reorder failed'), findsOneWidget);
  });

  testWidgets('keeps the dropped order until the caller catches up', (
    tester,
  ) async {
    final write = Completer<void>();
    await tester.pumpWidget(
      host(items: ['A', 'B', 'C'], onReorder: (_) => write.future),
    );

    await dragBelow(tester, 'C', -150);
    expect(visibleOrder(tester), ['C', 'A', 'B']);

    write.complete();
    await tester.pumpAndSettle();
    // The caller re-emits the persisted order.
    await tester.pumpWidget(
      host(items: ['C', 'A', 'B'], onReorder: (_) async {}),
    );
    expect(visibleOrder(tester), ['C', 'A', 'B']);
  });

  testWidgets('a plain tap still opens the row', (tester) async {
    String? tapped;
    await tester.pumpWidget(
      host(
        items: ['A', 'B', 'C'],
        onReorder: (_) async {},
        onTap: (item) => tapped = item,
      ),
    );

    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();

    expect(tapped, 'B');
  });
}
