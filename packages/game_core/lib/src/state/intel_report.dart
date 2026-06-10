/// Result of a successful espionage mission (ARCHITECTURE.md, PROJECT_REQUIREMENTS.md):
/// fuzzed (±10%) values about a target realm, timestamped with the in-game
/// year. Stored in the spying realm's private state; survives turns.
class IntelReport {
  IntelReport({
    required this.targetSlot,
    required this.year,
    required this.values,
  });

  factory IntelReport.fromJson(Map<String, dynamic> json) => IntelReport(
        targetSlot: json['targetSlot'] as int,
        year: json['year'] as int,
        values: (json['values'] as Map).cast<String, int>(),
      );

  final int targetSlot;

  /// In-game year the intel was gathered ("as of year X").
  final int year;

  /// Fuzzed values keyed by stat name (e.g. "treasury", "armySize",
  /// "guardLevel", "grainStock").
  final Map<String, int> values;

  IntelReport copy() => IntelReport(
        targetSlot: targetSlot,
        year: year,
        values: Map.of(values),
      );

  Map<String, dynamic> toJson() => {
        'targetSlot': targetSlot,
        'year': year,
        'values': values,
      };
}
