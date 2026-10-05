import 'dart:convert';
import 'dart:typed_data';

import 'agent_generated.dart';

/// Keep each single-use token paired with the model it authorizes.
class LiveToken {
  const LiveToken(this.token, {this.model = kAgentModel});
  static const legacyModel = 'gemini-3.1-flash-live-preview';
  final String token;
  final String model;
  bool get isEmpty => token.isEmpty;
  bool get isNotEmpty => token.isNotEmpty;
}

/// Wire details live here, independently of widgets, persistence and audio I/O.
abstract final class LiveProtocol {
  static const inputRate = 16000;
  static const outputRate = 24000;

  static Uri endpoint({required String token}) => Uri(
    scheme: 'wss',
    host: 'generativelanguage.googleapis.com',
    path:
        '/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContentConstrained',
    queryParameters: {'access_token': token},
  );

  static Map<String, dynamic> setup({String model = kAgentModel}) => {
    'setup': {
      'model': 'models/$model',
      'generationConfig': {
        'responseModalities': ['AUDIO'],
        'speechConfig': {
          'voiceConfig': {
            'prebuiltVoiceConfig': {'voiceName': kAgentVoiceName},
          },
        },
      },
      'inputAudioTranscription': <String, dynamic>{},
      'outputAudioTranscription': <String, dynamic>{},
      'sessionResumption': <String, dynamic>{},
      'contextWindowCompression': {'slidingWindow': <String, dynamic>{}},
    },
  };

  static Map<String, dynamic> text(String text, {bool complete = true}) => {
    'clientContent': {
      'turns': [
        {
          'role': 'user',
          'parts': [
            {'text': text},
          ],
        },
      ],
      'turnComplete': complete,
    },
  };

  /// Opens a user turn on a socket minted with voice activity detection off.
  static Map<String, dynamic> activityStart() => {
    'realtimeInput': {'activityStart': <String, dynamic>{}},
  };

  /// Closes the turn [activityStart] opened; the model answers right away.
  static Map<String, dynamic> activityEnd() => {
    'realtimeInput': {'activityEnd': <String, dynamic>{}},
  };

  static Map<String, dynamic> audio(Uint8List bytes) => {
    'realtimeInput': {
      'audio': {
        'data': base64Encode(bytes),
        'mimeType': 'audio/pcm;rate=$inputRate',
      },
    },
  };

  static Map<String, dynamic> decode(Object? raw) {
    final text = raw is String ? raw : utf8.decode(raw as List<int>);
    final value = jsonDecode(text);
    if (value is! Map) {
      throw const FormatException('Expected a Live message object');
    }
    return value.cast<String, dynamic>();
  }

  /// Ignore non-audio inline data; never play it as arbitrary PCM.
  static Uint8List? pcm(Map part) {
    final inline = part['inlineData'];
    if (inline is! Map || inline['data'] is! String) return null;
    final mime = inline['mimeType'];
    if (mime is! String || !RegExp(r'^audio/pcm(?:;|$)').hasMatch(mime)) {
      return null;
    }
    final rate = RegExp(r'(?:^|;)\s*rate=(\d+)').firstMatch(mime);
    if (rate != null && rate[1] != '$outputRate') {
      throw FormatException('Unsupported Live output rate: ${rate[1]}');
    }
    final bytes = base64Decode(inline['data'] as String);
    if (bytes.length.isOdd) {
      throw const FormatException('Unaligned PCM16 audio');
    }
    return bytes;
  }
}
