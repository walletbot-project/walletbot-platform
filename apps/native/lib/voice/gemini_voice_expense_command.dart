import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'pcm_audio_player.dart';
import 'voice_expense_command.dart';

class GeminiVoiceExpenseCommandFactory implements VoiceExpenseCommandFactory {
  const GeminiVoiceExpenseCommandFactory({
    this.apiKey = const String.fromEnvironment('GEMINI_API_KEY'),
    this.liveToken = const String.fromEnvironment('GEMINI_LIVE_TOKEN'),
    this.convexSiteUrl = const String.fromEnvironment('CONVEX_SITE_URL'),
  });

  final String apiKey;
  final String liveToken;
  final String convexSiteUrl;

  @override
  VoiceExpenseCommand create() => GeminiVoiceExpenseCommand(
    apiKey: apiKey,
    liveToken: liveToken,
    convexSiteUrl: convexSiteUrl,
  );
}

class GeminiVoiceExpenseCommand implements VoiceExpenseCommand {
  GeminiVoiceExpenseCommand({
    required this.apiKey,
    required this.liveToken,
    required this.convexSiteUrl,
  });

  static const _model = 'gemini-3.1-flash-live-preview';
  static const _voiceName = 'Kore';

  final String apiKey;
  final String liveToken;
  final String convexSiteUrl;
  final _audioPlayer = PcmAudioPlayer();
  final _events = StreamController<String>.broadcast();
  final _setupComplete = Completer<void>();

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  bool _connected = false;
  bool _disposed = false;
  int _inputChunks = 0;
  int _outputAudioChunks = 0;
  int _outputAudioBytes = 0;
  DateTime? _lastAudioSummaryAt;

  @override
  String get label => 'Gemini Live voice expense command';

  @override
  Stream<String> get events => _events.stream;

