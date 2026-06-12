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
}
