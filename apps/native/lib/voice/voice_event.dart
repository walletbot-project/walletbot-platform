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
  VoiceErrorEvent(this.message, {this.isTransient = false});
  final String message;

  /// Whether the operation can recover without user action. Transient errors
  /// remain available to persistence/export consumers, while the UI may
  /// collapse repeated retries into one connection-state notice.
  final bool isTransient;
}

// -- Generic system notice (informational) -----------------------------------

class VoiceSystemEvent extends VoiceEvent {
  VoiceSystemEvent(this.message);
  final String message;
}

/// Explicit user/client action that is part of the conversation audit trail
/// (mute changes, send button, screen attach/detach, playback mode, etc.).
class VoiceClientActionEvent extends VoiceEvent {
  VoiceClientActionEvent(this.action, [this.details = const {}]);
  final String action;
  final Map<String, Object?> details;
}

class VoiceSessionResumptionEvent extends VoiceEvent {
  VoiceSessionResumptionEvent({
    required this.resumable,
    required this.hasNewHandle,
  });
  final bool resumable;
  final bool hasNewHandle;
}

class VoiceGoAwayEvent extends VoiceEvent {
  VoiceGoAwayEvent(this.timeLeft);
  final String? timeLeft;
}

class VoiceUsageMetadataEvent extends VoiceEvent {
  VoiceUsageMetadataEvent(this.metadata);
  final Map<String, Object?> metadata;
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

/// The server or client cut the agent's current audio response short.
class VoiceAgentInterruptedEvent extends VoiceEvent {
  VoiceAgentInterruptedEvent({this.reason = 'server_interrupted'});
  final String reason;
}

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
