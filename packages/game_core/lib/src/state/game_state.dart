import 'chronicle.dart';
import 'constants.dart';
import 'dynasty.dart';
import 'election.dart';
import 'game_event.dart';
import 'pending_decision.dart';
import 'person.dart';
import 'realm.dart';
import 'versioning.dart';
import 'war.dart';
import 'world_map.dart';

/// The complete game state (ORIGINAL_GAME.md §2). One JSON document — the
/// same schema is saved locally and stored in the server's JSONB column;
/// it must stay forward-compatible (add fields, never remove).
class GameState {
  GameState({
    this.schemaVersion = currentSchemaVersion,
    this.rulesVersion = currentRulesVersion,
    required this.year,
    required this.reformationYear,
    required this.ottomanYear,
    this.grainPrice = 0,
    this.cattlePrice = 0,
    this.kaiserId,
    this.sultanId,
    this.kaiserPot = 0,
    this.sultanPot = 0,
    List<int>? kurfuerstenIds,
    List<ChronicleRecord>? kaiserChronicle,
    List<ChronicleRecord>? sultanChronicle,
    Map<int, Person>? persons,
    this.nextPersonId = 1,
    List<AssassinationOrder>? assassinationOrders,
    this.currentPlayer = 1,
    required this.map,
    required this.realms,
    required this.dynasties,
    required this.rngSeed,
    this.activeElection,
    this.activeWar,
    List<PendingDecision>? pendingDecisions,
    List<GameEvent>? events,
    this.prunedEventCount = 0,
    Map<int, int>? recapBaselines,
  })  : assert(realms.length == World.realmCount),
        assert(dynasties.length == World.realmCount),
        kurfuerstenIds = kurfuerstenIds ?? [],
        kaiserChronicle = kaiserChronicle ?? [],
        sultanChronicle = sultanChronicle ?? [],
        persons = persons ?? {},
        assassinationOrders = assassinationOrders ?? [],
        pendingDecisions = pendingDecisions ?? [],
        events = events ?? [],
        recapBaselines = recapBaselines ?? {};

