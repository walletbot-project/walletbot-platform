/// Structured events emitted by a [VoiceExpenseCommand] for the UI to render
/// as a chat conversation. Each event is one observable moment in the
/// session — speech delta, tool call, lifecycle change, or system notice.
///
/// [at] defaults to the emission time; restored events (session replay,
/// durable-log rehydration) pass the original occurrence time instead.
sealed class VoiceEvent {
  VoiceEvent({DateTime? at}) : at = at ?? DateTime.now();

  final DateTime at;
}

// -- Lifecycle ---------------------------------------------------------------

class VoiceConnectingEvent extends VoiceEvent {
  VoiceConnectingEvent(this.message, {super.at});
  final String message;
}

class VoiceConnectedEvent extends VoiceEvent {
  VoiceConnectedEvent({super.at});
}

class VoiceDisconnectedEvent extends VoiceEvent {
  VoiceDisconnectedEvent({this.code, this.reason, super.at});
  final int? code;
  final String? reason;
}

class VoiceErrorEvent extends VoiceEvent {
  VoiceErrorEvent(this.message, {this.isTransient = false, super.at});
  final String message;

  /// Whether the operation can recover without user action. Transient errors
  /// remain available to persistence/export consumers, while the UI may
  /// collapse repeated retries into one connection-state notice.
  final bool isTransient;
}

// -- Generic system notice (informational) -----------------------------------

class VoiceSystemEvent extends VoiceEvent {
  VoiceSystemEvent(this.message, {super.at});
  final String message;
}

/// Explicit user/client action that is part of the conversation audit trail
/// (mute changes, send button, screen attach/detach, playback mode, etc.).
class VoiceClientActionEvent extends VoiceEvent {
  VoiceClientActionEvent(this.action, {this.details = const {}, super.at});
  final String action;
  final Map<String, Object?> details;
}

class VoiceSessionResumptionEvent extends VoiceEvent {
  VoiceSessionResumptionEvent({
    required this.resumable,
    required this.hasNewHandle,
    super.at,
  });
  final bool resumable;
  final bool hasNewHandle;
}

class VoiceGoAwayEvent extends VoiceEvent {
  VoiceGoAwayEvent(this.timeLeft, {super.at});
  final String? timeLeft;
}

class VoiceUsageMetadataEvent extends VoiceEvent {
  VoiceUsageMetadataEvent(this.metadata, {super.at});
  final Map<String, Object?> metadata;
}

// -- Speech ------------------------------------------------------------------

/// Partial transcript chunk for the current user turn. The view accumulates
/// consecutive deltas into a single bubble until a turn boundary is signaled
/// (next agent delta, tool call, or explicit finalisation).
class VoiceUserTranscriptDelta extends VoiceEvent {
  VoiceUserTranscriptDelta(this.text, {super.at});
  final String text;
}

/// Partial transcript chunk for the current agent turn.
class VoiceAgentTranscriptDelta extends VoiceEvent {
  VoiceAgentTranscriptDelta(this.text, {super.at});
  final String text;
}

/// Server signaled `turnComplete: true` — finalise the agent bubble.
class VoiceAgentTurnComplete extends VoiceEvent {
  VoiceAgentTurnComplete({super.at});
}

/// The server or client cut the agent's current audio response short.
class VoiceAgentInterruptedEvent extends VoiceEvent {
  VoiceAgentInterruptedEvent({this.reason = 'server_interrupted', super.at});
  final String reason;
}

// -- Tools -------------------------------------------------------------------

class VoiceToolCallEvent extends VoiceEvent {
  VoiceToolCallEvent({
    required this.id,
    required this.name,
    required this.args,
    super.at,
  });

  final String id;
  final String name;
  final Map<String, dynamic> args;
}

class VoiceToolResultEvent extends VoiceEvent {
  VoiceToolResultEvent({
    required this.id,
    required this.name,
    required this.result,
    super.at,
  });

  final String id;
  final String name;
  final Map<String, dynamic> result;
}

class VoiceToolCancelledEvent extends VoiceEvent {
  VoiceToolCancelledEvent(this.ids, {super.at});
  final List<String> ids;
}

// -- Durable-log restoration ---------------------------------------------------

/// Persisted event types that carry conversation content a restored screen
/// can render. Everything else in the durable log (audio chunks, raw protocol
/// frames, lifecycle noise) is diagnostic-only.
const Set<String> kConversationEventTypes = {
  'user_transcript_delta',
  'agent_transcript_delta',
  'agent_turn_complete',
  'agent_interrupted',
  'send_message',
  'tool_call',
  'tool_result',
  'tool_cancelled',
};

/// Rebuilds the [VoiceEvent] for a persisted session-event row, the inverse of
/// the command's event-record encoding. Returns null for rows that carry no
/// renderable conversation content.
VoiceEvent? voiceEventFromRecord({
  required String type,
  required Map<String, Object?> payload,
  required DateTime at,
}) {
  switch (type) {
    case 'user_transcript_delta':
    case 'agent_transcript_delta':
      final text = payload['text'];
      if (text is! String || text.isEmpty) return null;
      return type == 'user_transcript_delta'
          ? VoiceUserTranscriptDelta(text, at: at)
          : VoiceAgentTranscriptDelta(text, at: at);
    case 'agent_turn_complete':
      return VoiceAgentTurnComplete(at: at);
    case 'agent_interrupted':
      return VoiceAgentInterruptedEvent(
        reason: payload['reason']?.toString() ?? 'server_interrupted',
        at: at,
      );
    case 'send_message':
      final text = payload['text'];
      if (text is! String || text.isEmpty) return null;
      return VoiceClientActionEvent(
        'send_message',
        details: {'text': text},
        at: at,
      );
    case 'tool_call':
      final args = payload['args'];
      return VoiceToolCallEvent(
        id: payload['id']?.toString() ?? '',
        name: payload['name']?.toString() ?? '',
        args: args is Map ? args.cast<String, dynamic>() : <String, dynamic>{},
        at: at,
      );
    case 'tool_result':
      final result = payload['result'];
      return VoiceToolResultEvent(
        id: payload['id']?.toString() ?? '',
        name: payload['name']?.toString() ?? '',
        result: result is Map
            ? result.cast<String, dynamic>()
            : <String, dynamic>{},
        at: at,
      );
    case 'tool_cancelled':
      final ids = payload['ids'];
      return VoiceToolCancelledEvent(
        ids is List
            ? ids.map((id) => id.toString()).toList(growable: false)
            : const [],
        at: at,
      );
    default:
      return null;
  }
}
