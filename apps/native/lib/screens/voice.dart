import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:app/l10n/l10n.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../voice/voice_event.dart';
import '../voice/voice_expense_command.dart';
import 'voice_action_widget.dart';

/// Whether the model should respond with audio (TTS) when the user starts
/// the session by sending a text message. Hardcoded for now; future work will
/// expose this as a user-configurable preference.
const bool _kRespondToTextWithAudio = false;

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

class _VoiceScreenState extends State<VoiceScreen> {
  static const _liveEdgeTolerance = 1.0;

  final AudioRecorder _recorder = AudioRecorder();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocusNode = FocusNode();
  final List<_ChatItem> _items = [];
  final Map<String, _ToolItem> _toolsById = {};

  StreamSubscription<Uint8List>? _audioSubscription;
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  StreamSubscription<VoiceEvent>? _commandEventsSubscription;
  VoiceExpenseCommand? _command;

  _UserBubbleItem? _pendingUser;
  _AgentBubbleItem? _pendingAgent;
  _SystemItem? _connectionNotice;

  String? _pendingTextSend;
  bool _isStarting = false;
  bool _isConnected = false;
  bool _isReconnecting = false;
  bool _micActive = false;
  bool _userMicOn = false;
  bool _isBrowsingHistory = false;
  double _level = 0;

  bool get _isTextComposing => _textController.text.trim().isNotEmpty;
  bool get _isMicEffectivelyMuted =>
      !_micActive || !_userMicOn || _isTextComposing;

