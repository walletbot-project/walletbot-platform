import 'package:app/shared/adaptive_detail_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Probe extends StatefulWidget {
  const _Probe({super.key, required this.inSheet});

  final bool inSheet;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  int count = 0;

  @override
  Widget build(BuildContext context) {
    return Material(
      child: SizedBox(
        height: 200,
        child: Column(
          children: [
            Text('mode:${widget.inSheet ? 'sheet' : 'pane'}'),
            Text('count:$count'),
            TextButton(
              onPressed: () => setState(() => count++),
              child: const Text('inc'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Harness extends StatefulWidget {
  const _Harness();

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  bool _open = false;
  GlobalKey _key = GlobalKey(debugLabel: 'probe');

  void open() {
    setState(() {
      _key = GlobalKey(debugLabel: 'probe');
      _open = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveDetailView(
      list: Scaffold(
        body: Center(
          child: TextButton(onPressed: open, child: const Text('open')),
        ),
      ),
      hasDetail: _open,
      detailBuilder: (context, {required bool inSheet}) =>
          _open ? _Probe(key: _key, inSheet: inSheet) : null,
      onSheetDismissed: () => setState(() => _open = false),
      placeholder: const Center(child: Text('placeholder')),
      isActiveTab: true,
    );
  }
}

void _resize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
}

void main() {
  testWidgets('pane → sheet handoff on shrink keeps State, is a real sheet', (
    tester,
  ) async {
    _resize(tester, const Size(1200, 800));
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: _Harness()));
    expect(find.text('placeholder'), findsOneWidget);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('mode:pane'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);

    await tester.tap(find.text('inc'));
    await tester.pump();
    expect(find.text('count:1'), findsOneWidget);

    _resize(tester, const Size(500, 800));
    await tester.pumpAndSettle();

    // State survived, and the presentation is a genuine modal bottom sheet.
    expect(find.text('count:1'), findsOneWidget);
    expect(find.text('mode:sheet'), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('sheet → pane handoff on grow keeps State, removes the sheet', (
    tester,
  ) async {
    _resize(tester, const Size(500, 800));
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: _Harness()));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle(); // normal animated sheet entrance
    expect(find.byType(BottomSheet), findsOneWidget);

    await tester.tap(find.text('inc'));
    await tester.pump();
    await tester.tap(find.text('inc'));
    await tester.pump();
    expect(find.text('count:2'), findsOneWidget);

    _resize(tester, const Size(1200, 800));
    await tester.pumpAndSettle();

    expect(find.text('count:2'), findsOneWidget);
    expect(find.text('mode:pane'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);

    // Round-trip: shrink again — still alive, back in a sheet.
    _resize(tester, const Size(500, 800));
    await tester.pumpAndSettle();
    expect(find.text('count:2'), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('scrim dismissal clears the selection', (tester) async {
    _resize(tester, const Size(500, 800));
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: _Harness()));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);

    await tester.tapAt(const Offset(20, 20)); // scrim, above the sheet
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(_Probe), findsNothing);

    // Selection was cleared: growing shows the empty pane, not the probe.
    _resize(tester, const Size(1200, 800));
    await tester.pumpAndSettle();
    expect(find.text('placeholder'), findsOneWidget);
  });
}
