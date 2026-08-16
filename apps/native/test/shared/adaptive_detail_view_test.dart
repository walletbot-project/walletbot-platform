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

/// Form probe with its own Scaffold/AppBar, so route mode grows the
/// automatic back button — proof it is a genuine pushed route.
class _FormProbe extends StatefulWidget {
  const _FormProbe({super.key});

  @override
  State<_FormProbe> createState() => _FormProbeState();
}

class _FormProbeState extends State<_FormProbe> {
  int count = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('form')),
      body: Column(
        children: [
          Text('fcount:$count'),
          TextButton(
            onPressed: () => setState(() => count++),
            child: const Text('finc'),
          ),
        ],
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
  bool _formOpen = false;
  GlobalKey _formKey = GlobalKey(debugLabel: 'form');

  void open() {
    setState(() {
      _key = GlobalKey(debugLabel: 'probe');
      _open = true;
      _formOpen = false;
    });
  }

  void openForm() {
    setState(() {
      _formKey = GlobalKey(debugLabel: 'form');
      _formOpen = true;
      _open = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveDetailView(
      list: Scaffold(
        body: Column(
          children: [
            TextButton(onPressed: open, child: const Text('open')),
            TextButton(onPressed: openForm, child: const Text('openForm')),
          ],
        ),
      ),
      hasDetail: _open,
      detailBuilder: (context, {required bool inSheet}) =>
          _open ? _Probe(key: _key, inSheet: inSheet) : null,
      onSheetDismissed: () => setState(() => _open = false),
      hasForm: _formOpen,
      formBuilder: (context, {required bool inRoute}) =>
          _formOpen ? _FormProbe(key: _formKey) : null,
      onFormDismissed: () => setState(() => _formOpen = false),
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

  testWidgets('form: pane ⇄ route handoffs keep State; route is genuine', (
    tester,
  ) async {
    _resize(tester, const Size(1200, 800));
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: _Harness()));
    await tester.tap(find.text('openForm'));
    await tester.pumpAndSettle();
    expect(find.byType(_FormProbe), findsOneWidget); // inline pane
    expect(find.byType(BackButton), findsNothing);

    await tester.tap(find.text('finc'));
    await tester.pump();
    expect(find.text('fcount:1'), findsOneWidget);

    _resize(tester, const Size(500, 800));
    await tester.pumpAndSettle();
    // State survived the shrink, and the presentation is a real route.
    expect(find.text('fcount:1'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);

    await tester.tap(find.text('finc'));
    await tester.pump();
    _resize(tester, const Size(1200, 800));
    await tester.pumpAndSettle();
    expect(find.text('fcount:2'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing); // route removed
  });

  testWidgets('form: fresh compact open is an animated route; back clears', (
    tester,
  ) async {
    _resize(tester, const Size(500, 800));
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: _Harness()));
    await tester.tap(find.text('openForm'));
    await tester.pumpAndSettle();
    expect(find.byType(BackButton), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(_FormProbe), findsNothing);

    // Cleared: growing shows the empty pane.
    _resize(tester, const Size(1200, 800));
    await tester.pumpAndSettle();
    expect(find.text('placeholder'), findsOneWidget);
  });

  testWidgets('medium window frames the detail as a real dialog', (
    tester,
  ) async {
    _resize(tester, const Size(800, 800));
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: _Harness()));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Too narrow to split, too wide for a bottom sheet: the panel
    // presentation (mode:pane) inside a real dialog route.
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('mode:pane'), findsOneWidget);
    expect(find.text('placeholder'), findsNothing);
  });

  testWidgets('sheet → dialog → pane handoffs all keep State', (tester) async {
    _resize(tester, const Size(500, 800));
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: _Harness()));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);

    await tester.tap(find.text('inc'));
    await tester.pump();
    await tester.tap(find.text('inc'));
    await tester.pump();
    expect(find.text('count:2'), findsOneWidget);

    // Sheet → dialog.
    _resize(tester, const Size(800, 800));
    await tester.pumpAndSettle();
    expect(find.text('count:2'), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);

    // Dialog → pane.
    _resize(tester, const Size(1200, 800));
    await tester.pumpAndSettle();
    expect(find.text('count:2'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(VerticalDivider), findsOneWidget);

    // All the way back down, in one step.
    _resize(tester, const Size(500, 800));
    await tester.pumpAndSettle();
    expect(find.text('count:2'), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('dismissing the dialog clears the selection', (tester) async {
    _resize(tester, const Size(800, 800));
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: _Harness()));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);

    await tester.tapAt(const Offset(10, 10)); // scrim, outside the dialog
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);

    // Selection was cleared, not merely hidden: growing shows the empty pane.
    _resize(tester, const Size(1200, 800));
    await tester.pumpAndSettle();
    expect(find.text('placeholder'), findsOneWidget);
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
