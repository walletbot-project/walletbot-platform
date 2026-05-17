/// Structured events emitted by a [VoiceExpenseCommand] for the UI to render
/// as a chat conversation. Each event is one observable moment in the
/// session — speech delta, tool call, lifecycle change, or system notice.
sealed class VoiceEvent {
  VoiceEvent() : at = DateTime.now();

  final DateTime at;
}

// -- Lifecycle ---------------------------------------------------------------

class VoiceConnectingEvent extends VoiceEvent {
  VoiceConnectingEvent(this.message);
  final String message;
}

class VoiceConnectedEvent extends VoiceEvent {}

class VoiceDisconnectedEvent extends VoiceEvent {
  VoiceDisconnectedEvent({this.code, this.reason});
  final int? code;
  final String? reason;
}

class VoiceErrorEvent extends VoiceEvent {
  VoiceErrorEvent(this.message);
  final String message;
}

// -- Generic system notice (informational) -----------------------------------

class VoiceSystemEvent extends VoiceEvent {
  VoiceSystemEvent(this.message);
  final String message;
}

// -- Speech ------------------------------------------------------------------

/// Partial transcript chunk for the current user turn. The view accumulates
/// consecutive deltas into a single bubble until a turn boundary is signaled
/// (next agent delta, tool call, or explicit finalisation).
class VoiceUserTranscriptDelta extends VoiceEvent {
  VoiceUserTranscriptDelta(this.text);
  final String text;
}

/// Partial transcript chunk for the current agent turn.
class VoiceAgentTranscriptDelta extends VoiceEvent {
  VoiceAgentTranscriptDelta(this.text);
  final String text;
}

/// Server signaled `turnComplete: true` — finalise the agent bubble.
class VoiceAgentTurnComplete extends VoiceEvent {}

/// Server signaled `interrupted: true` — the agent's audio was cut short.
class VoiceAgentInterruptedEvent extends VoiceEvent {}

// -- Tools -------------------------------------------------------------------

class VoiceToolCallEvent extends VoiceEvent {
  VoiceToolCallEvent({
    required this.id,
    required this.name,
    required this.args,
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
  });

  final String id;
  final String name;
  final Map<String, dynamic> result;
}

class VoiceToolCancelledEvent extends VoiceEvent {
  VoiceToolCancelledEvent(this.ids);
  final List<String> ids;
}
