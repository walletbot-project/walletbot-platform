import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:app/app_config/app_config_controller.dart';
import 'package:app/app_config/client_info.dart';
import 'package:app/components/voice/ai_consent_sheet.dart';
import 'package:app/components/voice/report_response_sheet.dart';
import 'package:app/data/data.dart';
import 'package:app/l10n/l10n.dart';
import 'package:app/legal/ai_consent_controller.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../voice/mic_capture.dart';
import '../voice/prompt_suggestions.dart';
import '../voice/voice_event.dart';
import '../voice/voice_expense_command.dart';
import 'voice_action_widget.dart';

/// Whether the model should respond with audio (TTS) when the user starts
/// the session by sending a text message. Hardcoded for now; future work will
/// expose this as a user-configurable preference.
const bool _kRespondToTextWithAudio = false;

/// Whether the chat shows a card ("Herramienta") for each tool call the agent
/// makes. Hidden for now.
const bool _kShowToolCards = false;

const double _kLockDistance = 80;

enum _SessionMode { audio, text }

class VoiceScreen extends StatefulWidget {
  const VoiceScreen({
    super.key,
    this.commandFactory = const DebugVoiceExpenseCommandFactory(),
  });

  final VoiceExpenseCommandFactory commandFactory;

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> with WidgetsBindingObserver {
  static const _liveEdgeTolerance = 1.0;

  final MicCapture _mic = MicCapture.forPlatform();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocusNode = FocusNode();
  final List<_ChatItem> _items = [];
  final Map<String, _ToolItem> _toolsById = {};

  StreamSubscription<Uint8List>? _audioSubscription;
  StreamSubscription<double>? _amplitudeSubscription;
  StreamSubscription<VoiceEvent>? _commandEventsSubscription;
  VoiceExpenseCommand? _command;

  _UserBubbleItem? _pendingUser;
  _AgentBubbleItem? _pendingAgent;
  _SystemItem? _connectionNotice;

  final List<String> _pendingTexts = [];
  bool _isStarting = false;
  bool _isConnected = false;
  bool _isReconnecting = false;
  bool _micActive = false;
  bool _micStarting = false;
  Future<void>? _micStopping;
  int _micGeneration = 0;
  // Only the initial, user-requested connection may buffer microphone audio.
  static const _startupAudioLimit = MicCapture.sampleRate * 2 * 5;
  List<Uint8List>? _startupAudio;
  int _startupAudioBytes = 0;
  bool _resumeMicrophone = false;
  bool _foreground = true;
  int _lifecycleGeneration = 0;
  bool _playbackEnabled = true;
  Future<void>? _backgroundAudioStop;
  bool _userMicOn = false;
  bool _isBrowsingHistory = false;
  bool _conversationRestored = false;
  bool _aiConsentAsked = false;
  double _level = 0;

  bool _handsFree = false;
  bool _holding = false;
  bool _paused = false;
  final ValueNotifier<double> _holdDrag = ValueNotifier(0);
  final GlobalKey _recordingTimerKey = GlobalKey();
  List<PromptSuggestion>? _suggestions;
  bool _suggestionsRequested = false;

  bool get _isTextComposing => _textController.text.trim().isNotEmpty;
  bool get _isMicEffectivelyMuted =>
      !_micActive || !_userMicOn || _isTextComposing;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _textController.addListener(_onTextChanged);
    final active = widget.commandFactory.activeCommand;
    if (active != null && active.isActive) {
      _command = active;
      _commandEventsSubscription = active.events.listen(_onVoiceEvent);
      _isConnected = active.isConnected;
      _isReconnecting = !active.isConnected;
      active.recordClientEvent('screen_attached');
      // Don't sit out a pending backoff delay while the user is looking at
      // the screen — reconnect immediately.
      if (!active.isConnected) unawaited(active.ensureConnected());
    } else {
      // No session yet: start minting the live token now so it's already
      // resolved by the time the user taps the mic or sends a message —
      // the mint round trip is roughly half of a cold connect.
      widget.commandFactory.prefetchToken();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Restored here rather than initState because rebuilding items may need
    // localized strings. `events` is live-only and no async gap exists
    // between the initState subscription and this snapshot, so the history
    // batch and the live stream can neither overlap nor miss events.
    if (!_aiConsentAsked) {
      _aiConsentAsked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_showAiConsentIfNeeded());
      });
    }
    if (!_conversationRestored) {
      _conversationRestored = true;
      final active = _command;
      if (active != null) {
        _restoreConversation(active.history);
      } else {
        unawaited(_rehydrateFromLog());
      }
    }
    if (_isReconnecting) _showConnectionNotice();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (!_foreground) return;
      _foreground = false;
      ++_lifecycleGeneration;
      _resumeMicrophone = _resumeMicrophone || _userMicOn || _micStarting;
      _backgroundAudioStop = _suspendAudioForBackground();
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    _foreground = true;
    ++_lifecycleGeneration;
    unawaited(_resumeAudioAfterBackground());
    final command = _command;
    // The OS may have killed the socket and suspended the reconnect timer
    // while backgrounded — reconnect immediately on return.
    if (command != null && command.isActive && !command.isConnected) {
      unawaited(command.ensureConnected());
    }
  }

  Future<void> _suspendAudioForBackground() async {
    await _stopMicCapture();
    try {
      await _command?.interruptAgentResponse(reason: 'app_backgrounded');
    } catch (error) {
      debugPrint('[voice] background audio cleanup failed: $error');
    }
  }

  Future<void> _resumeAudioAfterBackground() async {
    final generation = _lifecycleGeneration;
    final stopping = _backgroundAudioStop;
    await stopping;
    if (!mounted || !_foreground || generation != _lifecycleGeneration) return;
    if (identical(_backgroundAudioStop, stopping)) _backgroundAudioStop = null;
    if (_command?.isActive != true) return;
    // Playback intent is independent of the microphone's mute state.
    _command?.setAudioPlaybackEnabled(_playbackEnabled);
    // A pending permission dialog will retry here from its finally block.
    if (!_resumeMicrophone || _micStarting) return;
    _resumeMicrophone = false;
    await _startMicCapture(turnOn: true);
  }

  void _setAudioPlaybackEnabled(bool enabled) {
    _playbackEnabled = enabled;
    _command?.setAudioPlaybackEnabled(enabled);
  }

  /// Rebuilds the visible conversation from already-emitted session events in
  /// one pass — no per-event setState, no per-event scroll animation.
  void _restoreConversation(List<VoiceEvent> events) {
    for (final event in events) {
      _applyConversationEvent(event, replay: true);
    }
    if (_items.isNotEmpty) _jumpToBottomAfterBuild();
  }

  /// When no session is live, restores the conversation of the session the
  /// next start would resume, from the durable local log.
  Future<void> _rehydrateFromLog() async {
    final List<VoiceEvent> events;
    try {
      events = await widget.commandFactory.restorableHistory();
    } catch (error) {
      debugPrint('[voice] failed to rehydrate session log: $error');
      return;
    }
    if (!mounted || events.isEmpty) return;
    // A session may have started while the log was loading — don't clobber
    // the live conversation.
    if (_command != null || _items.isNotEmpty) return;
    setState(() {
      for (final event in events) {
        _applyConversationEvent(event, replay: true);
      }
      // Unlike a live re-attach, nothing will stream in to complete a
      // half-open bubble — close them out.
      _finalisePending();
    });
    _jumpToBottomAfterBuild();
  }

  /// Report one agent turn.
  ///
  /// The user turn immediately before it travels along: a reply reads very
  /// differently next to what prompted it, and for a report filed from a
  /// local-only account (whose history never leaves the device) it is the only
  /// context a moderator will ever see.
  Future<void> _reportAgentBubble(_AgentBubbleItem item) async {
    final index = _items.indexOf(item);
    final preceding = _items
        .take(index < 0 ? _items.length : index)
        .whereType<_UserBubbleItem>()
        .lastOrNull;
    final reported = await _openReportSheet(
      reportedText: item.text,
      precedingUserText: preceding?.text,
      occurredAt: item.at,
    );
    if (!mounted || !reported) return;
    setState(() => item.reported = true);
  }

  /// The fallback entry point, from the app bar: report the conversation rather
  /// than one turn, for a reply that was audio-only or has scrolled out of
  /// reach.
  Future<void> _reportSession() async {
    final l10n = context.l10n;
    if (_items.whereType<_AgentBubbleItem>().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.reportResponseNoResponseYet)));
      return;
    }
    await _openReportSheet();
  }

  /// Resolves the session pointers and opens the sheet. The providers are read
  /// as nullable on purpose: this screen is also built in tests without the
  /// app-level providers, and a missing one must not crash the chat.
  Future<bool> _openReportSheet({
    String? reportedText,
    String? precedingUserText,
    DateTime? occurredAt,
  }) async {
    final clientInfo = context.read<ClientInfo?>();
    if (clientInfo == null) return false;
    final locale = context.read<AppConfigController?>()?.locale ?? 'en';
    final sessionId =
        _command?.sessionId ??
        await widget.commandFactory.restorableSessionId();
    if (!mounted) return false;
    return showReportResponseSheet(
      context,
      clientInfo: clientInfo,
      locale: locale,
      reportedText: reportedText,
      precedingUserText: precedingUserText,
      sessionId: sessionId,
      // The session/setup log identifies the actual model, including switches.
      // A compiled default would mislabel reports from rollback sessions.
      model: null,
      occurredAt: occurredAt,
    );
  }

  void _jumpToBottomAfterBuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isBrowsingHistory || !_scrollController.hasClients) {
        return;
      }
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    ++_micGeneration;
    _startupAudio = null;
    WidgetsBinding.instance.removeObserver(this);
    _command?.recordClientEvent('screen_detached', {
      'micMuted': true,
      'sessionKeptActive': identical(
        widget.commandFactory.activeCommand,
        _command,
      ),
    });
    unawaited(_command?.interruptAgentResponse(reason: 'screen_detached'));
    unawaited(_command?.endAudioStream());
    unawaited(_audioSubscription?.cancel());
    unawaited(_amplitudeSubscription?.cancel());
    unawaited(_commandEventsSubscription?.cancel());
    if (!identical(widget.commandFactory.activeCommand, _command)) {
      unawaited(_command?.dispose());
    }
    unawaited(_mic.dispose());
    _scrollController.dispose();
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _textFocusNode.dispose();
    _holdDrag.dispose();
    super.dispose();
  }

  bool _wasTextComposing = false;

  void _onTextChanged() {
    if (!mounted) return;
    final isComposing = _isTextComposing;
    final startedComposing = isComposing && !_wasTextComposing;
    _wasTextComposing = isComposing;
    setState(() {});
    if (startedComposing && _startupAudio != null) {
      unawaited(_stopMicCapture());
    }
    if (startedComposing && _isConnected && _micActive) {
      // User started typing while the mic was open: we already stop
      // forwarding audio chunks via _isMicEffectivelyMuted, but the
      // server still has buffered audio for this turn. Flush it so the
      // next utterance starts clean once the user goes back to voice.
      unawaited(_command?.endAudioStream());
      _recordMuteEvent('text_composing');
    }
    if (startedComposing) _switchToTextOnTyping();
  }

  /// The hidden text field keeps the keyboard up while the mic is open, so
  /// typing is the same as the switch-to-text button: the mic closes and the
  /// composer comes back with what was typed.
  void _switchToTextOnTyping() {
    if (!_handsFree && !_holding && !_paused && !_micActive && !_micStarting) {
      return;
    }
    setState(() {
      _handsFree = false;
      _holding = false;
      _paused = false;
    });
    if (_micActive || _micStarting) unawaited(_stopMicCapture());
  }

  // -- Voice button gestures ------------------------------------------------

  void _handleVoiceTap() {
    _resumeMicrophone = false;
    if (_isStarting) {
      unawaited(_stopMicCapture());
      return;
    }
    if (_isTextComposing) return;
    if (!_isConnected) {
      unawaited(_startSession(mode: _SessionMode.audio));
      return;
    }
    if (!_micActive) {
      unawaited(_startMicCapture(turnOn: true));
      return;
    }
    final wasOn = _userMicOn;
    setState(() {
      _userMicOn = !wasOn;
      if (!_userMicOn) _level = 0;
    });
    _recordMuteEvent(wasOn ? 'tap_mute' : 'tap_unmute');
    if (wasOn) {
      unawaited(_stopMicCapture());
    }
  }

  void _handleVoiceLongPressStart() {
    if (_isStarting || _isTextComposing) return;
    if (!_isConnected) {
      unawaited(_startSession(mode: _SessionMode.audio));
      return;
    }
    if (!_micActive) {
      unawaited(_startMicCapture(turnOn: true));
      return;
    }
    setState(() {
      _userMicOn = true;
    });
    _recordMuteEvent('long_press_start');
  }

  void _handleVoiceLongPressEnd() {
    if (!mounted) return;
    final wasOn = _userMicOn;
    setState(() {
      _userMicOn = false;
      _level = 0;
    });
    _recordMuteEvent('long_press_end');
    if (wasOn || _micStarting) {
      unawaited(_stopMicCapture());
    }
  }

  // The controls of the welcome view and the recording bar. They only drive
  // the UI state and delegate every microphone action to the handlers above.

  void _onMicPressed() {
    if (_isTextComposing) return;
    if (!_isStarting) {
      setState(() {
        _handsFree = true;
        _paused = false;
      });
    }
    _handleVoiceTap();
  }

  void _onHoldStart() {
    if (_isStarting || _isTextComposing) return;
    unawaited(HapticFeedback.lightImpact());
    _holdDrag.value = 0;
    setState(() {
      _holding = true;
      _paused = false;
    });
    _handleVoiceLongPressStart();
  }

  void _onHoldMove(double dy) {
    if (!_holding) return;
    _holdDrag.value = dy.clamp(-_kLockDistance, 0);
    if (dy > -_kLockDistance) return;
    unawaited(HapticFeedback.mediumImpact());
    setState(() {
      _holding = false;
      _handsFree = true;
    });
  }

  void _onHoldEnd() {
    if (!_holding) return;
    setState(() => _holding = false);
    _handleVoiceLongPressEnd();
  }

  void _onPausePressed() {
    setState(() => _paused = true);
    _handleVoiceTap();
  }

  void _onResumePressed() {
    setState(() => _paused = false);
    _handleVoiceTap();
  }

  void _onStopPressed() {
    final micOn = _isStarting || (_micActive && _userMicOn);
    setState(() {
      _handsFree = false;
      _paused = false;
    });
    if (micOn) {
      _handleVoiceTap();
    } else if (_micStarting || _micActive) {
      // A tap here would open the mic again instead of closing it.
      _resumeMicrophone = false;
      unawaited(_stopMicCapture());
    }
  }

  void _onSendPressed() {
    setState(() => _handsFree = false);
    _handleSendText();
  }

  void _onEndPressed() {
    setState(() {
      _handsFree = false;
      _holding = false;
      _paused = false;
    });
    unawaited(_endConversation());
  }

  void _applySuggestion(String text) {
    _textController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _textFocusNode.requestFocus();
  }

  Future<void> _loadSuggestions() async {
    final repositories = context.read<AppRepositories?>();
    if (repositories == null) return;
    try {
      final data = await loadSuggestionData(repositories);
      if (!mounted) return;
      setState(() => _suggestions = nextPromptSuggestions(data));
    } catch (error) {
      debugPrint('[voice] prompt suggestions failed: $error');
    }
  }

  String _suggestionText(PromptSuggestion s) {
    final l10n = context.l10n;
    String amount() => NumberFormat.decimalPattern(
      Localizations.localeOf(context).toString(),
    ).format((s.amountCents ?? 0) / 100);
    final category = s.category ?? '';
    final account = s.account ?? '';
    return switch (s.kind) {
      PromptSuggestionKind.logExpense =>
        s.account == null
            ? l10n.suggestionLogExpense(amount(), category)
            : l10n.suggestionLogExpenseWithAccount(amount(), category, account),
      PromptSuggestionKind.spentInCategoryThisMonth =>
        l10n.suggestionSpentInCategoryThisMonth(category),
      PromptSuggestionKind.accountBalance => l10n.suggestionAccountBalance(
        account,
      ),
      PromptSuggestionKind.topSpendingThisMonth =>
        l10n.suggestionTopSpendingThisMonth,
      PromptSuggestionKind.compareCategoryLastMonth =>
        l10n.suggestionCompareCategoryLastMonth(category),
      PromptSuggestionKind.transfer => l10n.suggestionTransfer(
        amount(),
        account,
        s.toAccount ?? '',
      ),
      PromptSuggestionKind.logIncome => l10n.suggestionLogIncome(
        amount(),
        account,
      ),
      PromptSuggestionKind.spentWithTag => l10n.suggestionSpentWithTag(
        s.tag ?? '',
      ),
      PromptSuggestionKind.recentExpenses => l10n.suggestionRecentExpenses,
      PromptSuggestionKind.whatCanYouDo => l10n.suggestionWhatCanYouDo,
      PromptSuggestionKind.createCashAccount =>
        l10n.suggestionCreateCashAccount,
      PromptSuggestionKind.setupCategories => l10n.suggestionSetupCategories,
      PromptSuggestionKind.howToLogExpense => l10n.suggestionHowToLogExpense,
      PromptSuggestionKind.homeWidget =>
        s.category == null
            ? l10n.suggestionHomeWidget
            : l10n.suggestionHomeWidgetForCategory(category),
    };
  }

  // -- Text input -----------------------------------------------------------

  void _handleSendText() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final startingFresh = !_isConnected && !_isStarting;
    final wasConnected = _isConnected;

    setState(() {
      _finalisePending();
      _items.add(
        _UserBubbleItem(at: DateTime.now(), text: text, isFinal: true),
      );
      if (!wasConnected) {
        _pendingTexts.add(text);
      }
    });

    if (wasConnected) {
      // Text send → expect a silent (text-only) reply, even mid-session.
      // sendText() also flushes any open audio turn server-side.
      _setAudioPlaybackEnabled(false);
      unawaited(_command?.sendText(text));
    } else if (startingFresh) {
      unawaited(_startSession(mode: _SessionMode.text));
    }

    _textController.clear();
    _scrollToBottom(force: true);
  }

  void _flushPendingTexts() {
    if (_pendingTexts.isEmpty) return;
    final pending = List<String>.of(_pendingTexts);
    _pendingTexts.clear();
    // Same semantics as a live typed send: expect a silent text-only reply.
    _setAudioPlaybackEnabled(false);
    for (final text in pending) {
      unawaited(_command?.sendText(text));
    }
  }

  // -- Session lifecycle ----------------------------------------------------

  /// Shows the AI disclosure the first time this account opens the screen.
  ///
  /// On open, not on the mic: tapping the mic means "let me talk", and
  /// answering that with a legal wall — stacked in front of the iOS microphone
  /// permission dialog — is the wrong place for it. Declining leaves the
  /// screen, which is the only honest outcome when the assistant is the whole
  /// point of it.
  Future<void> _showAiConsentIfNeeded() async {
    final outcome = await ensureAiConsent(
      context,
      context.read<AiConsentController?>(),
    );
    if (outcome == AiConsentOutcome.granted || !mounted) return;
    if (outcome == AiConsentOutcome.failed) {
      _addSystemSetState(context.l10n.aiConsentFailed, kind: _SystemKind.error);
      return;
    }
    Navigator.of(context).maybePop();
  }

  Future<void> _startSession({required _SessionMode mode}) async {
    if (_isStarting || _isConnected) return;
    final l10n = context.l10n;
    final micGeneration = _micGeneration;

    setState(() {
      _isStarting = true;
      _userMicOn = false;
      _level = 0;
    });

    final respondWithAudio = switch (mode) {
      _SessionMode.audio => true,
      _SessionMode.text => _kRespondToTextWithAudio,
    };

    _playbackEnabled = respondWithAudio;
    try {
      final command = widget.commandFactory.create();
      if (!identical(_command, command)) {
        await _commandEventsSubscription?.cancel();
        _command = command;
        _commandEventsSubscription = command.events.listen(_onVoiceEvent);
      }
      if (!mounted) return;
      if (micGeneration != _micGeneration) {
        setState(() => _isStarting = false);
        return;
      }
      final connecting = command.start(respondWithAudio: respondWithAudio);
      if (mode == _SessionMode.audio) {
        _startupAudio = [];
        _startupAudioBytes = 0;
        await Future.wait([connecting, _startMicCapture(turnOn: true)]);
      } else {
        await connecting;
      }
      command.recordClientEvent('screen_attached', {'startMode': mode.name});
    } catch (error) {
      // Unexpected startup failure (connect errors retry inside the command
      // and never surface here). Release the command without ending the
      // logged session: the conversation stays restorable/resumable and any
      // queued text is kept for the next attempt. Raw errors never reach the
      // chat — details go to the debug console and the session log.
      debugPrint('[voice] start failed: $error');
      try {
        await _stopMicCapture();
      } catch (cleanupError) {
        debugPrint('[voice] startup cleanup failed: $cleanupError');
      } finally {
        if (mounted) setState(() => _isStarting = false);
      }
      final failedSubscription = _commandEventsSubscription;
      final failedCommand = _command;
      _commandEventsSubscription = null;
      _command = null;
      if (mounted) {
        setState(() {
          _isStarting = false;
          _isReconnecting = false;
          _clearConnectionNotice();
          _addSystem(l10n.voiceStartFailed, kind: _SystemKind.error);
        });
        _scrollToBottom();
      }
      try {
        await failedSubscription?.cancel();
      } catch (cleanupError) {
        debugPrint('[voice] subscription cleanup failed: $cleanupError');
      }
      try {
        await failedCommand?.dispose();
      } catch (cleanupError) {
        debugPrint('[voice] command cleanup failed: $cleanupError');
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isStarting = false;
      });
    }
  }

  Future<void> _startMicCapture({required bool turnOn}) async {
    if (_micStarting || !mounted || !_foreground) return;
    final stopping = _micStopping;
    if (stopping != null) {
      await stopping;
      if (!mounted || _micStarting) return;
    }
    if (_micActive) {
      if (turnOn && mounted) {
        setState(() => _userMicOn = true);
      }
      return;
    }
    final l10n = context.l10n;
    final generation = ++_micGeneration;
    _micStarting = true;
    bool current() => mounted && _foreground && generation == _micGeneration;

    try {
      final permission = await Permission.microphone.request();
      if (!permission.isGranted) _resumeMicrophone = false;
      if (!current()) return;
      if (!permission.isGranted) {
        _addSystemSetState(
          l10n.microphonePermissionDenied,
          kind: _SystemKind.error,
        );
        return;
      }

      final issue = await _mic.checkAvailability();
      if (!current()) return;
      if (issue == MicCaptureIssue.permissionDenied) {
        _addSystemSetState(
          l10n.recorderPermissionFailed,
          kind: _SystemKind.error,
        );
        return;
      }
      if (issue == MicCaptureIssue.pcmUnsupported) {
        _addSystemSetState(l10n.pcmUnsupported, kind: _SystemKind.error);
        return;
      }

      await _command?.prepareAudio();
      if (!current()) return;
      final audioStream = await _mic.start();
      if (!current()) {
        await _mic.stop();
        return;
      }
      _audioSubscription = audioStream.listen(
        _handleAudioChunk,
        onError: (Object error) {
          if (!current()) return;
          _addSystemSetState(
            l10n.audioStreamFailed(error),
            kind: _SystemKind.error,
          );
          unawaited(_stopMicCapture());
        },
      );

      _amplitudeSubscription = _mic
          .onAmplitudeDbfs(const Duration(milliseconds: 100))
          .listen(
            (dbfs) {
              if (!mounted) return;
              setState(() {
                _level = _dbfsToLevel(dbfs);
              });
            },
            onError: (Object _) {
              /* Audio subscription reports capture errors. */
            },
          );

      if (mounted) {
        setState(() {
          _micActive = true;
          if (turnOn) _userMicOn = true;
        });
        _recordMuteEvent('mic_capture_started');
      }
    } catch (error) {
      if (!current()) return;
      _addSystemSetState(
        l10n.microphoneOpenFailed(error),
        kind: _SystemKind.error,
      );
      await _stopMicCapture();
    } finally {
      if (mounted) {
        setState(() => _micStarting = false);
      } else {
        _micStarting = false;
      }
      if (mounted && _foreground && _resumeMicrophone) {
        unawaited(_resumeAudioAfterBackground());
      }
    }
  }

  Future<void> _stopMicCapture() {
    final existing = _micStopping;
    if (existing != null) return existing;
    final operation = _stopMicCaptureOnce();
    _micStopping = operation;
    return operation.whenComplete(() {
      if (identical(_micStopping, operation)) _micStopping = null;
    });
  }

  Future<void> _stopMicCaptureOnce() async {
    _startupAudio = null;
    ++_micGeneration;
    final audio = _audioSubscription;
    final amplitude = _amplitudeSubscription;
    _audioSubscription = null;
    _amplitudeSubscription = null;
    _micActive = false;
    for (final subscription in [audio, amplitude]) {
      try {
        await subscription?.cancel();
      } catch (error) {
        debugPrint('[voice] capture subscription cleanup failed: $error');
      }
    }

    try {
      await _mic.stop();
    } catch (_) {
      // best-effort cleanup
    }

    // Mic is going away entirely — flush any buffered audio on the server.
    try {
      await _command?.endAudioStream();
      _command?.recordClientEvent('mic_capture_stopped', {'muted': true});
    } catch (error) {
      debugPrint('[voice] audio stream cleanup failed: $error');
    }

    if (!mounted) return;
    setState(() {
      _micActive = false;
      _userMicOn = false;
      _level = 0;
    });
  }

  /// The End button's action: stops any live session, ends the logged
  /// session so it neither rehydrates nor resumes on the next open, and
  /// clears the visible conversation. This is the one deliberate wipe —
  /// mere disconnection never clears the chat.
  Future<void> _endConversation() async {
    await _stop();
    // Also covers the no-live-command case (rehydrated transcript) and a
    // stop() that failed midway: a no-op when stop() already ended it.
    await widget.commandFactory.discardRestorableSession();
    if (!mounted) return;
    setState(() {
      _items.clear();
      _toolsById.clear();
      _pendingUser = null;
      _pendingAgent = null;
      _connectionNotice = null;
      _isBrowsingHistory = false;
    });
  }

  Future<void> _stop() async {
    _resumeMicrophone = false;
    await _stopMicCapture();

    try {
      await _command?.stop();
    } catch (error) {
      // Never surface raw errors in the chat. _endConversation's discard
      // still ends the logged session even when stop() failed midway.
      debugPrint('[voice] stop failed: $error');
    } finally {
      await _commandEventsSubscription?.cancel();
      _commandEventsSubscription = null;
      await _command?.dispose();
      _command = null;
    }

    if (!mounted) return;
    setState(() {
      _isConnected = false;
      _isStarting = false;
      _isReconnecting = false;
      _pendingTexts.clear();
      _clearConnectionNotice();
      _finalisePending();
    });
  }

  void _recordMuteEvent(String reason) {
    _command?.recordClientEvent('mute_changed', {
      'muted': _isMicEffectivelyMuted,
      'reason': reason,
      'micCaptureActive': _micActive,
      'userMicOn': _userMicOn,
      'textComposing': _isTextComposing,
    });
  }

  void _handleAudioChunk(Uint8List chunk) {
    if (!mounted) return;
    if (!_isMicEffectivelyMuted) {
      final pending = _startupAudio;
      if (pending != null) {
        if (_startupAudioBytes + chunk.length > _startupAudioLimit) {
          // Keep the beginning intact or discard the whole attempt. Never
          // silently send a truncated utterance after a slow connection.
          unawaited(_stopMicCapture());
          _addSystemSetState(
            context.l10n.voiceStartFailed,
            kind: _SystemKind.error,
          );
          return;
        }
        pending.add(Uint8List.fromList(chunk));
        _startupAudioBytes += chunk.length;
      } else {
        unawaited(_command?.addAudioChunk(chunk));
      }
    }
    if (_level == 0 && !_isMicEffectivelyMuted) {
      setState(() {
        _level = _estimatePcmLevel(chunk);
      });
    }
  }

  // -- Event routing --------------------------------------------------------

  void _onVoiceEvent(VoiceEvent event) {
    if (!mounted) return;
    var conversationChanged = false;
    setState(() {
      switch (event) {
        case VoiceConnectingEvent(:final message):
          _isReconnecting = true;
          if (message.startsWith('Reconnecting')) {
            _showConnectionNotice();
            conversationChanged = true;
          }
        case VoiceConnectedEvent():
          _isConnected = true;
          _isReconnecting = false;
          conversationChanged = _connectionNotice != null;
          _clearConnectionNotice();
          final pending = _startupAudio;
          _startupAudio = null;
          if (!_isMicEffectivelyMuted && _command?.isConnected == true) {
            for (final chunk in pending ?? <Uint8List>[]) {
              unawaited(_command?.addAudioChunk(chunk));
            }
          }
          _flushPendingTexts();
        case VoiceDisconnectedEvent():
          if (_startupAudio != null) unawaited(_stopMicCapture());
          conversationChanged = true;
          _isConnected = false;
          _isReconnecting = _command?.isActive ?? false;
          // Queued text is never dropped here: it flushes on the next
          // VoiceConnectedEvent, and even across a session teardown the next
          // start resumes the same logged conversation.
          _finalisePending();
          if (_isReconnecting) {
            _showConnectionNotice();
          } else {
            _clearConnectionNotice();
          }
        case VoiceErrorEvent(:final message, :final isTransient, :final code):
          if (_startupAudio != null) unawaited(_stopMicCapture());
          // Raw error text never reaches the chat; details are persisted in
          // the session log. Most errors leave the session running (and
          // reconnecting) — the End button is the explicit way out. Only a
          // coded error is terminal: the command has already stopped itself,
          // so this branch owns the last word the user sees.
          debugPrint('[voice] error (transient: $isTransient): $message');
          if (isTransient) {
            conversationChanged = true;
            _isReconnecting = true;
            _showConnectionNotice();
          } else if (code != null) {
            // Replace the "reconnecting" notice rather than leaving it up
            // forever next to a session that has already ended.
            conversationChanged = true;
            _isReconnecting = false;
            _clearConnectionNotice();
            _addSystem(
              code == 'local_accounts_disabled'
                  ? context.l10n.voiceRequiresAccount
                  : context.l10n.voiceUnavailable,
              kind: _SystemKind.error,
            );
          }
        case VoiceSystemEvent():
        case VoiceClientActionEvent():
        case VoiceSessionResumptionEvent():
        case VoiceGoAwayEvent():
        case VoiceUsageMetadataEvent():
          break;
        case VoiceUserTranscriptDelta():
          // A typed turn disables playback for its reply. Voice input starts a
          // new audio turn, so subsequent agent audio must be audible again.
          _setAudioPlaybackEnabled(true);
          conversationChanged = _applyConversationEvent(event, replay: false);
        case VoiceAgentTranscriptDelta():
        case VoiceAgentTurnComplete():
        case VoiceAgentInterruptedEvent():
        case VoiceToolCallEvent():
        case VoiceToolResultEvent():
        case VoiceToolCancelledEvent():
          conversationChanged = _applyConversationEvent(event, replay: false);
      }
    });
    if (conversationChanged) _scrollToBottom();
  }

  /// Applies one conversation-content event to the chat items. Shared by the
  /// live stream and both restore paths (in-memory session history, durable
  /// log). Replay skips side effects that only make sense live: unmatched
  /// system notices, and typed-message bubbles that the send handler already
  /// added. Returns whether the visible conversation changed.
  bool _applyConversationEvent(VoiceEvent event, {required bool replay}) {
    switch (event) {
      case VoiceUserTranscriptDelta(:final text):
        _appendUser(text, at: event.at);
        return true;
      case VoiceAgentTranscriptDelta(:final text):
        _appendAgent(text, at: event.at);
        return true;
      case VoiceAgentTurnComplete():
        _finalisePendingAgent();
        return true;
      case VoiceAgentInterruptedEvent():
        _markAgentInterrupted(replay: replay);
        return true;
      case VoiceToolCallEvent(:final id, :final name, :final args):
        _addToolCall(id: id, name: name, args: args, at: event.at);
        return true;
      case VoiceToolResultEvent(:final id, :final result):
        _completeToolCall(id: id, result: result, at: event.at, replay: replay);
        return true;
      case VoiceToolCancelledEvent(:final ids):
        _cancelToolCalls(ids, replay: replay);
        return true;
      case VoiceClientActionEvent(:final action, :final details):
        // Typed messages only reach a restored transcript through the audit
        // trail; live sends add their bubble directly in _handleSendText.
        if (replay && action == 'send_message') {
          final text = details['text'];
          if (text is String && text.isNotEmpty) {
            _finalisePending();
            _items.add(
              _UserBubbleItem(at: event.at, text: text, isFinal: true),
            );
            return true;
          }
        }
        return false;
      default:
        return false;
    }
  }

  // -- Chat item management -------------------------------------------------

  void _addSystem(String message, {required _SystemKind kind}) {
    _items.add(_SystemItem(at: DateTime.now(), message: message, kind: kind));
  }

  void _showConnectionNotice() {
    final message = context.l10n.connectionLostReconnecting;
    final existing = _connectionNotice;
    if (existing != null) {
      existing.message = message;
      return;
    }
    final notice = _SystemItem(
      at: DateTime.now(),
      message: message,
      kind: _SystemKind.info,
    );
    _connectionNotice = notice;
    _items.add(notice);
  }

  void _clearConnectionNotice() {
    final notice = _connectionNotice;
    if (notice == null) return;
    _items.remove(notice);
    _connectionNotice = null;
  }

  void _addSystemSetState(String message, {required _SystemKind kind}) {
    if (!mounted) return;
    setState(() => _addSystem(message, kind: kind));
    _scrollToBottom();
  }

  void _appendUser(String chunk, {required DateTime at}) {
    _finalisePendingAgent();
    final existing = _pendingUser;
    if (existing == null) {
      final item = _UserBubbleItem(at: at, text: chunk, isFinal: false);
      _items.add(item);
      _pendingUser = item;
    } else {
      existing.text += chunk;
    }
  }

  void _appendAgent(String chunk, {required DateTime at}) {
    _finalisePendingUser();
    final existing = _pendingAgent;
    if (existing == null) {
      final item = _AgentBubbleItem(
        at: at,
        text: chunk,
        isFinal: false,
        wasInterrupted: false,
      );
      _items.add(item);
      _pendingAgent = item;
    } else {
      existing.text += chunk;
    }
  }

  void _finalisePending() {
    _finalisePendingUser();
    _finalisePendingAgent();
  }

  void _finalisePendingUser() {
    final p = _pendingUser;
    if (p == null) return;
    p.isFinal = true;
    _pendingUser = null;
  }

  void _finalisePendingAgent() {
    final p = _pendingAgent;
    if (p == null) return;
    p.isFinal = true;
    _pendingAgent = null;
  }

  void _markAgentInterrupted({required bool replay}) {
    final p = _pendingAgent;
    if (p != null) {
      p.wasInterrupted = true;
      p.isFinal = true;
      _pendingAgent = null;
    } else if (!replay) {
      _addSystem(context.l10n.agentInterrupted, kind: _SystemKind.info);
    }
  }

  void _addToolCall({
    required String id,
    required String name,
    required Map<String, dynamic> args,
    required DateTime at,
  }) {
    _finalisePending();
    final item = _ToolItem(at: at, id: id, name: name, args: args);
    _items.add(item);
    if (id.isNotEmpty) {
      _toolsById[id] = item;
    }
  }

  void _completeToolCall({
    required String id,
    required Map<String, dynamic> result,
    required DateTime at,
    required bool replay,
  }) {
    final tool = id.isNotEmpty ? _toolsById[id] : null;
    if (tool != null) {
      final wasPending = tool.status == _ToolStatus.pending;
      tool.result = result;
      tool.status = _ToolStatus.completed;
      if (wasPending &&
          isPreviewableTool(tool.name) &&
          result['ok'] == true &&
          result['id'] is String) {
        _items.add(
          _ActionResultItem(
            at: at,
            toolName: tool.name,
            entityId: result['id'] as String,
          ),
        );
      }
    } else if (!replay) {
      _addSystem(
        context.l10n.toolResponseUnmatched(result),
        kind: _SystemKind.info,
      );
    }
  }

  void _cancelToolCalls(List<String> ids, {required bool replay}) {
    for (final id in ids) {
      final tool = _toolsById[id];
      if (tool != null) {
        tool.status = _ToolStatus.cancelled;
      }
    }
    if (!replay) {
      _addSystem(
        context.l10n.toolCallsCancelled(ids.join(', ')),
        kind: _SystemKind.info,
      );
    }
  }

  bool _handleUserScroll(UserScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    final atLiveEdge = notification.metrics.extentAfter <= _liveEdgeTolerance;
    if (notification.direction == ScrollDirection.forward) {
      _isBrowsingHistory = true;
    } else if (atLiveEdge) {
      _isBrowsingHistory = false;
    }
    return false;
  }

  void _scrollToBottom({bool force = false}) {
    if (force) _isBrowsingHistory = false;
    if (_isBrowsingHistory || !_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isBrowsingHistory || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  // -- Audio helpers --------------------------------------------------------

  double _estimatePcmLevel(Uint8List bytes) {
    if (bytes.length < 2) return 0;
    final data = ByteData.sublistView(bytes);
    var sumSquares = 0.0;
    final samples = bytes.length ~/ 2;
    for (var i = 0; i < samples; i++) {
      final sample = data.getInt16(i * 2, Endian.little) / 32768.0;
      sumSquares += sample * sample;
    }
    final rms = math.sqrt(sumSquares / samples);
    return (rms * 8).clamp(0, 1);
  }

  double _dbfsToLevel(double dbfs) {
    if (dbfs.isInfinite || dbfs <= -60) return 0;
    return ((dbfs + 60) / 60).clamp(0, 1);
  }

  // -- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phase = _paused
        ? _MicPhase.paused
        : _micActive && _userMicOn
        ? _MicPhase.listening
        : _micStarting || (_isStarting && (_handsFree || _holding))
        ? _MicPhase.opening
        : _MicPhase.idle;
    final barMode = _holding
        ? _BarMode.holding
        : _paused || _micActive || _micStarting || (_handsFree && _isStarting)
        ? _BarMode.locked
        : _BarMode.composer;

    final suggestionsEnabled =
        context.watch<AppConfigController?>()?.isFlagEnabled(
          'agentPromptSuggestions',
        ) ??
        false;
    if (suggestionsEnabled && !_suggestionsRequested) {
      _suggestionsRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_loadSuggestions());
      });
    }
    final suggestions = suggestionsEnabled
        ? [for (final s in _suggestions ?? const []) _suggestionText(s)]
        : const <String>[];

    // Defaults to shown, both when the controller is absent (tests build this
    // screen bare) and when its config fetch never landed: this is the control
    // Google Play expects to find, so a missing config must not remove it.
    final showReportButton =
        context.watch<AppConfigController?>()?.isFlagEnabled(
          'agentReportButton',
          orElse: true,
        ) ??
        true;

    // Anything to end? A live/reconnecting session, or a restored
    // transcript whose logged session is still resumable.
    final showEndButton = _command != null || _items.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.liveVoice),
        actions: [
          if (showEndButton)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: IconButton(
                  icon: Icon(
                    Icons.call_end_rounded,
                    color: theme.colorScheme.error,
                  ),
                  tooltip: context.l10n.endSession,
                  onPressed: _onEndPressed,
                ),
              ),
            ),
          // The fallback reporting path, always present: a response the user
          // only heard, or one that has scrolled away, has no bubble to
          // long-press, and Google Play's policy has no exception for either.
          PopupMenuButton<String>(
            onSelected: (_) => unawaited(_reportSession()),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'report',
                child: Text(context.l10n.reportResponseMenuItem),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _items.isEmpty
                ? _WelcomeView(
                    phase: phase,
                    suggestions: suggestions,
                    onSuggestion: _applySuggestion,
                    onStart: _isTextComposing ? null : _onMicPressed,
                  )
                : NotificationListener<UserScrollNotification>(
                    onNotification: _handleUserScroll,
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 16,
                      ),
                      itemCount: _items.length,
                      itemBuilder: (context, i) {
                        final item = _items[i];
                        if (item is _ToolItem && !_kShowToolCards) {
                          return SizedBox.shrink(key: ObjectKey(item));
                        }
                        return Padding(
                          // The report icon's fade keeps state, so its element
                          // has to track the item and not the row index.
                          key: ObjectKey(item),
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: _ChatItemView(
                            item: item,
                            onReport: _reportAgentBubble,
                            showReportButton: showReportButton,
                          ),
                        );
                      },
                    ),
                  ),
          ),
          _ControlBar(
            mode: barMode,
            phase: phase,
            showSpinner: _isStarting && !_micActive && !_isTextComposing,
            showHoldHint:
                _items.isEmpty &&
                barMode == _BarMode.composer &&
                phase == _MicPhase.idle &&
                !_isTextComposing,
            hasText: _isTextComposing,
            level: _level,
            canPause: _isConnected && _micActive && _userMicOn && !_isStarting,
            canResume: !_isStarting && !_micStarting,
            textController: _textController,
            textFocusNode: _textFocusNode,
            recordingTimerKey: _recordingTimerKey,
            holdDrag: _holdDrag,
            onSendText: _onSendPressed,
            onMicTap: _onMicPressed,
            onHoldStart: _onHoldStart,
            onHoldMove: _onHoldMove,
            onHoldEnd: _onHoldEnd,
            onPause: _onPausePressed,
            onResume: _onResumePressed,
            onStop: _onStopPressed,
          ),
        ],
      ),
      backgroundColor: theme.colorScheme.surface,
    );
  }
}

