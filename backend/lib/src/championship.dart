/// The yearly "PCKaiser-Weltmeisterschaft" (`[DESIGNED 2026-10-26, user
/// request]`, ARCHITECTURE.md "Weltmeisterschaft"): once a year the server
/// hosts ONE online match for up to 16 players that starts on a fixed date
/// with everybody who signed up — the remaining realms are AI. Its final
/// ranking of every participant is kept forever (the match itself is
/// deleted by the retention sweep like any other) and shown in the app's
/// hall of fame.
///
/// The calendar is a fixed rule, not configuration: every 1 November at
/// 18:00 German time, sign-up opens [championshipSignupWindow] before.
library;

import 'models.dart';

/// Start of the [year]'s championship: 1 November, 18:00 German time.
/// Daylight saving ends on the last Sunday of October (25–31 Oct), so
/// 1 November is always CET = UTC+1.
DateTime championshipStart(int year) => DateTime.utc(year, 11, 1, 17);

/// How long before the start the sign-up opens (and the announcement push
/// goes out).
const Duration championshipSignupWindow = Duration(days: 30);

/// The first app build that subscribes to the announcement topic. Players
/// on an older (or unknown) build only learn of a championship through the
/// one-off notice.
const String championshipTopicSince = '0.3.0';

/// Whether [version] (`x.y.z`, null = unknown) predates [than].
bool isOlderBuild(String? version, String than) {
  if (version == null) return true;
  List<int> parts(String v) =>
      [for (final p in v.split('.')) int.tryParse(p) ?? 0];
  final a = parts(version), b = parts(than);
  for (var i = 0; i < 3; i++) {
    final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
    if (x != y) return x < y;
  }
  return false;
}

/// Human seats — the original's maximum.
const int championshipSeats = 16;

/// The settings every championship plays with: the full 30-realm world on
/// the large map, 24 h turns, the standard war clock and AI defaults.
MatchSettings championshipSettings(int year) => MatchSettings(
      turnTimeoutHours: 24,
      warRoundTimeoutSeconds: 600,
      mapSize: 'gross',
      realmCount: 30,
      championship: year,
    );

/// Why a participant's placing ended where it did.
abstract final class StandingReason {
  /// Won the match (`gameWon` on one of their realms).
  static const String winner = 'winner';

  /// Still ruling land when the match ended without them winning (an AI
  /// won the last war in the same turn, or a draw).
  static const String survived = 'survived';

  /// Lost their last realm in the game.
  static const String eliminated = 'eliminated';

  /// Left the running match — their realm fell to the AI.
  static const String left = 'left';

  /// Kicked for idling — their realm fell to the AI.
  static const String kicked = 'kicked';
}

/// One participant's line in a championship: recorded on the match when
/// they drop out ([MatchRecord.championshipExits]) and, once the match
/// ends, as a placing in [ChampionshipRecord.ranking].
class ChampionshipStanding {
  ChampionshipStanding({
    required this.playerId,
    required this.name,
    required this.slot,
    required this.reason,
    this.rank,
    this.year,
    this.step = 0,
    this.tiles = 0,
  });

  factory ChampionshipStanding.fromJson(Map<String, dynamic> json) =>
      ChampionshipStanding(
        playerId: json['player_id'] as String,
        name: json['name'] as String,
        slot: json['slot'] as int,
        reason: json['reason'] as String,
        rank: json['rank'] as int?,
        year: json['year'] as int?,
        step: json['step'] as int? ?? 0,
        tiles: json['tiles'] as int? ?? 0,
      );

  final String playerId;

  /// Display name at the time of the placing — players may rename later,
  /// the hall of fame keeps the name they played under.
  final String name;

  /// The seat's home realm (the client localizes the realm name).
  final int slot;

  /// A [StandingReason] value.
  final String reason;

  /// Final placing, 1 = Weltmeister. Null while the match still runs.
  int? rank;

  /// Game year of the exit; null for the winner/survivors.
  final int? year;

  /// Exit order: seats dropping out in the same commit share a step, a
  /// later step ranks better. Tie-broken by [tiles].
  final int step;

  /// Map tiles the seat's realms held just before the exit (tie-break).
  final int tiles;

  Map<String, dynamic> toJson() => {
        'player_id': playerId,
        'name': name,
        'slot': slot,
        'reason': reason,
        if (rank != null) 'rank': rank,
        if (year != null) 'year': year,
        'step': step,
        'tiles': tiles,
      };

  /// What the client sees in the hall of fame. Never the player id — it is
  /// the player's credential and the hall of fame is public; [viewerId]
  /// only marks the viewer's own line.
  Map<String, dynamic> toClientJson({String? viewerId}) => {
        'rank': rank,
        'you': viewerId != null && viewerId == playerId,
        'name': name,
        'slot': slot,
        'reason': reason,
        'year': year,
      };
}

/// One year's championship (`championships` store): which match hosts it,
/// whether the sign-up was announced and — once it ended — the ranking.
class ChampionshipRecord {
  ChampionshipRecord({
    required this.year,
    this.matchId,
    this.announcedAt,
    this.oldBuildNoticeAt,
    this.finishedAt,
    this.ranking,
  });

  factory ChampionshipRecord.fromJson(Map<String, dynamic> json) =>
      ChampionshipRecord(
        year: json['year'] as int,
        matchId: json['match_id'] as String?,
        announcedAt: json['announced_at'] == null
            ? null
            : DateTime.parse(json['announced_at'] as String),
        oldBuildNoticeAt: json['old_build_notice_at'] == null
            ? null
            : DateTime.parse(json['old_build_notice_at'] as String),
        finishedAt: json['finished_at'] == null
            ? null
            : DateTime.parse(json['finished_at'] as String),
        ranking: (json['ranking'] as List?)
            ?.map((s) =>
                ChampionshipStanding.fromJson((s as Map).cast<String, dynamic>()))
            .toList(),
      );

  final int year;

  /// The hosting match; null before the sign-up opened, and again when the
  /// start found nobody signed up (the empty match is deleted).
  String? matchId;

  /// When the "sign-up is open" push went out — sent once per year.
  DateTime? announcedAt;

  /// When the one-off "update the app to sign up" notice went out to the
  /// players on builds without the announcement topic (`bin/
  /// announce_championship.dart`) — it is sent at most once per year.
  DateTime? oldBuildNoticeAt;

  DateTime? finishedAt;

  /// Every participant by final placing; null while the match runs.
  List<ChampionshipStanding>? ranking;

  Map<String, dynamic> toJson() => {
        'year': year,
        'match_id': matchId,
        'announced_at': announcedAt?.toIso8601String(),
        if (oldBuildNoticeAt != null)
          'old_build_notice_at': oldBuildNoticeAt!.toIso8601String(),
        'finished_at': finishedAt?.toIso8601String(),
        if (ranking != null) 'ranking': [for (final s in ranking!) s.toJson()],
      };
}
