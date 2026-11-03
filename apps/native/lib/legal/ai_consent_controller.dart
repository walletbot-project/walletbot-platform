import 'package:app/app_config/client_info.dart';
import 'package:app/convex/convex_client.dart';
import 'package:app/legal/legal_versions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Consent to send this account's data to the third-party AI providers, asked
/// for once before the first agent session.
///
/// Apple guideline 5.1.2(i) wants the disclosure and the permission *in the
/// app*, not only in the Privacy Policy, so this gate sits in front of
/// `VoiceScreen._startSession` rather than at launch. It is deliberately NOT
/// one of [LegalDocumentKind]'s documents: those drive the launch gate, and a
/// third one there would hard-block every existing account on next launch.
///
/// Storage is per device and per account, in secure storage. A new device asks
/// again, which is the behaviour we want: the permission is granted where the
/// disclosure was actually read. For a remote account the backend also keeps
/// the authoritative append-only row, and the mint checks it
/// (`v1/live/actions.ts`), so the local record is a fast path, never the only
/// evidence.
class AiConsentController extends ChangeNotifier {
  AiConsentController({
    required this.accountId,
    required this.isRemote,
    required ClientInfo clientInfo,
    required String locale,
    FlutterSecureStorage? storage,
    ConvexClient? client,
  }) : _clientInfo = clientInfo,
       _locale = locale,
       _storage = storage ?? const FlutterSecureStorage(),
       _client = client;

  final String accountId;
  final bool isRemote;
  final ClientInfo _clientInfo;
  final String _locale;
  final FlutterSecureStorage _storage;
  final ConvexClient? _client;

  /// Where the device record of [accountId]'s consent lives. Public so a local
  /// account's promotion can read it without a controller.
  static String storageKey(String accountId) => 'ai_consent:$accountId';

  String get _key => storageKey(accountId);

  String? _accepted;
  bool _resolved = false;

  /// False until [load] has answered. The caller waits rather than showing the
  /// sheet to someone who already consented.
  bool get resolved => _resolved;

  /// Whether this platform asks at all. iOS only, by product decision: the
  /// rejection that motivated the gate is App Store review, and Android/web
  /// keep the flow they have.
  bool get isApplicable => _clientInfo.platform == 'ios';

  /// Whether the agent may run without showing the sheet.
  bool get accepted {
    if (!isApplicable) return true;
    final accepted = _accepted;
    return accepted != null &&
        isLegalVersionAtLeast(accepted, aiConsentVersion);
  }

  /// Restores the device record. Never throws: a storage failure means we ask
  /// again, which is the safe direction for a consent gate.
  Future<void> load() async {
    if (!isApplicable) {
      _resolved = true;
      notifyListeners();
      return;
    }
    try {
      _accepted = await _storage.read(key: _key);
    } catch (e) {
      debugPrint('ai_consent: reading stored consent failed: $e');
      _accepted = null;
    }
    _resolved = true;
    notifyListeners();
  }

  /// Records the consent the sheet collected.
  ///
  /// The backend write happens FIRST for a remote account and a failure
  /// propagates: the mint refuses without a server row, so storing the device
  /// record on a failed write would leave the user consenting to a session
  /// that is then refused with no explanation.
  Future<void> accept() async {
    if (isRemote) {
      final client = _client;
      if (client == null) throw StateError('ai_consent: no ConvexClient');
      await client.mutation<Object?>('v1/legal/mutations:acceptAiConsent', {
        'platform': _clientInfo.platform,
        'appVersion': _clientInfo.appVersion,
        'locale': _locale,
      });
    }

    try {
      await _storage.write(key: _key, value: aiConsentVersion);
    } catch (e) {
      // The consent stands — it is recorded server-side for a remote account
      // and the session may start. Only the fast path is lost, so the sheet
      // shows again next launch.
      debugPrint('ai_consent: storing consent failed: $e');
    }
    _accepted = aiConsentVersion;
    _resolved = true;
    notifyListeners();
  }
}
