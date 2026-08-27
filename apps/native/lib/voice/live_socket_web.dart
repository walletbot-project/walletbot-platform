import 'package:web_socket_channel/web_socket_channel.dart';

import 'live_socket.dart';

/// The browser owns the WebSocket keepalive, so there is no ping interval to
/// set here — see live_socket_io.dart for why native needs one.
const kLiveSocketPingInterval = Duration(seconds: 10);
const kLiveSocketConnectTimeout = Duration(seconds: 15);

LiveSocket connectLiveSocket(Uri uri) =>
    _ChannelLiveSocket(WebSocketChannel.connect(uri));

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
