import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'live_socket.dart';

/// WebSocket-level keepalive on the Gemini socket.
///
/// Gemini Live sends nothing while a session is idle, so a socket whose
/// network died under it (WiFi → cellular, VPN flap, NAT timeout) stays open
/// as far as Dart is concerned and every frame written to it is dropped
/// silently until the OS TCP stack gives up, tens of seconds later. That is
/// what made a typed message sit unanswered for 10-20 s. `dart:io` closes the
/// socket when a pong does not come back within the interval, so a half-open
/// socket surfaces as a normal `onDone` and the reconnect path takes over.
const kLiveSocketPingInterval = Duration(seconds: 10);

/// Bounds DNS + TLS + the WS upgrade. Without it a connect against a black
/// hole sits until the OS times out.
const kLiveSocketConnectTimeout = Duration(seconds: 15);

LiveSocket connectLiveSocket(Uri uri) => _ChannelLiveSocket(
  IOWebSocketChannel.connect(
    uri,
    pingInterval: kLiveSocketPingInterval,
    connectTimeout: kLiveSocketConnectTimeout,
  ),
);

class _ChannelLiveSocket implements LiveSocket {
  _ChannelLiveSocket(this._channel);

  final WebSocketChannel _channel;

  @override
  Stream<dynamic> get messages => _channel.stream;

  @override
  void send(String data) => _channel.sink.add(data);

  @override
  Future<void> close([int? code, String? reason]) =>
      _channel.sink.close(code, reason);

  @override
  int? get closeCode => _channel.closeCode;

  @override
  String? get closeReason => _channel.closeReason;
}
