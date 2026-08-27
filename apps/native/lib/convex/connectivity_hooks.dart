import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

import 'convex_client.dart';

/// Wires platform signals into the client's proactive reconnect triggers
/// (docs/dart-convex-client.md §5.1): connectivity regained and app resumed.
///
/// These are hints, never gates — the client never refuses to connect because
/// connectivity_plus claims offline (captive portals and VPNs lie in both
/// directions); it only reconnects *sooner* when a usable network appears.
class ConvexConnectivityHooks {
  ConvexConnectivityHooks(this._client, {Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final ConvexClient _client;
  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  AppLifecycleListener? _lifecycleListener;
  bool _hadUsableNetwork = true;

  void attach() {
    _subscription ??= _connectivity.onConnectivityChanged.listen((results) {
      final usable = results.any(
        (r) =>
            r != ConnectivityResult.none && r != ConnectivityResult.bluetooth,
      );
      if (usable && !_hadUsableNetwork) {
        _client.onNetworkAvailable();
      }
      _hadUsableNetwork = usable;
    });
    _lifecycleListener ??= AppLifecycleListener(onResume: _client.onAppResumed);
  }

  void detach() {
    _subscription?.cancel();
    _subscription = null;
    _lifecycleListener?.dispose();
    _lifecycleListener = null;
  }
}
