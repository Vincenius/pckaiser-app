/// One reign in the Kaiser or Sultan chronicle (ORIGINAL_GAME.md §2, §17.5).
class ChronicleRecord {
  ChronicleRecord({
    required this.name,
    required this.accessionYear,
    this.personId,
    this.slot,
    this.deathYear,
    this.epithet,
  });

  factory ChronicleRecord.fromJson(Map<String, dynamic> json) =>
      ChronicleRecord(
        name: json['name'] as String,
        accessionYear: json['accessionYear'] as int,
        personId: json['personId'] as int?,
        slot: json['slot'] as int?,
        deathYear: json['deathYear'] as int?,
        epithet: json['epithet'] as String?,
      );

  final String name;
  final int accessionYear;

  /// Office holder's person id — table names repeat, so the open record
  /// is matched by id (null only in pre-personId saves).
  final int? personId;

  /// Home realm slot (dynasty index) at coronation — the country the
  /// office holder "stammt aus" in the chronicle (null in older saves;
  /// the UI falls back to the person's dynasty then).
  final int? slot;

  /// Null while the office holder is alive / in office.
  int? deathYear;

  /// Awarded only on death in office, 50% chance of none (§17.5).
  String? epithet;

  ChronicleRecord copy() => ChronicleRecord(
        name: name,
        accessionYear: accessionYear,
        personId: personId,
        slot: slot,
        deathYear: deathYear,
        epithet: epithet,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'accessionYear': accessionYear,
        'personId': personId,
        'slot': slot,
        'deathYear': deathYear,
        'epithet': epithet,
      };
}

/// A pending assassination order (ORIGINAL_GAME.md §2, §13.3).
class AssassinationOrder {
  AssassinationOrder({
    required this.sponsorSlot,
    required this.targetSlot,
    required this.count,
  });

  factory AssassinationOrder.fromJson(Map<String, dynamic> json) =>
      AssassinationOrder(
        sponsorSlot: json['sponsorSlot'] as int,
        targetSlot: json['targetSlot'] as int,
        count: json['count'] as int,
      );

  final int sponsorSlot;
  final int targetSlot;
  int count;

  AssassinationOrder copy() => AssassinationOrder(
        sponsorSlot: sponsorSlot,
        targetSlot: targetSlot,
        count: count,
      );

  Map<String, dynamic> toJson() => {
        'sponsorSlot': sponsorSlot,
        'targetSlot': targetSlot,
        'count': count,
      };
}
