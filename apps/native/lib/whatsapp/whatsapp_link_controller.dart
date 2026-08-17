import 'dart:async';

import 'package:app/sync/wire.dart';
import 'package:convex_flutter/convex_flutter.dart';
import 'package:flutter/foundation.dart';

/// The two backend calls the link controller makes.
///
/// Exists because `ConvexClient` has a private constructor and a singleton
/// `instance` getter that throws under `flutter test`, so it cannot be faked or
/// subclassed. Narrowing the dependency to these two methods is what makes the
/// parsing and state transitions below testable at all — [ConvexLinkApi] is the
/// only part that then needs a real client.
abstract interface class WhatsappLinkApi {
  Future<String> query(String name, Map<String, dynamic> args);

  Future<String> mutation({
    required String name,
    required Map<String, dynamic> args,
  });
}

/// Production [WhatsappLinkApi], backed by the real Convex client.
///
/// Resolves `ConvexClient.instance` lazily, per call, so constructing this for
/// a local-only account never requires `ConvexClient.initialize()`.
class ConvexLinkApi implements WhatsappLinkApi {
  const ConvexLinkApi({ConvexClient? client}) : _client = client;

  final ConvexClient? _client;
  ConvexClient get _resolved => _client ?? ConvexClient.instance;

  @override
  Future<String> query(String name, Map<String, dynamic> args) =>
      _resolved.query(name, args);

  @override
  Future<String> mutation({
    required String name,
    required Map<String, dynamic> args,
  }) => _resolved.mutation(name: name, args: args);
}

enum WhatsappLinkState {
  /// Never loaded, or reloading after a failure.
  loading,

  /// Loaded. Read [numbers], [available] and [code].
  ready,

  /// The load itself failed — network, auth, or a backend error.
  failed,
}

@immutable
class LinkedWhatsappNumber {
  const LinkedWhatsappNumber({required this.waId, this.linkedAt});

  /// WhatsApp's own identifier for the number. Never reconstructed from a
  /// phone number: for Argentina and several other countries the two differ.
  /// See `docs/whatsapp-platform.md` § Part 6.
  final String waId;
  final DateTime? linkedAt;
}

@immutable
class WhatsappLinkCode {
  const WhatsappLinkCode({
    required this.code,
    required this.expiresAt,
    this.deepLink,
  });

  /// Display form, already hyphenated by the backend (`A1B2-C3D4`).
  final String code;
  final DateTime expiresAt;

  /// `wa.me` link that opens WhatsApp with the code prefilled. Null when the
  /// deployment has no business number configured.
  final String? deepLink;

  bool get isExpired => !expiresAt.isAfter(DateTime.now());
}

/// Connects this device's WhatsApp number to the signed-in Wallet Bot account.
///
/// The backend webhook that receives WhatsApp messages is public and
/// unauthenticated, so a phone number proves nothing on its own. Linking
/// therefore starts here, in an authenticated session: the backend mints a
/// short-lived code (`v1/whatsapp/mutations:createLinkCode`) and the *user*
/// sends it over WhatsApp. Holding both is the proof.
///
/// Unlike `DefaultCurrencyController` this deliberately caches nothing. That
/// controller caches because a default currency is needed offline to prefill a
/// form; link state is only ever read on a screen that cannot do anything
/// without the network, and a cached code would be a stale credential. Offline
/// shows an error with a retry instead of a plausible-looking lie.
///
/// [isRemote] gates every call: a local-only account has no backend user, so
/// there is nothing to link it to.
class WhatsappLinkController extends ChangeNotifier {
  WhatsappLinkController({required this.isRemote, WhatsappLinkApi? api})
    : _api = api ?? const ConvexLinkApi();

  final bool isRemote;
  final WhatsappLinkApi _api;

  WhatsappLinkState _state = WhatsappLinkState.loading;
  WhatsappLinkState get state => _state;

  List<LinkedWhatsappNumber> _numbers = const [];
  List<LinkedWhatsappNumber> get numbers => _numbers;

  /// False when the backend has no `WHATSAPP_BUSINESS_NUMBER`, i.e. the flow
  /// cannot be completed. The UI hides the entry point rather than offering a
  /// dead end.
  bool _available = false;
  bool get available => _available;

  String? _businessNumber;
  String? get businessNumber => _businessNumber;

  WhatsappLinkCode? _code;
  WhatsappLinkCode? get code => _code;

  Object? _loadError;
  Object? get loadError => _loadError;

  bool _busy = false;

