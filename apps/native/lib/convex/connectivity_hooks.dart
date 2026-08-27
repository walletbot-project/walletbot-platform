import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../connectivity_hooks.dart';
import 'convex_client.dart';

/// Wires platform signals into the client's proactive reconnect triggers
/// (docs/dart-convex-client.md §5.1): connectivity regained and app resumed.
///
/// These are hints, never gates — the client never refuses to connect because
/// connectivity_plus claims offline (captive portals and VPNs lie in both
/// directions); it only reconnects *sooner* when a usable network appears.
class ConvexConnectivityHooks {
  ConvexConnectivityHooks(ConvexClient client, {Connectivity? connectivity})
    : _hooks = ConnectivityLifecycleHooks(
        onNetworkAvailable: client.onNetworkAvailable,
        onNetworkChanged: client.onNetworkChanged,
        onAppResumed: client.onAppResumed,
        connectivity: connectivity,
      );

  final ConnectivityLifecycleHooks _hooks;

  @visibleForTesting
  ConnectivityLifecycleHooks get hooks => _hooks;

  void attach() => _hooks.attach();

  void detach() => _hooks.detach();
}
