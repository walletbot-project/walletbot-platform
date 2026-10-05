import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../convex/convex_client.dart';
import '../data/data.dart';
import '../fx/fx_rates_controller.dart';
import '../settings/display_settings.dart';
import '../telemetry/agent_metrics.dart';
import '../user_settings/default_currency_controller.dart';
import 'live_token_provider.dart';
import 'live_protocol.dart';
import 'voice_expense_command.dart';
import 'voice_event.dart';
import 'voice_session_repository.dart';
import 'voice_session_remote_sync.dart';
import 'gemini_voice_expense_command.dart';

class GeminiVoiceExpenseCommandFactory implements VoiceExpenseCommandFactory {
  GeminiVoiceExpenseCommandFactory({
    required this.repositories,
    required this.sessionRepository,
    this.remoteSync,
    this.agentMetrics,
    this.useAuthenticatedTokenAction = false,
    this.sessionToken,
    this.deviceId,
    this.buildMintArgs,
    this.displaySettings,
    this.defaultCurrency,
    this.fxRates,
    this.convexClient,
    this.liveToken = const String.fromEnvironment('GEMINI_LIVE_TOKEN'),
    this.convexSiteUrl = const String.fromEnvironment('CONVEX_SITE_URL'),
  });

  final AppRepositories repositories;
  final VoiceSessionRepository sessionRepository;
  final VoiceSessionRemoteSync? remoteSync;
  final AgentMetrics? agentMetrics;
  final bool useAuthenticatedTokenAction;
  final String? sessionToken;

  /// Device identity for the unauthenticated mint (`ClientInfo.deviceId`).
  /// This is what lets a local account run the agent at all; a remote account
  /// sends it too, and the server's session wins.
  final String? deviceId;

  /// Builds the mint request (platform identity, locale/timezone and the
  /// USER_CONTEXT snapshot from Drift) — see `agent_context.dart`. Null keeps
  /// the bare mint of older builds.
  final Future<Map<String, Object?>> Function()? buildMintArgs;

  /// Controllers the `updateSettings` tool writes through, passed by
  /// reference at factory construction (main.dart): the app-scoped display
  /// settings and this account's default-currency controller.
  final DisplaySettingsController? displaySettings;
  final DefaultCurrencyController? defaultCurrency;

  /// Device-scoped exchange-rate cache the `getExchangeRate` tool reads.
  final FxRatesController? fxRates;

  /// Null when the app runs without a Convex transport (widget tests, and a
  /// local account without the authenticated action); the HTTP endpoint is
  /// the only token source then.
  final ConvexClient? convexClient;
  final String liveToken;
  final String convexSiteUrl;
  GeminiVoiceExpenseCommand? _active;

  // Tokens are single-use with a 2-minute new-session window (see
  // packages/backend/convex/live/createToken.ts). The freshness bound stays
  // well inside that window so a consumed prefetch is always startable.
  static const _prefetchFreshness = Duration(seconds: 60);
  Future<LiveToken>? _prefetchedToken;
  DateTime? _prefetchedAt;

  @override
  VoiceExpenseCommand? get activeCommand {
    final active = _active;
    return active != null && active.isActive ? active : null;
  }

  @override
  void prefetchToken() {
    if (liveToken.isNotEmpty) return;
    final startedAt = _prefetchedAt;
    if (_prefetchedToken != null &&
        startedAt != null &&
        DateTime.now().difference(startedAt) < _prefetchFreshness) {
      return;
    }
    late final Future<LiveToken> future;
    future = fetchLiveToken(
      useAuthenticatedTokenAction: useAuthenticatedTokenAction,
      convexClient: convexClient,
      sessionToken: sessionToken,
      deviceId: deviceId,
      convexSiteUrl: convexSiteUrl,
      buildMintArgs: buildMintArgs,
      onPhase: (phase, extra) =>
          debugPrint('[voice] token prefetch $phase: $extra'),
      // Conversations open in chat; live mode always mints its own token.
      turnDetection: VoiceConversationMode.chat.turnDetection,
    );
    // A failed or credential-less prefetch must not poison the real connect:
    // drop it so takeFreshPrefetch hands out nothing and the command runs
    // its own fetch (with its own error surfacing).
    future.then(
      (token) {
        if (token.isEmpty && identical(_prefetchedToken, future)) {
          _prefetchedToken = null;
          _prefetchedAt = null;
        }
      },
      onError: (Object error) {
        debugPrint('[voice] token prefetch failed: $error');
        if (identical(_prefetchedToken, future)) {
          _prefetchedToken = null;
          _prefetchedAt = null;
        }
      },
    );
    _prefetchedToken = future;
    _prefetchedAt = DateTime.now();
  }

  /// Hands a still-fresh prefetched token fetch to a connecting command,
  /// consuming it. Null when none was started or it aged out of the token's
  /// new-session window.
  Future<LiveToken>? takeFreshPrefetch() {
    final future = _prefetchedToken;
    final startedAt = _prefetchedAt;
    _prefetchedToken = null;
    _prefetchedAt = null;
    if (future == null || startedAt == null) return null;
    if (DateTime.now().difference(startedAt) >= _prefetchFreshness) {
      return null;
    }
    return future;
  }

  @override
  VoiceExpenseCommand create() {
    final existing = activeCommand;
    if (existing != null) return existing;
    late final GeminiVoiceExpenseCommand command;
    command = GeminiVoiceExpenseCommand(
      repositories: repositories,
      sessionRepository: sessionRepository,
      remoteSync: remoteSync,
      agentMetrics: agentMetrics,
      useAuthenticatedTokenAction: useAuthenticatedTokenAction,
      sessionToken: sessionToken,
      deviceId: deviceId,
      buildMintArgs: buildMintArgs,
      displaySettings: displaySettings,
      defaultCurrency: defaultCurrency,
      fxRates: fxRates,
      convexClient: convexClient,
      liveToken: liveToken,
      convexSiteUrl: convexSiteUrl,
      takePrefetchedToken: takeFreshPrefetch,
      onEnded: () {
        if (identical(_active, command)) _active = null;
      },
    );
    _active = command;
    return command;
  }

  @override
  Future<List<VoiceEvent>> restorableHistory() async {
    final rows = await sessionRepository.resumableConversationEvents(
      types: kConversationEventTypes,
    );
    final events = <VoiceEvent>[];
    for (final row in rows) {
      final decoded = jsonDecode(row.payloadJson);
      if (decoded is! Map) continue;
      final event = voiceEventFromRecord(
        type: row.type,
        payload: decoded.cast<String, Object?>(),
        at: DateTime.fromMillisecondsSinceEpoch(row.occurredAt.toInt()),
      );
      if (event != null) events.add(event);
    }
    return events;
  }

  @override
  Future<void> discardRestorableSession() async {
    await sessionRepository.endResumableSession();
    remoteSync?.schedule();
  }

  @override
  Future<String?> restorableSessionId() =>
      sessionRepository.resumableSessionId();

  Future<void> dispose() async {
    await _active?.dispose();
    _active = null;
    await remoteSync?.dispose();
  }
}
