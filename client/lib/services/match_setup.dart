import 'package:game_core/game_core.dart'
    show
        AiDifficulty,
        MapSize,
        defaultOttomanYear,
        defaultReformationYear,
        defaultWarStartYear;

/// A player's choices for creating or joining an online match — the client
/// half of the wire protocol (mirrored by `backend/lib/src/models.dart`).
/// Lives next to the API layer so every snake_case key has ONE home:
/// [setupJson] is the per-seat payload, [settingsJson] the host settings.
class MatchSetup {
  MatchSetup({
    required this.founderName,
    required this.gender,
    required this.countrySlot,
    required this.dorfName,
    required this.turnTimeoutHours,
    this.warRoundTimeoutSeconds = 600,
    this.reformationYear = defaultReformationYear,
    this.ottomanYear = defaultOttomanYear,
    this.warStartYear = defaultWarStartYear,
    this.isPublic = false,
    this.genderEqualSuccession = true,
    this.suggestChildNames = true,
    this.aiDifficulty = AiDifficulty.mittel,
    this.mapSize = MapSize.gross,
    int? realmCount,
  }) : realmCount = realmCount ?? mapSize.defaultRealmCount;

  final String founderName;
  final int gender;
  final int? countrySlot;
  final String dorfName;
  final int? turnTimeoutHours;
  // Host-only choices (ignored when joining an existing match).
  final int warRoundTimeoutSeconds;
  final int reformationYear;
  final int ottomanYear;
  final int warStartYear;
  final bool isPublic;
  final bool genderEqualSuccession;
  final bool suggestChildNames;
  final AiDifficulty aiDifficulty;
  final MapSize mapSize;
  final int realmCount;

  /// Per-seat setup sent on create AND join.
  Map<String, dynamic> setupJson() => {
    'founder_name': founderName,
    'gender': gender,
    if (countrySlot != null) 'country_slot': countrySlot,
    'dorf_name': dorfName,
  };

  /// Match settings sent by the host on create only.
  Map<String, dynamic> settingsJson() => {
    'turn_timeout_hours': turnTimeoutHours,
    'war_round_timeout': warRoundTimeoutSeconds,
    'reformation_year': reformationYear,
    'ottoman_year': ottomanYear,
    'war_start_year': warStartYear,
    'is_public': isPublic,
    'gender_equal_succession': genderEqualSuccession,
    'suggest_child_names': suggestChildNames,
    'ai_difficulty': aiDifficulty.name,
    'map_size': mapSize.name,
    'realm_count': realmCount,
  };
}
