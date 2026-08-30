import 'package:app/shared/adaptive_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stateful content that reports the framing it is in and holds a counter, so
/// tests can prove the State object survives a live route swap.
class _Probe extends StatefulWidget {
  const _Probe();

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  int count = 0;

  @override
  Widget build(BuildContext context) {
    final style = AdaptiveModalScope.maybeOf(context);
    return SizedBox(
      height: 200,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('style:${style?.name}'),
          Text('count:$count'),
          TextButton(
            onPressed: () => setState(() => count++),
            child: const Text('inc'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('picked'),
            child: const Text('pick'),
          ),
        ],
      ),
    );
  }
}

/// Pumps a host whose "open" button awaits the modal and records its result.
Future<List<String?>> _pumpHost(WidgetTester tester) async {
  final results = <String?>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                final result = await showAdaptiveModal<String>(
                  context,
                  showDragHandle: true,
                  builder: (_) => const _Probe(),
                );
                results.add(result);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  return results;
}

void _resize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
}

void main() {
  testWidgets('compact window presents a real modal bottom sheet', (
    tester,
  ) async {
    _resize(tester, const Size(500, 800));
    addTearDown(tester.view.reset);

    await _pumpHost(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('style:bottomSheet'), findsOneWidget);
    // The platform's own sheet, not a hand-rolled framing: the drag handle is
    // present and the sheet is anchored to the bottom edge.
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(tester.getRect(find.byType(_Probe)).bottom, 800);
  });

  testWidgets('medium window presents a real dialog', (tester) async {
    _resize(tester, const Size(900, 800));
    addTearDown(tester.view.reset);

    await _pumpHost(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('style:dialog'), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    // Centered and capped, not stretched across the window. (The Dialog
    // widget itself spans the window — it holds the inset padding and the
    // centering — so measure the content it frames.)
    final rect = tester.getRect(find.byType(_Probe));
    expect(rect.width, lessThanOrEqualTo(560));
    expect(rect.center.dx, closeTo(450, 1));
    expect(rect.center.dy, closeTo(400, 1));
  });

  testWidgets('sheet → dialog swap on grow keeps State', (tester) async {
    _resize(tester, const Size(500, 800));
    addTearDown(tester.view.reset);

    await _pumpHost(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);

    await tester.tap(find.text('inc'));
    await tester.pump();
    await tester.tap(find.text('inc'));
    await tester.pump();
    expect(find.text('count:2'), findsOneWidget);

    _resize(tester, const Size(900, 800));
    await tester.pumpAndSettle();

    expect(find.text('count:2'), findsOneWidget);
    expect(find.text('style:dialog'), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('dialog → sheet swap on shrink keeps State, and round-trips', (
    tester,
  ) async {
    _resize(tester, const Size(900, 800));
    addTearDown(tester.view.reset);

    await _pumpHost(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);

    await tester.tap(find.text('inc'));
    await tester.pump();
    expect(find.text('count:1'), findsOneWidget);

    _resize(tester, const Size(500, 800));
    await tester.pumpAndSettle();
    expect(find.text('count:1'), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);

    // Round-trip: grow again — still the same State object.
    _resize(tester, const Size(900, 800));
    await tester.pumpAndSettle();
    expect(find.text('count:1'), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);
  });

  testWidgets('a resize swap does NOT resolve the caller\'s future', (
    tester,
  ) async {
    _resize(tester, const Size(500, 800));
    addTearDown(tester.view.reset);

    final results = await _pumpHost(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    _resize(tester, const Size(900, 800));
    await tester.pumpAndSettle();
    _resize(tester, const Size(500, 800));
    await tester.pumpAndSettle();

    // Two swaps, and the caller is still waiting.
    expect(results, isEmpty);
    expect(find.byType(_Probe), findsOneWidget);
  });

  testWidgets('popping with a value resolves the future in both framings', (
    tester,
  ) async {
    _resize(tester, const Size(500, 800));
    addTearDown(tester.view.reset);

    final results = await _pumpHost(tester);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('pick'));
    await tester.pumpAndSettle();
    expect(results, ['picked']);
    expect(find.byType(_Probe), findsNothing);

    _resize(tester, const Size(900, 800));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    await tester.tap(find.text('pick'));
    await tester.pumpAndSettle();
    expect(results, ['picked', 'picked']);
  });

  testWidgets('scrim dismissal resolves the future with null', (tester) async {
    _resize(tester, const Size(500, 800));
    addTearDown(tester.view.reset);

    final results = await _pumpHost(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(20, 20)); // scrim, above the sheet
    await tester.pumpAndSettle();

    expect(results, [null]);
    expect(find.byType(_Probe), findsNothing);
  });
}