  factory GameState.fromJson(Map<String, dynamic> raw) {
    // Older documents are migrated up to the current schema first; newer
    // ones (from a future app version) are rejected with a clear error.
    final json = migrateGameStateJson(raw);
    return GameState(
        schemaVersion: json['schemaVersion'] as int? ?? 1,
        // Missing field = game created before rules were versioned (v1).
        rulesVersion: json['rulesVersion'] as int? ?? 1,
        year: json['year'] as int,
        reformationYear: json['reformationYear'] as int,
        ottomanYear: json['ottomanYear'] as int,
        grainPrice: (json['grainPrice'] as num? ?? 0).toDouble(),
        cattlePrice: (json['cattlePrice'] as num? ?? 0).toDouble(),
        kaiserId: json['kaiserId'] as int?,
        sultanId: json['sultanId'] as int?,
        kaiserPot: json['kaiserPot'] as int? ?? 0,
        sultanPot: json['sultanPot'] as int? ?? 0,
        kurfuerstenIds: (json['kurfuerstenIds'] as List?)?.cast<int>(),
        kaiserChronicle: _recordList(json['kaiserChronicle']),
        sultanChronicle: _recordList(json['sultanChronicle']),
        persons: {
          for (final p in (json['persons'] as List? ?? const []))
            (p as Map)['id'] as int:
                Person.fromJson(p.cast<String, dynamic>()),
        },
        nextPersonId: json['nextPersonId'] as int? ?? 1,
        assassinationOrders: (json['assassinationOrders'] as List?)
            ?.map((o) => AssassinationOrder.fromJson(
                (o as Map).cast<String, dynamic>()))
            .toList(),
        currentPlayer: json['currentPlayer'] as int? ?? 1,
        map: WorldMap.fromJson((json['map'] as Map).cast<String, dynamic>()),
        realms: (json['realms'] as List)
            .map((r) => Realm.fromJson((r as Map).cast<String, dynamic>()))
            .toList(),
        dynasties: (json['dynasties'] as List)
            .map((d) => Dynasty.fromJson((d as Map).cast<String, dynamic>()))
            .toList(),
        rngSeed: json['rngSeed'] as int,
        activeElection: json['activeElection'] == null
            ? null
            : ActiveElection.fromJson(
                (json['activeElection'] as Map).cast<String, dynamic>()),
        activeWar: json['activeWar'] == null
            ? null
            : ActiveWar.fromJson(
                (json['activeWar'] as Map).cast<String, dynamic>()),
        pendingDecisions: (json['pendingDecisions'] as List?)
            ?.map((d) => PendingDecision.fromJson(
                (d as Map).cast<String, dynamic>()))
            .toList(),
        events: (json['events'] as List?)
            ?.map((e) =>
                GameEvent.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        prunedEventCount: json['prunedEventCount'] as int? ?? 0,
        recapBaselines: {
          for (final e in ((json['recapBaselines'] as Map?) ?? {}).entries)
            int.parse(e.key as String): e.value as int,
        });
  }

  static List<ChronicleRecord> _recordList(Object? json) =>
      (json as List? ?? const [])
          .map((r) =>
              ChronicleRecord.fromJson((r as Map).cast<String, dynamic>()))
          .toList();

  /// JSON shape version (see versioning.dart). Bumped only on
  /// incompatible reshapes; additions never bump it. Old documents are
  /// migrated in [GameState.fromJson].
  final int schemaVersion;

  /// Gameplay-rules version, pinned when the game is created and never
  /// changed afterwards: rule/balance changes gate on this so running
  /// games (local saves, online matches) keep their original rules.
  final int rulesVersion;

  /// Starts at 999; becomes 1000 at the first round (§1).
  int year;

  /// Player-chosen at setup, validated ≥ 1011 (§5).
  final int reformationYear;
  final int ottomanYear;

  /// Global market prices, rolled once per year (§9.1).
  double grainPrice;
  double cattlePrice;

  /// Person ids; null = vacant / Interregnum.
  int? kaiserId;
  int? sultanId;

  /// Accumulated tribute for the office holders (§7.2).
  int kaiserPot;
  int sultanPot;

  /// Person ids — capacity exactly 7, never grows (§2).
  final List<int> kurfuerstenIds;

  final List<ChronicleRecord> kaiserChronicle;
  final List<ChronicleRecord> sultanChronicle;

  /// Master list of every living person, by id.
  final Map<int, Person> persons;

  /// Next person id to assign; ids are never reused.
  int nextPersonId;

  final List<AssassinationOrder> assassinationOrders;

  /// Active player slot (1–30).
  int currentPlayer;

  final WorldMap map;

  /// Exactly 30 realms, list index = slot − 1; use [realm] for slot access.
  final List<Realm> realms;

  /// Exactly 30 dynasties, list index = slot − 1; use [dynasty].
  final List<Dynasty> dynasties;

  /// Current RNG seed. Updated after every entry point that rolled dice;
  /// makes saves replayable (ARCHITECTURE.md "RNG & Determinism").
  int rngSeed;

  /// Ongoing Kaiser/Sultan election, while human bribery/votes are pending
  /// (§17.3); null when no election is running.
  ActiveElection? activeElection;

  /// Ongoing war (§11); at most one at a time, as in the original (wars
  /// run synchronously inside the declaring player's turn).
  ActiveWar? activeWar;

  final List<PendingDecision> pendingDecisions;

  /// Append-only event log — feeds the event feed, recap and replay.
  /// Capped: the turn pipeline drops the oldest entries past
  /// `maxRetainedEvents` and counts them in [prunedEventCount], so the
  /// state (copied per action, serialized per auto-save) stays bounded.
  final List<GameEvent> events;

  /// How many old events have been pruned off the front of [events].
  /// `prunedEventCount + index` is an event's stable absolute position —
  /// recap baselines use it to survive pruning.
  int prunedEventCount;

  /// Per-slot absolute event position up to which that seat has seen its
  /// "since your last turn" recap (modern UX). Lives in the state so it
  /// survives app restarts (local) and travels with the match (online).
  final Map<int, int> recapBaselines;

  /// Realm for a 1-based slot index.
  Realm realm(int slot) => realms[slot - 1];

  /// Dynasty for a 1-based slot index.
  Dynasty dynasty(int slot) => dynasties[slot - 1];

  Person? person(int? id) => id == null ? null : persons[id];

  /// Deep copy — the working idiom for `(state, action, rng) → state`
  /// until a real persistent-structure need shows up.
  GameState copy() => GameState(
        schemaVersion: schemaVersion,
        rulesVersion: rulesVersion,
        year: year,
        reformationYear: reformationYear,
        ottomanYear: ottomanYear,
        grainPrice: grainPrice,
        cattlePrice: cattlePrice,
        kaiserId: kaiserId,
        sultanId: sultanId,
        kaiserPot: kaiserPot,
        sultanPot: sultanPot,
        kurfuerstenIds: List.of(kurfuerstenIds),
        kaiserChronicle: [for (final r in kaiserChronicle) r.copy()],
        sultanChronicle: [for (final r in sultanChronicle) r.copy()],
        persons: {for (final e in persons.entries) e.key: e.value.copy()},
        nextPersonId: nextPersonId,
        assassinationOrders: [
          for (final o in assassinationOrders) o.copy()
        ],
        currentPlayer: currentPlayer,
        map: map.copy(),
        realms: [for (final r in realms) r.copy()],
        dynasties: [for (final d in dynasties) d.copy()],
        rngSeed: rngSeed,
        activeElection: activeElection?.copy(),
        activeWar: activeWar?.copy(),
        pendingDecisions: [for (final d in pendingDecisions) d.copy()],
        events: List.of(events),
        prunedEventCount: prunedEventCount,
        recapBaselines: Map.of(recapBaselines),
      );

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'rulesVersion': rulesVersion,
        'year': year,
        'reformationYear': reformationYear,
        'ottomanYear': ottomanYear,
        'grainPrice': grainPrice,
        'cattlePrice': cattlePrice,
        'kaiserId': kaiserId,
        'sultanId': sultanId,
        'kaiserPot': kaiserPot,
        'sultanPot': sultanPot,
        'kurfuerstenIds': kurfuerstenIds,
        'kaiserChronicle': [for (final r in kaiserChronicle) r.toJson()],
        'sultanChronicle': [for (final r in sultanChronicle) r.toJson()],
        'persons': [for (final p in persons.values) p.toJson()],
        'nextPersonId': nextPersonId,
        'assassinationOrders': [
          for (final o in assassinationOrders) o.toJson()
        ],
        'currentPlayer': currentPlayer,
        'map': map.toJson(),
        'realms': [for (final r in realms) r.toJson()],
        'dynasties': [for (final d in dynasties) d.toJson()],
        'rngSeed': rngSeed,
        'activeElection': activeElection?.toJson(),
        'activeWar': activeWar?.toJson(),
        'pendingDecisions': [for (final d in pendingDecisions) d.toJson()],
        'events': [for (final e in events) e.toJson()],
        'prunedEventCount': prunedEventCount,
        'recapBaselines': {
          for (final e in recapBaselines.entries) '${e.key}': e.value,
        },
      };
}
