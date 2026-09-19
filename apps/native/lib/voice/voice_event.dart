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
  VoiceErrorEvent(
    this.message, {
    this.isTransient = false,
    this.code,
    super.at,
  });
  final String message;

  /// Whether the operation can recover without user action. Transient errors
  /// remain available to persistence/export consumers, while the UI may
  /// collapse repeated retries into one connection-state notice.
  final bool isTransient;

  /// Machine-readable cause for the cases the UI must word differently, so the
  /// screen never has to match on [message]. Currently the mint refusals from
  /// `live/helpers.ts:LiveTokenError` plus `missing_credentials`. Null for
  /// everything else.
  final String? code;
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

/// Builds the transcript seed a (re)connect sends to the model as its first
/// client message, restoring conversation context from the durable log.
///
/// Gemini session-resumption handles are not reliable for this: after an
/// abrupt disconnect (airplane mode, background kill — anything that dies
/// without a close frame) a handle stops resuming within seconds, and the
/// server then silently opens a BLANK session instead of failing (verified
/// against the live API, 2026-08-21). Re-seeding from the local log is
/// deterministic and guarantees the model's context always matches the
/// conversation the user sees on screen.
///
/// [pendingTexts] are typed messages still queued for live delivery after
/// the seed — their trailing `send_message` log entries are excluded so the
/// model doesn't see them twice. Returns null when there is nothing to
/// restore.
String? buildConversationSeed(
  List<VoiceEvent> events, {
  List<String> pendingTexts = const [],
  int maxChars = 6000,
}) {
  final lines = <({String role, String text})>[];
  final user = StringBuffer();
  final agent = StringBuffer();

  void flushUser() {
    final text = user.toString().trim();
    if (text.isNotEmpty) lines.add((role: 'User', text: text));
    user.clear();
  }

  void flushAgent() {
    final text = agent.toString().trim();
    if (text.isNotEmpty) lines.add((role: 'Assistant', text: text));
    agent.clear();
  }

  for (final event in events) {
    switch (event) {
      case VoiceUserTranscriptDelta(:final text):
        flushAgent();
        user.write(text);
      case VoiceAgentTranscriptDelta(:final text):
        flushUser();
        agent.write(text);
      case VoiceAgentTurnComplete():
      case VoiceAgentInterruptedEvent():
        flushAgent();
      case VoiceClientActionEvent(:final action, :final details)
          when action == 'send_message':
        final text = details['text'];
        if (text is String && text.isNotEmpty) {
          flushUser();
          flushAgent();
          lines.add((role: 'User', text: text));
        }
      default:
        break;
    }
  }
  flushUser();
  flushAgent();

  // Trailing user messages that are still queued for live delivery would
  // otherwise appear twice: once in the seed, once when the queue flushes.
  final pending = List<String>.of(pendingTexts);
  while (lines.isNotEmpty && pending.isNotEmpty) {
    final last = lines.last;
    if (last.role != 'User') break;
    final index = pending.indexOf(last.text);
    if (index < 0) break;
    pending.removeAt(index);
    lines.removeLast();
  }

  if (lines.isEmpty) return null;

  var transcript = lines.map((line) => '${line.role}: ${line.text}').join('\n');
  var truncated = false;
  if (transcript.length > maxChars) {
    transcript = transcript.substring(transcript.length - maxChars);
    truncated = true;
  }
  final scope = truncated
      ? 'the recent part of the conversation'
      : 'the conversation';
  return '[Context restore: the previous connection dropped. This is '
      '$scope so far:]\n$transcript\n'
      '[End of transcript. Continue this conversation naturally in the same '
      'language. Do not greet again and do not mention the reconnection.]';
}

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