// =============================================================================
// Chat item model
// =============================================================================

sealed class _ChatItem {
  _ChatItem({required this.at});
  final DateTime at;
}

class _UserBubbleItem extends _ChatItem {
  _UserBubbleItem({
    required super.at,
    required this.text,
    required this.isFinal,
  });
  String text;
  bool isFinal;
}

class _AgentBubbleItem extends _ChatItem {
  _AgentBubbleItem({
    required super.at,
    required this.text,
    required this.isFinal,
    required this.wasInterrupted,
  });
  String text;
  bool isFinal;
  bool wasInterrupted;

  /// The user reported this response. Purely cosmetic — the report is already
  /// on the server — but without it the bubble forgets the moment the snackbar
  /// clears.
  bool reported = false;
}

class _ToolItem extends _ChatItem {
  _ToolItem({
    required super.at,
    required this.id,
    required this.name,
    required this.args,
  });

  final String id;
  final String name;
  final Map<String, dynamic> args;
  Map<String, dynamic>? result;
  _ToolStatus status = _ToolStatus.pending;
}

enum _ToolStatus { pending, completed, cancelled }

class _SystemItem extends _ChatItem {
  _SystemItem({required super.at, required this.message, required this.kind});
  String message;
  final _SystemKind kind;
}

class _ActionResultItem extends _ChatItem {
  _ActionResultItem({
    required super.at,
    required this.toolName,
    required this.entityId,
  });