  /// True while a mutation is in flight, so the UI can disable its buttons.
  bool get busy => _busy;

  bool get isLinked => _numbers.isNotEmpty;

  // Clears the code the moment it expires, so the screen never shows a code
  // that would be rejected. One-shot rather than a periodic tick: a periodic
  // timer would make `pumpAndSettle` in widget tests never settle.
  Timer? _expiryTimer;

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    super.dispose();
  }

  /// Loads the current link status. Never throws — the failure is exposed as
  /// [state] so the screen can offer a retry.
  Future<void> load() async {
    if (!isRemote) {
      _state = WhatsappLinkState.ready;
      _numbers = const [];
      _available = false;
      notifyListeners();
      return;
    }

    _state = WhatsappLinkState.loading;
    _loadError = null;
    notifyListeners();

    try {
      final raw = await _api.query('v1/whatsapp/queries:linkStatus', {});
      final decoded = decodeConvexResponse(raw);
      if (decoded is! Map) {
        throw const FormatException('linkStatus did not return an object');
      }
      _available = decoded['available'] == true;
      _businessNumber = decoded['businessNumber'] as String?;
      _numbers = _parseNumbers(decoded['numbers']);
      _state = WhatsappLinkState.ready;
    } catch (e) {
      debugPrint('whatsappLink: load failed: $e');
      _loadError = e;
      _state = WhatsappLinkState.failed;
    }
    notifyListeners();
  }

  /// Mints a link code. Rethrows so the caller can surface a toast — this only
  /// ever runs from an explicit tap, never a background path.
  Future<void> createCode() async {
    if (!isRemote || _busy) return;
    _busy = true;
    notifyListeners();
    try {
      final raw = await _api.mutation(
        name: 'v1/whatsapp/mutations:createLinkCode',
        args: const {},
      );
      final decoded = decodeConvexResponse(raw);
      if (decoded is! Map) {
        throw const FormatException('createLinkCode did not return an object');
      }
      final code = decoded['code'];
      final expiresAt = _parseTimestamp(decoded['expiresAt']);
      if (code is! String || expiresAt == null) {
        throw const FormatException('createLinkCode returned an unusable code');
      }
      _code = WhatsappLinkCode(
        code: code,
        expiresAt: expiresAt,
        deepLink: decoded['deepLink'] as String?,
      );
      _scheduleExpiry(expiresAt);
    } catch (e) {
      debugPrint('whatsappLink: createCode failed: $e');
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Disconnects [waId], or every linked number when it is omitted. Reloads on
  /// success so the list reflects what the backend actually did.
  Future<void> unlink({String? waId}) async {
    if (!isRemote || _busy) return;
    _busy = true;
    notifyListeners();
    try {
      await _api.mutation(
        name: 'v1/whatsapp/mutations:unlink',
        args: {'waId': ?waId},
      );
      // Unlinking revokes pending codes server-side, so drop ours too rather
      // than leaving a code on screen that can no longer link anything.
      _clearCode();
    } catch (e) {
      debugPrint('whatsappLink: unlink failed: $e');
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
    await load();
  }

  /// Drops the on-screen code without touching the backend. Used when the user
  /// dismisses it — the code stays valid until it expires or is redeemed.
  void dismissCode() {
    if (_code == null) return;
    _clearCode();
    notifyListeners();
  }

  void _clearCode() {
    _code = null;
    _expiryTimer?.cancel();
    _expiryTimer = null;
  }

  void _scheduleExpiry(DateTime expiresAt) {
    _expiryTimer?.cancel();
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining.isNegative || remaining == Duration.zero) {
      _code = null;
      _expiryTimer = null;
      return;
    }
    _expiryTimer = Timer(remaining, () {
      _code = null;
      _expiryTimer = null;
      notifyListeners();
    });
  }

  static List<LinkedWhatsappNumber> _parseNumbers(Object? raw) {
    if (raw is! List) return const [];
    final parsed = <LinkedWhatsappNumber>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final waId = entry['waId'];
      if (waId is! String || waId.isEmpty) continue;
      parsed.add(
        LinkedWhatsappNumber(
          waId: waId,
          linkedAt: _parseTimestamp(entry['linkedAt']),
        ),
      );
    }
    return parsed;
  }

  // The backend stores these as `v.number()` (float64), so they arrive as a
  // plain JSON number rather than an int64 envelope.
  static DateTime? _parseTimestamp(Object? raw) {
    if (raw is num) {
      return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    }
    if (raw is BigInt) {
      return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    }
    return null;
  }
}
