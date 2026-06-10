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

  /// Deep copy — payloads hold nested lists/maps, and sharing them across
  /// `GameState.copy()` snapshots would let a mutation leak into the undo
  /// stack.
  PendingDecision copy() => PendingDecision(
        id: id,
        type: type,
        decidingSlot: decidingSlot,
        payload: _copyJsonMap(payload),
        deadline: deadline,
      );

  static Map<String, dynamic> _copyJsonMap(Map<String, dynamic> map) => {
        for (final e in map.entries) e.key: _copyJsonValue(e.value),
      };

  static Object? _copyJsonValue(Object? value) => switch (value) {
        final Map<dynamic, dynamic> m => {
            for (final e in m.entries) e.key: _copyJsonValue(e.value),
          },
        final List<dynamic> l => [for (final v in l) _copyJsonValue(v)],
        _ => value,
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'decidingSlot': decidingSlot,
        'payload': payload,
        'deadline': deadline,
      };
}
