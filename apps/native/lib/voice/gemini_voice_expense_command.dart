import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../data/data.dart';
import 'pcm_audio_player.dart';
import 'tool_executors.dart';
import 'voice_event.dart';
import 'voice_expense_command.dart';

class GeminiVoiceExpenseCommandFactory implements VoiceExpenseCommandFactory {
  GeminiVoiceExpenseCommandFactory({
    required this.repositories,
    this.apiKey = const String.fromEnvironment('GEMINI_API_KEY'),
    this.liveToken = const String.fromEnvironment('GEMINI_LIVE_TOKEN'),
    this.convexSiteUrl = const String.fromEnvironment('CONVEX_SITE_URL'),
  });

  final AppRepositories repositories;
  final String apiKey;
  final String liveToken;
  final String convexSiteUrl;

  @override
  VoiceExpenseCommand create() => GeminiVoiceExpenseCommand(
    repositories: repositories,
    apiKey: apiKey,
    liveToken: liveToken,
    convexSiteUrl: convexSiteUrl,
  );
}

class GeminiVoiceExpenseCommand implements VoiceExpenseCommand {
  GeminiVoiceExpenseCommand({
    required this.repositories,
    required this.apiKey,
    required this.liveToken,
    required this.convexSiteUrl,
  }) : _executors = ToolExecutors(repositories);

  static const _model = 'gemini-3.1-flash-live-preview';
  static const _voiceName = 'Kore';

  final AppRepositories repositories;
  final String apiKey;
  final String liveToken;
  final String convexSiteUrl;
  final ToolExecutors _executors;
  final _audioPlayer = PcmAudioPlayer();
  final _events = StreamController<VoiceEvent>.broadcast();
  final _setupComplete = Completer<void>();

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  bool _connected = false;
  bool _disposed = false;
  bool _audioPlaybackEnabled = true;
  bool _audioStreamOpen = false;
  int _inputChunks = 0;
  int _outputAudioChunks = 0;
  int _outputAudioBytes = 0;

  @override
  String get label => 'Gemini Live voice expense command';

  @override
  Stream<VoiceEvent> get events => _events.stream;