  final String toolName;
  final String entityId;
}

enum _SystemKind { info, success, error }

enum _MicPhase { idle, opening, listening, paused }

enum _BarMode { composer, holding, locked }

// =============================================================================
// Widgets
// =============================================================================

class _ChatItemView extends StatelessWidget {
  const _ChatItemView({
    required this.item,
    required this.onReport,
    required this.showReportButton,
  });
  final _ChatItem item;
  final ValueChanged<_AgentBubbleItem> onReport;
  final bool showReportButton;

  @override
  Widget build(BuildContext context) {
    final item = this.item;
    return switch (item) {
      _UserBubbleItem() => _UserBubble(item: item),
      _AgentBubbleItem() => _AgentBubble(
        item: item,
        onReport: onReport,
        showReportButton: showReportButton,
      ),
      _ToolItem() => _ToolCard(item: item),
      _SystemItem() => _SystemLine(item: item),
      _ActionResultItem() => VoiceActionWidget(
        toolName: item.toolName,
        entityId: item.entityId,
      ),
    };
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.item});
  final _UserBubbleItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = item.text.trim();
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _RoleLabel(label: context.l10n.you, time: item.at, alignEnd: true),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (text.isNotEmpty)
                    Text(
                      text,
                      style: TextStyle(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontSize: 15,
                      ),
                    ),
                  if (!item.isFinal) ...[
                    if (text.isNotEmpty) const SizedBox(height: 6),
                    _SpeakingDots(
                      color: theme.colorScheme.onPrimaryContainer.withValues(
                        alpha: 0.7,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentBubble extends StatelessWidget {
  const _AgentBubble({
    required this.item,
    required this.onReport,
    required this.showReportButton,
  });
  final _AgentBubbleItem item;
  final ValueChanged<_AgentBubbleItem> onReport;

  /// Whether the `agentReportButton` flag put the visible flag icon on the
  /// bubble. The long-press menu below stays either way, so turning the flag
  /// off narrows how reporting is *found*, never whether it works.
  final bool showReportButton;

  /// Long-press menu on the bubble. Google Play requires a way to flag
  /// generated content without leaving the app; long-press is where a message
  /// action lives on both platforms, so this is the primary entry point and the
  /// app bar's is only the fallback.
  Future<void> _showActions(BuildContext context) async {
    final l10n = context.l10n;
    final text = item.text.trim();
    if (text.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!item.reported)
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: Text(l10n.reportResponseAction),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onReport(item);
                },
              ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: Text(l10n.reportResponseCopy),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await Clipboard.setData(ClipboardData(text: text));
                messenger.showSnackBar(
                  SnackBar(content: Text(l10n.reportResponseCopied)),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = item.text.trim();
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _RoleLabel(label: 'Gaston', time: item.at),
                  const SizedBox(height: 4),
                  // Always drawn once the flag is on, never on hover and never
                  // behind a gesture: Google Play's AI-Generated Content policy
                  // wants flagging reachable without leaving the app, and a
                  // long-press is not something a user can see. Centred on the
                  // bubble rather than on the whole column, so it does not
                  // drift upward once the header sits above it.
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: GestureDetector(
                          onLongPress: () => unawaited(_showActions(context)),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(4),
                                topRight: Radius.circular(18),
                                bottomLeft: Radius.circular(18),
                                bottomRight: Radius.circular(18),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (text.isNotEmpty)
                                  Text(
                                    text,
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurface,
                                      fontSize: 15,
                                    ),
                                  ),
                                if (!item.isFinal) ...[
                                  if (text.isNotEmpty)
                                    const SizedBox(height: 6),
                                  _SpeakingDots(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                                ],
                                if (item.wasInterrupted) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    context.l10n.interrupted,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (showReportButton && text.isNotEmpty && !item.reported)
                        _DelayedFadeIn(
                          show: item.isFinal,
                          child: _ReportBubbleButton(
                            onPressed: () => onReport(item),
                          ),
                        ),
                    ],
                  ),
                  if (item.reported) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.flag_rounded,
                          size: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          context.l10n.reportResponseBadge,
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({required this.item});
  final _ToolItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color, label) = switch (item.status) {
      _ToolStatus.pending => (
        Icons.hourglass_top_rounded,
        theme.colorScheme.tertiary,
        context.l10n.toolRunning,
      ),
      _ToolStatus.completed => (
        Icons.check_circle_rounded,
        theme.colorScheme.primary,
        context.l10n.toolDone,
      ),
      _ToolStatus.cancelled => (
        Icons.cancel_rounded,
        theme.colorScheme.error,
        context.l10n.toolCancelled,
      ),
    };

    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.92,
        ),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 6),
                  Text(
                    context.l10n.tool,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(color: color),
                  ),
                ],
              ),
              if (context.watch<AppConfigController>().isFlagEnabled(
                'debugToolCalls',
              )) ...[
                if (item.args.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _KvBlock(label: context.l10n.arguments, data: item.args),
                ],
                if (item.result != null) ...[
                  const SizedBox(height: 6),
                  _KvBlock(label: context.l10n.result, data: item.result!),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _KvBlock extends StatelessWidget {
  const _KvBlock({required this.label, required this.data});
  final String label;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _formatJson(data),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatJson(Map<String, dynamic> data) {
    if (data.isEmpty) return '{}';
    return data.entries.map((e) => '${e.key}: ${e.value}').join('\n');
  }
}

class _SystemLine extends StatelessWidget {
  const _SystemLine({required this.item});
  final _SystemItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (item.kind) {
      _SystemKind.info => theme.colorScheme.onSurfaceVariant,
      _SystemKind.success => theme.colorScheme.primary,
      _SystemKind.error => theme.colorScheme.error,
    };
    final icon = switch (item.kind) {
      _SystemKind.info => Icons.info_outline_rounded,
      _SystemKind.success => Icons.check_circle_outline_rounded,
      _SystemKind.error => Icons.error_outline_rounded,
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                item.message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How long after a response finishes before its report control appears, and
/// how long the fade itself takes. The delay keeps the icon from arriving
/// mid-sentence, when there is not yet a finished answer to report.
const _reportRevealDelay = Duration(milliseconds: 1000);
const _reportFadeDuration = Duration(milliseconds: 300);

/// Fades [child] in once [show] turns true, [_reportRevealDelay] later.
///
/// Occupies its space from the first build, so the bubble beside it never
/// reflows when the icon arrives. While invisible it takes no taps and puts
/// nothing in the semantics tree: an unseen button is worse than no button,
/// both for a stray tap mid-response and for a screen reader announcing a
/// control nobody can see.
///
/// Driven by a controller rather than a `Timer` so the animation settles under
/// `pumpAndSettle` and leaves nothing pending when a test ends.
class _DelayedFadeIn extends StatefulWidget {
  const _DelayedFadeIn({required this.show, required this.child});
  final bool show;
  final Widget child;

  @override
  State<_DelayedFadeIn> createState() => _DelayedFadeInState();
}

class _DelayedFadeInState extends State<_DelayedFadeIn>
    with SingleTickerProviderStateMixin {
  // Not const: adding two Durations is not a constant expression.
  static final _total = _reportRevealDelay + _reportFadeDuration;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _total,
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Interval(
      _reportRevealDelay.inMilliseconds / _total.inMilliseconds,
      1,
      curve: Curves.easeOut,
    ),
  );

  @override
  void initState() {
    super.initState();
    // Already finished at the first build means restored history, which would
    // otherwise fade every bubble in a second after the screen opens.
    if (widget.show) _controller.value = 1;
  }

  @override
  void didUpdateWidget(_DelayedFadeIn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.show && !oldWidget.show) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _fade,
    child: widget.child,
    builder: (context, child) {
      final visible = _fade.value > 0;
      return IgnorePointer(
        ignoring: !visible,
        child: ExcludeSemantics(
          excluding: !visible,
          child: Opacity(opacity: _fade.value, child: child),
        ),
      );
    },
  );
}

/// The flag icon beside an agent bubble: the discoverable way to report a
/// response.
///
/// Sized to the 48x48 minimum tap target even though the glyph itself is small,
/// so it is reachable and not merely visible. Sits outside the bubble so the
/// tap target never overlaps the text a long-press is meant to select.
class _ReportBubbleButton extends StatelessWidget {
  const _ReportBubbleButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = context.l10n.reportResponseAction;
    return Semantics(
      button: true,
      label: label,
      child: IconButton(
        onPressed: onPressed,
        tooltip: label,
        iconSize: 16,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        icon: Icon(
          Icons.flag_outlined,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _RoleLabel extends StatelessWidget {
  const _RoleLabel({
    required this.label,
    required this.time,
    this.alignEnd = false,
  });
  final String label;
  final DateTime time;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );
    final timeStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: alignEnd
          ? [
              Text('$hh:$mm', style: timeStyle),
              const SizedBox(width: 6),
              Text(label, style: labelStyle),
            ]
          : [
              Text(label, style: labelStyle),
              const SizedBox(width: 6),
              Text('$hh:$mm', style: timeStyle),
            ],
    );
  }
}

class _SpeakingDots extends StatefulWidget {
  const _SpeakingDots({required this.color});
  final Color color;

  @override
  State<_SpeakingDots> createState() => _SpeakingDotsState();
}

class _SpeakingDotsState extends State<_SpeakingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = (_controller.value + i * 0.2) % 1.0;
            final t = (math.sin(phase * 2 * math.pi) + 1) / 2;
            return Padding(
              padding: EdgeInsets.only(right: i == 2 ? 0 : 4),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.3 + 0.7 * t),
                  shape: BoxShape.circle,
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _WelcomeView extends StatelessWidget {
  const _WelcomeView({
    required this.phase,
    required this.suggestions,
    required this.onSuggestion,
    required this.onStart,
  });

  final _MicPhase phase;
  final List<String> suggestions;
  final ValueChanged<String> onSuggestion;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final muted = theme.colorScheme.onSurfaceVariant;
    final Widget content = phase == _MicPhase.idle
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  shape: BoxShape.circle,
                ),
                child: SvgPicture.asset(
                  'assets/agent-glyph.svg',
                  width: 34,
                  height: 34,
                  colorFilter: ColorFilter.mode(
                    theme.colorScheme.onSecondaryContainer,
                    BlendMode.srcIn,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                l10n.voiceWelcomeTitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(
                  l10n.voiceWelcome,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
              ),
              if (suggestions.isNotEmpty) ...[
                const SizedBox(height: 28),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final text in suggestions)
                        ActionChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(text),
                          onPressed: () => onSuggestion(text),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: onStart,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 56),
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                ),
                icon: const Icon(Icons.mic_rounded),
                label: Text(l10n.voiceStartTalking),
              ),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/icon/icon-android.png',
                width: 96,
                height: 96,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 16),
              Text(
                switch (phase) {
                  _MicPhase.opening => l10n.voicePreparingMic,
                  _MicPhase.paused => l10n.voiceMicPaused,
                  _ => l10n.voiceListening,
                },
                style: theme.textTheme.titleMedium?.copyWith(
                  color: phase == _MicPhase.listening
                      ? theme.colorScheme.onSurface
                      : muted,
                ),
              ),
            ],
          );
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: math.max(0, constraints.maxHeight - 32),
          ),
          child: Center(child: content),
        ),
      ),
    );
  }
}

