/// Server-side records (ARCHITECTURE.md "Data Model"). The game state
/// itself stays a `game_core` JSON document — these records only carry
/// the orchestration metadata around it.
library;

import 'dart:math';

/// RFC-4122 v4 UUID from a secure random source — avoids a package
/// dependency for the one thing we need.
String uuidV4() {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

/// Room code for a match: 5 uppercase letters, short enough to read out
/// loud or type by hand. 26⁵ ≈ 11.9M codes — the service retries on the
/// rare collision with an existing match.
String matchCode() {
  const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  final rng = Random.secure();
  return String.fromCharCodes(
      List.generate(5, (_) => letters.codeUnitAt(rng.nextInt(letters.length))));
}

/// A registered device (`players` table). No auth in V2's first cut:
/// the UUID is generated on the device and IS the identity.
class PlayerRecord {
  PlayerRecord({
    required this.id,
    required this.displayName,
    this.fcmToken,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toUtc();

  factory PlayerRecord.fromJson(Map<String, dynamic> json) => PlayerRecord(
        id: json['id'] as String,
        displayName: json['display_name'] as String,
        fcmToken: json['fcm_token'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final String id;
  String displayName;
  String? fcmToken;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'display_name': displayName,
        'fcm_token': fcmToken,
        'created_at': createdAt.toIso8601String(),
      };
}

/// One seat in a match (`match_players` row): which device plays which
/// realm slot, plus the founder setup used once the match starts.
class MatchPlayer {
  MatchPlayer({
    required this.playerId,
    required this.turnOrder,
    required this.slot,
    required this.founderName,
    required this.gender,
    required this.dorfName,
    this.color,
    this.idleTurns = 0,
  });

  factory MatchPlayer.fromJson(Map<String, dynamic> json) => MatchPlayer(
        playerId: json['player_id'] as String,
        turnOrder: json['turn_order'] as int,
        slot: json['dynasty_index'] as int,
        founderName: json['founder_name'] as String,
        gender: json['gender'] as int,
        dorfName: json['dorf_name'] as String,
        // Additive field — seats from older rows keep the default color.
        color: json['color'] as int?,
        idleTurns: json['idle_turns'] as int? ?? 0,
      );

  final String playerId;

  /// 0-based join order — equals the `humanPlayer` index inside the
  /// game state's dynasties. Mutable: seats are renumbered when someone
  /// leaves a waiting match so the sequence stays contiguous.
  int turnOrder;

  /// Realm slot 1–30 (`dynasty_index`).
  final int slot;

  final String founderName;
  final int gender;
  final String dorfName;

  /// Chosen map color (ARGB), or null = the client's slot-derived default.
  /// Passed into `HumanPlayerSetup.color` when the match starts.
  final int? color;

  /// Consecutive turns this seat let expire by timeout (never showed up).
  /// Reset to 0 on any submitted action / end-turn. Once it reaches 3 the
  /// match creator may kick the seat and hand its realm to the AI
  /// (`POST /matches/:id/kick`).
  int idleTurns;

  Map<String, dynamic> toJson() => {
        'player_id': playerId,
        'turn_order': turnOrder,
        'dynasty_index': slot,
        'founder_name': founderName,
        'gender': gender,
        'dorf_name': dorfName,
        if (color != null) 'color': color,
        'idle_turns': idleTurns,
      };
}

/// Host-configurable match settings (`matches.settings`).
class MatchSettings {
  MatchSettings({
    this.turnTimeoutHours,
    this.warRoundTimeoutSeconds = 600,
    this.reformationYear = 1020,
    this.ottomanYear = 1040,
    this.warStartYear = 1010,
    this.genderEqualSuccession = true,
    this.suggestChildNames = true,
    this.aiDifficulty = 'mittel',
    this.mapSize = 'gross',
    this.realmCount,
    this.isPublic = false,
    this.template,
    int? seed,
  }) : seed = seed ?? Random.secure().nextInt(1 << 31);

  factory MatchSettings.fromJson(Map<String, dynamic> json) => MatchSettings(
        // Floored at the boundary: a zero/negative timer off the wire would
        // arm every deadline already expired, so the sweep auto-plays the
        // whole match. (Like ai_difficulty, normalized here so the views
        // never echo a value the game doesn't actually play.)
        turnTimeoutHours: switch (json['turn_timeout_hours'] as int?) {
          null => null,
          final h when h < 1 => 1,
          final h => h,
        },
        warRoundTimeoutSeconds: switch (json['war_round_timeout'] as int? ?? 600) {
          final s when s < 60 => 60,
          final s => s,
        },
        reformationYear: json['reformation_year'] as int? ?? 1020,
        ottomanYear: json['ottoman_year'] as int? ?? 1040,
        warStartYear: json['war_start_year'] as int? ?? 1010,
        genderEqualSuccession: json['gender_equal_succession'] as bool? ?? true,
        suggestChildNames: json['suggest_child_names'] as bool? ?? true,
        // Normalized at the boundary: an unknown client value would
        // otherwise be stored and echoed to every seat while the game
        // silently plays mittel — the views must never lie about the
        // difficulty actually in effect.
        aiDifficulty: switch (json['ai_difficulty']) {
          'leicht' || 'mittel' || 'schwer' => json['ai_difficulty'] as String,
          _ => 'mittel',
        },
        // Additive (2026-07-21, map sizes): older matches and clients are
        // always the original large world. Normalized like ai_difficulty.
        mapSize: switch (json['map_size']) {
          'klein' || 'mittel' || 'gross' => json['map_size'] as String,
          _ => 'gross',
        },
        realmCount: json['realm_count'] as int?,
        isPublic: json['is_public'] as bool? ?? false,
        // Additive (matchmaking rooms): ordinary player-hosted matches
        // carry no template. Never accepted off the wire — the API strips
        // it like the seed, so only the server can host a template room.
        template: json['template'] as String?,
        seed: json['seed'] as int?,
      );

  /// null = no turn timer (PROJECT_REQUIREMENTS: off/12h/24h/48h/7d).
  final int? turnTimeoutHours;

  /// Short clock for awaited war-round input (ARCHITECTURE "war clock").
  final int warRoundTimeoutSeconds;

  final int reformationYear;
  final int ottomanYear;

  /// First year war declarations are allowed (§11.1; original 1010).
  final int warStartYear;

  /// Gender-neutral succession (deviation from the original) — passed into
  /// the game world at start as `GameState.genderEqualSuccession`.
  final bool genderEqualSuccession;

  /// Prefill the newborn-naming dialog with a suggested name — passed into
  /// the game world at start as `GameState.suggestChildNames`.
  final bool suggestChildNames;

  /// AI opponent strength ('leicht' | 'mittel' | 'schwer') — kept as the
  /// raw string here (this file stays free of `game_core`); parsed via
  /// `AiDifficulty.fromName` when the world is built, so an unknown value
  /// safely falls back to 'mittel'.
  final String aiDifficulty;

  /// World size ('klein' | 'mittel' | 'gross') — raw string like
  /// [aiDifficulty]; parsed via `MapSize.fromName` when the world is built.
  final String mapSize;

  /// Realm slots in play; null = the size's default. Clamped into the
  /// size's valid range by the service when seating/starting (never
  /// trusted raw — an out-of-range value must not 500 the match start).
  final int? realmCount;

  /// Public match: listed in the lobby's open-games list so anyone can
  /// join, not only those who know the room code. Default private.
  final bool isPublic;

  /// Matchmaking-room type this match was opened as ('blitz' | 'standard' |
  /// 'kaiserreich', see `match_templates.dart`), or null for an ordinary
  /// player-hosted match. Template rooms are server-hosted: they have no
  /// creator, start on their own and are replaced when they do.
  final String? template;

  final int seed;

  /// [includeSeed] is for persistence only. Client-facing views must pass
  /// false: newGame/startGame are deterministic on the seed, so exposing it
  /// lets anyone precompute the map and future random rolls —
  /// `visibleStateFor` zeroes `rngSeed` for exactly this reason.
  Map<String, dynamic> toJson({bool includeSeed = true}) => {
        'turn_timeout_hours': turnTimeoutHours,
        'war_round_timeout': warRoundTimeoutSeconds,
        'reformation_year': reformationYear,
        'ottoman_year': ottomanYear,
        'war_start_year': warStartYear,
        'gender_equal_succession': genderEqualSuccession,
        'suggest_child_names': suggestChildNames,
        'ai_difficulty': aiDifficulty,
        'map_size': mapSize,
        if (realmCount != null) 'realm_count': realmCount,
        'is_public': isPublic,
        if (template != null) 'template': template,
        if (includeSeed) 'seed': seed,
      };
}

enum MatchStatus { waiting, active, finished }

/// A match (`matches` row). [stateJson] is the authoritative `game_core`
/// document once the match started; null while waiting for players.
class MatchRecord {
  MatchRecord({
    required this.id,
    this.humanCount,
    required this.settings,
    required this.players,
    this.status = MatchStatus.waiting,
    this.stateJson,
    this.turnDeadline,
    this.autoStartAt,
    this.warReminderFor,
    this.warPrepFallbackDeadline,
    this.expiryWarnedAt,
    this.winnerPlayerId,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now().toUtc(),
        updatedAt = updatedAt ?? DateTime.now().toUtc();

  factory MatchRecord.fromJson(Map<String, dynamic> json) => MatchRecord(
        id: json['id'] as String,
        humanCount: json['human_count'] as int?,
        settings:
            MatchSettings.fromJson(json['settings'] as Map<String, dynamic>),
        players: [
          for (final p in json['players'] as List)
            MatchPlayer.fromJson((p as Map).cast<String, dynamic>()),
        ],
        status: MatchStatus.values.byName(json['status'] as String),
        stateJson: (json['state'] as Map?)?.cast<String, dynamic>(),
        turnDeadline: json['turn_deadline'] == null
            ? null
            : DateTime.parse(json['turn_deadline'] as String),
        // Additive field — ordinary matches never start on a schedule.
        autoStartAt: json['auto_start_at'] == null
            ? null
            : DateTime.parse(json['auto_start_at'] as String),
        // Additive field — pre-scheduling records sent no war reminder.
        warReminderFor: json['war_reminder_for'] == null
            ? null
            : DateTime.parse(json['war_reminder_for'] as String),
        // Additive field — pre-2026-08-09 records reconstruct it from the
        // running turn deadline (see MatchService._commit).
        warPrepFallbackDeadline: json['war_prep_fallback_deadline'] == null
            ? null
            : DateTime.parse(json['war_prep_fallback_deadline'] as String),
        // Additive field — pre-retention records were never warned.
        expiryWarnedAt: json['expiry_warned_at'] == null
            ? null
            : DateTime.parse(json['expiry_warned_at'] as String),
        winnerPlayerId: json['winner'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  final String id;

  /// Legacy pre-room-code field: matches used to fix their seat count at
  /// creation and auto-start when full. New matches leave it null — the
  /// creator starts the game explicitly (`POST /matches/:id/start`).
  final int? humanCount;

  final MatchSettings settings;
  final List<MatchPlayer> players;
  MatchStatus status;
  Map<String, dynamic>? stateJson;
  DateTime? turnDeadline;

  /// When a waiting matchmaking room starts even though it never filled up
  /// (armed once `MatchTemplate.fallbackSeats` players have joined, cleared
  /// again if the room drops back below that). Null on every ordinary match
  /// and on a room that is still too empty to schedule.
  DateTime? autoStartAt;

  /// The agreed war start this match was already REMINDED of (the ~15 min
  /// "duel starts soon" push) — sent at most once per agreed start time.
  DateTime? warReminderFor;

  /// The war preparation's FALLBACK start (declaration + full turn timer),
  /// kept separately from [turnDeadline] because the combatants may revise
  /// their appointment while the window runs (`WarPrepPlan`, 2026-08-09):
  /// agreeing on a time moves the deadline to it, WITHDRAWING the agreement
  /// has to fall back to this fixed instant instead of silently granting
  /// another full timer. Null outside a war preparation (and in a match
  /// without a turn timer).
  DateTime? warPrepFallbackDeadline;

  /// When the retention sweep warned this (active, stalled) match that it
  /// will be deleted. Cleared again by the sweep once [updatedAt] moves past
  /// it — any activity cancels the pending expiry. Null = never warned.
  DateTime? expiryWarnedAt;

  String? winnerPlayerId;
  final DateTime createdAt;
  DateTime updatedAt;

  MatchPlayer? playerById(String playerId) {
    for (final p in players) {
      if (p.playerId == playerId) return p;
    }
    return null;
  }

  MatchPlayer? playerBySlot(int slot) {
    for (final p in players) {
      if (p.slot == slot) return p;
    }
    return null;
  }

  /// The seat whose [MatchPlayer.turnOrder] equals [turnOrder] (= the
  /// `humanPlayer` index a dynasty carries after conquests/inheritances).
  MatchPlayer? playerByTurnOrder(int turnOrder) {
    for (final p in players) {
      if (p.turnOrder == turnOrder) return p;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'human_count': humanCount,
        'settings': settings.toJson(),
        'players': [for (final p in players) p.toJson()],
        'status': status.name,
        'state': stateJson,
        'turn_deadline': turnDeadline?.toIso8601String(),
        'auto_start_at': autoStartAt?.toIso8601String(),
        'war_reminder_for': warReminderFor?.toIso8601String(),
        'war_prep_fallback_deadline':
            warPrepFallbackDeadline?.toIso8601String(),
        'expiry_warned_at': expiryWarnedAt?.toIso8601String(),
        'winner': winnerPlayerId,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}
