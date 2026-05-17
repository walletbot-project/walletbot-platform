import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../voice/voice_event.dart';
import '../voice/voice_expense_command.dart';

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
  final AudioRecorder _recorder = AudioRecorder();
  final ScrollController _scrollController = ScrollController();
  final List<_ChatItem> _items = [];
  final Map<String, _ToolItem> _toolsById = {};

  StreamSubscription<Uint8List>? _audioSubscription;
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  StreamSubscription<VoiceEvent>? _commandEventsSubscription;
  VoiceExpenseCommand? _command;

  _UserBubbleItem? _pendingUser;
  _AgentBubbleItem? _pendingAgent;

  bool _isStarting = false;
  bool _isConnected = false;
  bool _isMuted = false;
  double _level = 0;

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
  void dispose() {
    unawaited(_audioSubscription?.cancel());
    unawaited(_amplitudeSubscription?.cancel());
    unawaited(_commandEventsSubscription?.cancel());
    unawaited(_command?.dispose());
    unawaited(_recorder.dispose());
    _scrollController.dispose();
    super.dispose();
  }

  // -- Session lifecycle ----------------------------------------------------

  Future<void> _toggle() async {
    if (_isConnected) {
      await _stop();
    } else {
      await _start();
    }
  }

  Future<void> _start() async {
    if (_isStarting || _isConnected) return;

    setState(() {
      _isStarting = true;
      _isMuted = false;
      _level = 0;
      _items.clear();
      _toolsById.clear();
      _pendingUser = null;
      _pendingAgent = null;
    });

    try {
      final permission = await Permission.microphone.request();
      if (!permission.isGranted) {
        _addSystemSetState(
          'Microphone permission denied',
          kind: _SystemKind.error,
        );
        return;
      }

      final hasRecorderPermission = await _recorder.hasPermission(
        request: false,
      );
      if (!hasRecorderPermission) {
        _addSystemSetState(
          'Recorder permission check failed',
          kind: _SystemKind.error,
        );
        return;
      }

      final supportsPcm = await _recorder.isEncoderSupported(
        AudioEncoder.pcm16bits,
      );
      if (!supportsPcm) {
        _addSystemSetState(
          'PCM 16-bit streaming is not supported on this device',
          kind: _SystemKind.error,
        );
        return;
      }

      _command = widget.commandFactory.create();
      _commandEventsSubscription = _command?.events.listen(_onVoiceEvent);
      await _command?.start();

      final audioStream = await _recorder.startStream(_recordConfig);
      _audioSubscription = audioStream.listen(
        _handleAudioChunk,
        onError: (Object error) {
          _addSystemSetState(
            'Audio stream error: $error',
            kind: _SystemKind.error,
          );
          unawaited(_stop());
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
    } catch (error) {
      _addSystemSetState('Failed to start: $error', kind: _SystemKind.error);
      await _stop();
    } finally {
      if (mounted) {
        setState(() {
          _isStarting = false;
        });
      }
    }
  }

  Future<void> _stop() async {
    await _audioSubscription?.cancel();
    await _amplitudeSubscription?.cancel();
    _audioSubscription = null;
    _amplitudeSubscription = null;

    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
      await _command?.stop();
    } catch (error) {
      _addSystemSetState(
        'Failed to stop cleanly: $error',
        kind: _SystemKind.error,
      );
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
      _level = 0;
      _finalisePending();
    });
  }

  void _handleAudioChunk(Uint8List chunk) {
    if (!mounted) return;
    if (!_isMuted) {
      unawaited(_command?.addAudioChunk(chunk));
    }
    if (_level == 0) {
      setState(() {
        _level = _estimatePcmLevel(chunk);
      });
    }
  }

  // -- Event routing --------------------------------------------------------

  void _onVoiceEvent(VoiceEvent event) {
    if (!mounted) return;
    setState(() {
      switch (event) {
        case VoiceConnectingEvent(:final message):
          _addSystem(message, kind: _SystemKind.info);
        case VoiceConnectedEvent():
          _isConnected = true;
          _addSystem('Connected. Start speaking.', kind: _SystemKind.success);
        case VoiceDisconnectedEvent(:final code, :final reason):
          _isConnected = false;
          final parts = <String>[
            'Disconnected',
            if (code != null) 'code $code',
            if (reason != null && reason.isNotEmpty) reason,
          ];
          _addSystem(parts.join(' · '), kind: _SystemKind.info);
          _finalisePending();
        case VoiceErrorEvent(:final message):
          _addSystem(message, kind: _SystemKind.error);
        case VoiceSystemEvent(:final message):
          _addSystem(message, kind: _SystemKind.info);
        case VoiceUserTranscriptDelta(:final text):
          _appendUser(text);
        case VoiceAgentTranscriptDelta(:final text):
          _appendAgent(text);
        case VoiceAgentTurnComplete():
          _finalisePendingAgent();
        case VoiceAgentInterruptedEvent():
          _markAgentInterrupted();
        case VoiceToolCallEvent(:final id, :final name, :final args):
          _addToolCall(id: id, name: name, args: args);
        case VoiceToolResultEvent(:final id, :final result):
          _completeToolCall(id: id, result: result);
        case VoiceToolCancelledEvent(:final ids):
          _cancelToolCalls(ids);
      }
    });
    _scrollToBottom();
  }

  // -- Chat item management -------------------------------------------------

  void _addSystem(String message, {required _SystemKind kind}) {
    _items.add(_SystemItem(at: DateTime.now(), message: message, kind: kind));
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
      _addSystem('Agent interrupted', kind: _SystemKind.info);
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
      tool.result = result;
      tool.status = _ToolStatus.completed;
    } else {
      _addSystem(
        'Tool response with no matching call: $result',
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
      'Tool calls cancelled: ${ids.join(', ')}',
      kind: _SystemKind.info,
    );
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
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
        : _isStarting
        ? _StatusLevel.connecting
        : _StatusLevel.disconnected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Voice'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: _StatusChip(level: status)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _items.isEmpty
                ? _EmptyState(isStarting: _isStarting)
                : ListView.builder(
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
          _ControlBar(
            isConnected: _isConnected,
            isStarting: _isStarting,
            isMuted: _isMuted,
            level: _level,
            onToggle: _isStarting ? null : _toggle,
            onToggleMute: _isConnected
                ? () {
                    setState(() {
                      _isMuted = !_isMuted;
                      if (_isMuted) _level = 0;
                    });
                  }
                : null,
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
  final String message;
  final _SystemKind kind;
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
            _RoleLabel(label: 'You', time: item.at, alignEnd: true),
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
                            '(interrupted)',
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
        'Running',
      ),
      _ToolStatus.completed => (
        Icons.check_circle_rounded,
        theme.colorScheme.primary,
        'Done',
      ),
      _ToolStatus.cancelled => (
        Icons.cancel_rounded,
        theme.colorScheme.error,
        'Cancelled',
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
                    'Tool',
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
                _KvBlock(label: 'args', data: item.args),
              ],
              if (item.result != null) ...[
                const SizedBox(height: 6),
                _KvBlock(label: 'result', data: item.result!),
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
      _StatusLevel.connected => (theme.colorScheme.primary, 'connected'),
      _StatusLevel.connecting => (theme.colorScheme.tertiary, 'connecting'),
      _StatusLevel.disconnected => (theme.colorScheme.outline, 'idle'),
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
            isStarting ? 'Connecting…' : 'Tap the mic to start a conversation',
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
    required this.isConnected,
    required this.isStarting,
    required this.isMuted,
    required this.level,
    required this.onToggle,
    required this.onToggleMute,
  });

  final bool isConnected;
  final bool isStarting;
  final bool isMuted;
  final double level;
  final VoidCallback? onToggle;
  final VoidCallback? onToggleMute;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isConnected)
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: isMuted ? 0 : level,
                    minHeight: 4,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
              if (isConnected) const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isConnected) ...[
                    _RoundIconButton(
                      icon: isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                      tooltip: isMuted ? 'Unmute' : 'Mute',
                      onPressed: onToggleMute,
                      color: isMuted
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary,
                      filled: false,
                    ),
                    const SizedBox(width: 16),
                  ],
                  _RoundIconButton(
                    icon: isConnected
                        ? Icons.call_end_rounded
                        : Icons.phone_rounded,
                    tooltip: isConnected ? 'Disconnect' : 'Connect',
                    onPressed: onToggle,
                    color: isConnected
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                    filled: true,
                    large: true,
                    busy: isStarting,
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

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.color,
    this.filled = false,
    this.large = false,
    this.busy = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color color;
  final bool filled;
  final bool large;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = large ? 64.0 : 48.0;
    final iconSize = large ? 28.0 : 22.0;
    final bg = filled ? color : Colors.transparent;
    final fg = filled ? theme.colorScheme.onPrimary : color;
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: size,
        height: size,
        child: Material(
          color: bg,
          shape: CircleBorder(
            side: filled
                ? BorderSide.none
                : BorderSide(color: color, width: 1.5),
          ),
          elevation: filled ? 2 : 0,
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: Center(
              child: busy
                  ? SizedBox(
                      width: iconSize,
                      height: iconSize,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: fg,
                      ),
                    )
                  : Icon(icon, color: fg, size: iconSize),
            ),
          ),
        ),
      ),
    );
  }
}