  @override
  Future<void> start({bool respondWithAudio = true}) async {
    _audioPlaybackEnabled = respondWithAudio;
    final effectiveToken = await _resolveLiveToken();

    if (apiKey.isEmpty && effectiveToken.isEmpty) {
      throw StateError(
        'Missing Gemini credentials. Run Flutter with '
        '--dart-define=CONVEX_SITE_URL=<convex-site-url>, '
        '--dart-define=GEMINI_LIVE_TOKEN=<ephemeral-token>, or '
        '--dart-define=GEMINI_API_KEY=<dev-key>.',
      );
    }

    final uri = _connectionUri(effectiveToken);

    _events.add(VoiceConnectingEvent('Connecting to Gemini Live'));
    await _audioPlayer.start(sampleRate: 24000);
    final channel = WebSocketChannel.connect(uri);
    _channel = channel;

    _subscription = channel.stream.listen(
      _handleServerMessage,
      onError: (Object error) {
        _events.add(VoiceErrorEvent('WebSocket error: $error'));
      },
      onDone: () {
        _connected = false;
        _events.add(
          VoiceDisconnectedEvent(
            code: channel.closeCode,
            reason: channel.closeReason,
          ),
        );
      },
    );

    // Tools, system instruction, response modality, and speech config are
    // pinned into the ephemeral token server-side (see
    // packages/backend/convex/live/actions.ts → liveConnectConstraints). The
    // session is always AUDIO at the protocol level; silent ("text-only")
    // sessions are achieved client-side by dropping inbound audio playback
    // while keeping the output transcription for the chat UI.
    _send({
      'setup': {
        'model': 'models/$_model',
        'generationConfig': {
          'responseModalities': ['AUDIO'],
          'speechConfig': {
            'voiceConfig': {
              'prebuiltVoiceConfig': {'voiceName': _voiceName},
            },
          },
        },
        'inputAudioTranscription': <String, dynamic>{},
        'outputAudioTranscription': <String, dynamic>{},
      },
    });

    await _setupComplete.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        throw TimeoutException('Gemini setup did not complete in time');
      },
    );
    _connected = true;
    _events.add(VoiceConnectedEvent());
  }

  Future<String> _resolveLiveToken() async {
    if (liveToken.isNotEmpty) return liveToken;
    if (convexSiteUrl.isEmpty) return '';

    final base = Uri.parse(convexSiteUrl);
    final endpoint = base.replace(path: '/api/live/token');

    _events.add(VoiceSystemEvent('Requesting live token from Convex'));
    final response = await http.post(endpoint);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Convex live token request failed: '
        '${response.statusCode} ${response.body}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final token = body['token'];
    final model = body['model'];
    if (model is String) {
      _events.add(VoiceSystemEvent('Live token received for model: $model'));
    }
    if (token is! String || token.isEmpty) {
      throw StateError('Convex live token response did not include token');
    }
    return token;
  }

  Uri _connectionUri(String effectiveLiveToken) {
    const basePath = '/ws/';
    if (effectiveLiveToken.isNotEmpty) {
      return Uri(
        scheme: 'wss',
        host: 'generativelanguage.googleapis.com',
        path:
            '${basePath}google.ai.generativelanguage.v1alpha.'
            'GenerativeService.BidiGenerateContentConstrained',
        queryParameters: {'access_token': effectiveLiveToken},
      );
    }

    return Uri(
      scheme: 'wss',
      host: 'generativelanguage.googleapis.com',
      path:
          '${basePath}google.ai.generativelanguage.v1beta.'
          'GenerativeService.BidiGenerateContent',
      queryParameters: {'key': apiKey},
    );
  }

  @override
  Future<void> addAudioChunk(Uint8List chunk) async {
    if (!_connected || _disposed) return;
    _inputChunks += 1;
    _audioStreamOpen = true;
    _send({
      'realtimeInput': {
        'audio': {
          'data': base64Encode(chunk),
          'mimeType': 'audio/pcm;rate=16000',
        },
      },
    });
  }

  @override
  Future<void> endAudioStream() async {
    if (!_connected || _disposed) return;
    if (!_audioStreamOpen) return;
    _audioStreamOpen = false;
    // Gemini Live (automatic VAD): tells the server to flush any cached
    // audio and finalise the current turn so the next utterance starts
    // clean. See https://ai.google.dev/gemini-api/docs/live-api/capabilities.
    _send({
      'realtimeInput': {'audioStreamEnd': true},
    });
  }

  @override
  void setAudioPlaybackEnabled(bool enabled) {
    _audioPlaybackEnabled = enabled;
  }

  @override
  Future<void> sendText(String text) async {
    if (!_connected || _disposed) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    // Close any open audio turn first so half-spoken audio doesn't bleed
    // into the text turn.
    await endAudioStream();
    _send({
      'realtimeInput': {'text': trimmed},
    });
  }

  @override
  Future<VoiceExpenseCommandResult> stop() async {
    await _closeChannel();
    await _audioPlayer.stop();
    final summary =
        'Sent $_inputChunks input chunks, received $_outputAudioChunks audio '
        'chunks ($_outputAudioBytes bytes).';
    _events.add(VoiceSystemEvent(summary));
    return VoiceExpenseCommandResult(message: summary);
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _closeChannel();
    await _audioPlayer.stop();
    await _events.close();
  }

  void _handleServerMessage(dynamic rawMessage) {
    final text = rawMessage is String
        ? rawMessage
        : rawMessage is List<int>
        ? utf8.decode(rawMessage)
        : rawMessage.toString();

    final message = jsonDecode(text) as Map<String, dynamic>;

    if (message.containsKey('setupComplete')) {
      if (!_setupComplete.isCompleted) {
        _setupComplete.complete();
      }
      return;
    }

    final toolCall = message['toolCall'];
    if (toolCall is Map<String, dynamic>) {
      unawaited(_handleToolCall(toolCall));
      return;
    }

    final cancellation = message['toolCallCancellation'];
    if (cancellation is Map<String, dynamic>) {
      final ids = cancellation['ids'];
      final idList = ids is List
          ? ids.map((e) => e.toString()).toList()
          : <String>[];
      _events.add(VoiceToolCancelledEvent(idList));
      return;
    }

    final serverContent = message['serverContent'];
    if (serverContent is Map<String, dynamic>) {
      _handleServerContent(serverContent);
      return;
    }
  }

  void _handleServerContent(Map<String, dynamic> serverContent) {
    final inputTranscription = serverContent['inputTranscription'];
    if (inputTranscription is Map<String, dynamic>) {
      final t = inputTranscription['text'];
      if (t is String && t.isNotEmpty) {
        _events.add(VoiceUserTranscriptDelta(t));
      }
    }

    final outputTranscription = serverContent['outputTranscription'];
    if (outputTranscription is Map<String, dynamic>) {
      final t = outputTranscription['text'];
      if (t is String && t.isNotEmpty) {
        _events.add(VoiceAgentTranscriptDelta(t));
      }
    }

    if (serverContent['interrupted'] == true) {
      _events.add(VoiceAgentInterruptedEvent());
      unawaited(_audioPlayer.interrupt());
    }

    final modelTurn = serverContent['modelTurn'];
    if (modelTurn is Map<String, dynamic>) {
      final parts = modelTurn['parts'];
      if (parts is List) {
        for (final part in parts) {
          if (part is! Map<String, dynamic>) continue;

          final text = part['text'];
          if (text is String && text.isNotEmpty) {
            _events.add(VoiceAgentTranscriptDelta(text));
          }

          final inlineData = part['inlineData'];
          if (inlineData is Map<String, dynamic>) {
            final data = inlineData['data'];
            if (data is String) {
              final pcmBytes = base64Decode(data);
              _outputAudioChunks += 1;
              _outputAudioBytes += pcmBytes.length;
              if (_audioPlaybackEnabled) {
                unawaited(_audioPlayer.enqueue(pcmBytes));
              }
            }
          }
        }
      }
    }

    if (serverContent['turnComplete'] == true) {
      _events.add(VoiceAgentTurnComplete());
    }
  }

  Future<void> _handleToolCall(Map<String, dynamic> toolCall) async {
    final calls = toolCall['functionCalls'];
    if (calls is! List) return;

    final responses = <Map<String, dynamic>>[];
    for (final call in calls) {
      if (call is! Map<String, dynamic>) continue;

      final id = call['id']?.toString() ?? '';
      final name = call['name']?.toString() ?? '';
      final args = call['args'] is Map<String, dynamic>
          ? call['args'] as Map<String, dynamic>
          : <String, dynamic>{};

      _events.add(VoiceToolCallEvent(id: id, name: name, args: args));
      final result = await _executors.execute(name, args);
      _events.add(VoiceToolResultEvent(id: id, name: name, result: result));

      responses.add({
        if (id.isNotEmpty) 'id': id,
        'name': name,
        'response': {'result': result},
      });
    }

    if (responses.isNotEmpty) {
      _send({
        'toolResponse': {'functionResponses': responses},
      });
    }
  }

  void _send(Map<String, dynamic> message) {
    _channel?.sink.add(jsonEncode(message));
  }

  Future<void> _closeChannel() async {
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    _connected = false;
  }
}
