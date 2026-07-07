/// Dynasty status — the human/AI turn dispatch byte of the original
/// (ORIGINAL_GAME.md §2): `FREE`, `AI`, or a human player number.
enum DynastyStatus { free, ai, human }

/// A dynasty, parallel to the realm slots (index = person.dynasty).
class Dynasty {
  Dynasty({
    required this.index,
    required this.status,
    this.humanPlayer,
    required this.religion,
    List<int>? memberIds,
  }) : memberIds = memberIds ?? [];

  factory Dynasty.fromJson(Map<String, dynamic> json) => Dynasty(
        index: json['index'] as int,
        status: DynastyStatus.values.byName(json['status'] as String),
        humanPlayer: json['humanPlayer'] as int?,
        religion: json['religion'] as int,
        // toList(): `cast` alone aliases the source list (toJson emits the
        // live list) — a fromJson(toJson()) clone would share the members.
        memberIds: (json['memberIds'] as List?)?.cast<int>().toList(),
      );

  /// Slot index 1–30.
  final int index;

  DynastyStatus status;

  /// Human player number (0-based among the humans), only when
  /// [status] == [DynastyStatus.human].
  int? humanPlayer;

  /// 0 = katholisch, 1 = evangelisch, 2 = moslemisch.
  int religion;

  /// Living members, insertion order — order matters for succession (§15.4).
  final List<int> memberIds;

  Dynasty copy() => Dynasty(
        index: index,
        status: status,
        humanPlayer: humanPlayer,
        religion: religion,
        memberIds: List.of(memberIds),
      );

  Map<String, dynamic> toJson() => {
        'index': index,
        'status': status.name,
        'humanPlayer': humanPlayer,
        'religion': religion,
        'memberIds': memberIds,
      };
}
