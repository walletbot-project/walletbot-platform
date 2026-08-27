export 'live_socket_io.dart'
    if (dart.library.js_interop) 'live_socket_web.dart';

/// Minimal socket surface for the Gemini Live connection, so the whole
/// connection lifecycle (keepalive, reconnect, context seeding, stale-audio
/// handling) runs against a scriptable fake under plain `flutter test`.
/// Mirrors `ConvexWebSocket` in the Convex client.
abstract interface class LiveSocket {
  /// Incoming frames, text or binary. Done = socket closed.
  Stream<dynamic> get messages;
  void send(String data);
  Future<void> close([int? code, String? reason]);
  int? get closeCode;
  String? get closeReason;
}

typedef LiveSocketFactory = LiveSocket Function(Uri uri);
