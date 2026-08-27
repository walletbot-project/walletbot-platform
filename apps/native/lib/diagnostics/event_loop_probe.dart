import 'dart:async';

import 'package:flutter/foundation.dart';

/// Measures how late a fixed-period timer actually fires. A timer can only run
/// once the isolate is free, so its lateness *is* the time the isolate spent
/// blocked. This separates "the network is slow" from "we could not process
/// the frame that already arrived", which look identical from the outside:
/// the agent goes quiet, then streams in bursts, with no disconnect and
/// nothing in the UI to show for it.
///
/// Diagnostic only — never armed in release.
class EventLoopProbe {
  EventLoopProbe({
    this.period = const Duration(milliseconds: 200),
    this.reportThreshold = const Duration(milliseconds: 400),
  });

  final Duration period;

  /// Only lateness above this is worth a line in the log.
  final Duration reportThreshold;

  Timer? _timer;

  void start() {
    if (kReleaseMode || _timer != null) return;
    final clock = Stopwatch()..start();
    var expectedMicros = 0;
    _timer = Timer.periodic(period, (_) {
      expectedMicros += period.inMicroseconds;
      final lateMicros = clock.elapsedMicroseconds - expectedMicros;
      if (lateMicros >= reportThreshold.inMicroseconds) {
        debugPrint(
          '[stall] event loop blocked ${(lateMicros / 1000).round()}ms',
        );
      }
      // Lateness is cumulative against a fixed schedule; rebase so one long
      // stall does not keep reporting forever.
      expectedMicros = clock.elapsedMicroseconds;
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
