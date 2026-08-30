import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Platform signals that make a dead socket recover sooner: a usable network
/// appearing, the set of network interfaces changing under a live socket, and
/// the app coming back to the foreground.
///
/// These are hints, never gates. Nothing here decides whether a connection is
/// allowed — captive portals and VPNs make connectivity_plus lie in both
/// directions — they only shorten the wait when the OS says something moved.
/// Both the Convex client and the Gemini Live session subscribe.
class ConnectivityLifecycleHooks {
  ConnectivityLifecycleHooks({
    required this.onNetworkAvailable,
    required this.onNetworkChanged,
    required this.onAppResumed,
    Connectivity? connectivity,
  }) : _connectivity = connectivity ?? Connectivity();

  /// Offline → online. Anything waiting out a backoff should retry now.
  final void Function() onNetworkAvailable;

  /// The interface set changed while still online (WiFi → cellular, VPN up or
  /// down). No outage is ever reported for this, but every socket bound to
  /// the old route is already dead: it stays `open` and swallows writes until
  /// the OS TCP stack gives up. Subscribers force a reconnect.
  final void Function() onNetworkChanged;

  final void Function() onAppResumed;
  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  AppLifecycleListener? _lifecycleListener;

  /// Null until the first reading lands. Starting at "unknown" rather than
  /// "online" is what makes a cold start in airplane mode fire the hint when
  /// the radio comes back — seeded online, that first edge was swallowed.
  Set<ConnectivityResult>? _last;

  static bool _isUsable(Iterable<ConnectivityResult> results) => results.any(
    (r) => r != ConnectivityResult.none && r != ConnectivityResult.bluetooth,
  );

  void attach() {
    _subscription ??= _connectivity.onConnectivityChanged.listen(onResults);
    _lifecycleListener ??= AppLifecycleListener(onResume: onAppResumed);
    // Seed the edge detector from the current state instead of assuming
    // online, so launching offline still gets woken when the radio comes up.
    unawaited(
      _connectivity.checkConnectivity().then(
        (results) => _last ??= results.toSet(),
        onError: (Object _) {},
      ),
    );
  }

  @visibleForTesting
  void onResults(List<ConnectivityResult> results) {
    final next = results.toSet();
    final previous = _last;
    _last = next;
    if (!_isUsable(next)) return;
    if (previous == null || !_isUsable(previous)) {
      onNetworkAvailable();
      return;
    }
    if (!setEquals(previous, next)) onNetworkChanged();
  }

  void detach() {
    _subscription?.cancel();
    _subscription = null;
    _lifecycleListener?.dispose();
    _lifecycleListener = null;
    _last = null;
  }
}
