import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Replicates the Activity detail presentation choreography (see
/// `lib/screens/activity.dart`): one GlobalKey'd stateful widget rendered in
/// a split pane on wide windows and in a REAL MaterialPageRoute on small
/// ones, with a bridge layer covering handoff frames. These tests prove the
/// mechanism the screen relies on: the widget's State survives resize
/// handoffs in BOTH directions, and the small-window presentation is a
/// genuine route (automatic back button, poppable).
class _Probe extends StatefulWidget {
  const _Probe({super.key});

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  int count = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('detail')),
      body: Column(
        children: [
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

class _InstantEntranceMaterialPageRoute<T> extends MaterialPageRoute<T> {
  _InstantEntranceMaterialPageRoute({required super.builder});

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 300);
}

class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool _open = false;
  final GlobalKey _key = GlobalKey(debugLabel: 'probe');
  MaterialPageRoute<void>? _route;

  bool get _split => MediaQuery.sizeOf(context).width >= 900;

  void open() {
    setState(() => _open = true);
    if (!_split) _push(instant: false);
  }

  void _push({required bool instant}) {
    final route = instant
        ? _InstantEntranceMaterialPageRoute<void>(
            builder: (_) => _buildRouteDetail(),
          )
        : MaterialPageRoute<void>(builder: (_) => _buildRouteDetail());
    _route = route;
    unawaited(
      Navigator.of(context).push(route).then((_) {
        if (!mounted || !identical(_route, route)) return;
        _route = null;
        setState(() => _open = false);
      }),
    );
    setState(() {});
  }

  Widget _buildRouteDetail() =>
      _open ? _Probe(key: _key) : const SizedBox.shrink();

  void _reconcile() {
    if (!mounted) return;
    final needsRoute = !_split && _open;
    final route = _route;
    if (needsRoute && route == null) {
      _push(instant: true);
    } else if (!needsRoute && route != null) {
      _route = null;
      Navigator.of(context).removeRoute(route);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final needsRoute = !_split && _open;
    if (needsRoute != (_route != null)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reconcile());
    }
    final detail = _open ? _Probe(key: _key) : null;
    if (_split) {
      // The pane may only claim the key once the route has released it —
      // inflating it while the (still-visible) route owns it would steal the
      // Element mid-frame: duplicate-key assert, hole in the route.
      final pane = _route == null ? detail : null;
      return Scaffold(
        body: Row(
          children: [
            TextButton(onPressed: open, child: const Text('open')),
            Expanded(child: pane ?? const Text('empty')),
          ],
        ),
      );
    }
    final bridge = _route == null ? detail : null;
    return Stack(
      fit: StackFit.expand,
      children: [
        Scaffold(
          body: TextButton(onPressed: open, child: const Text('open')),
        ),
        ?bridge,
      ],
    );
  }
}

void _resize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
}

void main() {
  testWidgets('pane → route handoff on shrink keeps State, is a real route', (
    tester,
  ) async {
    _resize(tester, const Size(1200, 800));
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: _Host()));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(BackButton), findsNothing); // inline pane, no route

    await tester.tap(find.text('inc'));
    await tester.pump();
    expect(find.text('count:1'), findsOneWidget);

    _resize(tester, const Size(500, 800));
    await tester.pumpAndSettle();

    // State survived the handoff, and the presentation is a genuine route:
    // the probe's AppBar gained the automatic back button.
    expect(find.text('count:1'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
  });

  testWidgets('route → pane handoff on grow keeps State, removes the route', (
    tester,
  ) async {
    _resize(tester, const Size(500, 800));
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: _Host()));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle(); // normal animated push
    expect(find.byType(BackButton), findsOneWidget);

    await tester.tap(find.text('inc'));
    await tester.pump();
    await tester.tap(find.text('inc'));
    await tester.pump();
    expect(find.text('count:2'), findsOneWidget);

    _resize(tester, const Size(1200, 800));
    await tester.pumpAndSettle();

    expect(find.text('count:2'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing); // route is gone
    // Round-trip: shrink again — still alive, back in a route.
    _resize(tester, const Size(500, 800));
    await tester.pumpAndSettle();
    expect(find.text('count:2'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
  });

  testWidgets('back button pops the route and clears the selection', (
    tester,
  ) async {
    _resize(tester, const Size(500, 800));
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: _Host()));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(_Probe), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });
}