  @override
  Future<void> start() async {
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

    _events.add('Connecting to Gemini Live');
    await _audioPlayer.start(sampleRate: 24000);
    final channel = WebSocketChannel.connect(uri);
    _channel = channel;

    _subscription = channel.stream.listen(
      _handleServerMessage,
      onError: (Object error) {
        _events.add('Gemini WebSocket error: $error');
      },
      onDone: () {
        _connected = false;
        final code = channel.closeCode;
        final reason = channel.closeReason;
        _events.add(
          'Gemini WebSocket closed'
          '${code == null ? '' : ' code=$code'}'
          '${reason == null || reason.isEmpty ? '' : ' reason=$reason'}',
        );
      },
    );

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
        'systemInstruction': {
          'parts': [
            {
              'text':
                  'You are a personal finance tracking assistant. You help '
                  'the user manage expenses, income, and transfers through '
                  'voice. Keep the same voice, tone, and speaking style for '
                  'the entire session.',
            },
          ],
        },
        'tools': [
          {'functionDeclarations': _toolDeclarations},
        ],
      },
    });

    await _setupComplete.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        throw TimeoutException('Gemini setup did not complete in time');
      },
    );
    _connected = true;
    _events.add('Gemini Live session ready');
  }

  Future<String> _resolveLiveToken() async {
    if (liveToken.isNotEmpty) return liveToken;
    if (convexSiteUrl.isEmpty) return '';

    final base = Uri.parse(convexSiteUrl);
    final endpoint = base.replace(path: '/api/live/token');

    _events.add('Requesting live token from Convex');
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
      _events.add('Live token received for model: $model');
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
  Future<VoiceExpenseCommandResult> stop() async {
    _events.add('Stopping Gemini session after $_inputChunks input chunks');
    await _closeChannel();
    await _audioPlayer.stop();
    return VoiceExpenseCommandResult(
      message:
          'Gemini session stopped. Sent $_inputChunks input chunks and '
          'received $_outputAudioChunks audio chunks ($_outputAudioBytes bytes).',
    );
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
      _events.add('Gemini setup complete');
      return;
    }

    final toolCall = message['toolCall'];
    if (toolCall is Map<String, dynamic>) {
      unawaited(_handleToolCall(toolCall));
      return;
    }

    final cancellation = message['toolCallCancellation'];
    if (cancellation is Map<String, dynamic>) {
      _events.add('Gemini cancelled tool calls: ${cancellation['ids']}');
      return;
    }

    final serverContent = message['serverContent'];
    if (serverContent is Map<String, dynamic>) {
      _handleServerContent(serverContent);
      return;
    }
  }

  void _handleServerContent(Map<String, dynamic> serverContent) {
    if (serverContent['interrupted'] == true) {
      _events.add('Gemini response interrupted');
      unawaited(_audioPlayer.interrupt());
    }

    final modelTurn = serverContent['modelTurn'];
    if (modelTurn is! Map<String, dynamic>) return;

    final parts = modelTurn['parts'];
    if (parts is! List) return;

    for (final part in parts) {
      if (part is! Map<String, dynamic>) continue;

      final text = part['text'];
      if (text is String && text.isNotEmpty) {
        _events.add('Gemini: $text');
      }

      final inlineData = part['inlineData'];
      if (inlineData is Map<String, dynamic>) {
        final data = inlineData['data'];
        if (data is String) {
          final pcmBytes = base64Decode(data);
          _outputAudioChunks += 1;
          _outputAudioBytes += pcmBytes.length;
          unawaited(_audioPlayer.enqueue(pcmBytes));
          _emitAudioSummaryIfNeeded();
        }
      }
    }
  }

  void _emitAudioSummaryIfNeeded() {
    final now = DateTime.now();
    final last = _lastAudioSummaryAt;
    if (_outputAudioChunks == 1 ||
        last == null ||
        now.difference(last) >= const Duration(seconds: 2)) {
      _lastAudioSummaryAt = now;
      _events.add(
        'Gemini audio received: $_outputAudioChunks chunks, '
        '$_outputAudioBytes bytes',
      );
    }
  }

  Future<void> _handleToolCall(Map<String, dynamic> toolCall) async {
    final calls = toolCall['functionCalls'];
    if (calls is! List) return;

    final responses = <Map<String, dynamic>>[];
    for (final call in calls) {
      if (call is! Map<String, dynamic>) continue;

      final id = call['id']?.toString();
      final name = call['name']?.toString() ?? '';
      final args = call['args'] is Map<String, dynamic>
          ? call['args'] as Map<String, dynamic>
          : <String, dynamic>{};

      _events.add('Tool call: $name($args)');
      final result = await _executeTool(name, args);
      _events.add('Tool response: $name -> $result');

      responses.add({
        'id': ?id,
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

  Future<Map<String, dynamic>> _executeTool(
    String name,
    Map<String, dynamic> args,
  ) async {
    switch (name) {
      case 'addTransaction':
        return {
          'success': true,
          'message': 'Mock: transaction added',
          'args': args,
        };
      case 'listTransactions':
        return {'transactions': <Map<String, dynamic>>[], 'count': 0};
      case 'listAccounts':
        return {'accounts': <Map<String, dynamic>>[]};
      default:
        return {'error': 'Unknown tool: $name'};
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

const _toolDeclarations = [
  {
    'name': 'addTransaction',
    'description':
        'Add a new transaction. Use type "expense" when spending, "income" '
        'when receiving money, "transfer" when moving between accounts.',
    'parameters': {
      'type': 'OBJECT',
      'properties': {
        'type': {
          'type': 'STRING',
          'description': 'Transaction type',
          'enum': ['expense', 'income', 'transfer'],
        },
        'amount': {'type': 'NUMBER', 'description': 'The amount, e.g. 12.50.'},
        'description': {
          'type': 'STRING',
          'description': 'Brief description of the transaction.',
        },
      },
      'required': ['type', 'amount', 'description'],
    },
  },
  {
    'name': 'listTransactions',
    'description': 'List recent transactions. Supports filtering by type.',
    'parameters': {
      'type': 'OBJECT',
      'properties': {
        'type': {
          'type': 'STRING',
          'description': 'Filter by type. Optional.',
          'enum': ['expense', 'income', 'transfer'],
        },
      },
    },
  },
  {
    'name': 'listAccounts',
    'description': 'List all user accounts.',
    'parameters': {'type': 'OBJECT', 'properties': <String, Object>{}},
  },
];
