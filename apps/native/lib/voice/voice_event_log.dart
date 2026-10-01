import 'voice_event.dart';

VoiceEventRecord voiceEventRecord(VoiceEvent event) => switch (event) {
  VoiceConnectingEvent(:final message) => VoiceEventRecord(
    'connecting',
    'local',
    {'message': message},
  ),
  VoiceConnectedEvent() => const VoiceEventRecord('connected', 'local', {}),
  VoiceDisconnectedEvent(:final code, :final reason) => VoiceEventRecord(
    'disconnected',
    'server',
    {'code': ?code, 'reason': ?reason},
  ),
  VoiceErrorEvent(:final message, :final isTransient, :final code) =>
    VoiceEventRecord('error', 'local', {
      'message': message,
      'isTransient': isTransient,
      'code': ?code,
    }),
  VoiceSystemEvent(:final message) => VoiceEventRecord('system', 'local', {
    'message': message,
  }),
  VoiceClientActionEvent(:final action, :final details) => VoiceEventRecord(
    action,
    'client',
    details,
    modality: details['interactionModality']?.toString(),
  ),
  VoiceSessionResumptionEvent(:final resumable, :final hasNewHandle) =>
    VoiceEventRecord('session_resumption_update', 'server', {
      'resumable': resumable,
      'hasNewHandle': hasNewHandle,
    }),
  VoiceGoAwayEvent(:final timeLeft) => VoiceEventRecord('go_away', 'server', {
    'timeLeft': ?timeLeft,
  }),
  VoiceUsageMetadataEvent(:final metadata) => VoiceEventRecord(
    'usage_metadata',
    'server',
    metadata,
  ),
  VoiceUserTranscriptDelta(:final text) => VoiceEventRecord(
    'user_transcript_delta',
    'server',
    {'text': text},
    modality: 'voice',
  ),
  VoiceAgentTranscriptDelta(:final text) => VoiceEventRecord(
    'agent_transcript_delta',
    'server',
    {'text': text},
    modality: 'voice',
  ),
  VoiceAgentTurnComplete() => const VoiceEventRecord(
    'agent_turn_complete',
    'server',
    {},
  ),
  VoiceAgentInterruptedEvent(:final reason) => VoiceEventRecord(
    'agent_interrupted',
    reason == 'server_interrupted' ? 'server' : 'client',
    {'reason': reason},
  ),
  VoiceToolCallEvent(:final id, :final name, :final args) => VoiceEventRecord(
    'tool_call',
    'server',
    {'id': id, 'name': name, 'args': args},
    modality: 'tool',
  ),
  VoiceToolResultEvent(:final id, :final name, :final result) =>
    VoiceEventRecord('tool_result', 'client', {
      'id': id,
      'name': name,
      'result': result,
    }, modality: 'tool'),
  VoiceToolCancelledEvent(:final ids) => VoiceEventRecord(
    'tool_cancelled',
    'server',
    {'ids': ids},
    modality: 'tool',
  ),
};

Map<String, Object?> withoutInlineBinary(Map<dynamic, dynamic> value) {
  Object? clean(Object? node) {
    if (node is List) return node.map(clean).toList(growable: false);
    if (node is! Map) return node;
    final mimeType = node['mimeType']?.toString();
    return <String, Object?>{
      for (final entry in node.entries)
        entry.key.toString():
            entry.key == 'data' &&
                mimeType != null &&
                mimeType.startsWith('audio/')
            ? '<stored in binary event>'
            : clean(entry.value),
    };
  }

  return (clean(value) as Map).cast<String, Object?>();
}

class VoiceEventRecord {
  const VoiceEventRecord(
    this.type,
    this.direction,
    this.payload, {
    this.modality,
  });

  final String type;
  final String direction;
  final Map<String, Object?> payload;
  final String? modality;
}