  static const _recordConfig = RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: 16000,
    numChannels: 1,
    echoCancel: true,
    noiseSuppress: true,
    autoGain: false,
    streamBufferSize: 3200,
    androidConfig: AndroidRecordConfig(
      audioSource: AndroidAudioSource.voiceCommunication,
    ),
  );

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onTextChanged);
    final active = widget.commandFactory.activeCommand;
    if (active != null && active.isActive) {
      _command = active;
      _commandEventsSubscription = active.events.listen(_onVoiceEvent);
      _isConnected = active.isConnected;
      _isReconnecting = !active.isConnected;
      active.recordClientEvent('screen_attached');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isReconnecting) _showConnectionNotice();
  }

  @override
  void dispose() {
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
    unawaited(_recorder.dispose());
    _scrollController.dispose();
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }

  bool _wasTextComposing = false;

  void _onTextChanged() {
    if (!mounted) return;
    final isComposing = _isTextComposing;
    final startedComposing = isComposing && !_wasTextComposing;
    _wasTextComposing = isComposing;
    setState(() {});
    if (startedComposing && _isConnected && _micActive) {
      // User started typing while the mic was open: we already stop
      // forwarding audio chunks via _isMicEffectivelyMuted, but the
      // server still has buffered audio for this turn. Flush it so the
      // next utterance starts clean once the user goes back to voice.
      unawaited(_command?.endAudioStream());
      _recordMuteEvent('text_composing');
    }
  }

  // -- Voice button gestures ------------------------------------------------

  void _handleVoiceTap() {
    if (_isStarting || _isTextComposing) return;
    if (!_isConnected) {
      setState(_resetChatLog);
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
      // Mic just went from on → off mid-turn: flush whatever the server
      // has buffered so the next utterance starts clean.
      unawaited(_command?.endAudioStream());
    }
  }

  void _handleVoiceLongPressStart() {
    if (_isStarting || _isTextComposing) return;
    if (!_isConnected) {
      setState(_resetChatLog);
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

  void _resetChatLog() {
    _items.clear();
    _toolsById.clear();
    _pendingUser = null;
    _pendingAgent = null;
    _connectionNotice = null;
    _isBrowsingHistory = false;
  }

  void _handleVoiceLongPressEnd() {
    if (!mounted) return;
    final wasOn = _userMicOn;
    setState(() {
      _userMicOn = false;
      _level = 0;
    });
    _recordMuteEvent('long_press_end');
    if (wasOn) {
      unawaited(_command?.endAudioStream());
    }
  }

  // -- Text input -----------------------------------------------------------

  void _handleSendText() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final startingFresh = !_isConnected && !_isStarting;
    final wasConnected = _isConnected;

    setState(() {
      if (startingFresh) {
        _resetChatLog();
      } else {
        _finalisePending();
      }
      _items.add(
        _UserBubbleItem(at: DateTime.now(), text: text, isFinal: true),
      );
      if (!wasConnected) {
        _pendingTextSend = text;
      }
    });

    if (wasConnected) {
      // Text send → expect a silent (text-only) reply, even mid-session.
      // sendText() also flushes any open audio turn server-side.
      _command?.setAudioPlaybackEnabled(false);
      unawaited(_command?.sendText(text));
    } else if (startingFresh) {
      unawaited(_startSession(mode: _SessionMode.text));
    }

    _textController.clear();
    _scrollToBottom(force: true);
  }

  void _flushPendingText() {
    final pending = _pendingTextSend;
    if (pending == null) return;
    _pendingTextSend = null;
    unawaited(_command?.sendText(pending));
  }

  // -- Session lifecycle ----------------------------------------------------

  Future<void> _startSession({required _SessionMode mode}) async {
    if (_isStarting || _isConnected) return;
    final l10n = context.l10n;

    setState(() {
      _isStarting = true;
      _userMicOn = false;
      _level = 0;
    });

    final respondWithAudio = switch (mode) {
      _SessionMode.audio => true,
      _SessionMode.text => _kRespondToTextWithAudio,
    };

    try {
      final command = widget.commandFactory.create();
      if (!identical(_command, command)) {
        await _commandEventsSubscription?.cancel();
        _command = command;
        _commandEventsSubscription = command.events.listen(_onVoiceEvent);
      }
      await _command?.start(respondWithAudio: respondWithAudio);
      _command?.recordClientEvent('screen_attached', {'startMode': mode.name});
    } catch (error) {
      _addSystemSetState(l10n.voiceStartFailed(error), kind: _SystemKind.error);
      await _stop();
      return;
    }

    if (mode == _SessionMode.audio) {
      await _startMicCapture(turnOn: true);
    }

    if (mounted) {
      setState(() {
        _isStarting = false;
      });
    }
  }

  Future<void> _startMicCapture({required bool turnOn}) async {
    if (_micActive) {
      if (turnOn && mounted) {
        setState(() => _userMicOn = true);
      }
      return;
    }
    final l10n = context.l10n;

    try {
      final permission = await Permission.microphone.request();
      if (!permission.isGranted) {
        _addSystemSetState(
          l10n.microphonePermissionDenied,
          kind: _SystemKind.error,
        );
        return;
      }

      final hasRecorderPermission = await _recorder.hasPermission(
        request: false,
      );
      if (!hasRecorderPermission) {
        _addSystemSetState(
          l10n.recorderPermissionFailed,
          kind: _SystemKind.error,
        );
        return;
      }

      final supportsPcm = await _recorder.isEncoderSupported(
        AudioEncoder.pcm16bits,
      );
      if (!supportsPcm) {
        _addSystemSetState(l10n.pcmUnsupported, kind: _SystemKind.error);
        return;
      }

      final audioStream = await _recorder.startStream(_recordConfig);
      _audioSubscription = audioStream.listen(
        _handleAudioChunk,
        onError: (Object error) {
          _addSystemSetState(
            l10n.audioStreamFailed(error),
            kind: _SystemKind.error,
          );
          unawaited(_stopMicCapture());
        },
      );

      _amplitudeSubscription = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((amplitude) {
            if (!mounted) return;
            setState(() {
              _level = _dbfsToLevel(amplitude.current);
            });
          });

      if (mounted) {
        setState(() {
          _micActive = true;
          if (turnOn) _userMicOn = true;
        });
        _recordMuteEvent('mic_capture_started');
      }
    } catch (error) {
      _addSystemSetState(
        l10n.microphoneOpenFailed(error),
        kind: _SystemKind.error,
      );
      await _stopMicCapture();
    }
  }

  Future<void> _stopMicCapture() async {
    await _audioSubscription?.cancel();
    await _amplitudeSubscription?.cancel();
    _audioSubscription = null;
    _amplitudeSubscription = null;

    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (_) {
      // best-effort cleanup
    }

    // Mic is going away entirely — flush any buffered audio on the server.
    await _command?.endAudioStream();
    _command?.recordClientEvent('mic_capture_stopped', {'muted': true});

    if (!mounted) return;
    setState(() {
      _micActive = false;
      _userMicOn = false;
      _level = 0;
    });
  }

  Future<void> _stop() async {
    final l10n = context.l10n;
    await _stopMicCapture();

    try {
      await _command?.stop();
    } catch (error) {
      _addSystemSetState(l10n.voiceStopFailed(error), kind: _SystemKind.error);
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
      _pendingTextSend = null;
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
      unawaited(_command?.addAudioChunk(chunk));
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
          _flushPendingText();
        case VoiceDisconnectedEvent():
          conversationChanged = true;
          _isConnected = false;
          _isReconnecting = _command?.isActive ?? false;
          _pendingTextSend = null;
          _finalisePending();
          if (_isReconnecting) {
            _showConnectionNotice();
          } else {
            _clearConnectionNotice();
          }
        case VoiceErrorEvent(:final message, :final isTransient):
          conversationChanged = true;
          _pendingTextSend = null;
          if (isTransient) {
            _isReconnecting = true;
            _showConnectionNotice();
          } else {
            _addSystem(
              context.l10n.voiceRuntimeError(message),
              kind: _SystemKind.error,
            );
          }
        case VoiceSystemEvent():
          break;
        case VoiceClientActionEvent():
        case VoiceSessionResumptionEvent():
        case VoiceGoAwayEvent():
        case VoiceUsageMetadataEvent():
          break;
        case VoiceUserTranscriptDelta(:final text):
          conversationChanged = true;
          // A typed turn disables playback for its reply. Voice input starts a
          // new audio turn, so subsequent agent audio must be audible again.
          _command?.setAudioPlaybackEnabled(true);
          _appendUser(text);
        case VoiceAgentTranscriptDelta(:final text):
          conversationChanged = true;
          _appendAgent(text);
        case VoiceAgentTurnComplete():
          conversationChanged = true;
          _finalisePendingAgent();
        case VoiceAgentInterruptedEvent():
          conversationChanged = true;
          _markAgentInterrupted();
        case VoiceToolCallEvent(:final id, :final name, :final args):
          conversationChanged = true;
          _addToolCall(id: id, name: name, args: args);
        case VoiceToolResultEvent(:final id, :final result):
          conversationChanged = true;
          _completeToolCall(id: id, result: result);
        case VoiceToolCancelledEvent(:final ids):
          conversationChanged = true;
          _cancelToolCalls(ids);
      }
    });
    if (conversationChanged) _scrollToBottom();
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

  void _appendUser(String chunk) {
    _finalisePendingAgent();
    final existing = _pendingUser;
    if (existing == null) {
      final item = _UserBubbleItem(
        at: DateTime.now(),
        text: chunk,
        isFinal: false,
      );
      _items.add(item);
      _pendingUser = item;
    } else {
      existing.text += chunk;
    }
  }

  void _appendAgent(String chunk) {
    _finalisePendingUser();
    final existing = _pendingAgent;
    if (existing == null) {
      final item = _AgentBubbleItem(
        at: DateTime.now(),
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

  void _markAgentInterrupted() {
    final p = _pendingAgent;
    if (p != null) {
      p.wasInterrupted = true;
      p.isFinal = true;
      _pendingAgent = null;
    } else {
      _addSystem(context.l10n.agentInterrupted, kind: _SystemKind.info);
    }
  }

  void _addToolCall({
    required String id,
    required String name,
    required Map<String, dynamic> args,
  }) {
    _finalisePending();
    final item = _ToolItem(at: DateTime.now(), id: id, name: name, args: args);
    _items.add(item);
    if (id.isNotEmpty) {
      _toolsById[id] = item;
    }
  }

  void _completeToolCall({
    required String id,
    required Map<String, dynamic> result,
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
            at: DateTime.now(),
            toolName: tool.name,
            entityId: result['id'] as String,
          ),
        );
      }
    } else {
      _addSystem(
        context.l10n.toolResponseUnmatched(result),
        kind: _SystemKind.info,
      );
    }
  }

  void _cancelToolCalls(List<String> ids) {
    for (final id in ids) {
      final tool = _toolsById[id];
      if (tool != null) {
        tool.status = _ToolStatus.cancelled;
      }
    }
    _addSystem(
      context.l10n.toolCallsCancelled(ids.join(', ')),
      kind: _SystemKind.info,
    );
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
    final status = _isConnected
        ? _StatusLevel.connected
        : _isStarting || _isReconnecting
        ? _StatusLevel.connecting
        : _StatusLevel.disconnected;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.liveVoice),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: _isConnected ? 4 : 12),
            child: Center(
              child: _isConnected
                  ? IconButton(
                      icon: Icon(
                        Icons.call_end_rounded,
                        color: theme.colorScheme.error,
                      ),
                      tooltip: context.l10n.endSession,
                      onPressed: () => unawaited(_stop()),
                    )
                  : _StatusChip(level: status),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _items.isEmpty
                ? _EmptyState(isStarting: _isStarting)
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
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: _ChatItemView(item: item),
                        );
                      },
                    ),
                  ),
          ),
          _ControlBar(
            isStarting: _isStarting,
            isMicActive: _micActive,
            isMicMuted: _isMicEffectivelyMuted,
            isTextComposing: _isTextComposing,
            level: _level,
            textController: _textController,
            textFocusNode: _textFocusNode,
            onSendText: _handleSendText,
            onTap: _handleVoiceTap,
            onLongPressStart: _handleVoiceLongPressStart,
            onLongPressEnd: _handleVoiceLongPressEnd,
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

enum _StatusLevel { disconnected, connecting, connected }

// =============================================================================
// Widgets
// =============================================================================

class _ChatItemView extends StatelessWidget {
  const _ChatItemView({required this.item});
  final _ChatItem item;

  @override
  Widget build(BuildContext context) {
    final item = this.item;
    return switch (item) {
      _UserBubbleItem() => _UserBubble(item: item),
      _AgentBubbleItem() => _AgentBubble(item: item),
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
  const _AgentBubble({required this.item});
  final _AgentBubbleItem item;

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
            CircleAvatar(
              radius: 14,
              backgroundColor: theme.colorScheme.secondaryContainer,
              child: Icon(
                Icons.auto_awesome_rounded,
                size: 16,
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _RoleLabel(label: 'WalletBot', time: item.at),
                  const SizedBox(height: 4),
                  Container(
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
                          if (text.isNotEmpty) const SizedBox(height: 6),
                          _SpeakingDots(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
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
              if (item.args.isNotEmpty) ...[
                const SizedBox(height: 8),
                _KvBlock(label: context.l10n.arguments, data: item.args),
              ],
              if (item.result != null) ...[
                const SizedBox(height: 6),
                _KvBlock(label: context.l10n.result, data: item.result!),
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.level});
  final _StatusLevel level;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (color, label) = switch (level) {
      _StatusLevel.connected => (
        theme.colorScheme.primary,
        context.l10n.connected,
      ),
      _StatusLevel.connecting => (
        theme.colorScheme.tertiary,
        context.l10n.connecting,
      ),
      _StatusLevel.disconnected => (
        theme.colorScheme.outline,
        context.l10n.idle,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (level == _StatusLevel.connecting)
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
            )
          else
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isStarting});
  final bool isStarting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isStarting ? Icons.cloud_sync_rounded : Icons.mic_none_rounded,
            size: 56,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            isStarting
                ? context.l10n.connectingPrompt
                : context.l10n.voiceStartPrompt,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlBar extends StatelessWidget {
  const _ControlBar({
    required this.isStarting,
    required this.isMicActive,
    required this.isMicMuted,
    required this.isTextComposing,
    required this.level,
    required this.textController,
    required this.textFocusNode,
    required this.onSendText,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressEnd,
  });

  final bool isStarting;
  final bool isMicActive;
  final bool isMicMuted;
  final bool isTextComposing;
  final double level;
  final TextEditingController textController;
  final FocusNode textFocusNode;
  final VoidCallback onSendText;
  final VoidCallback onTap;
  final VoidCallback onLongPressStart;
  final VoidCallback onLongPressEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showLevel = isMicActive && !isMicMuted;
    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showLevel) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: level,
                    minHeight: 4,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: _TextComposer(
                      controller: textController,
                      focusNode: textFocusNode,
                      onSend: onSendText,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _PrimaryActionButton(
                    isStarting: isStarting,
                    isMicActive: isMicActive,
                    isMicMuted: isMicMuted,
                    hasText: isTextComposing,
                    onTap: onTap,
                    onLongPressStart: onLongPressStart,
                    onLongPressEnd: onLongPressEnd,
                    onSend: onSendText,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        maxLines: 4,
        minLines: 1,
        textInputAction: TextInputAction.send,
        onSubmitted: (_) {
          if (controller.text.trim().isNotEmpty) onSend();
        },
        decoration: InputDecoration(
          hintText: context.l10n.typeMessage,
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
    required this.isStarting,
    required this.isMicActive,
    required this.isMicMuted,
    required this.hasText,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressEnd,
    required this.onSend,
  });

  final bool isStarting;
  final bool isMicActive;
  final bool isMicMuted;
  final bool hasText;
  final VoidCallback onTap;
  final VoidCallback onLongPressStart;
  final VoidCallback onLongPressEnd;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showMutedStyle = !hasText && isMicActive && isMicMuted;

    final Color bg;
    final Color fg;
    final BorderSide border;
    final double elevation;

    if (showMutedStyle) {
      bg = Colors.transparent;
      fg = theme.colorScheme.onSurfaceVariant;
      border = BorderSide(color: theme.colorScheme.outline, width: 1.5);
      elevation = 0;
    } else {
      bg = theme.colorScheme.primaryContainer;
      fg = theme.colorScheme.onPrimaryContainer;
      border = BorderSide.none;
      elevation = 2;
    }

    final IconData iconData;
    if (hasText) {
      iconData = Icons.arrow_upward_rounded;
    } else if (showMutedStyle) {
      iconData = Icons.mic_off_rounded;
    } else {
      iconData = Icons.mic_rounded;
    }

    final button = SizedBox(
      width: 56,
      height: 56,
      child: Material(
        color: bg,
        shape: CircleBorder(side: border),
        elevation: elevation,
        child: Center(
          child: isStarting && !hasText
              ? SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: fg),
                )
              : Icon(iconData, color: fg, size: 26),
        ),
      ),
    );

    if (hasText) {
      return GestureDetector(onTap: onSend, child: button);
    }

    return GestureDetector(
      onTap: onTap,
      onLongPressStart: (_) => onLongPressStart(),
      onLongPressEnd: (_) => onLongPressEnd(),
      child: button,
    );
  }
}
