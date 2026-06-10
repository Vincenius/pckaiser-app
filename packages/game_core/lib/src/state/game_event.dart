/// Who may see a [GameEvent] in filtered views (ARCHITECTURE.md).
enum EventVisibility {
  /// Everyone (e.g. war declarations, elections, world events).
  public,

  /// Only the realm in [GameEvent.slot] (e.g. own intel reports).
  owner,

  /// Only the slots listed in [GameEvent.participants].
  participants,
}

/// The single source for all player-facing notifications: the client's
/// event feed, the "since your last turn" recap, and undo/replay tooling
/// all consume this stream (ARCHITECTURE.md).
class GameEvent {
  GameEvent({
    required this.year,
    required this.slot,
    required this.type,
    required this.visibility,
    this.participants = const [],
    this.payload = const {},
  });

  factory GameEvent.fromJson(Map<String, dynamic> json) => GameEvent(
        year: json['year'] as int,
        slot: json['slot'] as int,
        type: json['type'] as String,
        visibility:
            EventVisibility.values.byName(json['visibility'] as String),
        participants: (json['participants'] as List?)?.cast<int>() ?? const [],
        payload:
            (json['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
      );

  final int year;

  /// Realm slot the event originates from (0 = world/system event).
  final int slot;

  /// Event type identifier, e.g. "warDeclared", "townGrew", "personDied".
  final String type;

  final EventVisibility visibility;

  /// Realm slots that may see this event when [visibility] is
  /// [EventVisibility.participants].
  final List<int> participants;

  final Map<String, dynamic> payload;

  /// Whether [viewerSlot] may see this event in a filtered view.
  bool visibleTo(int viewerSlot) => switch (visibility) {
        EventVisibility.public => true,
        EventVisibility.owner => viewerSlot == slot,
        EventVisibility.participants => participants.contains(viewerSlot),
      };

  Map<String, dynamic> toJson() => {
        'year': year,
        'slot': slot,
        'type': type,
        'visibility': visibility.name,
        'participants': participants,
        'payload': payload,
      };
}
