/// Which crown an election is for (§17.3, §17.4).
enum Office { kaiser, sultan }

/// State of an ongoing Kaiser/Sultan election (§17.3). Lives in the game
/// state because human finalists (bribery) and human electors (votes) act
/// through pending decisions — possibly across requests in online mode.
class ActiveElection {
  ActiveElection({
    required this.office,
    required this.finalistIds,
    required this.electorIds,
    Set<int>? bribesDone,
    Map<int, Map<int, int>>? bribes,
    Map<int, int>? votes,
  })  : bribesDone = bribesDone ?? {},
        bribes = bribes ?? {},
        votes = votes ?? {};

  factory ActiveElection.fromJson(Map<String, dynamic> json) =>
      ActiveElection(
        office: Office.values.byName(json['office'] as String),
        finalistIds: (json['finalistIds'] as List).cast<int>(),
        electorIds: (json['electorIds'] as List).cast<int>(),
        bribesDone:
            (json['bribesDone'] as List?)?.cast<int>().toSet(),
        bribes: {
          for (final e in ((json['bribes'] as Map?) ?? {}).entries)
            int.parse(e.key as String): {
              for (final b in (e.value as Map).entries)
                int.parse(b.key as String): b.value as int,
            },
        },
        votes: {
          for (final e in ((json['votes'] as Map?) ?? {}).entries)
            int.parse(e.key as String): e.value as int,
        },
      );

  final Office office;

  /// The two (or one, when acclaimed) finalist person ids.
  final List<int> finalistIds;

  /// Snapshot of the voting persons at election start.
  final List<int> electorIds;

  /// Finalists whose bribery phase has finished.
  final Set<int> bribesDone;

  /// elector id → finalist id → total Taler received.
  final Map<int, Map<int, int>> bribes;

  /// elector id → finalist id voted for.
  final Map<int, int> votes;

  int bribeFor(int electorId, int finalistId) =>
      bribes[electorId]?[finalistId] ?? 0;

  void addBribe(int electorId, int finalistId, int amount) {
    final perElector = bribes.putIfAbsent(electorId, () => {});
    perElector[finalistId] = (perElector[finalistId] ?? 0) + amount;
  }

  ActiveElection copy() => ActiveElection(
        office: office,
        finalistIds: List.of(finalistIds),
        electorIds: List.of(electorIds),
        bribesDone: Set.of(bribesDone),
        bribes: {
          for (final e in bribes.entries) e.key: Map.of(e.value),
        },
        votes: Map.of(votes),
      );

  Map<String, dynamic> toJson() => {
        'office': office.name,
        'finalistIds': finalistIds,
        'electorIds': electorIds,
        'bribesDone': bribesDone.toList(),
        'bribes': {
          for (final e in bribes.entries)
            '${e.key}': {for (final b in e.value.entries) '${b.key}': b.value},
        },
        'votes': {for (final e in votes.entries) '${e.key}': e.value},
      };
}
