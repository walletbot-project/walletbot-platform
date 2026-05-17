import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

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
  final List<String> _logs = [];

  StreamSubscription<Uint8List>? _audioSubscription;
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  StreamSubscription<String>? _commandEventsSubscription;
  VoiceExpenseCommand? _command;

  bool _isStarting = false;
  bool _isRecording = false;
  bool _isMuted = false;
  double _level = 0;
  int _chunks = 0;
  int _bytes = 0;

  static const _recordConfig = RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: 16000,
    numChannels: 1,
    echoCancel: true,
    noiseSuppress: true,
    autoGain: true,
    streamBufferSize: 3200,
  );

  @override
  void dispose() {
    unawaited(_audioSubscription?.cancel());
    unawaited(_amplitudeSubscription?.cancel());
    unawaited(_commandEventsSubscription?.cancel());
    unawaited(_command?.dispose());
    unawaited(_recorder.dispose());
    super.dispose();
  }

  Future<void> _toggleCapture() async {
    if (_isRecording) {
      await _stopCapture();
      return;
    }
    await _startCapture();
  }

  Future<void> _startCapture() async {
    if (_isStarting || _isRecording) return;

    setState(() {
      _isStarting = true;
      _isMuted = false;
      _chunks = 0;
      _bytes = 0;
      _level = 0;
      _logs.clear();
    });
    _addLog('Requesting microphone permission');

    try {
      final permission = await Permission.microphone.request();
      if (!permission.isGranted) {
        _addLog('Microphone permission denied');
        return;
      }

      final hasRecorderPermission = await _recorder.hasPermission(
        request: false,
      );
      if (!hasRecorderPermission) {
        _addLog('Recorder permission check failed');
        return;
      }

      final supportsPcm = await _recorder.isEncoderSupported(
        AudioEncoder.pcm16bits,
      );
      if (!supportsPcm) {
        _addLog('PCM 16-bit streaming is not supported on this device');
        return;
      }

      _command = widget.commandFactory.create();
      _commandEventsSubscription = _command?.events.listen(_addLog);
      _addLog('Command implementation: ${_command?.label}');
      await _command?.start();

      final audioStream = await _recorder.startStream(_recordConfig);
      _audioSubscription = audioStream.listen(
        _handleAudioChunk,
        onError: (Object error) {
          _addLog('Audio stream error: $error');
          unawaited(_stopCapture());
        },
        onDone: () => _addLog('Audio stream closed'),
      );

      _amplitudeSubscription = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((amplitude) {
            if (!mounted) return;
            setState(() {
              _level = _dbfsToLevel(amplitude.current);
            });
          });

      setState(() {
        _isRecording = true;
      });
      _addLog('Microphone capture started: PCM 16 kHz mono');
    } catch (error) {
      _addLog('Failed to start microphone capture: $error');
      await _stopCapture();
    } finally {
      if (mounted) {
        setState(() {
          _isStarting = false;
        });
      }
    }
  }

  Future<void> _stopCapture() async {
    await _audioSubscription?.cancel();
    await _amplitudeSubscription?.cancel();
    await _commandEventsSubscription?.cancel();
    _audioSubscription = null;
    _amplitudeSubscription = null;
    _commandEventsSubscription = null;

    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
      final result = await _command?.stop();
      if (result != null) {
        _addLog(result.message);
      }
    } catch (error) {
      _addLog('Failed to stop recorder cleanly: $error');
    } finally {
      await _command?.dispose();
      _command = null;
    }

    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _isStarting = false;
      _level = 0;
    });
    _addLog('Microphone capture stopped');
  }

  void _handleAudioChunk(Uint8List chunk) {
    if (!mounted) return;
    if (!_isMuted) {
      unawaited(_command?.addAudioChunk(chunk));
    }
    setState(() {
      _chunks += 1;
      _bytes += chunk.length;
      if (_level == 0) {
        _level = _estimatePcmLevel(chunk);
      }
    });
  }

  void _addLog(String message) {
    if (!mounted) return;
    final now = TimeOfDay.now();
    final formatted = '${now.format(context)} - $message';
    debugPrint('[VoiceScreen] $formatted');
    setState(() {
      _logs.insert(0, formatted);
      if (_logs.length > 40) {
        _logs.removeLast();
      }
    });
  }

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

  @override
  Widget build(BuildContext context) {
    final status = _isRecording
        ? 'connected'
        : _isStarting
        ? 'connecting'
        : 'disconnected';
    final statusColor = switch (status) {
      'connected' => Theme.of(context).colorScheme.primary,
      'connecting' => Theme.of(context).colorScheme.secondary,
      _ => Theme.of(context).colorScheme.outline,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Live Voice')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _isRecording && !_isMuted
                            ? Icons.mic_rounded
                            : Icons.mic_off_rounded,
                        color: _isRecording
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Live Voice',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: statusColor),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          child: Text(
                            status,
                            style: TextStyle(color: statusColor),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_isRecording) ...[
                    const SizedBox(height: 16),
                    LinearProgressIndicator(value: _level),
                    const SizedBox(height: 8),
                    Text('Mic level: ${(_level * 100).round()}%'),
                  ],
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (!_isRecording)
                        FilledButton.icon(
                          onPressed: _isStarting ? null : _toggleCapture,
                          icon: const Icon(Icons.phone_rounded),
                          label: Text(
                            _isStarting ? 'Connecting...' : 'Connect',
                          ),
                        )
                      else
                        FilledButton.icon(
                          onPressed: _toggleCapture,
                          icon: const Icon(Icons.phone_disabled_rounded),
                          label: const Text('Disconnect'),
                        ),
                      if (_isRecording)
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _isMuted = !_isMuted;
                              if (_isMuted) {
                                _level = 0;
                              }
                            });
                            _addLog(_isMuted ? 'Muted' : 'Unmuted');
                          },
                          icon: Icon(
                            _isMuted
                                ? Icons.mic_off_rounded
                                : Icons.mic_rounded,
                          ),
                          label: Text(_isMuted ? 'Unmute' : 'Mute'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Captured audio',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text('Chunks: $_chunks'),
                  Text('Bytes: $_bytes'),
                  const SizedBox(height: 8),
                  const Text('Format: PCM 16-bit, 16 kHz, mono'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Event Log',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Clear log',
                        onPressed: _logs.isEmpty
                            ? null
                            : () => setState(_logs.clear),
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_logs.isEmpty)
                    const Text('No events yet. Connect to start.')
                  else
                    for (final log in _logs)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(log),
                      ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
