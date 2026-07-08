/// Push notifications (ARCHITECTURE.md "FCM"): fire-and-forget — the
/// game must work without them, so failures are logged and swallowed.
///
/// The FCM HTTP-v1 implementation needs service-account credentials
/// (`FIREBASE_SERVICE_ACCOUNT`); until those are wired up in deployment,
/// the default [LogPushService] just logs what would have been sent.
library;

import 'models.dart';

abstract class PushService {
  Future<void> yourTurn(PlayerRecord player, MatchRecord match);
  Future<void> yourDecision(PlayerRecord player, MatchRecord match);
  Future<void> warStarted(PlayerRecord player, MatchRecord match);

  /// Both combatants answered their warPlan: the duel start is now fixed
  /// at [start] — [agreed] when the sides found a common slot, false when
  /// no proposals overlapped (the half-turn fallback stands).
  Future<void> warStartFixed(
      PlayerRecord player, MatchRecord match, DateTime start,
      {required bool agreed});

  /// ~15 minutes before an AGREED duel start (never for the fallback).
  Future<void> warStartSoon(PlayerRecord player, MatchRecord match);
}

class LogPushService implements PushService {
  void _log(String kind, PlayerRecord player, MatchRecord match) {
    // ignore: avoid_print — the server's stdout IS the log.
    print('[push:$kind] player=${player.id} match=${match.id} '
        'token=${player.fcmToken == null ? 'none' : 'set'}');
  }

  @override
  Future<void> yourTurn(PlayerRecord player, MatchRecord match) async =>
      _log('YOUR_TURN', player, match);

  @override
  Future<void> yourDecision(PlayerRecord player, MatchRecord match) async =>
      _log('YOUR_DECISION', player, match);

  @override
  Future<void> warStarted(PlayerRecord player, MatchRecord match) async =>
      _log('WAR_STARTED', player, match);

  @override
  Future<void> warStartFixed(
          PlayerRecord player, MatchRecord match, DateTime start,
          {required bool agreed}) async =>
      _log('WAR_START_FIXED(${agreed ? 'agreed' : 'fallback'}, $start)',
          player, match);

  @override
  Future<void> warStartSoon(PlayerRecord player, MatchRecord match) async =>
      _log('WAR_START_SOON', player, match);
}
