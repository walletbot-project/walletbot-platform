import 'package:app/shared/adaptive_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stateful content that reports the style it is framed in and holds a
/// counter, so tests can prove the State object survives a live morph.
class _StatefulProbe extends StatefulWidget {
  const _StatefulProbe();

  @override
  State<_StatefulProbe> createState() => _StatefulProbeState();
}

class _StatefulProbeState extends State<_StatefulProbe> {
  int count = 0;

  @override
  Widget build(BuildContext context) {
    final style = AdaptiveSurfaceScope.maybeOf(context);
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
        ],
      ),
    );
  }
}

Future<void> _pumpHost(WidgetTester tester) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => presentSurface<void>(
                context,
                builder: (_) => const _StatefulProbe(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

void _resize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
}

void main() {
  testWidgets('compact window presents a full-width bottom sheet', (
    tester,
  ) async {
    _resize(tester, const Size(500, 800));
    addTearDown(tester.view.reset);

    await _pumpHost(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('style:bottomSheet'), findsOneWidget);
    final rect = tester.getRect(find.byType(_StatefulProbe));
    expect(rect.width, 500);
    expect(rect.bottom, 800);
    expect(rect.height, 200);
  });

  testWidgets('wide window presents a right-anchored side sheet', (
    tester,
  ) async {
    _resize(tester, const Size(1000, 800));
    addTearDown(tester.view.reset);

    await _pumpHost(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('style:sideSheet'), findsOneWidget);
    final rect = tester.getRect(find.byType(_StatefulProbe));
    expect(rect.width, 400);
    expect(rect.right, 1000);
    expect(rect.height, 800);
  });

  testWidgets('resize across the breakpoint morphs in place and keeps state', (
    tester,
  ) async {
    _resize(tester, const Size(500, 800));
    addTearDown(tester.view.reset);

    await _pumpHost(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('style:bottomSheet'), findsOneWidget);

    await tester.tap(find.text('inc'));
    await tester.pump();
    expect(find.text('count:1'), findsOneWidget);

    _resize(tester, const Size(1000, 800));
    await tester.pumpAndSettle();
    expect(find.text('style:sideSheet'), findsOneWidget);
    expect(find.text('count:1'), findsOneWidget);

    _resize(tester, const Size(500, 800));
    await tester.pumpAndSettle();
    expect(find.text('style:bottomSheet'), findsOneWidget);
    expect(find.text('count:1'), findsOneWidget);
  });
}
