/// A decision required from a player outside their own turn — marriage
/// consent, Kurfürst votes, convert-or-die, heir selection
/// (ARCHITECTURE.md "Pending decisions").
///
/// Local mode resolves these inline in the UI; online mode pauses the turn
/// pipeline and notifies the deciding player. Every type defines an
/// AI/default fallback so a timeout can resolve it.
class PendingDecision {
  PendingDecision({
    required this.id,
    required this.type,
    required this.decidingSlot,
    this.payload = const {},
    this.deadline,
  });

  factory PendingDecision.fromJson(Map<String, dynamic> json) =>
      PendingDecision(
        id: json['id'] as String,
        type: json['type'] as String,
        decidingSlot: json['decidingSlot'] as int,
        payload:
            (json['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
        deadline: json['deadline'] as String?,
      );

  final String id;

  /// e.g. "marriageConsent", "electorVote", "convertOrDie", "heirChoice".
  final String type;

  /// Realm slot whose player must decide.
  final int decidingSlot;

  final Map<String, dynamic> payload;

  /// ISO-8601 timestamp; null = no timer (local mode, or timer off).
  final String? deadline;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'decidingSlot': decidingSlot,
        'payload': payload,
        'deadline': deadline,
      };
}
