import 'package:app/connectivity_hooks.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';

/// The edge detector behind both the Convex client's and the Live session's
/// proactive reconnects. Getting these edges wrong is invisible until a device
/// is on a train.
void main() {
  late List<String> fired;
  late ConnectivityLifecycleHooks hooks;

  setUp(() {
    fired = [];
    hooks = ConnectivityLifecycleHooks(
      onNetworkAvailable: () => fired.add('available'),
      onNetworkChanged: () => fired.add('changed'),
      onAppResumed: () => fired.add('resumed'),
    );
  });

  test('a cold start with no network still fires when the radio comes up', () {
    // Seeding the detector "online" swallowed exactly this edge: launch in
    // airplane mode, turn WiFi on, nothing woke the sockets.
    hooks.onResults(const [ConnectivityResult.none]);
    expect(fired, isEmpty);
    hooks.onResults(const [ConnectivityResult.wifi]);
    expect(fired, ['available']);
  });

  test('the very first usable reading counts as network available', () {
    hooks.onResults(const [ConnectivityResult.mobile]);
    expect(fired, ['available']);
  });

  test('offline then online fires available, not changed', () {
    hooks.onResults(const [ConnectivityResult.wifi]);
    hooks.onResults(const [ConnectivityResult.none]);
    hooks.onResults(const [ConnectivityResult.mobile]);
    expect(fired, ['available', 'available']);
  });

  test('wifi to cellular with no outage fires changed', () {
    // The case the sockets cannot see: no offline edge is ever reported, but
    // every connection bound to the old route is already dead.
    hooks.onResults(const [ConnectivityResult.wifi]);
    hooks.onResults(const [ConnectivityResult.mobile]);
    expect(fired, ['available', 'changed']);
  });

  test('a repeated reading fires nothing', () {
    hooks.onResults(const [ConnectivityResult.wifi]);
    hooks.onResults(const [ConnectivityResult.wifi]);
    hooks.onResults(const [ConnectivityResult.wifi]);
    expect(fired, ['available']);
  });

  test('order within a multi-interface reading is not a change', () {
    hooks.onResults(const [ConnectivityResult.wifi, ConnectivityResult.vpn]);
    hooks.onResults(const [ConnectivityResult.vpn, ConnectivityResult.wifi]);
    expect(fired, ['available']);
  });

  test('a VPN coming up over wifi fires changed', () {
    hooks.onResults(const [ConnectivityResult.wifi]);
    hooks.onResults(const [ConnectivityResult.wifi, ConnectivityResult.vpn]);
    expect(fired, ['available', 'changed']);
  });

  test('bluetooth-only is not a usable network', () {
    hooks.onResults(const [ConnectivityResult.bluetooth]);
    expect(fired, isEmpty);
    hooks.onResults(const [ConnectivityResult.wifi]);
    expect(fired, ['available']);
  });
}