class _ControlBar extends StatelessWidget {
  const _ControlBar({
    required this.mode,
    required this.phase,
    required this.showSpinner,
    required this.showHoldHint,
    required this.hasText,
    required this.level,
    required this.canPause,
    required this.canResume,
    required this.textController,
    required this.textFocusNode,
    required this.recordingTimerKey,
    required this.holdDrag,
    required this.onSendText,
    required this.onMicTap,
    required this.onHoldStart,
    required this.onHoldMove,
    required this.onHoldEnd,
    required this.onPause,
    required this.onResume,
    required this.onStop,
  });

  final _BarMode mode;
  final _MicPhase phase;
  final bool showSpinner;
  final bool showHoldHint;
  final bool hasText;
  final double level;
  final bool canPause;
  final bool canResume;
  final TextEditingController textController;
  final FocusNode textFocusNode;
  final GlobalKey recordingTimerKey;
  final ValueListenable<double> holdDrag;
  final VoidCallback onSendText;
  final VoidCallback onMicTap;
  final VoidCallback onHoldStart;
  final ValueChanged<double> onHoldMove;
  final VoidCallback onHoldEnd;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          // The composer stays mounted while the mic is open, so the text
          // field keeps its focus and the keyboard stays up.
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Offstage(
                offstage: mode == _BarMode.locked,
                child: _buildComposer(context),
              ),
              if (mode == _BarMode.locked) _buildLocked(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComposer(BuildContext context) {
    final holding = mode == _BarMode.holding;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _HoldHint(visible: showHoldHint && !holding),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.passthrough,
                children: [
                  Offstage(
                    offstage: holding,
                    child: _TextComposer(
                      controller: textController,
                      focusNode: textFocusNode,
                      onSend: onSendText,
                    ),
                  ),
                  if (holding)
                    _HoldStrip(
                      timerKey: recordingTimerKey,
                      listening: phase == _MicPhase.listening,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _MicButton(
              holding: holding,
              showSpinner: showSpinner,
              hasText: hasText,
              holdDrag: holdDrag,
              onTap: hasText ? onSendText : onMicTap,
              onHoldStart: hasText ? null : onHoldStart,
              onHoldMove: onHoldMove,
              onHoldEnd: onHoldEnd,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLocked(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final paused = phase == _MicPhase.paused;
    final listening = phase == _MicPhase.listening;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 40,
          child: Row(
            children: [
              const SizedBox(width: 8),
              if (phase == _MicPhase.opening)
                SizedBox.square(
                  dimension: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else
                _RecordingDot(active: listening),
              const SizedBox(width: 10),
              _RecordingTimer(key: recordingTimerKey, running: listening),
              const SizedBox(width: 16),
              Expanded(
                child: _Waveform(level: level, running: listening),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: paused
                  ? FilledButton.icon(
                      onPressed: canResume ? onResume : null,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                      icon: const Icon(Icons.mic_rounded),
                      label: Text(l10n.voiceResume),
                    )
                  : FilledButton.icon(
                      onPressed: canPause ? onPause : null,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                        foregroundColor: theme.colorScheme.onSurface,
                      ),
                      icon: const Icon(Icons.pause_rounded),
                      label: Text(l10n.voicePause),
                    ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: onStop,
              tooltip: l10n.voiceSwitchToText,
              style: IconButton.styleFrom(
                minimumSize: const Size.square(48),
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.onPrimaryContainer,
              ),
              icon: const Icon(Icons.chat_rounded),
            ),
          ],
        ),
      ],
    );
  }
}

/// Points at the composer's mic, so it is clear which mic can be held.
class _HoldHint extends StatelessWidget {
  const _HoldHint({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final color = theme.colorScheme.inverseSurface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Align(
        alignment: Alignment.centerRight,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Text(
                  context.l10n.voiceHoldHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onInverseSurface,
                  ),
                ),
              ),
            ),
            Padding(
              // Centres the caret on the 48px mic button below.
              padding: const EdgeInsets.only(right: 18),
              child: CustomPaint(
                size: const Size(12, 6),
                painter: _CaretPainter(color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CaretPainter extends CustomPainter {
  const _CaretPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..lineTo(size.width, 0)
        ..lineTo(size.width / 2, size.height)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_CaretPainter oldDelegate) => oldDelegate.color != color;
}

class _HoldStrip extends StatelessWidget {
  const _HoldStrip({required this.timerKey, required this.listening});

  final GlobalKey timerKey;
  final bool listening;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          _RecordingDot(active: listening, icon: Icons.mic_rounded),
          const SizedBox(width: 10),
          _RecordingTimer(key: timerKey, running: listening),
          const Spacer(),
          Icon(Icons.keyboard_arrow_up_rounded, size: 18, color: muted),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              context.l10n.voiceSlideToLock,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordingDot extends StatefulWidget {
  const _RecordingDot({required this.active, this.icon});

  final bool active;
  final IconData? icon;

  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBlink();
  }

  @override
  void didUpdateWidget(_RecordingDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncBlink();
  }

  void _syncBlink() {
    final blink = widget.active && !MediaQuery.disableAnimationsOf(context);
    if (blink && !_blink.isAnimating) {
      _blink.repeat(reverse: true);
    } else if (!blink && _blink.isAnimating) {
      _blink
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = widget.active ? scheme.error : scheme.onSurfaceVariant;
    final icon = widget.icon;
    return FadeTransition(
      opacity: Tween(begin: 1.0, end: 0.25).animate(_blink),
      child: icon == null
          ? Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            )
          : Icon(icon, size: 20, color: color),
    );
  }
}

class _RecordingTimer extends StatefulWidget {
  const _RecordingTimer({super.key, required this.running});

  final bool running;

  @override
  State<_RecordingTimer> createState() => _RecordingTimerState();
}

class _RecordingTimerState extends State<_RecordingTimer> {
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_RecordingTimer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.running && !_stopwatch.isRunning) {
      _stopwatch.start();
      _ticker = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => setState(() {}),
      );
    } else if (!widget.running && _stopwatch.isRunning) {
      _stopwatch.stop();
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = _stopwatch.elapsed.inSeconds;
    return Text(
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

class _Waveform extends StatefulWidget {
  const _Waveform({required this.level, required this.running});

  final double level;
  final bool running;

  @override
  State<_Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<_Waveform> {
  static const _capacity = 64;

  List<double> _levels = List.filled(_capacity, 0);
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_Waveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.running && _ticker == null) {
      _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
        setState(() => _levels = [..._levels.skip(1), widget.level]);
      });
    } else if (!widget.running && _ticker != null) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: CustomPaint(
        size: Size.infinite,
        painter: _WaveformPainter(
          levels: _levels,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({required this.levels, required this.color});

  static const _barWidth = 3.0;
  static const _gap = 3.0;

  final List<double> levels;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final count = math.min(
      levels.length,
      (size.width / (_barWidth + _gap)).floor(),
    );
    final centerY = size.height / 2;
    for (var i = 0; i < count; i++) {
      final level = levels[levels.length - 1 - i];
      final height = math.max(_barWidth, level * size.height);
      final right = size.width - i * (_barWidth + _gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            right - _barWidth,
            centerY - height / 2,
            right,
            centerY + height / 2,
          ),
          const Radius.circular(_barWidth / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      !identical(oldDelegate.levels, levels) || oldDelegate.color != color;
}

class _TextComposer extends StatelessWidget {
  const _TextComposer({
    required this.controller,
    required this.focusNode,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;

  /// A physical keyboard's Enter sends and Shift+Enter breaks the line. An
  /// on-screen keyboard types its Enter as text instead of a key event, so it
  /// never reaches here: the multiline field breaks the line and the send
  /// button sends.
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    final isEnter =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!isEnter || event is KeyUpEvent) return KeyEventResult.ignored;
    if (HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    // An input method composing from a physical keyboard commits on Enter.
    if (controller.value.isComposingRangeValid) return KeyEventResult.ignored;
    if (event is KeyDownEvent && controller.text.trim().isNotEmpty) onSend();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _handleKey,
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          maxLines: 4,
          minLines: 1,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          decoration: InputDecoration(
            hintText: context.l10n.typeMessage,
            border: InputBorder.none,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );
  }
}

class _MicButton extends StatefulWidget {
  const _MicButton({
    required this.holding,
    required this.showSpinner,
    required this.hasText,
    required this.holdDrag,
    required this.onTap,
    required this.onHoldStart,
    required this.onHoldMove,
    required this.onHoldEnd,
  });

  final bool holding;
  final bool showSpinner;
  final bool hasText;
  final ValueListenable<double> holdDrag;
  final VoidCallback onTap;
  final VoidCallback? onHoldStart;
  final ValueChanged<double> onHoldMove;
  final VoidCallback onHoldEnd;

  @override
  State<_MicButton> createState() => _MicButtonState();
}

/// Press and hold to talk, drag up to lock, tap for hands-free. Raw pointer
/// events instead of a long-press recognizer: the button's subtree is swapped
/// for the locked bar while the finger is still down, and every callback here
/// has to tolerate arriving after that.
class _MicButtonState extends State<_MicButton> {
  static const _holdDelay = Duration(milliseconds: 300);

  int? _pointer;
  Offset _origin = Offset.zero;
  Timer? _holdTimer;
  bool _held = false;

  void _onDown(PointerDownEvent event) {
    if (_pointer != null) return;
    _pointer = event.pointer;
    _origin = event.position;
    _held = false;
    final onHoldStart = widget.onHoldStart;
    if (onHoldStart == null) return;
    _holdTimer = Timer(_holdDelay, () {
      _holdTimer = null;
      if (!mounted) return;
      _held = true;
      onHoldStart();
    });
  }

  void _onMove(PointerMoveEvent event) {
    if (event.pointer != _pointer || !_held || !mounted) return;
    widget.onHoldMove(event.position.dy - _origin.dy);
  }

  void _onUp(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _holdTimer?.cancel();
    _holdTimer = null;
    if (!mounted) return;
    if (_held) {
      _held = false;
      widget.onHoldEnd();
    } else {
      widget.onTap();
    }
  }

  void _onCancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _holdTimer?.cancel();
    _holdTimer = null;
    if (!mounted || !_held) return;
    _held = false;
    widget.onHoldEnd();
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final fg = scheme.onPrimaryContainer;
    return Semantics(
      button: true,
      label: widget.hasText ? l10n.voiceSend : l10n.voiceStartTalking,
      onTap: widget.onTap,
      child: Listener(
        onPointerDown: _onDown,
        onPointerMove: _onMove,
        onPointerUp: _onUp,
        onPointerCancel: _onCancel,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            AnimatedScale(
              scale: widget.holding ? 1.45 : 1,
              duration: const Duration(milliseconds: 150),
              child: SizedBox.square(
                dimension: 48,
                child: Material(
                  color: scheme.primaryContainer,
                  shape: const CircleBorder(),
                  elevation: widget.holding ? 3 : 0,
                  child: Center(
                    child: widget.showSpinner
                        ? SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: fg,
                            ),
                          )
                        : Icon(
                            widget.hasText
                                ? Icons.arrow_upward_rounded
                                : Icons.mic_rounded,
                            color: fg,
                          ),
                  ),
                ),
              ),
            ),
            if (widget.holding)
              Positioned(bottom: 72, child: _LockPill(drag: widget.holdDrag)),
          ],
        ),
      ),
    );
  }
}

class _LockPill extends StatelessWidget {
  const _LockPill({required this.drag});

  final ValueListenable<double> drag;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<double>(
      valueListenable: drag,
      builder: (context, offset, _) {
        final progress = (-offset / _kLockDistance).clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(0, offset * 0.6),
          child: Material(
            color: scheme.surfaceContainerHigh,
            elevation: 2,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    progress > 0.6
                        ? Icons.lock_rounded
                        : Icons.lock_open_rounded,
                    size: 22,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 6),
                  Icon(
                    Icons.keyboard_arrow_up_rounded,
                    size: 22,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
